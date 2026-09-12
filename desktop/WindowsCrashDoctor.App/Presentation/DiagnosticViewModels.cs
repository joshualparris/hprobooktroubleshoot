using System.Windows.Media;
using WindowsCrashDoctor.Models;

namespace WindowsCrashDoctor.Presentation;

public sealed class DiagnosticFindingViewModel
{
    private DiagnosticFindingViewModel(DiagnosticFinding finding)
    {
        Id = finding.Id;
        Severity = finding.Severity;
        Confidence = finding.Confidence;
        Title = finding.Title;
        Evidence = finding.Evidence;
        Interpretation = finding.Interpretation;
        NextStep = finding.NextStep;
    }

    public string Id { get; }
    public string Severity { get; }
    public string Confidence { get; }
    public string Title { get; }
    public string Evidence { get; }
    public string Interpretation { get; }
    public string NextStep { get; }

    public Brush SeverityBrush => Severity switch
    {
        "Critical" or "High" => new SolidColorBrush(Color.FromRgb(180, 35, 24)),
        "Medium" => new SolidColorBrush(Color.FromRgb(180, 83, 0)),
        "Low" => new SolidColorBrush(Color.FromRgb(29, 78, 216)),
        _ => new SolidColorBrush(Color.FromRgb(2, 122, 72))
    };

    public Brush SeverityBackground => Severity switch
    {
        "Critical" or "High" => new SolidColorBrush(Color.FromRgb(254, 243, 242)),
        "Medium" => new SolidColorBrush(Color.FromRgb(255, 246, 232)),
        "Low" => new SolidColorBrush(Color.FromRgb(234, 241, 255)),
        _ => new SolidColorBrush(Color.FromRgb(236, 253, 243))
    };

    public static DiagnosticFindingViewModel From(DiagnosticFinding finding) => new(finding);
}

public sealed class DiagnosticRunHistoryViewModel
{
    private DiagnosticRunHistoryViewModel(DiagnosticRunHistory run)
    {
        Run = run;
    }

    public DiagnosticRunHistory Run { get; }
    public string WhenText => Run.RanAt.LocalDateTime.ToString("ddd d MMM, h:mm tt");
    public string Status => Run.Status;
    public string HealthLabel => Run.HealthLabel;
    public string SummaryText => $"{Run.FindingCount} findings • {Run.CoveragePercent:0}% coverage";
    public string Model => Run.Model;
    public string EvidencePath => Run.EvidencePath;

    public static DiagnosticRunHistoryViewModel From(DiagnosticRunHistory run) => new(run);
}
