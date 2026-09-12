using WindowsCrashDoctor.Models;

namespace WindowsCrashDoctor.Services;

public sealed record DiagnosticWorkflowProgress(int Percent, string Status);

public sealed record DiagnosticWorkflowResult(
    CrashDoctorReport Report,
    string EvidencePath,
    DiagnosticRunHistory RunHistory,
    PreflightReport Preflight,
    RunComparisonSummary Comparison,
    ProcessResult Collection,
    ProcessResult Analysis,
    IReadOnlyList<string> Warnings);

public sealed class DiagnosticWorkflowService
{
    private const int MaxCollectorResultBytes = 16 * 1024;

    private readonly EngineExtractor _engine;
    private readonly PowerShellRunner _powerShell;
    private readonly HistoryService _history;
    private readonly CrashDoctorReportReader _reportReader;
    private readonly PreflightService _preflight;
    private readonly FingerprintService _fingerprints;
    private readonly RunComparisonService _comparison;
    private readonly ReportEnrichmentService _reportEnrichment;

    public DiagnosticWorkflowService(
        EngineExtractor engine,
        PowerShellRunner powerShell,
        HistoryService history,
        CrashDoctorReportReader reportReader,
        PreflightService preflight,
        FingerprintService fingerprints,
        RunComparisonService comparison,
        ReportEnrichmentService reportEnrichment)
    {
        _engine = engine;
        _powerShell = powerShell;
        _history = history;
        _reportReader = reportReader;
        _preflight = preflight;
        _fingerprints = fingerprints;
        _comparison = comparison;
        _reportEnrichment = reportEnrichment;
    }

    public async Task<PreflightReport> RunPreflightAsync(
        string outputRoot,
        CancellationToken cancellationToken = default)
    {
        _engine.EnsureExtracted();
        var registry = DiagnosticRegistry.Load(_engine.RegistryPath);
        return await _preflight.RunAsync(outputRoot, _engine, _history, _powerShell, registry, cancellationToken);
    }

    public async Task<DiagnosticWorkflowResult> RunFullDiagnosisAsync(
        string outputRoot,
        int eventHours,
        IProgress<DiagnosticWorkflowProgress>? progress = null,
        Action<string>? onLog = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(outputRoot);
        if (eventHours is < 1 or > 168)
            throw new ArgumentOutOfRangeException(nameof(eventHours));

        _engine.EnsureExtracted();
        var resolvedOutputRoot = Path.GetFullPath(outputRoot);
        Directory.CreateDirectory(resolvedOutputRoot);
        var registry = DiagnosticRegistry.Load(_engine.RegistryPath);
        var warnings = new List<string>();

        progress?.Report(new DiagnosticWorkflowProgress(5, "Running preflight…"));
        var preflight = await _preflight.RunAsync(
            resolvedOutputRoot,
            _engine,
            _history,
            _powerShell,
            registry,
            cancellationToken);
        foreach (var item in preflight.Items.Where(x => x.State != "healthy"))
            onLog?.Invoke($"PREFLIGHT {item.State.ToUpperInvariant()}: {item.Name} — {item.Detail}");
        if (preflight.BlockingCount > 0)
            throw new InvalidOperationException("Preflight found a blocking prerequisite. Review the diagnostic log before collecting evidence.");

        var resultPathFile = Path.Combine(Path.GetTempPath(), $"wcd-collector-result-{Guid.NewGuid():N}.txt");
        try
        {
            progress?.Report(new DiagnosticWorkflowProgress(15, "Collecting Windows, firmware, storage and power evidence…"));
            onLog?.Invoke("Requesting Administrator rights for the read-only collector only; the desktop app remains standard-user.");
            var collect = await _powerShell.RunFileElevatedAsync(
                _engine.CollectorPath,
                new[]
                {
                    "-OutputRoot", resolvedOutputRoot,
                    "-EventHours", eventHours.ToString(System.Globalization.CultureInfo.InvariantCulture),
                    "-ResultPathFile", resultPathFile
                },
                cancellationToken,
                new ProcessRunOptions(TimeSpan.FromMinutes(4), OperationId: "full-collector"));
            if (!collect.Succeeded)
                throw new InvalidOperationException($"The diagnostic collector ended as {collect.Status}: {collect.FailureReason}");

            var evidencePath = ReadCollectorResult(resultPathFile, resolvedOutputRoot);
            onLog?.Invoke("Collector returned exact snapshot: " + Path.GetFileName(evidencePath));

            progress?.Report(new DiagnosticWorkflowProgress(62, "Analysing the returned evidence snapshot…"));
            var analyse = await _powerShell.RunFileAsync(
                _engine.CrashDoctorPath,
                new[] { "-EvidencePath", evidencePath, "-OutputDirectory", evidencePath },
                onLog,
                cancellationToken,
                new ProcessRunOptions(TimeSpan.FromMinutes(2), OperationId: "rules-analysis"));
            if (!analyse.Succeeded)
                throw new InvalidOperationException($"Crash Doctor analysis ended as {analyse.Status}: {analyse.FailureReason}");

            progress?.Report(new DiagnosticWorkflowProgress(82, "Validating and comparing the diagnostic report…"));
            var reportPath = Path.Combine(evidencePath, "crash-doctor-report.json");
            var markdownPath = Path.Combine(evidencePath, "crash-doctor-report.md");
            var report = await _reportReader.ReadAsync(reportPath, cancellationToken);
            if (!File.Exists(markdownPath))
                throw new InvalidDataException("Crash Doctor did not create its Markdown report.");

            var findingSnapshots = _fingerprints.StampFindings(report, registry);
            var deviceFingerprint = _fingerprints.DeviceFingerprint(report);
            DiagnosticRunHistory? previous = null;
            if (_history.CheckHealth(out var historyHealth))
            {
                previous = _history.GetLatestComparableRun(deviceFingerprint);
            }
            else
            {
                warnings.Add(historyHealth);
            }

            var comparison = _comparison.Compare(report, findingSnapshots, previous);
            var evidenceHash = _fingerprints.EvidenceBundleHash(evidencePath);
            var executions = BuildCollectorExecutions(report, collect, analyse, registry);
            var runMetadata = CreateRunMetadata(collect, analyse, deviceFingerprint, evidenceHash, executions, preflight);

            report.Run = runMetadata;
            report.Preflight = preflight;
            report.CollectorExecutions = executions;
            report.Comparison = comparison;
            report.DiagnosticRegistry = new RegistryProvenance
            {
                RegistryVersion = registry.RegistryVersion,
                SchemaVersion = registry.SchemaVersion,
                DiagnosticCount = registry.Diagnostics.Count
            };

            _reportEnrichment.Enrich(
                reportPath,
                markdownPath,
                runMetadata,
                preflight,
                executions,
                comparison,
                registry,
                report.Findings);

            report = await _reportReader.ReadAsync(reportPath, cancellationToken);
            comparison = report.Comparison ?? comparison;
            var historyItem = CreateHistoryEntry(report, evidencePath, markdownPath, runMetadata, findingSnapshots, executions, comparison);

            progress?.Report(new DiagnosticWorkflowProgress(92, "Persisting the run ledger…"));
            if (_history.CheckHealth(out historyHealth))
            {
                try
                {
                    _history.AddHistory(historyItem);
                }
                catch (Exception ex)
                {
                    warnings.Add("Run history could not be saved: " + ex.Message);
                }
            }
            else if (!warnings.Contains(historyHealth, StringComparer.Ordinal))
            {
                warnings.Add(historyHealth);
            }

            try
            {
                var settings = _history.LoadSettings();
                settings.LastEvidencePath = evidencePath;
                _history.SaveSettings(settings);
            }
            catch (Exception ex)
            {
                warnings.Add("Last-run setting could not be saved: " + ex.Message);
            }

            progress?.Report(new DiagnosticWorkflowProgress(100, warnings.Count == 0 ? "Diagnosis complete" : "Diagnosis complete with warnings"));
            return new DiagnosticWorkflowResult(report, evidencePath, historyItem, preflight, comparison, collect, analyse, warnings);
        }
        finally
        {
            TryDelete(resultPathFile);
        }
    }

    private static string ReadCollectorResult(string resultPathFile, string outputRoot)
    {
        var info = new FileInfo(resultPathFile);
        if (!info.Exists || info.Length <= 0 || info.Length > MaxCollectorResultBytes)
            throw new InvalidDataException("The elevated collector did not return a valid snapshot path.");

        var candidate = File.ReadAllText(resultPathFile).Trim().Trim('\uFEFF');
        if (string.IsNullOrWhiteSpace(candidate))
            throw new InvalidDataException("The elevated collector returned an empty snapshot path.");

        var resolved = Path.GetFullPath(candidate);
        var relative = Path.GetRelativePath(outputRoot, resolved);
        if (Path.IsPathRooted(relative) || relative == ".." || relative.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal))
            throw new InvalidDataException("The elevated collector returned a snapshot outside the configured results directory.");
        if (!Directory.Exists(resolved))
            throw new DirectoryNotFoundException("The elevated collector returned a snapshot directory that does not exist.");
        return resolved;
    }

    private static RunMetadata CreateRunMetadata(
        ProcessResult collection,
        ProcessResult analysis,
        string deviceFingerprint,
        string evidenceHash,
        IReadOnlyList<CollectorExecutionRecord> executions,
        PreflightReport preflight)
    {
        var started = collection.StartedAt < analysis.StartedAt ? collection.StartedAt : analysis.StartedAt;
        var finished = collection.FinishedAt > analysis.FinishedAt ? collection.FinishedAt : analysis.FinishedAt;
        var status = executions.Any(x => x.Status is not "completed" and not "completed-with-warnings") ||
                     preflight.OverallState == "degraded"
            ? "completed-with-warnings"
            : "completed";
        return new RunMetadata
        {
            RunId = Guid.NewGuid().ToString("N"),
            StartedAt = started,
            FinishedAt = finished,
            DurationMs = Math.Max(0, (long)(finished - started).TotalMilliseconds),
            DeviceFingerprint = deviceFingerprint,
            EvidenceBundleHash = evidenceHash,
            Status = status
        };
    }

    private static List<CollectorExecutionRecord> BuildCollectorExecutions(
        CrashDoctorReport report,
        ProcessResult collection,
        ProcessResult analysis,
        DiagnosticRegistry registry)
    {
        var present = report.Coverage.PresentFiles.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var missing = report.Coverage.MissingFiles.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var records = registry.Diagnostics.Select(definition =>
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
                DurationMs = (long)collection.Duration.TotalMilliseconds,
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

    private static DiagnosticRunHistory CreateHistoryEntry(
        CrashDoctorReport report,
        string evidencePath,
        string markdownPath,
        RunMetadata metadata,
        IReadOnlyList<FindingSnapshot> findings,
        IReadOnlyList<CollectorExecutionRecord> executions,
        RunComparisonSummary comparison)
    {
        return new DiagnosticRunHistory
        {
            RunId = metadata.RunId,
            RanAt = metadata.FinishedAt,
            Status = metadata.Status,
            HealthLabel = GetHealthLabel(report),
            EvidencePath = evidencePath,
            ReportPath = markdownPath,
            Model = report.Inventory.Model ?? "Unknown device",
            DeviceFingerprint = metadata.DeviceFingerprint,
            EvidenceBundleHash = metadata.EvidenceBundleHash,
            ProductVersion = report.Product.ProductVersion ?? "unknown",
            RuleSetVersion = report.Product.RuleSetVersion ?? "unknown",
            DurationMs = metadata.DurationMs,
            HighCount = report.Findings.Count(f => f.Severity is "High" or "Critical"),
            MediumCount = report.Findings.Count(f => f.Severity == "Medium"),
            FindingCount = report.Findings.Count,
            CoveragePercent = report.Coverage.Percent,
            CollectorSuccessCount = executions.Count(x => x.Status == "completed"),
            CollectorFailureCount = executions.Count(x => x.Status is not "completed" and not "completed-with-warnings"),
            ComparisonSummary = comparison.SummaryText,
            Findings = findings.ToList(),
            CollectorExecutions = executions.ToList(),
            Comparisons = comparison.Items.ToList()
        };
    }

    public static string GetHealthLabel(CrashDoctorReport report)
    {
        if (report.Findings.Any(f => f.Severity == "Critical")) return "Critical evidence detected";
        if (report.Findings.Any(f => f.Severity == "High")) return "Needs attention";
        if (report.Findings.Any(f => f.Severity == "Medium")) return "Review recommended";
        return "No high-priority signal detected";
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

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path)) File.Delete(path);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Trace.WriteLine($"Collector result-file cleanup failed: {ex.Message}");
        }
    }
}
