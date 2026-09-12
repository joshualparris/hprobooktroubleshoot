using System.Reflection;
using System.Text.Json;

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
            ["WCD.Engine.windows-crash-doctor.TelemetryAnalysis.psm1"] = Path.Combine("windows-crash-doctor", "TelemetryAnalysis.psm1"),
            ["WCD.Engine.windows-crash-doctor.DumpParser.psm1"] = Path.Combine("windows-crash-doctor", "DumpParser.psm1"),
            ["WCD.Engine.windows-crash-doctor.FindingModel.psm1"] = Path.Combine("windows-crash-doctor", "FindingModel.psm1"),
            ["WCD.Engine.windows-crash-doctor.Reporting.psm1"] = Path.Combine("windows-crash-doctor", "Reporting.psm1"),
            ["WCD.Engine.windows-crash-doctor.Invoke-CrashDoctor.ps1"] = Path.Combine("windows-crash-doctor", "Invoke-CrashDoctor.ps1"),
            ["WCD.Engine.windows-crash-doctor.Integrations.psm1"] = Path.Combine("windows-crash-doctor", "Integrations.psm1"),
            ["WCD.Engine.windows-crash-doctor.Manage-Integrations.ps1"] = Path.Combine("windows-crash-doctor", "Manage-Integrations.ps1"),
            ["WCD.Engine.windows-crash-doctor.version.json"] = Path.Combine("windows-crash-doctor", "version.json"),
            ["WCD.Engine.windows-crash-doctor.integrations.catalog.json"] = Path.Combine("windows-crash-doctor", "integrations", "catalog.json")
        };

    private readonly string _buildIdentity;

    public string EngineVersion { get; }
    public string RootPath { get; }
    public string CollectorPath => Path.Combine(RootPath, "scripts", "collect-diagnostics.ps1");
    public string CrashDoctorPath => Path.Combine(RootPath, "windows-crash-doctor", "Invoke-CrashDoctor.ps1");
    public string TelemetryPath => Path.Combine(RootPath, "windows-crash-doctor", "TelemetryAnalysis.psm1");
    public string IntegrationManagerPath => Path.Combine(RootPath, "windows-crash-doctor", "Manage-Integrations.ps1");
    public string VersionPath => Path.Combine(RootPath, "windows-crash-doctor", "version.json");

    public EngineExtractor()
    {
        var version = ReadEmbeddedVersionManifest();
        EngineVersion = version.EngineVersion;

        var assembly = Assembly.GetExecutingAssembly();
        var informationalVersion = assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion ?? assembly.GetName().Version?.ToString() ?? "unknown";
        _buildIdentity = $"{EngineVersion}|{informationalVersion}";

        RootPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "WindowsCrashDoctor",
            "engine",
            EngineVersion);
    }

    public void EnsureExtracted()
    {
        if (IsCompleteEngine(RootPath))
            return;

        var parent = Directory.GetParent(RootPath)?.FullName
            ?? throw new InvalidOperationException("Unable to resolve the embedded-engine parent directory.");
        Directory.CreateDirectory(parent);

        var operationId = Guid.NewGuid().ToString("N");
        var staging = Path.Combine(parent, $".stage-{EngineVersion}-{operationId}");
        var backup = Path.Combine(parent, $".backup-{EngineVersion}-{operationId}");
        Directory.CreateDirectory(staging);

        var oldMoved = false;
        try
        {
            ExtractResources(staging);
            WriteBuildInfo(staging);
            File.WriteAllText(Path.Combine(staging, CompletionMarkerName), _buildIdentity);

            if (!IsCompleteEngine(staging))
                throw new InvalidOperationException("Embedded diagnostic engine staging validation failed.");

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

    private static (string ProductVersion, string EngineVersion, string SchemaVersion) ReadEmbeddedVersionManifest()
    {
        var assembly = Assembly.GetExecutingAssembly();
        using var stream = assembly.GetManifestResourceStream("WCD.Engine.windows-crash-doctor.version.json")
            ?? throw new InvalidOperationException("Embedded Windows Crash Doctor version manifest is missing.");
        using var document = JsonDocument.Parse(stream);
        var root = document.RootElement;

        static string RequiredString(JsonElement element, string name)
        {
            if (!element.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.String)
                throw new InvalidOperationException($"Embedded version manifest is missing '{name}'.");
            var text = value.GetString();
            if (string.IsNullOrWhiteSpace(text))
                throw new InvalidOperationException($"Embedded version manifest has an empty '{name}'.");
            return text;
        }

        return (
            RequiredString(root, "productVersion"),
            RequiredString(root, "engineVersion"),
            RequiredString(root, "schemaVersion"));
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

    private void WriteBuildInfo(string destinationRoot)
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
        var buildInfoPath = Path.Combine(destinationRoot, "windows-crash-doctor", "build-info.json");
        File.WriteAllText(buildInfoPath, JsonSerializer.Serialize(buildInfo, new JsonSerializerOptions { WriteIndented = true }));
    }

    private bool IsCompleteEngine(string root)
    {
        if (!Directory.Exists(root))
            return false;

        var marker = Path.Combine(root, CompletionMarkerName);
        if (!File.Exists(marker) || !string.Equals(File.ReadAllText(marker).Trim(), _buildIdentity, StringComparison.Ordinal))
            return false;

        if (!Resources.Values.All(relativePath => File.Exists(Path.Combine(root, relativePath))))
            return false;

        return File.Exists(Path.Combine(root, "windows-crash-doctor", "build-info.json"));
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
