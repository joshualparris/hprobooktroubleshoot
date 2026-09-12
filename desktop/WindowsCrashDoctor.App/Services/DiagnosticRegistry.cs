using System.Text.Json;

namespace WindowsCrashDoctor.Services;

public sealed class DiagnosticRegistry
{
    public string SchemaVersion { get; set; } = "1.0";
    public string RegistryVersion { get; set; } = "unknown";
    public List<DiagnosticDefinition> Diagnostics { get; set; } = new();

    public IReadOnlyList<string> ExpectedEvidenceFiles => Diagnostics
        .Select(x => x.EvidenceFile)
        .Where(x => !string.IsNullOrWhiteSpace(x))
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .ToList();

    public static DiagnosticRegistry Load(string path)
    {
        if (!File.Exists(path))
            throw new FileNotFoundException("Crash Doctor diagnostic registry is missing.", path);

        var registry = JsonSerializer.Deserialize<DiagnosticRegistry>(File.ReadAllText(path), new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        }) ?? throw new InvalidOperationException("Crash Doctor diagnostic registry is empty or invalid.");

        if (string.IsNullOrWhiteSpace(registry.RegistryVersion))
            throw new InvalidOperationException("Crash Doctor diagnostic registry has no registryVersion.");
        if (registry.Diagnostics.Count == 0)
            throw new InvalidOperationException("Crash Doctor diagnostic registry contains no diagnostics.");

        var duplicateIds = registry.Diagnostics
            .GroupBy(x => x.Id, StringComparer.OrdinalIgnoreCase)
            .Where(x => string.IsNullOrWhiteSpace(x.Key) || x.Count() > 1)
            .Select(x => string.IsNullOrWhiteSpace(x.Key) ? "(blank)" : x.Key)
            .ToList();
        if (duplicateIds.Count > 0)
            throw new InvalidOperationException("Diagnostic registry IDs must be unique: " + string.Join(", ", duplicateIds));

        foreach (var item in registry.Diagnostics)
        {
            if (string.IsNullOrWhiteSpace(item.Name) || string.IsNullOrWhiteSpace(item.Category) || string.IsNullOrWhiteSpace(item.EvidenceFile))
                throw new InvalidOperationException($"Diagnostic '{item.Id}' is missing required metadata.");
            if (item.DefaultTimeoutSeconds <= 0)
                throw new InvalidOperationException($"Diagnostic '{item.Id}' has an invalid timeout.");
        }

        return registry;
    }

    public DiagnosticDefinition? FindByEvidenceFile(string fileName) => Diagnostics.FirstOrDefault(
        x => string.Equals(x.EvidenceFile, fileName, StringComparison.OrdinalIgnoreCase));
}

public sealed class DiagnosticDefinition
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Description { get; set; } = "";
    public string Category { get; set; } = "system";
    public string EvidenceFile { get; set; } = "";
    public bool RequiresAdmin { get; set; }
    public int DefaultTimeoutSeconds { get; set; } = 30;
    public string RetryPolicy { get; set; } = "none";
    public string Sensitivity { get; set; } = "standard";
    public string FailureMode { get; set; } = "degradable";
    public string RuleVersion { get; set; } = "1";
}
