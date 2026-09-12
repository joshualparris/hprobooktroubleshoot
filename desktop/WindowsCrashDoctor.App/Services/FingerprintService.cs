using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using WindowsCrashDoctor.Models;

namespace WindowsCrashDoctor.Services;

public sealed class FingerprintService
{
    private static readonly Regex Whitespace = new(@"\s+", RegexOptions.Compiled);

    public string DeviceFingerprint(CrashDoctorReport report)
    {
        var material = string.Join("|", new[]
        {
            Environment.MachineName,
            report.Inventory.Model ?? "unknown-model",
            report.Inventory.BIOS ?? "unknown-bios"
        });
        return Sha256(material);
    }

    public string FindingFingerprint(DiagnosticFinding finding, string ruleVersion)
    {
        var evidence = Normalize(finding.Evidence);
        return Sha256($"{finding.Id}|{ruleVersion}|{finding.Severity}|{finding.Confidence}|{evidence}");
    }

    public string EvidenceBundleHash(string evidencePath)
    {
        using var aggregate = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        foreach (var file in Directory.EnumerateFiles(evidencePath, "*", SearchOption.AllDirectories)
                     .Where(x => !Path.GetFileName(x).StartsWith("crash-doctor-report", StringComparison.OrdinalIgnoreCase))
                     .Where(x => !Path.GetFileName(x).Equals("crash-doctor-run-metadata.json", StringComparison.OrdinalIgnoreCase))
                     .OrderBy(x => Path.GetRelativePath(evidencePath, x), StringComparer.OrdinalIgnoreCase))
        {
            var relative = Path.GetRelativePath(evidencePath, file).Replace('\\', '/');
            aggregate.AppendData(Encoding.UTF8.GetBytes(relative.ToLowerInvariant()));
            using var stream = File.OpenRead(file);
            var buffer = new byte[64 * 1024];
            int read;
            while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
                aggregate.AppendData(buffer, 0, read);
        }
        return Convert.ToHexString(aggregate.GetHashAndReset()).ToLowerInvariant();
    }

    public List<FindingSnapshot> StampFindings(CrashDoctorReport report, DiagnosticRegistry registry)
    {
        var snapshots = new List<FindingSnapshot>();
        foreach (var finding in report.Findings)
        {
            var source = InferSource(finding, report.Coverage, registry);
            var ruleVersion = source?.RuleVersion ?? report.Product.RuleSetVersion ?? "unknown";
            finding.SourceCollector = source?.Id ?? "analysis.rules";
            finding.RuleVersion = ruleVersion;
            finding.Fingerprint = FindingFingerprint(finding, ruleVersion);
            snapshots.Add(new FindingSnapshot
            {
                FindingId = finding.Id,
                Fingerprint = finding.Fingerprint,
                Severity = finding.Severity,
                Confidence = finding.Confidence,
                Title = finding.Title,
                Evidence = finding.Evidence,
                SourceCollector = finding.SourceCollector,
                RuleVersion = ruleVersion
            });
        }
        return snapshots;
    }

    private static DiagnosticDefinition? InferSource(DiagnosticFinding finding, CoverageInfo coverage, DiagnosticRegistry registry)
    {
        var id = finding.Id.ToLowerInvariant();
        string? category = id switch
        {
            var x when x.Contains("storage") || x.Contains("ssd") => "storage",
            var x when x.Contains("firmware") || x.Contains("bios") => "firmware",
            var x when x.Contains("whea") || x.Contains("kernel-power") || x.Contains("volmgr") => "events",
            var x when x.Contains("memory") || x.Contains("pagefile") || x.Contains("dump") => "memory",
            var x when x.Contains("power") || x.Contains("startup") || x.Contains("hibernate") => "power",
            _ => null
        };
        if (category is not null)
            return registry.Diagnostics.FirstOrDefault(x => string.Equals(x.Category, category, StringComparison.OrdinalIgnoreCase));
        return registry.Diagnostics.FirstOrDefault(x => coverage.PresentFiles.Contains(x.EvidenceFile, StringComparer.OrdinalIgnoreCase));
    }

    private static string Normalize(string value) => Whitespace.Replace((value ?? string.Empty).Trim(), " ").ToLowerInvariant();

    private static string Sha256(string material)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(material));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }
}
