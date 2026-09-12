using WindowsCrashDoctor.Models;

namespace WindowsCrashDoctor;

public partial class MainWindow
{
    private PreflightReport? _latestPreflight;
    private RunComparisonSummary? _latestComparison;

    private async Task InitialiseV2Async()
    {
        _latestPreflight = await _workflow.RunPreflightAsync(_outputRoot);
        AdminStatusText.Text = $"Standard-user desktop • collector elevates only when needed • preflight {_latestPreflight.OverallState}";
        DiagnosticStatusText.Text = $"Preflight {_latestPreflight.OverallState}";
        foreach (var item in _latestPreflight.Items.Where(x => x.State != "healthy"))
            AppendLog($"PREFLIGHT {item.State.ToUpperInvariant()}: {item.Name} — {item.Detail}");
    }

    private void ApplyV2DashboardSummary()
    {
        if (_latestComparison is null) return;
        HealthExplanation.Text += "  " + _latestComparison.SummaryText + $" • comparison trust {_latestComparison.Trust}.";
        if (_latestComparison.WorsenedCount > 0 || _latestComparison.NewCount > 0)
            RecommendationBody.Text += $" Since the previous comparable run: {_latestComparison.NewCount} new, {_latestComparison.WorsenedCount} worsened, {_latestComparison.ResolvedCount} resolved.";
    }
}
