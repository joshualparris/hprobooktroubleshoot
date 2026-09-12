using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using WindowsCrashDoctor.Models;

namespace WindowsCrashDoctor.Services;

public sealed class ReportEnrichmentService
{
    private const long MaxReportBytes = 16 * 1024 * 1024;
    private const long MaxMarkdownBytes = 32 * 1024 * 1024;
    private readonly JsonSerializerOptions _json = new() { WriteIndented = true };

    public void Enrich(
        string jsonPath,
        string markdownPath,
        RunMetadata run,
        PreflightReport preflight,
        IReadOnlyList<CollectorExecutionRecord> executions,
        RunComparisonSummary comparison,
        DiagnosticRegistry registry,
        IReadOnlyList<DiagnosticFinding> findings)
    {
        ValidateInputFile(jsonPath, MaxReportBytes, "Crash Doctor JSON report");
        var root = JsonNode.Parse(File.ReadAllText(jsonPath))?.AsObject()
            ?? throw new InvalidDataException("Crash Doctor JSON report could not be enriched because it is not an object.");

        root["Run"] = JsonSerializer.SerializeToNode(run, _json);
        root["Preflight"] = JsonSerializer.SerializeToNode(preflight, _json);
        root["CollectorExecutions"] = JsonSerializer.SerializeToNode(executions, _json);
        root["Comparison"] = JsonSerializer.SerializeToNode(comparison, _json);
        root["DiagnosticRegistry"] = JsonSerializer.SerializeToNode(new RegistryProvenance
        {
            RegistryVersion = registry.RegistryVersion,
            SchemaVersion = registry.SchemaVersion,
            DiagnosticCount = registry.Diagnostics.Count
        }, _json);

        if (root["Findings"] is JsonArray findingArray)
        {
            var byId = findings.ToDictionary(x => x.Id, StringComparer.OrdinalIgnoreCase);
            foreach (var node in findingArray.OfType<JsonObject>())
            {
                var id = node["Id"]?.GetValue<string>() ?? node["id"]?.GetValue<string>();
                if (id is null || !byId.TryGetValue(id, out var finding)) continue;
                node["Fingerprint"] = finding.Fingerprint;
                node["RuleVersion"] = finding.RuleVersion;
                node["SourceCollector"] = finding.SourceCollector;
                node["ComparisonState"] = finding.ComparisonState;
            }
        }
        WriteTextAtomically(jsonPath, root.ToJsonString(_json));

        var marker = $"<!-- WCD-V2-RUN:{run.RunId} -->";
        var markdown = File.Exists(markdownPath) ? ReadBoundedText(markdownPath, MaxMarkdownBytes, "Crash Doctor Markdown report") : "# Windows Crash Doctor report";
        if (markdown.Contains(marker, StringComparison.Ordinal)) return;

        var lines = new StringBuilder(markdown);
        lines.AppendLine().AppendLine();
        lines.AppendLine(marker);
        lines.AppendLine("## Run comparison and evidence provenance");
        lines.AppendLine();
        lines.AppendLine($"- **Run:** `{run.RunId}`");
        lines.AppendLine($"- **Status:** {run.Status}");
        lines.AppendLine($"- **Duration:** {TimeSpan.FromMilliseconds(run.DurationMs):g}");
        lines.AppendLine($"- **Preflight:** {preflight.OverallState} ({preflight.DegradedCount} degraded/not-configured check(s))");
        lines.AppendLine($"- **Diagnostic registry:** {registry.RegistryVersion} ({registry.Diagnostics.Count} definitions)");
        lines.AppendLine($"- **Evidence bundle fingerprint:** `{run.EvidenceBundleHash}`");
        lines.AppendLine($"- **Comparison trust:** {comparison.Trust}");
        lines.AppendLine($"- **Change summary:** {comparison.SummaryText}");

        var missing = executions.Where(x => x.Status != "completed").ToList();
        if (missing.Count > 0)
        {
            lines.AppendLine().AppendLine("### Incomplete/degraded evidence").AppendLine();
            foreach (var item in missing)
                lines.AppendLine($"- **{Escape(item.Name)}:** {Escape(item.Status)}{(string.IsNullOrWhiteSpace(item.FailureReason) ? "" : " — " + Escape(item.FailureReason))}");
        }

        if (comparison.Items.Count > 0)
        {
            lines.AppendLine().AppendLine("### Changes since the previous comparable run").AppendLine();
            lines.AppendLine("| State | Finding | Explanation |");
            lines.AppendLine("|---|---|---|");
            foreach (var item in comparison.Items.OrderBy(x => StateOrder(x.State)).ThenBy(x => x.Title, StringComparer.OrdinalIgnoreCase))
                lines.AppendLine($"| **{Escape(item.State)}** | {Escape(item.Title)} | {Escape(item.Explanation ?? "")} |");
        }
        lines.AppendLine().AppendLine("> A comparison describes evidence differences between snapshots. It does not prove that a changed item caused or fixed a crash.");
        WriteTextAtomically(markdownPath, lines.ToString());
    }

    private static void ValidateInputFile(string path, long maxBytes, string description)
    {
        var info = new FileInfo(path);
        if (!info.Exists || info.Length <= 0 || info.Length > maxBytes)
            throw new InvalidDataException($"{description} is missing, empty or above the {maxBytes}-byte limit.");
    }

    private static string ReadBoundedText(string path, long maxBytes, string description)
    {
        ValidateInputFile(path, maxBytes, description);
        return File.ReadAllText(path);
    }

    private static void WriteTextAtomically(string path, string content)
    {
        var directory = Path.GetDirectoryName(Path.GetFullPath(path))
            ?? throw new InvalidOperationException("Report output directory could not be resolved.");
        Directory.CreateDirectory(directory);
        var tempPath = Path.Combine(directory, $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
        try
        {
            using (var stream = new FileStream(tempPath, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            using (var writer = new StreamWriter(stream, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false)))
            {
                writer.Write(content);
                writer.Flush();
                stream.Flush(flushToDisk: true);
            }
            File.Move(tempPath, path, overwrite: true);
        }
        finally
        {
            try
            {
                if (File.Exists(tempPath)) File.Delete(tempPath);
            }
            catch (Exception ex)
            {
                Trace.WriteLine($"Report temporary-file cleanup failed: {ex.Message}");
            }
        }
    }

    private static int StateOrder(string state) => state switch
    {
        "WORSENED" => 0,
        "NEW" => 1,
        "IMPROVED" => 2,
        "RESOLVED" => 3,
        "UNKNOWN" => 4,
        _ => 5
    };

    private static string Escape(string value) => value.Replace("|", "\\|").Replace("\r", " ").Replace("\n", " ");
}
