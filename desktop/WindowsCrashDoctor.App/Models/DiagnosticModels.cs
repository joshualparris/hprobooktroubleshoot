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
}

public sealed class AppSettings
{
    public bool DarkMode { get; set; }
    public string? LastEvidencePath { get; set; }
}

public sealed class HistoryDocument
{
    public const string CurrentSchemaVersion = "1.0";
    public string SchemaVersion { get; set; } = CurrentSchemaVersion;
    public List<DiagnosticRunHistory> Runs { get; set; } = new();
}

public sealed class SettingsDocument
{
    public const string CurrentSchemaVersion = "1.0";
    public string SchemaVersion { get; set; } = CurrentSchemaVersion;
    public AppSettings Settings { get; set; } = new();
}

public sealed class CollectionStatus
{
    public string? SchemaVersion { get; set; }
    public string? CollectionId { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
    public bool CompletedWithErrors { get; set; }
    public int FailureCount { get; set; }
    public List<CollectionFailure> Failures { get; set; } = new();
}

public sealed class CollectionFailure
{
    public string Stage { get; set; } = "";
    public string Message { get; set; } = "";
}
