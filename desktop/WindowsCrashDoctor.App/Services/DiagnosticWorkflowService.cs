using System.Text.Json;
using WindowsCrashDoctor.Models;

namespace WindowsCrashDoctor.Services;

public sealed record DiagnosticProgressUpdate(int Percent, string Status);

public sealed record DiagnosticRunResult(
    CrashDoctorReport Report,
    string EvidencePath,
    string MarkdownReportPath,
    CollectionStatus? CollectionStatus);

public sealed record DumpAnalysisResult(string OutputDirectory, string MarkdownReportPath);

public sealed class DiagnosticWorkflowService
{
    private const int MaxResultPathBytes = 16 * 1024;
    private const int MaxCollectionStatusBytes = 4 * 1024 * 1024;

    private readonly EngineExtractor _engine;
    private readonly PowerShellRunner _powerShell;
    private readonly CrashDoctorReportReader _reportReader;
    private readonly HistoryService _history;

    public DiagnosticWorkflowService(
        EngineExtractor engine,
        PowerShellRunner powerShell,
        CrashDoctorReportReader reportReader,
        HistoryService history)
    {
        _engine = engine;
        _powerShell = powerShell;
        _reportReader = reportReader;
        _history = history;
    }

    public async Task<DiagnosticRunResult> RunFullDiagnosisAsync(
        string outputRoot,
        int eventHours,
        IProgress<DiagnosticProgressUpdate>? progress = null,
        Action<string>? onLog = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(outputRoot);
        if (eventHours is < 1 or > 168)
            throw new ArgumentOutOfRangeException(nameof(eventHours));

        _engine.EnsureExtracted();
        Directory.CreateDirectory(outputRoot);
        var resolvedOutputRoot = Path.GetFullPath(outputRoot);
        var resultPathFile = Path.Combine(Path.GetTempPath(), $"wcd-collector-result-{Guid.NewGuid():N}.txt");

        try
        {
            progress?.Report(new DiagnosticProgressUpdate(15, "Collecting Windows, firmware, storage and power evidence…"));
            onLog?.Invoke("Starting the read-only evidence collector with Administrator rights only for collection.");

            var collectorExitCode = await _powerShell.RunFileElevatedAsync(
                _engine.CollectorPath,
                new[]
                {
                    "-OutputRoot", resolvedOutputRoot,
                    "-EventHours", eventHours.ToString(System.Globalization.CultureInfo.InvariantCulture),
                    "-ResultPathFile", resultPathFile
                },
                cancellationToken,
                TimeSpan.FromMinutes(15));

            if (collectorExitCode != 0)
                throw new InvalidOperationException($"The elevated diagnostic collector exited with code {collectorExitCode}.");

            var evidencePath = ReadAndValidateCollectorResult(resultPathFile, resolvedOutputRoot);
            var collectionStatus = ReadCollectionStatus(evidencePath);
            if (collectionStatus?.CompletedWithErrors == true)
                onLog?.Invoke($"Collection completed with {collectionStatus.FailureCount} unavailable stage(s); analysis will preserve those gaps as unknown evidence.");

            progress?.Report(new DiagnosticProgressUpdate(62, "Analysing the exact evidence snapshot returned by the collector…"));
            var analyse = await _powerShell.RunFileAsync(
                _engine.CrashDoctorPath,
                new[] { "-EvidencePath", evidencePath, "-OutputDirectory", evidencePath },
                onLog,
                cancellationToken,
                TimeSpan.FromMinutes(10));
            if (analyse.ExitCode != 0)
                throw new InvalidOperationException($"Crash Doctor analysis exited with code {analyse.ExitCode}. {SummarizeError(analyse.StandardError)}");

            progress?.Report(new DiagnosticProgressUpdate(88, "Validating report and recording diagnostic history…"));
            var jsonReportPath = Path.Combine(evidencePath, "crash-doctor-report.json");
            var markdownReportPath = Path.Combine(evidencePath, "crash-doctor-report.md");
            var report = await _reportReader.ReadAsync(jsonReportPath, cancellationToken);
            if (!File.Exists(markdownReportPath))
                throw new InvalidDataException("Crash Doctor did not create the Markdown report.");

            var settings = _history.LoadSettings();
            settings.LastEvidencePath = evidencePath;
            _history.SaveSettings(settings);
            _history.AddHistory(CreateHistoryEntry(report, evidencePath));

            progress?.Report(new DiagnosticProgressUpdate(100, "Diagnosis complete"));
            return new DiagnosticRunResult(report, evidencePath, markdownReportPath, collectionStatus);
        }
        finally
        {
            TryDelete(resultPathFile);
        }
    }

    public async Task<DumpAnalysisResult> AnalyseDumpAsync(
        string dumpPath,
        string outputRoot,
        Action<string>? onLog = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(dumpPath);
        ArgumentException.ThrowIfNullOrWhiteSpace(outputRoot);
        if (!File.Exists(dumpPath))
            throw new FileNotFoundException("Windows dump file was not found.", dumpPath);

        _engine.EnsureExtracted();
        Directory.CreateDirectory(outputRoot);
        var output = Path.Combine(
            Path.GetFullPath(outputRoot),
            $"Dump-{DateTime.UtcNow:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}"[..37]);
        Directory.CreateDirectory(output);

        var result = await _powerShell.RunFileAsync(
            _engine.CrashDoctorPath,
            new[] { "-DumpPath", Path.GetFullPath(dumpPath), "-OutputDirectory", output },
            onLog,
            cancellationToken,
            TimeSpan.FromMinutes(10));
        if (result.ExitCode != 0)
            throw new InvalidOperationException($"Dump analysis exited with code {result.ExitCode}. {SummarizeError(result.StandardError)}");

        var markdown = Path.Combine(output, "crash-doctor-dump-report.md");
        var json = Path.Combine(output, "crash-doctor-dump-report.json");
        if (!File.Exists(markdown) || !File.Exists(json))
            throw new InvalidDataException("Dump analysis did not produce both Markdown and JSON reports.");
        return new DumpAnalysisResult(output, markdown);
    }

    private static string ReadAndValidateCollectorResult(string resultPathFile, string outputRoot)
    {
        var info = new FileInfo(resultPathFile);
        if (!info.Exists || info.Length == 0 || info.Length > MaxResultPathBytes)
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

    private static CollectionStatus? ReadCollectionStatus(string evidencePath)
    {
        var path = Path.Combine(evidencePath, "collection-status.json");
        if (!File.Exists(path))
            return null;
        var info = new FileInfo(path);
        if (info.Length == 0 || info.Length > MaxCollectionStatusBytes)
            throw new InvalidDataException("collection-status.json has an invalid size.");

        var status = JsonSerializer.Deserialize<CollectionStatus>(File.ReadAllText(path), new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        }) ?? throw new InvalidDataException("collection-status.json was empty or invalid.");

        if (status.SchemaVersion != "1.0" || string.IsNullOrWhiteSpace(status.CollectionId) || status.FailureCount < 0)
            throw new InvalidDataException("collection-status.json failed schema validation.");
        if (status.FailureCount != status.Failures.Count)
            throw new InvalidDataException("collection-status.json failure count does not match its failure records.");
        return status;
    }

    private static DiagnosticRunHistory CreateHistoryEntry(CrashDoctorReport report, string evidencePath)
    {
        var high = report.Findings.Count(f => f.Severity is "High" or "Critical");
        var medium = report.Findings.Count(f => f.Severity == "Medium");
        return new DiagnosticRunHistory
        {
            RanAt = DateTimeOffset.Now,
            Status = "Completed",
            HealthLabel = GetHealthLabel(report),
            EvidencePath = evidencePath,
            Model = report.Inventory.Model ?? "Unknown device",
            HighCount = high,
            MediumCount = medium,
            FindingCount = report.Findings.Count,
            CoveragePercent = report.Coverage.Percent
        };
    }

    public static string GetHealthLabel(CrashDoctorReport report)
    {
        if (report.Findings.Any(f => f.Severity == "Critical")) return "Critical evidence detected";
        if (report.Findings.Any(f => f.Severity == "High")) return "Needs attention";
        if (report.Findings.Any(f => f.Severity == "Medium")) return "Review recommended";
        return "No high-priority signal detected";
    }

    private static string SummarizeError(string error)
    {
        if (string.IsNullOrWhiteSpace(error))
            return "See the diagnostic log for details.";
        var singleLine = error.Replace('\r', ' ').Replace('\n', ' ').Trim();
        return singleLine.Length <= 500 ? singleLine : singleLine[..500] + "…";
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path)) File.Delete(path);
        }
        catch
        {
            // The workflow result is already known; temporary-file cleanup must not replace it.
        }
    }
}
