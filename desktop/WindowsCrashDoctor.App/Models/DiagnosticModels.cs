using System.Text.Json.Serialization;
using System.Windows.Media;

namespace WindowsCrashDoctor.Models;

public sealed class CrashDoctorReport
{
    public string? SchemaVersion { get; set; }
    public DateTimeOffset? GeneratedAt { get; set; }
    public string? EvidencePath { get; set; }
    public CoverageInfo Coverage { get; set; } = new();
    public InventoryInfo Inventory { get; set; } = new();
    public EventSummaryInfo EventSummary { get; set; } = new();
    public List<DiagnosticFinding> Findings { get; set; } = new();
}

public sealed class CoverageInfo
{
    public List<string> PresentFiles { get; set; } = new();
    public List<string> MissingFiles { get; set; } = new();
    public int PresentCount { get; set; }
    public int ExpectedCount { get; set; }
    public double Percent { get; set; }
}

public sealed class InventoryInfo
{
    public string? Model { get; set; }
    public string? BIOS { get; set; }
    public double? PhysicalMemoryGiB { get; set; }
}

public sealed class EventSummaryInfo
{
    public int WHEAReferences { get; set; }
    public int KernelPower41Records { get; set; }
    public int Volmgr161Records { get; set; }
}

public sealed class DiagnosticFinding
{
    public string Id { get; set; } = "";
    public string Severity { get; set; } = "Info";
    public string Confidence { get; set; } = "Medium";
    public string Title { get; set; } = "";
    public string Evidence { get; set; } = "";
    public string Interpretation { get; set; } = "";
    public string NextStep { get; set; } = "";

    [JsonIgnore]
    public Brush SeverityBrush => Severity switch
    {
        "Critical" or "High" => new SolidColorBrush(Color.FromRgb(217, 45, 32)),
        "Medium" => new SolidColorBrush(Color.FromRgb(220, 104, 3)),
        "Low" => new SolidColorBrush(Color.FromRgb(37, 99, 235)),
        _ => new SolidColorBrush(Color.FromRgb(3, 152, 85))
    };

    [JsonIgnore]
    public Brush SeverityBackground => Severity switch
    {
        "Critical" or "High" => new SolidColorBrush(Color.FromRgb(254, 243, 242)),
        "Medium" => new SolidColorBrush(Color.FromRgb(255, 246, 232)),
        "Low" => new SolidColorBrush(Color.FromRgb(234, 241, 255)),
        _ => new SolidColorBrush(Color.FromRgb(236, 253, 243))
    };
}

public sealed class DiagnosticRunHistory
{
    public DateTimeOffset RanAt { get; set; }
    public string Status { get; set; } = "Completed";
    public string HealthLabel { get; set; } = "Unknown";
    public string EvidencePath { get; set; } = "";
    public string Model { get; set; } = "Unknown device";
    public int HighCount { get; set; }
    public int MediumCount { get; set; }
    public int FindingCount { get; set; }
    public double CoveragePercent { get; set; }

    [JsonIgnore]
    public string WhenText => RanAt.LocalDateTime.ToString("ddd d MMM, h:mm tt");

    [JsonIgnore]
    public string SummaryText => $"{FindingCount} findings • {CoveragePercent:0}% coverage";
}

public sealed class AppSettings
{
    public bool DarkMode { get; set; }
    public string? LastEvidencePath { get; set; }
}
