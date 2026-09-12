using System.ComponentModel;
using System.Diagnostics;
using System.Text;

namespace WindowsCrashDoctor.Services;

public enum ProcessExecutionStatus
{
    Completed,
    CompletedWithWarnings,
    Cancelled,
    TimedOut,
    FailedRetryable,
    FailedPermanent,
    Unavailable,
    SkippedNotApplicable
}

public sealed record ProcessRunOptions(
    TimeSpan Timeout,
    int MaxRetries = 0,
    bool RetryTransientFailures = false,
    string? OperationId = null)
{
    public static ProcessRunOptions Default { get; } = new(TimeSpan.FromMinutes(5));
}

public sealed record ProcessResult(
    int ExitCode,
    string StandardOutput,
    string StandardError,
    ProcessExecutionStatus Status,
    DateTimeOffset StartedAt,
    DateTimeOffset FinishedAt,
    TimeSpan Duration,
    int AttemptCount,
    string? FailureReason)
{
    public bool Succeeded => Status is ProcessExecutionStatus.Completed or ProcessExecutionStatus.CompletedWithWarnings;
    public bool TimedOut => Status == ProcessExecutionStatus.TimedOut;
    public bool Cancelled => Status == ProcessExecutionStatus.Cancelled;
}

public sealed class PowerShellRunner
{
    private const int MaxCapturedCharacters = 8 * 1024 * 1024;
    private static readonly TimeSpan MaximumTimeout = TimeSpan.FromHours(2);
    private static readonly TimeSpan CleanupGrace = TimeSpan.FromSeconds(3);
    private readonly RedactionService _redaction = new();

    public async Task<ProcessResult> RunFileAsync(
        string scriptPath,
        IEnumerable<string>? arguments = null,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default,
        ProcessRunOptions? options = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(scriptPath);
        var effectiveOptions = ValidateOptions(options ?? ProcessRunOptions.Default);
        var psi = CreatePowerShellStartInfo(redirectOutput: true);
        psi.ArgumentList.Add("-File");
        psi.ArgumentList.Add(scriptPath);
        AddArguments(psi, arguments);
        return await RunWithPolicyAsync(psi, onOutput, cancellationToken, effectiveOptions);
    }

    public async Task<ProcessResult> RunCommandAsync(
        string command,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default,
        ProcessRunOptions? options = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(command);
        var effectiveOptions = ValidateOptions(options ?? ProcessRunOptions.Default);
        var psi = CreatePowerShellStartInfo(redirectOutput: true);
        psi.ArgumentList.Add("-Command");
        psi.ArgumentList.Add(command);
        return await RunWithPolicyAsync(psi, onOutput, cancellationToken, effectiveOptions);
    }

    public async Task<ProcessResult> RunFileElevatedAsync(
        string scriptPath,
        IEnumerable<string>? arguments = null,
        CancellationToken cancellationToken = default,
        ProcessRunOptions? options = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(scriptPath);
        var effectiveOptions = ValidateOptions(options ?? ProcessRunOptions.Default);
        var started = DateTimeOffset.UtcNow;
        var psi = CreatePowerShellStartInfo(redirectOutput: false);
        psi.UseShellExecute = true;
        psi.Verb = "runas";
        psi.CreateNoWindow = false;
        psi.ArgumentList.Add("-File");
        psi.ArgumentList.Add(scriptPath);
        AddArguments(psi, arguments);

        using var process = new Process { StartInfo = psi };
        try
        {
            if (!process.Start())
                return CreateResult(-1, ProcessExecutionStatus.Unavailable, "Elevated collector could not be started.", started);
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            return CreateResult(-1, ProcessExecutionStatus.Cancelled, "Administrator permission was not granted.", started);
        }
        catch (Exception ex)
        {
            return CreateResult(-1, ProcessExecutionStatus.Unavailable, _redaction.RedactForLog(ex.Message), started);
        }

        using var timeoutCts = new CancellationTokenSource(effectiveOptions.Timeout);
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutCts.Token);
        try
        {
            await process.WaitForExitAsync(linkedCts.Token);
        }
        catch (OperationCanceledException)
        {
            KillTree(process);
            await WaitForExitWithGraceAsync(process, CleanupGrace);
            var state = cancellationToken.IsCancellationRequested
                ? ProcessExecutionStatus.Cancelled
                : ProcessExecutionStatus.TimedOut;
            var reason = state == ProcessExecutionStatus.Cancelled
                ? "Operation cancelled."
                : $"Operation exceeded timeout of {effectiveOptions.Timeout}.";
            return CreateResult(-1, state, reason, started);
        }

        var exitCode = process.ExitCode;
        return CreateResult(
            exitCode,
            exitCode == 0 ? ProcessExecutionStatus.Completed : ProcessExecutionStatus.FailedPermanent,
            exitCode == 0 ? null : $"Elevated collector exited with code {exitCode}.",
            started);
    }

    private static ProcessStartInfo CreatePowerShellStartInfo(bool redirectOutput)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = false,
            RedirectStandardOutput = redirectOutput,
            RedirectStandardError = redirectOutput,
            CreateNoWindow = redirectOutput
        };
        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-ExecutionPolicy");
        psi.ArgumentList.Add("Bypass");
        return psi;
    }

    private static void AddArguments(ProcessStartInfo psi, IEnumerable<string>? arguments)
    {
        if (arguments is null) return;
        foreach (var argument in arguments)
            psi.ArgumentList.Add(argument ?? throw new ArgumentException("PowerShell arguments cannot contain null values.", nameof(arguments)));
    }

    private static ProcessRunOptions ValidateOptions(ProcessRunOptions options)
    {
        if (options.Timeout <= TimeSpan.Zero || options.Timeout > MaximumTimeout)
            throw new ArgumentOutOfRangeException(nameof(options), $"Timeout must be greater than zero and no more than {MaximumTimeout.TotalHours:0} hours.");
        if (options.MaxRetries is < 0 or > 5)
            throw new ArgumentOutOfRangeException(nameof(options), "MaxRetries must be between 0 and 5.");
        return options;
    }

    private async Task<ProcessResult> RunWithPolicyAsync(
        ProcessStartInfo psi,
        Action<string>? onOutput,
        CancellationToken cancellationToken,
        ProcessRunOptions options)
    {
        ProcessResult? latest = null;
        var attempts = Math.Max(1, options.MaxRetries + 1);
        for (var attempt = 1; attempt <= attempts; attempt++)
        {
            latest = await RunOnceAsync(psi, onOutput, cancellationToken, options.Timeout, attempt);
            if (latest.Succeeded || latest.Cancelled) return latest;
            if (!options.RetryTransientFailures || attempt >= attempts || !IsRetryable(latest)) return latest;

            var delayMs = Math.Min(8000, (int)Math.Pow(2, attempt - 1) * 500) + Random.Shared.Next(0, 251);
            onOutput?.Invoke($"Transient diagnostic failure; retrying attempt {attempt + 1}/{attempts} after {delayMs} ms.");
            try
            {
                await Task.Delay(delayMs, cancellationToken);
            }
            catch (OperationCanceledException)
            {
                return latest with { Status = ProcessExecutionStatus.Cancelled, FailureReason = "Operation cancelled before retry." };
            }
        }
        return latest!;
    }

    private async Task<ProcessResult> RunOnceAsync(
        ProcessStartInfo psi,
        Action<string>? onOutput,
        CancellationToken cancellationToken,
        TimeSpan timeout,
        int attempt)
    {
        var started = DateTimeOffset.UtcNow;
        using var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
        var stdout = new StringBuilder();
        var stderr = new StringBuilder();

        try
        {
            if (!process.Start())
                return Result(-1, ProcessExecutionStatus.Unavailable, "Process could not be started.");
        }
        catch (Exception ex)
        {
            return Result(-1, ProcessExecutionStatus.Unavailable, _redaction.RedactForLog(ex.Message));
        }

        using var timeoutCts = new CancellationTokenSource(timeout);
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutCts.Token);
        using var registration = linkedCts.Token.Register(() => KillTree(process));

        async Task PumpAsync(StreamReader reader, StringBuilder destination, bool error)
        {
            while (true)
            {
                // Do not cancel pipe reads independently; killing the process closes the pipes and
                // lets the pump finish without a second cancellation race.
                var line = await reader.ReadLineAsync();
                if (line is null) break;
                AppendBounded(destination, line);
                onOutput?.Invoke(error ? $"ERROR: {_redaction.RedactForLog(line)}" : _redaction.RedactForLog(line));
            }
        }

        var stdoutTask = PumpAsync(process.StandardOutput, stdout, false);
        var stderrTask = PumpAsync(process.StandardError, stderr, true);
        try
        {
            await process.WaitForExitAsync(linkedCts.Token);
        }
        catch (OperationCanceledException)
        {
            KillTree(process);
            await WaitForExitWithGraceAsync(process, CleanupGrace);
        }

        var pumps = Task.WhenAll(stdoutTask, stderrTask);
        if (await Task.WhenAny(pumps, Task.Delay(CleanupGrace)) == pumps)
        {
            try
            {
                await pumps;
            }
            catch (Exception ex)
            {
                Trace.WriteLine($"PowerShell output pump cleanup failed: {ex.Message}");
            }
        }
        else
        {
            Trace.WriteLine("PowerShell output pumps did not finish within the cleanup grace period.");
        }

        var finished = DateTimeOffset.UtcNow;
        var rawError = stderr.ToString();
        var redactedError = _redaction.RedactForLog(rawError);
        var exitCode = process.HasExited ? process.ExitCode : -1;
        var status = cancellationToken.IsCancellationRequested
            ? ProcessExecutionStatus.Cancelled
            : timeoutCts.IsCancellationRequested
                ? ProcessExecutionStatus.TimedOut
                : exitCode == 0
                    ? (string.IsNullOrWhiteSpace(rawError) ? ProcessExecutionStatus.Completed : ProcessExecutionStatus.CompletedWithWarnings)
                    : ClassifyFailure(redactedError);
        var reason = status switch
        {
            ProcessExecutionStatus.Cancelled => "Operation cancelled.",
            ProcessExecutionStatus.TimedOut => $"Operation exceeded timeout of {timeout}.",
            ProcessExecutionStatus.Completed => null,
            ProcessExecutionStatus.CompletedWithWarnings => redactedError,
            _ => string.IsNullOrWhiteSpace(redactedError) ? $"Process exited with code {exitCode}." : redactedError
        };
        return new ProcessResult(exitCode, stdout.ToString(), rawError, status, started, finished, finished - started, attempt, reason);

        ProcessResult Result(int code, ProcessExecutionStatus state, string? reason)
        {
            var finishedAt = DateTimeOffset.UtcNow;
            return new ProcessResult(code, "", "", state, started, finishedAt, finishedAt - started, attempt, reason);
        }
    }

    private static void AppendBounded(StringBuilder destination, string line)
    {
        if (destination.Length >= MaxCapturedCharacters) return;
        var remaining = MaxCapturedCharacters - destination.Length;
        if (line.Length + Environment.NewLine.Length <= remaining)
            destination.AppendLine(line);
        else if (remaining > 0)
            destination.Append(line.AsSpan(0, Math.Min(line.Length, remaining)));
    }

    private static async Task WaitForExitWithGraceAsync(Process process, TimeSpan grace)
    {
        if (process.HasExited) return;
        using var cleanupCts = new CancellationTokenSource(grace);
        try
        {
            await process.WaitForExitAsync(cleanupCts.Token);
        }
        catch (OperationCanceledException)
        {
            KillTree(process);
        }
        catch (InvalidOperationException ex)
        {
            Trace.WriteLine($"PowerShell cleanup observed an invalid process state: {ex.Message}");
        }
    }

    private static bool IsRetryable(ProcessResult result) =>
        result.Status is ProcessExecutionStatus.TimedOut or ProcessExecutionStatus.FailedRetryable;

    private static ProcessExecutionStatus ClassifyFailure(string error)
    {
        var transient = new[] { "429", "502", "503", "504", "timed out", "timeout", "temporarily unavailable", "connection reset", "econnreset", "eai_again", "name resolution", "dns" };
        return transient.Any(x => error.Contains(x, StringComparison.OrdinalIgnoreCase))
            ? ProcessExecutionStatus.FailedRetryable
            : ProcessExecutionStatus.FailedPermanent;
    }

    private static ProcessResult CreateResult(int exitCode, ProcessExecutionStatus status, string? reason, DateTimeOffset started)
    {
        var finished = DateTimeOffset.UtcNow;
        return new ProcessResult(exitCode, "", "", status, started, finished, finished - started, 1, reason);
    }

    private static void KillTree(Process process)
    {
        try
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
        }
        catch (Exception ex)
        {
            Trace.WriteLine($"Process cleanup failed: {ex.Message}");
        }
    }
}
