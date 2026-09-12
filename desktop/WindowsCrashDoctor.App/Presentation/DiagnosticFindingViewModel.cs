using System.Windows.Media;
using WindowsCrashDoctor.Models;

namespace WindowsCrashDoctor.Presentation;

public sealed class DiagnosticFindingViewModel
{
    public required string Severity { get; init; }
    public required string Title { get; init; }
    public required string Interpretation { get; init; }
    public Brush SeverityBrush { get; init; } = Brushes.Green;
    public Brush SeverityBackground { get; init; } = Brushes.Honeydew;

    public static DiagnosticFindingViewModel From(DiagnosticFinding finding)
    {
        var (foreground, background) = finding.Severity switch
        {
            "Critical" or "High" => (Color.FromRgb(217, 45, 32), Color.FromRgb(254, 243, 242)),
            "Medium" => (Color.FromRgb(220, 104, 3), Color.FromRgb(255, 246, 232)),
            "Low" => (Color.FromRgb(37, 99, 235), Color.FromRgb(234, 241, 255)),
            _ => (Color.FromRgb(3, 152, 85), Color.FromRgb(236, 253, 243))
        };

        return new DiagnosticFindingViewModel
        {
            Severity = finding.Severity,
            Title = finding.Title,
            Interpretation = finding.Interpretation,
            SeverityBrush = new SolidColorBrush(foreground),
            SeverityBackground = new SolidColorBrush(background)
        };
    }
}
