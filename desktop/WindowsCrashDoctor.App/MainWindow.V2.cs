using WindowsCrashDoctor.Models;
using WindowsCrashDoctor.Services;

namespace WindowsCrashDoctor;

public partial class MainWindow
{
    private readonly PreflightService _preflightService = new();
    private readonly FingerprintService _fingerprintService = new();
    private readonly RunComparisonService _comparisonService = new();
    private readonly ReportEnrichmentService _reportEnrichment = new();
    private readonly RedactionService _redaction = new();
    private DiagnosticRegistry? _diagnosticRegistry;
    private PreflightReport? _latestPreflight;
    private RunComparisonSummary? _latestComparison;

    private async Task InitialiseV2Async()
    {
        _diagnosticRegistry = DiagnosticRegistry.Load(_engine.RegistryPath);
        _latestPreflight = await _preflightService.RunAsync(_outputRoot, _engine, _history, _powerShell, _diagnosticRegistry);
        var admin = IsAdministrator() ? "Administrator mode" : "Standard mode • elevates when needed";
        AdminStatusText.Text = $"{admin} • preflight {_latestPreflight.OverallState}";
        DiagnosticStatusText.Text = $"Preflight {_latestPreflight.OverallState} • registry {_diagnosticRegistry.RegistryVersion}";
        if (!string.IsNullOrWhiteSpace(_history.StartupWarning))
            AppendLog("HISTORY WARNING: " + _history.StartupWarning);
    }

    private async Task<PreflightReport> RefreshPreflightForRunAsync()
    {
        _diagnosticRegistry ??= DiagnosticRegistry.Load(_engine.RegistryPath);
        _latestPreflight = await _preflightService.RunAsync(_outputRoot, _engine, _history, _powerShell, _diagnosticRegistry);
        foreach (var item in _latestPreflight.Items.Where(x => x.State != "healthy"))
            AppendLog($"PREFLIGHT {item.State.ToUpperInvariant()}: {item.Name} — {item.Detail}");
        return _latestPreflight;
    }

    private DiagnosticRunHistory CompleteV2Run(
        CrashDoctorReport report,
        string evidencePath,
        ProcessResult collection,
        ProcessResult analysis,
        string healthLabel)
    {
        _diagnosticRegistry ??= DiagnosticRegistry.Load(_engine.RegistryPath);
        _latestPreflight ??= new PreflightReport { OverallState = "unknown" };

        var runId = Guid.NewGuid().ToString("N");
        var deviceFingerprint = _fingerprintService.DeviceFingerprint(report);
        var findingSnapshots = _fingerprintService.StampFindings(report, _diagnosticRegistry);
        var previous = _history.GetLatestComparableRun(deviceFingerprint);
        _latestComparison = _comparisonService.Compare(report, findingSnapshots, previous);
        var evidenceHash = _fingerprintService.EvidenceBundleHash(evidencePath);
        var executions = BuildCollectorExecutions(report, collection, analysis);
        var started = collection.StartedAt < analysis.StartedAt ? collection.StartedAt : analysis.StartedAt;
        var finished = collection.FinishedAt > analysis.FinishedAt ? collection.FinishedAt : analysis.FinishedAt;
        var status = executions.Any(x => x.Status != "completed") || _latestPreflight.OverallState == "degraded"
            ? "completed-with-warnings" : "completed";
        var metadata = new RunMetadata
        {
            RunId = runId,
            StartedAt = started,
            FinishedAt = finished,
            DurationMs = (long)(finished - started).TotalMilliseconds,
            DeviceFingerprint = deviceFingerprint,
            EvidenceBundleHash = evidenceHash,
            Status = status
        };

        report.Run = metadata;
        report.Preflight = _latestPreflight;
        report.CollectorExecutions = executions;
        report.Comparison = _latestComparison;
        report.DiagnosticRegistry = new RegistryProvenance
        {
            RegistryVersion = _diagnosticRegistry.RegistryVersion,
            SchemaVersion = _diagnosticRegistry.SchemaVersion,
            DiagnosticCount = _diagnosticRegistry.Diagnostics.Count
        };

        var reportPath = Path.Combine(evidencePath, "crash-doctor-report.json");
        var markdownPath = Path.Combine(evidencePath, "crash-doctor-report.md");
        _reportEnrichment.Enrich(reportPath, markdownPath, metadata, _latestPreflight, executions, _latestComparison, _diagnosticRegistry, report.Findings);

        var history = new DiagnosticRunHistory
        {
            RunId = runId,
            RanAt = finished,
            Status = status,
            HealthLabel = healthLabel,
            EvidencePath = evidencePath,
            ReportPath = markdownPath,
            Model = report.Inventory.Model ?? "Unknown device",
            DeviceFingerprint = deviceFingerprint,
            EvidenceBundleHash = evidenceHash,
            ProductVersion = report.Product.ProductVersion ?? "unknown",
            RuleSetVersion = report.Product.RuleSetVersion ?? "unknown",
            DurationMs = metadata.DurationMs,
            HighCount = report.Findings.Count(f => f.Severity is "High" or "Critical"),
            MediumCount = report.Findings.Count(f => f.Severity == "Medium"),
            FindingCount = report.Findings.Count,
            CoveragePercent = report.Coverage.Percent,
            CollectorSuccessCount = executions.Count(x => x.Status == "completed"),
            CollectorFailureCount = executions.Count(x => x.Status != "completed"),
            ComparisonSummary = _latestComparison.SummaryText,
            Findings = findingSnapshots,
            CollectorExecutions = executions,
            Comparisons = _latestComparison.Items
        };
        _history.AddHistory(history);
        return history;
    }

    private List<CollectorExecutionRecord> BuildCollectorExecutions(CrashDoctorReport report, ProcessResult collection, ProcessResult analysis)
    {
        var present = report.Coverage.PresentFiles.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var missing = report.Coverage.MissingFiles.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var records = (_diagnosticRegistry?.Diagnostics ?? new List<DiagnosticDefinition>()).Select(definition =>
        {
            var ok = present.Contains(definition.EvidenceFile);
            var absent = missing.Contains(definition.EvidenceFile);
            return new CollectorExecutionRecord
            {
                DiagnosticId = definition.Id,
                Name = definition.Name,
                EvidenceFile = definition.EvidenceFile,
                Status = ok ? "completed" : absent ? "unavailable" : "skipped-not-applicable",
                StartedAt = collection.StartedAt,
                FinishedAt = collection.FinishedAt,
                DurationMs = 0,
                ExitCode = collection.ExitCode,
                RetryCount = Math.Max(0, collection.AttemptCount - 1),
                FailureReason = ok ? null : absent ? "Expected evidence file was not produced or was empty." : "No registry coverage state was produced."
            };
        }).ToList();

        records.Add(new CollectorExecutionRecord
        {
            DiagnosticId = "analysis.rules",
            Name = "Crash Doctor rule analysis",
            EvidenceFile = "crash-doctor-report.json",
            Status = ToStatus(analysis),
            StartedAt = analysis.StartedAt,
            FinishedAt = analysis.FinishedAt,
            DurationMs = (long)analysis.Duration.TotalMilliseconds,
            ExitCode = analysis.ExitCode,
            RetryCount = Math.Max(0, analysis.AttemptCount - 1),
            FailureReason = analysis.FailureReason
        });
        return records;
    }

    private static string ToStatus(ProcessResult result) => result.Status switch
    {
        ProcessExecutionStatus.Completed => "completed",
        ProcessExecutionStatus.CompletedWithWarnings => "completed-with-warnings",
        ProcessExecutionStatus.Cancelled => "cancelled",
        ProcessExecutionStatus.TimedOut => "timed-out",
        ProcessExecutionStatus.FailedRetryable => "failed-retryable",
        ProcessExecutionStatus.FailedPermanent => "failed-permanent",
        ProcessExecutionStatus.Unavailable => "unavailable",
        _ => "skipped-not-applicable"
    };

    private void ApplyV2DashboardSummary()
    {
        if (_latestComparison is null) return;
        HealthExplanation.Text += "  " + _latestComparison.SummaryText + $" • comparison trust {_latestComparison.Trust}.";
        if (_latestComparison.WorsenedCount > 0 || _latestComparison.NewCount > 0)
            RecommendationBody.Text += $" Since the previous comparable run: {_latestComparison.NewCount} new, {_latestComparison.WorsenedCount} worsened, {_latestComparison.ResolvedCount} resolved.";
    }
}
