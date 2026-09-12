using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using WindowsCrashDoctor.Models;

namespace WindowsCrashDoctor.Services;

public sealed class ReportEnrichmentService
{
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
        var root = JsonNode.Parse(File.ReadAllText(jsonPath))?.AsObject()
            ?? throw new InvalidOperationException("Crash Doctor JSON report could not be enriched because it is not an object.");

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
        File.WriteAllText(jsonPath, root.ToJsonString(_json));

        var marker = $"<!-- WCD-V2-RUN:{run.RunId} -->";
        var markdown = File.Exists(markdownPath) ? File.ReadAllText(markdownPath) : "# Windows Crash Doctor report";
        if (markdown.Contains(marker, StringComparison.Ordinal)) return;

        var lines = new StringBuilder();
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
                lines.AppendLine($"- **{item.Name}:** {item.Status}{(string.IsNullOrWhiteSpace(item.FailureReason) ? "" : " — " + item.FailureReason)}");
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
        File.AppendAllText(markdownPath, lines.ToString());
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
