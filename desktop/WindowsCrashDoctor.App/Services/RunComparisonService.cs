using WindowsCrashDoctor.Models;

namespace WindowsCrashDoctor.Services;

public sealed class RunComparisonService
{
    public RunComparisonSummary Compare(
        CrashDoctorReport current,
        IReadOnlyList<FindingSnapshot> currentFindings,
        DiagnosticRunHistory? previous)
    {
        if (previous is null)
        {
            var baseline = currentFindings.Select(x => new ComparisonItem
            {
                FindingId = x.FindingId,
                Title = x.Title,
                State = "NEW",
                CurrentFingerprint = x.Fingerprint,
                Explanation = "No previous comparable run exists; this run establishes the baseline."
            }).ToList();
            ApplyStates(current, baseline);
            return Summarize(null, false, "baseline", baseline);
        }

        var previousById = previous.Findings.ToDictionary(x => x.FindingId, StringComparer.OrdinalIgnoreCase);
        var currentById = currentFindings.ToDictionary(x => x.FindingId, StringComparer.OrdinalIgnoreCase);
        var items = new List<ComparisonItem>();

        foreach (var now in currentFindings)
        {
            if (!previousById.TryGetValue(now.FindingId, out var before))
            {
                items.Add(new ComparisonItem
                {
                    FindingId = now.FindingId,
                    Title = now.Title,
                    State = "NEW",
                    CurrentFingerprint = now.Fingerprint,
                    Explanation = "Finding is present now and was absent from the previous comparable run."
                });
                continue;
            }

            var state = string.Equals(now.Fingerprint, before.Fingerprint, StringComparison.OrdinalIgnoreCase)
                ? "UNCHANGED"
                : CompareSeverity(before.Severity, now.Severity);
            items.Add(new ComparisonItem
            {
                FindingId = now.FindingId,
                Title = now.Title,
                State = state,
                PreviousFingerprint = before.Fingerprint,
                CurrentFingerprint = now.Fingerprint,
                Explanation = state switch
                {
                    "IMPROVED" => "The same finding family remains but its ranked severity decreased.",
                    "WORSENED" => "The same finding family remains but its ranked severity increased.",
                    "UNCHANGED" => "The same finding family persists without a trustworthy directional change.",
                    _ => "The finding changed, but the change cannot be safely classified as better or worse."
                }
            });
        }

        var canResolve = current.Coverage.Percent >= Math.Min(90, previous.CoveragePercent) && current.Coverage.Percent >= 75;
        foreach (var before in previous.Findings.Where(x => !currentById.ContainsKey(x.FindingId)))
        {
            items.Add(new ComparisonItem
            {
                FindingId = before.FindingId,
                Title = before.Title,
                State = canResolve ? "RESOLVED" : "UNKNOWN",
                PreviousFingerprint = before.Fingerprint,
                Explanation = canResolve
                    ? "Finding is absent and current evidence coverage is sufficient to treat the absence as resolved for this snapshot."
                    : "Finding is absent, but current evidence coverage is too incomplete to safely call it resolved."
            });
        }

        var trust = current.Coverage.Percent >= 90 && previous.CoveragePercent >= 90 ? "high"
            : current.Coverage.Percent >= 75 && previous.CoveragePercent >= 75 ? "medium" : "low";
        ApplyStates(current, items);
        return Summarize(previous.RunId, true, trust, items);
    }

    private static string CompareSeverity(string before, string now)
    {
        var beforeRank = Rank(before);
        var nowRank = Rank(now);
        if (nowRank < beforeRank) return "IMPROVED";
        if (nowRank > beforeRank) return "WORSENED";
        return "UNCHANGED";
    }

    private static int Rank(string severity) => severity switch
    {
        "Critical" => 5,
        "High" => 4,
        "Medium" => 3,
        "Low" => 2,
        _ => 1
    };

    private static void ApplyStates(CrashDoctorReport report, IEnumerable<ComparisonItem> items)
    {
        var states = items.ToDictionary(x => x.FindingId, x => x.State, StringComparer.OrdinalIgnoreCase);
        foreach (var finding in report.Findings)
            if (states.TryGetValue(finding.Id, out var state)) finding.ComparisonState = state;
    }

    private static RunComparisonSummary Summarize(string? previousRunId, bool hasBaseline, string trust, List<ComparisonItem> items) => new()
    {
        PreviousRunId = previousRunId,
        HasBaseline = hasBaseline,
        Trust = trust,
        NewCount = items.Count(x => x.State == "NEW"),
        ResolvedCount = items.Count(x => x.State == "RESOLVED"),
        ImprovedCount = items.Count(x => x.State == "IMPROVED"),
        WorsenedCount = items.Count(x => x.State == "WORSENED"),
        UnchangedCount = items.Count(x => x.State == "UNCHANGED"),
        UnknownCount = items.Count(x => x.State == "UNKNOWN"),
        Items = items
    };
}
