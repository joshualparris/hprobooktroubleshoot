using System.Text.RegularExpressions;

namespace WindowsCrashDoctor.Services;

public sealed class IntegrationService
{
    private static readonly Regex SafeProviderId = new("^[a-z0-9][a-z0-9-]{0,63}$", RegexOptions.Compiled | RegexOptions.CultureInvariant);
    private readonly EngineExtractor _engine;
    private readonly PowerShellRunner _powerShell;

    public IntegrationService(EngineExtractor engine, PowerShellRunner powerShell)
    {
        _engine = engine;
        _powerShell = powerShell;
    }

    public Task<ProcessResult> GetStatusAsync(CancellationToken cancellationToken = default)
    {
        _engine.EnsureExtracted();
        return _powerShell.RunFileAsync(
            _engine.IntegrationManagerPath,
            new[] { "-Action", "status" },
            cancellationToken: cancellationToken,
            options: new ProcessRunOptions(TimeSpan.FromSeconds(45), OperationId: "integration-status"));
    }

    public Task<ProcessResult> InstallAsync(
        string providerId,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(providerId) || !SafeProviderId.IsMatch(providerId))
            throw new ArgumentException("Integration provider ID is invalid.", nameof(providerId));

        _engine.EnsureExtracted();
        return _powerShell.RunFileAsync(
            _engine.IntegrationManagerPath,
            new[] { "-Action", "install", "-Id", providerId },
            onOutput,
            cancellationToken,
            new ProcessRunOptions(TimeSpan.FromMinutes(2), MaxRetries: 2, RetryTransientFailures: true, OperationId: "integration-install"));
    }

    public Task<ProcessResult> CaptureSensorsAsync(
        string outputPath,
        int durationMinutes,
        int intervalSeconds,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(outputPath);
        if (durationMinutes is < 1 or > 120)
            throw new ArgumentOutOfRangeException(nameof(durationMinutes));
        if (intervalSeconds is < 1 or > 60)
            throw new ArgumentOutOfRangeException(nameof(intervalSeconds));

        var fullPath = Path.GetFullPath(outputPath);
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)
            ?? throw new InvalidOperationException("Sensor output directory could not be resolved."));

        _engine.EnsureExtracted();
        return _powerShell.RunFileAsync(
            _engine.IntegrationManagerPath,
            new[]
            {
                "-Action", "sensors",
                "-DurationMinutes", durationMinutes.ToString(System.Globalization.CultureInfo.InvariantCulture),
                "-IntervalSeconds", intervalSeconds.ToString(System.Globalization.CultureInfo.InvariantCulture),
                "-OutputPath", fullPath
            },
            onOutput,
            cancellationToken,
            new ProcessRunOptions(TimeSpan.FromMinutes(durationMinutes + 2), OperationId: "sensor-capture"));
    }
}
