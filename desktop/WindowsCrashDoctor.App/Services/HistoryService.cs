using System.Text.Json;
using WindowsCrashDoctor.Models;

namespace WindowsCrashDoctor.Services;

public sealed class HistoryService
{
    private const long MaxDocumentBytes = 4 * 1024 * 1024;
    private const int MaxHistoryEntries = 30;

    private readonly string _root;
    private readonly string _historyPath;
    private readonly string _settingsPath;
    private readonly JsonSerializerOptions _json = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };

    public HistoryService()
    {
        _root = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "WindowsCrashDoctor");
        Directory.CreateDirectory(_root);
        _historyPath = Path.Combine(_root, "history.json");
        _settingsPath = Path.Combine(_root, "settings.json");
    }

    public List<DiagnosticRunHistory> LoadHistory()
    {
        if (!File.Exists(_historyPath))
            return new();

        var json = ReadBoundedDocument(_historyPath, "diagnostic history");
        using var document = JsonDocument.Parse(json);
        if (document.RootElement.ValueKind == JsonValueKind.Array)
        {
            var legacy = JsonSerializer.Deserialize<List<DiagnosticRunHistory>>(json, _json)
                ?? throw new InvalidDataException("Legacy diagnostic history was empty or invalid.");
            var migrated = ValidateHistory(legacy);
            SaveHistory(migrated);
            return migrated;
        }

        var envelope = JsonSerializer.Deserialize<HistoryDocument>(json, _json)
            ?? throw new InvalidDataException("Diagnostic history document was empty or invalid.");
        if (!string.Equals(envelope.SchemaVersion, HistoryDocument.CurrentSchemaVersion, StringComparison.Ordinal))
            throw new InvalidDataException($"Unsupported diagnostic history schema '{envelope.SchemaVersion}'.");

        return ValidateHistory(envelope.Runs);
    }

    public void AddHistory(DiagnosticRunHistory item)
    {
        ArgumentNullException.ThrowIfNull(item);
        ValidateHistoryEntry(item);

        var history = LoadHistory();
        history.Insert(0, item);
        if (history.Count > MaxHistoryEntries)
            history = history.Take(MaxHistoryEntries).ToList();
        SaveHistory(history);
    }

    public AppSettings LoadSettings()
    {
        if (!File.Exists(_settingsPath))
            return new();

        var json = ReadBoundedDocument(_settingsPath, "settings");
        using var document = JsonDocument.Parse(json);

        // v0.1 stored AppSettings directly. Migrate once into the versioned envelope.
        if (document.RootElement.ValueKind == JsonValueKind.Object &&
            !document.RootElement.TryGetProperty(nameof(SettingsDocument.SchemaVersion), out _))
        {
            var legacy = JsonSerializer.Deserialize<AppSettings>(json, _json)
                ?? throw new InvalidDataException("Legacy settings document was empty or invalid.");
            ValidateSettings(legacy);
            SaveSettings(legacy);
            return legacy;
        }

        var envelope = JsonSerializer.Deserialize<SettingsDocument>(json, _json)
            ?? throw new InvalidDataException("Settings document was empty or invalid.");
        if (!string.Equals(envelope.SchemaVersion, SettingsDocument.CurrentSchemaVersion, StringComparison.Ordinal))
            throw new InvalidDataException($"Unsupported settings schema '{envelope.SchemaVersion}'.");

        ValidateSettings(envelope.Settings);
        return envelope.Settings;
    }

    public void SaveSettings(AppSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ValidateSettings(settings);
        var document = new SettingsDocument { Settings = settings };
        WriteAtomicJson(_settingsPath, document);
    }

    private void SaveHistory(List<DiagnosticRunHistory> history)
    {
        var validated = ValidateHistory(history);
        var document = new HistoryDocument { Runs = validated };
        WriteAtomicJson(_historyPath, document);
    }

    private static List<DiagnosticRunHistory> ValidateHistory(IEnumerable<DiagnosticRunHistory>? history)
    {
        if (history is null)
            throw new InvalidDataException("Diagnostic history has no runs collection.");

        var result = history.Take(MaxHistoryEntries + 1).ToList();
        if (result.Count > MaxHistoryEntries)
            throw new InvalidDataException($"Diagnostic history exceeds the {MaxHistoryEntries}-entry limit.");

        foreach (var item in result)
            ValidateHistoryEntry(item);
        return result;
    }

    private static void ValidateHistoryEntry(DiagnosticRunHistory item)
    {
        if (item.RanAt == default)
            throw new InvalidDataException("Diagnostic history contains a run with no timestamp.");
        if (string.IsNullOrWhiteSpace(item.Status) || item.Status.Length > 100)
            throw new InvalidDataException("Diagnostic history contains an invalid status.");
        if (string.IsNullOrWhiteSpace(item.EvidencePath) || item.EvidencePath.Length > 4096)
            throw new InvalidDataException("Diagnostic history contains an invalid evidence path.");
        if (item.FindingCount < 0 || item.HighCount < 0 || item.MediumCount < 0)
            throw new InvalidDataException("Diagnostic history contains a negative finding count.");
        if (double.IsNaN(item.CoveragePercent) || item.CoveragePercent < 0 || item.CoveragePercent > 100)
            throw new InvalidDataException("Diagnostic history contains an invalid coverage percentage.");
    }

    private static void ValidateSettings(AppSettings settings)
    {
        if (settings.LastEvidencePath is { Length: > 4096 })
            throw new InvalidDataException("Last evidence path is too long.");
    }

    private static string ReadBoundedDocument(string path, string description)
    {
        var info = new FileInfo(path);
        if (info.Length > MaxDocumentBytes)
            throw new InvalidDataException($"{description} file exceeds the {MaxDocumentBytes}-byte safety limit.");
        return File.ReadAllText(path);
    }

    private void WriteAtomicJson<T>(string path, T value)
    {
        Directory.CreateDirectory(_root);
        var temp = Path.Combine(_root, $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllText(temp, JsonSerializer.Serialize(value, _json));
            using (var stream = new FileStream(temp, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                if (stream.Length == 0 || stream.Length > MaxDocumentBytes)
                    throw new IOException("Serialized persistence document has an invalid size.");
            }
            File.Move(temp, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temp))
                File.Delete(temp);
        }
    }
}
