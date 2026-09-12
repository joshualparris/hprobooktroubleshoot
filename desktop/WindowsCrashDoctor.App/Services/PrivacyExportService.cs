using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace WindowsCrashDoctor.Services;

public sealed record PrivacyExportEntry(
    string RelativePath,
    bool Included,
    string? Reason,
    int RedactionCount,
    long SizeBytes);

public sealed record PrivacyExportPlan(
    string SourceDirectory,
    IReadOnlyList<PrivacyExportEntry> Entries)
{
    public int IncludedCount => Entries.Count(x => x.Included);
    public int ExcludedCount => Entries.Count(x => !x.Included);
    public int RedactedFileCount => Entries.Count(x => x.Included && x.RedactionCount > 0);
    public int TotalRedactions => Entries.Sum(x => x.RedactionCount);
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

    private static readonly (Regex Pattern, string Replacement, string Label)[] Redactors =
    {
        (new Regex(@"(?<!\d)(?:\d{6}-){7}\d{6}(?!\d)", RegexOptions.Compiled), "[REDACTED_BITLOCKER_RECOVERY_PASSWORD]", "BitLocker recovery password"),
        (new Regex(@"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", RegexOptions.Compiled | RegexOptions.IgnoreCase), "[REDACTED_PRIVATE_KEY]", "private key"),
        (new Regex(@"\bgh[pousr]_[A-Za-z0-9_]{20,}\b", RegexOptions.Compiled), "[REDACTED_GITHUB_TOKEN]", "GitHub token"),
        (new Regex(@"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b", RegexOptions.Compiled), "[REDACTED_JWT]", "JWT"),
        (new Regex(@"(?i)\b(Authorization\s*:\s*Bearer\s+)[A-Za-z0-9._~+/-]{12,}={0,2}", RegexOptions.Compiled), "$1[REDACTED_TOKEN]", "bearer token"),
        (new Regex(@"(?i)\b(password|passwd|pwd|api[_-]?key|access[_-]?token|refresh[_-]?token|secret)\b(\s*[:=]\s*)([^\s,;\"']+)", RegexOptions.Compiled), "$1$2[REDACTED_SECRET]", "credential-like value"),
        (new Regex(@"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", RegexOptions.Compiled), "[REDACTED_EMAIL]", "email address"),
        (new Regex(@"(?i)\b[A-Z]:\\Users\\[^\\\r\n\t\"']+", RegexOptions.Compiled), @"C:\Users\[REDACTED_USER]", "Windows user path"),
        (new Regex(@"(?i)\b(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}\b", RegexOptions.Compiled), "[REDACTED_MAC]", "MAC address")
    };

    public PrivacyExportPlan CreatePlan(string sourceDirectory)
    {
        if (!Directory.Exists(sourceDirectory))
            throw new DirectoryNotFoundException(sourceDirectory);

        var entries = new List<PrivacyExportEntry>();
        foreach (var file in Directory.EnumerateFiles(sourceDirectory, "*", SearchOption.AllDirectories))
        {
            var info = new FileInfo(file);
            var relative = Path.GetRelativePath(sourceDirectory, file);
            var classification = Classify(info, relative);
            entries.Add(classification);
        }

        return new PrivacyExportPlan(sourceDirectory, entries.OrderBy(x => x.RelativePath, StringComparer.OrdinalIgnoreCase).ToList());
    }

    public PrivacyExportResult Export(PrivacyExportPlan plan, string zipPath)
    {
        var sourceRoot = Path.GetFullPath(plan.SourceDirectory);
        if (!Directory.Exists(sourceRoot))
            throw new DirectoryNotFoundException(sourceRoot);

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

                if (!planned.Included)
                {
                    finalEntries.Add(planned);
                    continue;
                }

                var destination = Path.Combine(staging, planned.RelativePath);
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);

                if (IsTextFile(source))
                {
                    var text = File.ReadAllText(source);
                    var redacted = Redact(text, out var redactionCount);
                    File.WriteAllText(destination, redacted, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
                    finalEntries.Add(planned with { RedactionCount = redactionCount });
                }
                else
                {
                    File.Copy(source, destination, overwrite: true);
                    finalEntries.Add(planned);
                }
            }

            var manifest = new
            {
                schemaVersion = 1,
                generatedAtUtc = DateTimeOffset.UtcNow.ToString("O"),
                sourceDirectory = "local diagnostic evidence (path intentionally omitted)",
                policy = "privacy-reviewed-local-export-v1",
                note = "This ZIP is a derivative. Original evidence was not modified.",
                included = finalEntries.Where(x => x.Included).Select(x => new { path = x.RelativePath, redactions = x.RedactionCount, sizeBytes = x.SizeBytes }),
                excluded = finalEntries.Where(x => !x.Included).Select(x => new { path = x.RelativePath, reason = x.Reason, sizeBytes = x.SizeBytes })
            };
            File.WriteAllText(
                Path.Combine(staging, "export-manifest.json"),
                JsonSerializer.Serialize(manifest, new JsonSerializerOptions { WriteIndented = true }),
                new UTF8Encoding(false));

            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(zipPath))!);
            if (File.Exists(zipPath)) File.Delete(zipPath);
            ZipFile.CreateFromDirectory(staging, zipPath, CompressionLevel.Optimal, includeBaseDirectory: false);

            return new PrivacyExportResult(
                zipPath,
                finalEntries.Count(x => x.Included),
                finalEntries.Count(x => !x.Included),
                finalEntries.Count(x => x.Included && x.RedactionCount > 0),
                finalEntries.Where(x => x.Included).Sum(x => x.RedactionCount));
        }
        finally
        {
            try { Directory.Delete(staging, recursive: true); } catch { }
        }
    }

    private static PrivacyExportEntry Classify(FileInfo file, string relativePath)
    {
        if (ExcludedExtensions.Contains(file.Extension))
            return new PrivacyExportEntry(relativePath, false, $"High-risk artefact type ({file.Extension}); excluded by default.", 0, file.Length);

        var lowerName = file.Name.ToLowerInvariant();
        if (lowerName.Contains("memory.dmp") || lowerName.Contains("credential") || lowerName.Contains("cookies") || lowerName.Contains("browser-history"))
            return new PrivacyExportEntry(relativePath, false, "High-risk filename; excluded by default.", 0, file.Length);

        if (IsTextFile(file.FullName))
        {
            try
            {
                if (file.Length > MaxTextScanBytes)
                    return new PrivacyExportEntry(relativePath, false, "Text-like file exceeds the privacy scanner size limit; excluded rather than copied blindly.", 0, file.Length);

                var text = File.ReadAllText(file.FullName);
                _ = Redact(text, out var redactionCount);
                return new PrivacyExportEntry(relativePath, true, null, redactionCount, file.Length);
            }
            catch
            {
                return new PrivacyExportEntry(relativePath, false, "File could not be safely scanned as text; excluded by default.", 0, file.Length);
            }
        }

        // Unknown binary formats can carry opaque identifiers/secrets. The safe export is opt-out rather than optimistic.
        return new PrivacyExportEntry(relativePath, false, "Unknown binary format; excluded because it cannot be privacy-scanned safely.", 0, file.Length);
    }

    private static bool IsTextFile(string path) => TextExtensions.Contains(Path.GetExtension(path));

    private static string Redact(string input, out int count)
    {
        count = 0;
        var output = input;
        foreach (var (pattern, replacement, _) in Redactors)
        {
            var matches = pattern.Matches(output).Count;
            if (matches == 0) continue;
            output = pattern.Replace(output, replacement);
            count += matches;
        }
        return output;
    }
}
