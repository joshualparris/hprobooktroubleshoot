using System.Text.Json;
using WindowsCrashDoctor.Models;

namespace WindowsCrashDoctor.Services;

public sealed class CrashDoctorReportReader
{
    private const long MaxReportBytes = 16 * 1024 * 1024;
    private const int MaxFindings = 10_000;
    private static readonly HashSet<string> SupportedSchemaVersions = new(StringComparer.Ordinal)
    {
        "1.0",
        "1.1"
    };
    private static readonly HashSet<string> SupportedSeverities = new(StringComparer.OrdinalIgnoreCase)
    {
        "Critical",
        "High",
        "Medium",
        "Low",
        "Info"
    };

    private readonly JsonSerializerOptions _json = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public async Task<CrashDoctorReport> ReadAsync(string reportPath, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(reportPath);
        var info = new FileInfo(reportPath);
        if (!info.Exists)
            throw new FileNotFoundException("Crash Doctor JSON report was not created.", reportPath);
        if (info.Length == 0 || info.Length > MaxReportBytes)
            throw new InvalidDataException($"Crash Doctor JSON report has an invalid size: {info.Length} bytes.");

        await using var stream = new FileStream(reportPath, FileMode.Open, FileAccess.Read, FileShare.Read);
        var report = await JsonSerializer.DeserializeAsync<CrashDoctorReport>(stream, _json, cancellationToken)
            ?? throw new InvalidDataException("Crash Doctor JSON report was empty or invalid.");
        Validate(report);
        return report;
    }

    public static void Validate(CrashDoctorReport report)
    {
        ArgumentNullException.ThrowIfNull(report);
        if (string.IsNullOrWhiteSpace(report.SchemaVersion) || !SupportedSchemaVersions.Contains(report.SchemaVersion))
            throw new InvalidDataException($"Unsupported Crash Doctor report schema '{report.SchemaVersion ?? "(missing)"}'.");
        if (report.GeneratedAt is null)
            throw new InvalidDataException("Crash Doctor report is missing GeneratedAt.");
        if (string.IsNullOrWhiteSpace(report.EvidencePath) || report.EvidencePath.Length > 4096)
            throw new InvalidDataException("Crash Doctor report has an invalid EvidencePath.");

        if (report.Coverage.ExpectedCount < 0 || report.Coverage.PresentCount < 0 ||
            report.Coverage.PresentCount > report.Coverage.ExpectedCount)
            throw new InvalidDataException("Crash Doctor report has inconsistent coverage counts.");
        if (double.IsNaN(report.Coverage.Percent) || report.Coverage.Percent < 0 || report.Coverage.Percent > 100)
            throw new InvalidDataException("Crash Doctor report has an invalid coverage percentage.");

        if (report.Findings.Count > MaxFindings)
            throw new InvalidDataException($"Crash Doctor report exceeds the {MaxFindings}-finding safety limit.");

        var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var finding in report.Findings)
        {
            if (string.IsNullOrWhiteSpace(finding.Id) || finding.Id.Length > 200)
                throw new InvalidDataException("Crash Doctor report contains a finding with an invalid ID.");
            if (!ids.Add(finding.Id))
                throw new InvalidDataException($"Crash Doctor report contains duplicate finding ID '{finding.Id}'.");
            if (!SupportedSeverities.Contains(finding.Severity))
                throw new InvalidDataException($"Crash Doctor report contains unsupported severity '{finding.Severity}'.");
            ValidateText(finding.Title, 1000, "finding title");
            ValidateText(finding.Evidence, 16_384, "finding evidence");
            ValidateText(finding.Interpretation, 16_384, "finding interpretation");
            ValidateText(finding.NextStep, 16_384, "finding next step");
        }
    }

    private static void ValidateText(string? value, int maxLength, string field)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length > maxLength)
            throw new InvalidDataException($"Crash Doctor report contains an invalid {field}.");
    }
}
