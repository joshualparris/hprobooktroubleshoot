using System.Text.Json;
using WindowsCrashDoctor.Models;

namespace WindowsCrashDoctor.Services;

public sealed class CrashDoctorReportReader
{
    private const long MaxReportBytes = 16 * 1024 * 1024;
    private const int MaxFindings = 5000;
    private static readonly HashSet<string> AllowedSeverities = new(StringComparer.Ordinal)
    {
        "Critical", "High", "Medium", "Low", "Info"
    };
    private static readonly HashSet<string> AllowedConfidences = new(StringComparer.Ordinal)
    {
        "High", "Medium", "Low"
    };

    private readonly EngineExtractor _engine;
    private readonly JsonSerializerOptions _json = new() { PropertyNameCaseInsensitive = true };

    public CrashDoctorReportReader(EngineExtractor engine) => _engine = engine;

    public async Task<CrashDoctorReport> ReadAsync(string reportPath, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(reportPath);
        var info = new FileInfo(reportPath);
        if (!info.Exists)
            throw new FileNotFoundException("Crash Doctor JSON report was not created.", reportPath);
        if (info.Length <= 0 || info.Length > MaxReportBytes)
            throw new InvalidDataException($"Crash Doctor JSON report size is outside the allowed 1-{MaxReportBytes} byte range.");

        CrashDoctorReport report;
        try
        {
            await using var stream = new FileStream(reportPath, FileMode.Open, FileAccess.Read, FileShare.Read, 64 * 1024, useAsync: true);
            report = await JsonSerializer.DeserializeAsync<CrashDoctorReport>(stream, _json, cancellationToken)
                ?? throw new InvalidDataException("Crash Doctor JSON report was empty.");
        }
        catch (JsonException ex)
        {
            throw new InvalidDataException("Crash Doctor JSON report is malformed.", ex);
        }

        Validate(report, GetExpectedSchemaVersion());
        return report;
    }

    private string GetExpectedSchemaVersion()
    {
        _engine.EnsureExtracted();
        var info = new FileInfo(_engine.VersionPath);
        if (!info.Exists || info.Length <= 0 || info.Length > 64 * 1024)
            throw new InvalidDataException("Embedded engine version metadata is missing or invalid.");

        using var document = JsonDocument.Parse(File.ReadAllText(info.FullName));
        if (!document.RootElement.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.String)
            throw new InvalidDataException("Embedded engine version metadata does not define schemaVersion.");
        return schema.GetString() ?? throw new InvalidDataException("Embedded engine schemaVersion is empty.");
    }

    private static void Validate(CrashDoctorReport report, string expectedSchemaVersion)
    {
        if (!string.Equals(report.SchemaVersion, expectedSchemaVersion, StringComparison.Ordinal))
            throw new InvalidDataException($"Unsupported report schema '{report.SchemaVersion ?? "missing"}'; expected '{expectedSchemaVersion}'.");
        if (!string.IsNullOrWhiteSpace(report.Product.SchemaVersion) &&
            !string.Equals(report.Product.SchemaVersion, report.SchemaVersion, StringComparison.Ordinal))
            throw new InvalidDataException("Report and product schema versions disagree.");

        if (report.Coverage.PresentCount < 0 || report.Coverage.ExpectedCount < 0 ||
            report.Coverage.PresentCount > report.Coverage.ExpectedCount ||
            double.IsNaN(report.Coverage.Percent) || double.IsInfinity(report.Coverage.Percent) ||
            report.Coverage.Percent is < 0 or > 100)
            throw new InvalidDataException("Report coverage fields are outside valid bounds.");

        if (report.Findings.Count > MaxFindings)
            throw new InvalidDataException($"Report contains more than {MaxFindings} findings.");

        var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var finding in report.Findings)
        {
            if (string.IsNullOrWhiteSpace(finding.Id) || finding.Id.Length > 200 || !ids.Add(finding.Id))
                throw new InvalidDataException("Report contains a missing, oversized or duplicate finding ID.");
            if (string.IsNullOrWhiteSpace(finding.Title) || finding.Title.Length > 2000)
                throw new InvalidDataException($"Finding '{finding.Id}' has an invalid title.");
            if (!AllowedSeverities.Contains(finding.Severity))
                throw new InvalidDataException($"Finding '{finding.Id}' has unsupported severity '{finding.Severity}'.");
            if (!AllowedConfidences.Contains(finding.Confidence))
                throw new InvalidDataException($"Finding '{finding.Id}' has unsupported confidence '{finding.Confidence}'.");
        }

        if (report.Inventory.PhysicalMemoryGiB is double memory &&
            (double.IsNaN(memory) || double.IsInfinity(memory) || memory < 0 || memory > 16384))
            throw new InvalidDataException("Report physical-memory value is outside plausible bounds.");
    }
}
