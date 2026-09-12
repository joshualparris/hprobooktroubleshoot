using System.Reflection;

namespace WindowsCrashDoctor.Services;

public sealed class EngineExtractor
{
    private const string EngineVersion = "0.1.0";

    private static readonly IReadOnlyDictionary<string, string> Resources =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["WCD.Engine.scripts.collect-diagnostics.ps1"] = Path.Combine("scripts", "collect-diagnostics.ps1"),
            ["WCD.Engine.scripts.check-public-evidence.ps1"] = Path.Combine("scripts", "check-public-evidence.ps1"),
            ["WCD.Engine.windows-crash-doctor.CrashDoctor.psm1"] = Path.Combine("windows-crash-doctor", "CrashDoctor.psm1"),
            ["WCD.Engine.windows-crash-doctor.DumpParser.psm1"] = Path.Combine("windows-crash-doctor", "DumpParser.psm1"),
            ["WCD.Engine.windows-crash-doctor.Invoke-CrashDoctor.ps1"] = Path.Combine("windows-crash-doctor", "Invoke-CrashDoctor.ps1"),
            ["WCD.Engine.windows-crash-doctor.Integrations.psm1"] = Path.Combine("windows-crash-doctor", "Integrations.psm1"),
            ["WCD.Engine.windows-crash-doctor.Manage-Integrations.ps1"] = Path.Combine("windows-crash-doctor", "Manage-Integrations.ps1"),
            ["WCD.Engine.windows-crash-doctor.integrations.catalog.json"] = Path.Combine("windows-crash-doctor", "integrations", "catalog.json")
        };

    public string RootPath { get; }
    public string CollectorPath => Path.Combine(RootPath, "scripts", "collect-diagnostics.ps1");
    public string CrashDoctorPath => Path.Combine(RootPath, "windows-crash-doctor", "Invoke-CrashDoctor.ps1");
    public string IntegrationManagerPath => Path.Combine(RootPath, "windows-crash-doctor", "Manage-Integrations.ps1");

    public EngineExtractor()
    {
        RootPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "WindowsCrashDoctor",
            "engine",
            EngineVersion);
    }

    public void EnsureExtracted()
    {
        var assembly = Assembly.GetExecutingAssembly();
        foreach (var (resourceName, relativePath) in Resources)
        {
            using var stream = assembly.GetManifestResourceStream(resourceName)
                ?? throw new InvalidOperationException($"Embedded diagnostic resource is missing: {resourceName}");

            var destination = Path.Combine(RootPath, relativePath);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            using var output = File.Create(destination);
            stream.CopyTo(output);
        }
    }
}
