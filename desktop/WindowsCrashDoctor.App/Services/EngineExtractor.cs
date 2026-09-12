using System.Diagnostics;
using System.Reflection;
using System.Text.Json;

namespace WindowsCrashDoctor.Services;

public sealed class EngineExtractor
{
    private const string CompletionMarkerName = ".complete";
    private const string VersionResourceName = "WCD.Engine.windows-crash-doctor.version.json";
    private static readonly Lazy<string> ResolvedEngineVersion = new(ReadEmbeddedEngineVersion);

    private static readonly IReadOnlyDictionary<string, string> Resources =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["WCD.Engine.scripts.collect-diagnostics.ps1"] = Path.Combine("scripts", "collect-diagnostics.ps1"),
            ["WCD.Engine.scripts.check-public-evidence.ps1"] = Path.Combine("scripts", "check-public-evidence.ps1"),
            ["WCD.Engine.windows-crash-doctor.CrashDoctor.psm1"] = Path.Combine("windows-crash-doctor", "CrashDoctor.psm1"),
            ["WCD.Engine.windows-crash-doctor.TelemetryAnalysis.psm1"] = Path.Combine("windows-crash-doctor", "TelemetryAnalysis.psm1"),
            ["WCD.Engine.windows-crash-doctor.DumpParser.psm1"] = Path.Combine("windows-crash-doctor", "DumpParser.psm1"),
            ["WCD.Engine.windows-crash-doctor.Invoke-CrashDoctor.ps1"] = Path.Combine("windows-crash-doctor", "Invoke-CrashDoctor.ps1"),
            ["WCD.Engine.windows-crash-doctor.DiagnosticRegistry.psm1"] = Path.Combine("windows-crash-doctor", "DiagnosticRegistry.psm1"),
            ["WCD.Engine.windows-crash-doctor.diagnostics.registry.json"] = Path.Combine("windows-crash-doctor", "diagnostics", "registry.json"),
            ["WCD.Engine.windows-crash-doctor.Integrations.psm1"] = Path.Combine("windows-crash-doctor", "Integrations.psm1"),
            ["WCD.Engine.windows-crash-doctor.Manage-Integrations.ps1"] = Path.Combine("windows-crash-doctor", "Manage-Integrations.ps1"),
            [VersionResourceName] = Path.Combine("windows-crash-doctor", "version.json"),
            ["WCD.Engine.windows-crash-doctor.integrations.catalog.json"] = Path.Combine("windows-crash-doctor", "integrations", "catalog.json")
        };

    public static string EngineVersion => ResolvedEngineVersion.Value;
    public string RootPath { get; }
    public string CollectorPath => Path.Combine(RootPath, "scripts", "collect-diagnostics.ps1");
    public string CrashDoctorPath => Path.Combine(RootPath, "windows-crash-doctor", "Invoke-CrashDoctor.ps1");
    public string TelemetryPath => Path.Combine(RootPath, "windows-crash-doctor", "TelemetryAnalysis.psm1");
    public string IntegrationManagerPath => Path.Combine(RootPath, "windows-crash-doctor", "Manage-Integrations.ps1");
    public string VersionPath => Path.Combine(RootPath, "windows-crash-doctor", "version.json");
    public string RegistryPath => Path.Combine(RootPath, "windows-crash-doctor", "diagnostics", "registry.json");

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
        if (IsCompleteEngine(RootPath)) return;

        var parent = Directory.GetParent(RootPath)?.FullName
            ?? throw new InvalidOperationException("Unable to resolve the embedded-engine parent directory.");
        Directory.CreateDirectory(parent);
        var operationId = Guid.NewGuid().ToString("N");
        var staging = Path.Combine(parent, $".stage-{EngineVersion}-{operationId}");
        var backup = Path.Combine(parent, $".backup-{EngineVersion}-{operationId}");
        Directory.CreateDirectory(staging);
        var previousMoved = false;

        try
        {
            ExtractResources(staging);
            WriteBuildInfo(staging);
            File.WriteAllText(Path.Combine(staging, CompletionMarkerName), EngineVersion);
            if (!IsCompleteEngine(staging))
                throw new InvalidOperationException("Embedded diagnostic engine staging validation failed.");

            if (Directory.Exists(RootPath))
            {
                Directory.Move(RootPath, backup);
                previousMoved = true;
            }
            Directory.Move(staging, RootPath);
            if (previousMoved) TryDeleteDirectory(backup);
        }
        catch
        {
            if (!Directory.Exists(RootPath) && previousMoved && Directory.Exists(backup))
                Directory.Move(backup, RootPath);
            throw;
        }
        finally
        {
            TryDeleteDirectory(staging);
            if (Directory.Exists(RootPath)) TryDeleteDirectory(backup);
        }
    }

    private static string ReadEmbeddedEngineVersion()
    {
        var assembly = Assembly.GetExecutingAssembly();
        using var stream = assembly.GetManifestResourceStream(VersionResourceName)
            ?? throw new InvalidOperationException("Embedded version.json resource is missing.");
        using var document = JsonDocument.Parse(stream);
        if (!document.RootElement.TryGetProperty("engineVersion", out var versionElement) || versionElement.ValueKind != JsonValueKind.String)
            throw new InvalidDataException("Embedded version.json does not define engineVersion.");
        var version = versionElement.GetString();
        if (string.IsNullOrWhiteSpace(version))
            throw new InvalidDataException("Embedded engineVersion is empty.");
        return version;
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

    private static void WriteBuildInfo(string destinationRoot)
    {
        var assembly = Assembly.GetExecutingAssembly();
        var informationalVersion = assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion ?? assembly.GetName().Version?.ToString() ?? "unknown";
        var commit = informationalVersion.Contains('+')
            ? informationalVersion[(informationalVersion.IndexOf('+') + 1)..]
            : "unknown";
        var buildInfo = new
        {
            appVersion = informationalVersion,
            engineVersion = EngineVersion,
            commit,
            extractedAtUtc = DateTimeOffset.UtcNow.ToString("O")
        };
        var path = Path.Combine(destinationRoot, "windows-crash-doctor", "build-info.json");
        File.WriteAllText(path, JsonSerializer.Serialize(buildInfo, new JsonSerializerOptions { WriteIndented = true }));
    }

    private static bool IsCompleteEngine(string root)
    {
        if (!Directory.Exists(root)) return false;
        var marker = Path.Combine(root, CompletionMarkerName);
        if (!File.Exists(marker) || !string.Equals(File.ReadAllText(marker).Trim(), EngineVersion, StringComparison.Ordinal))
            return false;
        return Resources.Values.All(relativePath => File.Exists(Path.Combine(root, relativePath)));
    }

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            if (Directory.Exists(path)) Directory.Delete(path, recursive: true);
        }
        catch (Exception ex)
        {
            Trace.WriteLine($"Embedded-engine cleanup failed for '{Path.GetFileName(path)}': {ex.Message}");
        }
    }
}
