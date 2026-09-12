using System.Reflection;

namespace WindowsCrashDoctor.Services;

public sealed class EngineExtractor
{
    private const string CompletionMarkerName = ".complete";

    private static readonly IReadOnlyDictionary<string, string> Resources =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["WCD.Engine.scripts.collect-diagnostics.ps1"] = Path.Combine("scripts", "collect-diagnostics.ps1"),
            ["WCD.Engine.scripts.check-public-evidence.ps1"] = Path.Combine("scripts", "check-public-evidence.ps1"),
            ["WCD.Engine.windows-crash-doctor.CrashDoctor.psm1"] = Path.Combine("windows-crash-doctor", "CrashDoctor.psm1"),
            ["WCD.Engine.windows-crash-doctor.DumpParser.psm1"] = Path.Combine("windows-crash-doctor", "DumpParser.psm1"),
            ["WCD.Engine.windows-crash-doctor.FindingModel.psm1"] = Path.Combine("windows-crash-doctor", "FindingModel.psm1"),
            ["WCD.Engine.windows-crash-doctor.Reporting.psm1"] = Path.Combine("windows-crash-doctor", "Reporting.psm1"),
            ["WCD.Engine.windows-crash-doctor.TelemetryAnalysis.psm1"] = Path.Combine("windows-crash-doctor", "TelemetryAnalysis.psm1"),
            ["WCD.Engine.windows-crash-doctor.Invoke-CrashDoctor.ps1"] = Path.Combine("windows-crash-doctor", "Invoke-CrashDoctor.ps1"),
            ["WCD.Engine.windows-crash-doctor.Integrations.psm1"] = Path.Combine("windows-crash-doctor", "Integrations.psm1"),
            ["WCD.Engine.windows-crash-doctor.Manage-Integrations.ps1"] = Path.Combine("windows-crash-doctor", "Manage-Integrations.ps1"),
            ["WCD.Engine.windows-crash-doctor.integrations.catalog.json"] = Path.Combine("windows-crash-doctor", "integrations", "catalog.json")
        };

    public string Version { get; }
    public string RootPath { get; }
    public string CollectorPath => Path.Combine(RootPath, "scripts", "collect-diagnostics.ps1");
    public string CrashDoctorPath => Path.Combine(RootPath, "windows-crash-doctor", "Invoke-CrashDoctor.ps1");
    public string IntegrationManagerPath => Path.Combine(RootPath, "windows-crash-doctor", "Manage-Integrations.ps1");

    public EngineExtractor()
    {
        Version = GetAssemblyVersion();
        RootPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "WindowsCrashDoctor",
            "engine",
            Version);
    }

    public void EnsureExtracted()
    {
        if (IsCompleteEngine(RootPath))
            return;

        var parent = Directory.GetParent(RootPath)?.FullName
            ?? throw new InvalidOperationException("Unable to resolve the embedded-engine parent directory.");
        Directory.CreateDirectory(parent);

        var operationId = Guid.NewGuid().ToString("N");
        var staging = Path.Combine(parent, $".stage-{Version}-{operationId}");
        var backup = Path.Combine(parent, $".backup-{Version}-{operationId}");
        Directory.CreateDirectory(staging);

        var oldMoved = false;
        try
        {
            ExtractResources(staging);
            File.WriteAllText(Path.Combine(staging, CompletionMarkerName), Version);
            if (!IsCompleteEngine(staging))
                throw new InvalidOperationException("Embedded diagnostic engine staging validation failed.");

            // Preserve the previous complete copy until the replacement is fully staged.
            if (Directory.Exists(RootPath))
            {
                Directory.Move(RootPath, backup);
                oldMoved = true;
            }

            Directory.Move(staging, RootPath);
            if (oldMoved)
                TryDeleteDirectory(backup);
        }
        catch
        {
            if (!Directory.Exists(RootPath) && oldMoved && Directory.Exists(backup))
                Directory.Move(backup, RootPath);
            throw;
        }
        finally
        {
            TryDeleteDirectory(staging);
            if (Directory.Exists(RootPath))
                TryDeleteDirectory(backup);
        }
    }

    private static string GetAssemblyVersion()
    {
        var version = Assembly.GetExecutingAssembly().GetName().Version;
        if (version is null)
            throw new InvalidOperationException("Desktop assembly version is unavailable.");
        return $"{version.Major}.{version.Minor}.{version.Build}";
    }

    private static void ExtractResources(string destinationRoot)
    {
        var assembly = Assembly.GetExecutingAssembly();
        foreach (var (resourceName, relativePath) in Resources)
        {
            using var stream = assembly.GetManifestResourceStream(resourceName)
                ?? throw new InvalidOperationException($"Embedded diagnostic resource is missing: {resourceName}");

            var destination = Path.Combine(destinationRoot, relativePath);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            using var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            stream.CopyTo(output);
            output.Flush(flushToDisk: true);
        }
    }

    private bool IsCompleteEngine(string root)
    {
        if (!Directory.Exists(root))
            return false;

        var marker = Path.Combine(root, CompletionMarkerName);
        if (!File.Exists(marker) || !string.Equals(File.ReadAllText(marker).Trim(), Version, StringComparison.Ordinal))
            return false;

        return Resources.Values.All(relativePath => File.Exists(Path.Combine(root, relativePath)));
    }

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            if (Directory.Exists(path))
                Directory.Delete(path, recursive: true);
        }
        catch
        {
            // Cleanup failure must not invalidate a complete current engine or its rollback copy.
        }
    }
}
