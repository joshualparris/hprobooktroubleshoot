namespace WindowsCrashDoctor.Services;

public sealed record SensorCaptureProgress(double Percent, string Status);
public sealed record SensorCaptureResult(string OutputPath);

public sealed class IntegrationWorkflowService
{
    private static readonly HashSet<string> InstallableIds = new(StringComparer.OrdinalIgnoreCase)
    {
        "librehardwaremonitor",
        "evtx",
        "hayabusa",
        "osquery",
        "perfview"
    };

    private readonly EngineExtractor _engine;
    private readonly PowerShellRunner _powerShell;

    public IntegrationWorkflowService(EngineExtractor engine, PowerShellRunner powerShell)
    {
        _engine = engine;
        _powerShell = powerShell;
    }

    public async Task<string> GetStatusAsync(CancellationToken cancellationToken = default)
    {
        _engine.EnsureExtracted();
        var result = await _powerShell.RunFileAsync(
            _engine.IntegrationManagerPath,
            new[] { "-Action", "status" },
            cancellationToken: cancellationToken,
            timeout: TimeSpan.FromMinutes(2));
        if (result.ExitCode != 0)
            throw new InvalidOperationException($"Provider status exited with code {result.ExitCode}.");
        return string.IsNullOrWhiteSpace(result.StandardOutput)
            ? "Provider status returned no output."
            : result.StandardOutput.Trim();
    }

    public async Task InstallAsync(
        string id,
        Action<string>? onLog = null,
        CancellationToken cancellationToken = default)
    {
        ValidateInstallableId(id);
        _engine.EnsureExtracted();
        var result = await _powerShell.RunFileAsync(
            _engine.IntegrationManagerPath,
            new[] { "-Action", "install", "-Id", id },
            onLog,
            cancellationToken,
            TimeSpan.FromMinutes(10));
        if (result.ExitCode != 0)
            throw new InvalidOperationException($"Provider '{id}' installation exited with code {result.ExitCode}.");
    }

    public async Task<SensorCaptureResult> CaptureSensorsAsync(
        string outputRoot,
        TimeSpan duration,
        int intervalSeconds,
        IProgress<SensorCaptureProgress>? progress = null,
        Action<string>? onLog = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(outputRoot);
        if (duration <= TimeSpan.Zero || duration > TimeSpan.FromHours(24))
            throw new ArgumentOutOfRangeException(nameof(duration));
        if (intervalSeconds is < 1 or > 300)
            throw new ArgumentOutOfRangeException(nameof(intervalSeconds));

        progress?.Report(new SensorCaptureProgress(2, "Preparing LibreHardwareMonitor…"));
        await InstallAsync("librehardwaremonitor", onLog, cancellationToken);

        Directory.CreateDirectory(outputRoot);
        var output = Path.Combine(
            Path.GetFullPath(outputRoot),
            $"sensor-{DateTime.UtcNow:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}.jsonl");
        var minutes = Math.Max(0.1, duration.TotalMinutes);
        var captureTask = _powerShell.RunFileAsync(
            _engine.IntegrationManagerPath,
            new[]
            {
                "-Action", "sensors",
                "-DurationMinutes", minutes.ToString(System.Globalization.CultureInfo.InvariantCulture),
                "-IntervalSeconds", intervalSeconds.ToString(System.Globalization.CultureInfo.InvariantCulture),
                "-OutputPath", output
            },
            onLog,
            cancellationToken,
            duration + TimeSpan.FromMinutes(5));

        var started = DateTimeOffset.UtcNow;
        while (!captureTask.IsCompleted)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var elapsed = DateTimeOffset.UtcNow - started;
            var percent = Math.Clamp(100.0 * elapsed.TotalSeconds / duration.TotalSeconds, 2, 99);
            var remaining = duration - elapsed;
            if (remaining < TimeSpan.Zero) remaining = TimeSpan.Zero;
            progress?.Report(new SensorCaptureProgress(
                percent,
                $"Recording… {remaining:mm\\:ss} remaining • {Path.GetFileName(output)}"));
            await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken);
        }

        var result = await captureTask;
        if (result.ExitCode != 0)
            throw new InvalidOperationException($"Deep sensor capture exited with code {result.ExitCode}.");
        if (!File.Exists(output))
            throw new InvalidDataException("Deep sensor capture completed without creating its output file.");

        progress?.Report(new SensorCaptureProgress(100, $"Complete: {output}"));
        return new SensorCaptureResult(output);
    }

    private static void ValidateInstallableId(string id)
    {
        if (string.IsNullOrWhiteSpace(id) || !InstallableIds.Contains(id))
            throw new ArgumentException($"Unsupported installable provider id '{id}'.", nameof(id));
    }
}
