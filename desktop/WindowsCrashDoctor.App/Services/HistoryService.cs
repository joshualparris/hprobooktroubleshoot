using Microsoft.Data.Sqlite;
using System.Text.Json;
using WindowsCrashDoctor.Models;

namespace WindowsCrashDoctor.Services;

public sealed class HistoryService
{
    private readonly string _root;
    private readonly string _legacyHistoryPath;
    private readonly string _settingsPath;
    private readonly string _databasePath;
    private readonly JsonSerializerOptions _json = new() { WriteIndented = true };

    public string? StartupWarning { get; private set; }
    public string DatabasePath => _databasePath;

    public HistoryService()
    {
        _root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WindowsCrashDoctor");
        Directory.CreateDirectory(_root);
        _legacyHistoryPath = Path.Combine(_root, "history.json");
        _settingsPath = Path.Combine(_root, "settings.json");
        _databasePath = Path.Combine(_root, "history.db");
        EnsureDatabase();
        TryMigrateLegacyHistory();
    }

    private string ConnectionString => new SqliteConnectionStringBuilder
    {
        DataSource = _databasePath,
        Mode = SqliteOpenMode.ReadWriteCreate,
        Cache = SqliteCacheMode.Shared
    }.ToString();

    private void EnsureDatabase()
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            PRAGMA journal_mode=WAL;
            PRAGMA foreign_keys=ON;
            CREATE TABLE IF NOT EXISTS runs (
                run_id TEXT PRIMARY KEY,
                ran_at TEXT NOT NULL,
                status TEXT NOT NULL,
                health_label TEXT NOT NULL,
                evidence_path TEXT NOT NULL,
                report_path TEXT NOT NULL,
                model TEXT NOT NULL,
                device_fingerprint TEXT NOT NULL,
                evidence_bundle_hash TEXT NOT NULL,
                product_version TEXT NOT NULL,
                rule_set_version TEXT NOT NULL,
                duration_ms INTEGER NOT NULL,
                high_count INTEGER NOT NULL,
                medium_count INTEGER NOT NULL,
                finding_count INTEGER NOT NULL,
                coverage_percent REAL NOT NULL,
                collector_success_count INTEGER NOT NULL,
                collector_failure_count INTEGER NOT NULL,
                comparison_summary TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS findings (
                run_id TEXT NOT NULL,
                finding_id TEXT NOT NULL,
                fingerprint TEXT NOT NULL,
                severity TEXT NOT NULL,
                confidence TEXT NOT NULL,
                title TEXT NOT NULL,
                evidence TEXT NOT NULL,
                source_collector TEXT NOT NULL,
                rule_version TEXT NOT NULL,
                PRIMARY KEY (run_id, finding_id),
                FOREIGN KEY (run_id) REFERENCES runs(run_id) ON DELETE CASCADE
            );
            CREATE TABLE IF NOT EXISTS collector_executions (
                run_id TEXT NOT NULL,
                diagnostic_id TEXT NOT NULL,
                name TEXT NOT NULL,
                evidence_file TEXT NOT NULL,
                status TEXT NOT NULL,
                started_at TEXT,
                finished_at TEXT,
                duration_ms INTEGER NOT NULL,
                exit_code INTEGER,
                retry_count INTEGER NOT NULL,
                failure_reason TEXT,
                PRIMARY KEY (run_id, diagnostic_id),
                FOREIGN KEY (run_id) REFERENCES runs(run_id) ON DELETE CASCADE
            );
            CREATE TABLE IF NOT EXISTS run_comparisons (
                run_id TEXT NOT NULL,
                finding_id TEXT NOT NULL,
                title TEXT NOT NULL,
                state TEXT NOT NULL,
                previous_fingerprint TEXT,
                current_fingerprint TEXT,
                explanation TEXT,
                PRIMARY KEY (run_id, finding_id, state),
                FOREIGN KEY (run_id) REFERENCES runs(run_id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS ix_runs_device_time ON runs(device_fingerprint, ran_at DESC);
            """;
        command.ExecuteNonQuery();
    }

    public bool CheckHealth(out string detail)
    {
        try
        {
            using var connection = Open();
            using var command = connection.CreateCommand();
            command.CommandText = "SELECT COUNT(*) FROM runs;";
            var count = Convert.ToInt32(command.ExecuteScalar());
            detail = $"SQLite run ledger ready ({count} recorded run(s)).";
            return true;
        }
        catch (Exception ex)
        {
            detail = "SQLite run ledger unavailable: " + ex.Message;
            return false;
        }
    }

    public List<DiagnosticRunHistory> LoadHistory(int limit = 50)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT run_id, ran_at, status, health_label, evidence_path, report_path, model,
                   device_fingerprint, evidence_bundle_hash, product_version, rule_set_version,
                   duration_ms, high_count, medium_count, finding_count, coverage_percent,
                   collector_success_count, collector_failure_count, comparison_summary
            FROM runs ORDER BY ran_at DESC LIMIT $limit;
            """;
        command.Parameters.AddWithValue("$limit", Math.Clamp(limit, 1, 500));
        using var reader = command.ExecuteReader();
        var items = new List<DiagnosticRunHistory>();
        while (reader.Read()) items.Add(ReadRun(reader));
        return items;
    }

    public DiagnosticRunHistory? GetLatestComparableRun(string deviceFingerprint, string? excludingRunId = null)
    {
        if (string.IsNullOrWhiteSpace(deviceFingerprint)) return null;
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT run_id, ran_at, status, health_label, evidence_path, report_path, model,
                   device_fingerprint, evidence_bundle_hash, product_version, rule_set_version,
                   duration_ms, high_count, medium_count, finding_count, coverage_percent,
                   collector_success_count, collector_failure_count, comparison_summary
            FROM runs
            WHERE device_fingerprint = $fingerprint AND ($exclude = '' OR run_id <> $exclude)
            ORDER BY ran_at DESC LIMIT 1;
            """;
        command.Parameters.AddWithValue("$fingerprint", deviceFingerprint);
        command.Parameters.AddWithValue("$exclude", excludingRunId ?? "");
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return null;
        var run = ReadRun(reader);
        reader.Close();
        run.Findings = LoadFindings(connection, run.RunId);
        return run;
    }

    public void AddHistory(DiagnosticRunHistory item)
    {
        if (string.IsNullOrWhiteSpace(item.RunId)) item.RunId = Guid.NewGuid().ToString("N");
        using var connection = Open();
        using var transaction = connection.BeginTransaction();

        using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                INSERT OR REPLACE INTO runs (
                    run_id, ran_at, status, health_label, evidence_path, report_path, model,
                    device_fingerprint, evidence_bundle_hash, product_version, rule_set_version,
                    duration_ms, high_count, medium_count, finding_count, coverage_percent,
                    collector_success_count, collector_failure_count, comparison_summary)
                VALUES ($run_id, $ran_at, $status, $health_label, $evidence_path, $report_path, $model,
                    $device_fingerprint, $evidence_bundle_hash, $product_version, $rule_set_version,
                    $duration_ms, $high_count, $medium_count, $finding_count, $coverage_percent,
                    $collector_success_count, $collector_failure_count, $comparison_summary);
                """;
            Add(command, "$run_id", item.RunId); Add(command, "$ran_at", item.RanAt.ToString("O"));
            Add(command, "$status", item.Status); Add(command, "$health_label", item.HealthLabel);
            Add(command, "$evidence_path", item.EvidencePath); Add(command, "$report_path", item.ReportPath);
            Add(command, "$model", item.Model); Add(command, "$device_fingerprint", item.DeviceFingerprint);
            Add(command, "$evidence_bundle_hash", item.EvidenceBundleHash); Add(command, "$product_version", item.ProductVersion);
            Add(command, "$rule_set_version", item.RuleSetVersion); Add(command, "$duration_ms", item.DurationMs);
            Add(command, "$high_count", item.HighCount); Add(command, "$medium_count", item.MediumCount);
            Add(command, "$finding_count", item.FindingCount); Add(command, "$coverage_percent", item.CoveragePercent);
            Add(command, "$collector_success_count", item.CollectorSuccessCount); Add(command, "$collector_failure_count", item.CollectorFailureCount);
            Add(command, "$comparison_summary", item.ComparisonSummary);
            command.ExecuteNonQuery();
        }

        ReplaceChildren(connection, transaction, item);
        transaction.Commit();
    }

    private static void ReplaceChildren(SqliteConnection connection, SqliteTransaction transaction, DiagnosticRunHistory item)
    {
        foreach (var table in new[] { "findings", "collector_executions", "run_comparisons" })
        {
            using var delete = connection.CreateCommand();
            delete.Transaction = transaction;
            delete.CommandText = $"DELETE FROM {table} WHERE run_id = $run_id;";
            delete.Parameters.AddWithValue("$run_id", item.RunId);
            delete.ExecuteNonQuery();
        }

        foreach (var finding in item.Findings)
        {
            using var command = connection.CreateCommand(); command.Transaction = transaction;
            command.CommandText = "INSERT INTO findings VALUES ($r,$id,$fp,$s,$c,$t,$e,$src,$rv);";
            Add(command,"$r",item.RunId); Add(command,"$id",finding.FindingId); Add(command,"$fp",finding.Fingerprint);
            Add(command,"$s",finding.Severity); Add(command,"$c",finding.Confidence); Add(command,"$t",finding.Title);
            Add(command,"$e",finding.Evidence); Add(command,"$src",finding.SourceCollector); Add(command,"$rv",finding.RuleVersion);
            command.ExecuteNonQuery();
        }
        foreach (var execution in item.CollectorExecutions)
        {
            using var command = connection.CreateCommand(); command.Transaction = transaction;
            command.CommandText = "INSERT INTO collector_executions VALUES ($r,$id,$n,$f,$s,$a,$b,$d,$x,$rc,$reason);";
            Add(command,"$r",item.RunId); Add(command,"$id",execution.DiagnosticId); Add(command,"$n",execution.Name);
            Add(command,"$f",execution.EvidenceFile); Add(command,"$s",execution.Status); Add(command,"$a",execution.StartedAt?.ToString("O"));
            Add(command,"$b",execution.FinishedAt?.ToString("O")); Add(command,"$d",execution.DurationMs); Add(command,"$x",execution.ExitCode);
            Add(command,"$rc",execution.RetryCount); Add(command,"$reason",execution.FailureReason); command.ExecuteNonQuery();
        }
        foreach (var comparison in item.Comparisons)
        {
            using var command = connection.CreateCommand(); command.Transaction = transaction;
            command.CommandText = "INSERT INTO run_comparisons VALUES ($r,$id,$t,$s,$p,$c,$e);";
            Add(command,"$r",item.RunId); Add(command,"$id",comparison.FindingId); Add(command,"$t",comparison.Title);
            Add(command,"$s",comparison.State); Add(command,"$p",comparison.PreviousFingerprint); Add(command,"$c",comparison.CurrentFingerprint);
            Add(command,"$e",comparison.Explanation); command.ExecuteNonQuery();
        }
    }

    private static List<FindingSnapshot> LoadFindings(SqliteConnection connection, string runId)
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT finding_id,fingerprint,severity,confidence,title,evidence,source_collector,rule_version FROM findings WHERE run_id=$run_id;";
        command.Parameters.AddWithValue("$run_id", runId);
        using var reader = command.ExecuteReader();
        var findings = new List<FindingSnapshot>();
        while (reader.Read()) findings.Add(new FindingSnapshot
        {
            FindingId = reader.GetString(0), Fingerprint = reader.GetString(1), Severity = reader.GetString(2), Confidence = reader.GetString(3),
            Title = reader.GetString(4), Evidence = reader.GetString(5), SourceCollector = reader.GetString(6), RuleVersion = reader.GetString(7)
        });
        return findings;
    }

    private static DiagnosticRunHistory ReadRun(SqliteDataReader r) => new()
    {
        RunId = r.GetString(0), RanAt = DateTimeOffset.Parse(r.GetString(1)), Status = r.GetString(2), HealthLabel = r.GetString(3),
        EvidencePath = r.GetString(4), ReportPath = r.GetString(5), Model = r.GetString(6), DeviceFingerprint = r.GetString(7),
        EvidenceBundleHash = r.GetString(8), ProductVersion = r.GetString(9), RuleSetVersion = r.GetString(10), DurationMs = r.GetInt64(11),
        HighCount = r.GetInt32(12), MediumCount = r.GetInt32(13), FindingCount = r.GetInt32(14), CoveragePercent = r.GetDouble(15),
        CollectorSuccessCount = r.GetInt32(16), CollectorFailureCount = r.GetInt32(17), ComparisonSummary = r.GetString(18)
    };

    private void TryMigrateLegacyHistory()
    {
        if (!File.Exists(_legacyHistoryPath)) return;
        try
        {
            using var connection = Open(); using var count = connection.CreateCommand(); count.CommandText = "SELECT COUNT(*) FROM runs;";
            if (Convert.ToInt32(count.ExecuteScalar()) > 0) return;
            var legacy = JsonSerializer.Deserialize<List<DiagnosticRunHistory>>(File.ReadAllText(_legacyHistoryPath), _json) ?? new();
            foreach (var item in legacy) AddHistory(item);
            File.Move(_legacyHistoryPath, _legacyHistoryPath + ".migrated", overwrite: true);
        }
        catch (Exception ex)
        {
            StartupWarning = "Legacy history could not be migrated; it was left untouched. " + ex.Message;
        }
    }

    public AppSettings LoadSettings()
    {
        try
        {
            if (!File.Exists(_settingsPath)) return new();
            return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(_settingsPath), _json) ?? new();
        }
        catch (Exception ex)
        {
            StartupWarning = string.IsNullOrWhiteSpace(StartupWarning) ? "Settings could not be read: " + ex.Message : StartupWarning;
            return new();
        }
    }

    public void SaveSettings(AppSettings settings) => File.WriteAllText(_settingsPath, JsonSerializer.Serialize(settings, _json));

    private SqliteConnection Open() { var connection = new SqliteConnection(ConnectionString); connection.Open(); return connection; }
    private static void Add(SqliteCommand command, string name, object? value) => command.Parameters.AddWithValue(name, value ?? DBNull.Value);
}
