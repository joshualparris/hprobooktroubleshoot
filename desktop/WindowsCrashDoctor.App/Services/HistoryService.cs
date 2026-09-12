using System.Text.Json;
using WindowsCrashDoctor.Models;

namespace WindowsCrashDoctor.Services;

public sealed class HistoryService
{
    private readonly string _root;
    private readonly string _historyPath;
    private readonly string _settingsPath;
    private readonly JsonSerializerOptions _json = new() { WriteIndented = true };

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
        try
        {
            if (!File.Exists(_historyPath)) return new();
            return JsonSerializer.Deserialize<List<DiagnosticRunHistory>>(File.ReadAllText(_historyPath), _json) ?? new();
        }
        catch
        {
            return new();
        }
    }

    public void AddHistory(DiagnosticRunHistory item)
    {
        var history = LoadHistory();
        history.Insert(0, item);
        if (history.Count > 30)
            history = history.Take(30).ToList();
        File.WriteAllText(_historyPath, JsonSerializer.Serialize(history, _json));
    }

    public AppSettings LoadSettings()
    {
        try
        {
            if (!File.Exists(_settingsPath)) return new();
            return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(_settingsPath), _json) ?? new();
        }
        catch
        {
            return new();
        }
    }

    public void SaveSettings(AppSettings settings) =>
        File.WriteAllText(_settingsPath, JsonSerializer.Serialize(settings, _json));
}
