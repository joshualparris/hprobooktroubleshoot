using System.IO.Compression;
using System.Text;
using System.Text.Json;

namespace WindowsCrashDoctor.Services;

public sealed record PrivacyExportEntry(
    string RelativePath,
    bool Included,
    string? Reason,
    int RedactionCount,
    long SizeBytes,
    IReadOnlyList<SensitiveMatch>? SensitiveMatches = null);

public sealed record PrivacyExportPlan(
    string SourceDirectory,
    IReadOnlyList<PrivacyExportEntry> Entries)
{
    public int IncludedCount => Entries.Count(x => x.Included);
    public int ExcludedCount => Entries.Count(x => !x.Included);
    public int RedactedFileCount => Entries.Count(x => x.Included && x.RedactionCount > 0);
    public int TotalRedactions => Entries.Sum(x => x.RedactionCount);
    public int SensitiveMatchCount => Entries.Sum(x => x.SensitiveMatches?.Count ?? 0);
}

public sealed record PrivacyExportResult(
    string ZipPath,
    int IncludedCount,
    int ExcludedCount,
    int RedactedFileCount,
    int TotalRedactions);

public sealed class PrivacyExportService
{
    private const long MaxTextScanBytes = 12 * 1024 * 1024;
    private readonly RedactionService _redaction = new();

    private static readonly HashSet<string> ExcludedExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".dmp", ".mdmp", ".etl", ".evtx", ".pcap", ".pcapng", ".raw", ".bin",
        ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp"
    };

    private static readonly HashSet<string> TextExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".txt", ".log", ".md", ".json", ".jsonl", ".xml", ".html", ".htm", ".csv",
        ".ps1", ".psm1", ".cmd", ".bat", ".ini", ".cfg", ".conf", ".yml", ".yaml"
    };

    public PrivacyExportPlan CreatePlan(string sourceDirectory)
    {
        if (!Directory.Exists(sourceDirectory)) throw new DirectoryNotFoundException(sourceDirectory);
        var entries = Directory.EnumerateFiles(sourceDirectory, "*", SearchOption.AllDirectories)
            .Select(file => Classify(new FileInfo(file), Path.GetRelativePath(sourceDirectory, file)))
            .OrderBy(x => x.RelativePath, StringComparer.OrdinalIgnoreCase)
            .ToList();
        return new PrivacyExportPlan(sourceDirectory, entries);
    }

    public PrivacyExportResult Export(PrivacyExportPlan plan, string zipPath)
    {
        var sourceRoot = Path.GetFullPath(plan.SourceDirectory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (!Directory.Exists(sourceRoot)) throw new DirectoryNotFoundException(sourceRoot);
        var staging = Path.Combine(Path.GetTempPath(), "WindowsCrashDoctorExport-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(staging);

        try
        {
            var finalEntries = new List<PrivacyExportEntry>();
            foreach (var planned in plan.Entries)
            {
                var source = Path.GetFullPath(Path.Combine(sourceRoot, planned.RelativePath));
                if (!source.StartsWith(sourceRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) || !File.Exists(source))
                {
                    finalEntries.Add(planned with { Included = false, Reason = "Source changed or disappeared after preview." });
                    continue;
                }
                if (!planned.Included) { finalEntries.Add(planned); continue; }

                var current = Classify(new FileInfo(source), planned.RelativePath);
                if (!current.Included)
                {
                    finalEntries.Add(current with { Reason = "Changed after preview: " + current.Reason });
                    continue;
                }

                var destination = Path.Combine(staging, planned.RelativePath);
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                var result = _redaction.Redact(File.ReadAllText(source));
                File.WriteAllText(destination, result.Text, new UTF8Encoding(false));
                finalEntries.Add(current with { RedactionCount = result.Count, SensitiveMatches = result.Matches });
            }

            var manifest = new
            {
                schemaVersion = 2,
                generatedAtUtc = DateTimeOffset.UtcNow.ToString("O"),
                sourceDirectory = "local diagnostic evidence (path intentionally omitted)",
                policy = "privacy-reviewed-local-export-v2",
                note = "Secret scan records pattern type and line only; matched secret values are never written to the manifest. Original evidence was not modified.",
                included = finalEntries.Where(x => x.Included).Select(x => new
                {
                    path = x.RelativePath,
                    redactions = x.RedactionCount,
                    sizeBytes = x.SizeBytes,
                    sensitiveMatches = (x.SensitiveMatches ?? Array.Empty<SensitiveMatch>()).Select(m => new { type = m.PatternType, line = m.LineNumber })
                }),
                excluded = finalEntries.Where(x => !x.Included).Select(x => new { path = x.RelativePath, reason = x.Reason, sizeBytes = x.SizeBytes })
            };
            File.WriteAllText(Path.Combine(staging, "export-manifest.json"), JsonSerializer.Serialize(manifest, new JsonSerializerOptions { WriteIndented = true }), new UTF8Encoding(false));

            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(zipPath))!);
            if (File.Exists(zipPath)) File.Delete(zipPath);
            ZipFile.CreateFromDirectory(staging, zipPath, CompressionLevel.Optimal, includeBaseDirectory: false);
            return new PrivacyExportResult(zipPath, finalEntries.Count(x => x.Included), finalEntries.Count(x => !x.Included),
                finalEntries.Count(x => x.Included && x.RedactionCount > 0), finalEntries.Where(x => x.Included).Sum(x => x.RedactionCount));
        }
        finally
        {
            try { Directory.Delete(staging, recursive: true); } catch { }
        }
    }

    private PrivacyExportEntry Classify(FileInfo file, string relativePath)
    {
        if (ExcludedExtensions.Contains(file.Extension))
            return new(relativePath, false, $"High-risk artefact type ({file.Extension}); excluded by default.", 0, file.Length);
        var lowerName = file.Name.ToLowerInvariant();
        if (lowerName.Contains("memory.dmp") || lowerName.Contains("credential") || lowerName.Contains("cookies") || lowerName.Contains("browser-history"))
            return new(relativePath, false, "High-risk filename; excluded by default.", 0, file.Length);
        if (!TextExtensions.Contains(file.Extension))
            return new(relativePath, false, "Unknown binary format; excluded because it cannot be privacy-scanned safely.", 0, file.Length);
        if (file.Length > MaxTextScanBytes)
            return new(relativePath, false, "Text-like file exceeds the privacy scanner size limit; excluded rather than copied blindly.", 0, file.Length);

        try
        {
            var text = File.ReadAllText(file.FullName);
            if (_redaction.ContainsPrivateKeyMaterial(text))
                return new(relativePath, false, "Private-key material detected; file excluded rather than transformed.", 0, file.Length,
                    _redaction.Scan(text).Where(x => x.PatternType == "private-key-material").ToList());
            var result = _redaction.Redact(text);
            return new(relativePath, true, null, result.Count, file.Length, result.Matches);
        }
        catch
        {
            return new(relativePath, false, "File could not be safely scanned as text; excluded by default.", 0, file.Length);
        }
    }
}
