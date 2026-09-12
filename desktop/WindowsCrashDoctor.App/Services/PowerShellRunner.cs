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
    private readonly RedactionService _redaction = new();
    private static readonly TimeSpan CleanupGrace = TimeSpan.FromSeconds(3);

    public async Task<ProcessResult> RunFileAsync(
        string scriptPath,
        IEnumerable<string>? arguments = null,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default,
        ProcessRunOptions? options = null)
    {
        var psi = CreatePowerShellStartInfo();
        psi.ArgumentList.Add("-File");
        psi.ArgumentList.Add(scriptPath);
        if (arguments is not null)
            foreach (var argument in arguments) psi.ArgumentList.Add(argument);
        return await RunWithPolicyAsync(psi, onOutput, cancellationToken, options ?? ProcessRunOptions.Default);
    }

    public async Task<ProcessResult> RunCommandAsync(
        string command,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default,
        ProcessRunOptions? options = null)
    {
        var psi = CreatePowerShellStartInfo();
        psi.ArgumentList.Add("-Command");
        psi.ArgumentList.Add(command);
        return await RunWithPolicyAsync(psi, onOutput, cancellationToken, options ?? ProcessRunOptions.Default);
    }

    private static ProcessStartInfo CreatePowerShellStartInfo()
    {
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-ExecutionPolicy");
        psi.ArgumentList.Add("Bypass");
        return psi;
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
            try { await Task.Delay(delayMs, cancellationToken); }
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
                var line = await reader.ReadLineAsync();
                if (line is null) break;
                destination.AppendLine(line);
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
            try { await pumps; } catch { }
        }

        var finished = DateTimeOffset.UtcNow;
        var redactedError = _redaction.RedactForLog(stderr.ToString());
        var exitCode = process.HasExited ? process.ExitCode : -1;
        var status = cancellationToken.IsCancellationRequested
            ? ProcessExecutionStatus.Cancelled
            : timeoutCts.IsCancellationRequested
                ? ProcessExecutionStatus.TimedOut
                : exitCode == 0
                    ? (string.IsNullOrWhiteSpace(stderr.ToString()) ? ProcessExecutionStatus.Completed : ProcessExecutionStatus.CompletedWithWarnings)
                    : ClassifyFailure(redactedError);
        var reason = status switch
        {
            ProcessExecutionStatus.Cancelled => "Operation cancelled.",
            ProcessExecutionStatus.TimedOut => $"Operation exceeded timeout of {timeout}.",
            ProcessExecutionStatus.Completed => null,
            ProcessExecutionStatus.CompletedWithWarnings => redactedError,
            _ => string.IsNullOrWhiteSpace(redactedError) ? $"Process exited with code {exitCode}." : redactedError
        };
        return new ProcessResult(exitCode, stdout.ToString(), stderr.ToString(), status, started, finished, finished - started, attempt, reason);

        ProcessResult Result(int code, ProcessExecutionStatus state, string? reason)
        {
            var finishedAt = DateTimeOffset.UtcNow;
            return new ProcessResult(code, "", "", state, started, finishedAt, finishedAt - started, attempt, reason);
        }
    }

    private static async Task WaitForExitWithGraceAsync(Process process, TimeSpan grace)
    {
        if (process.HasExited) return;
        using var cleanupCts = new CancellationTokenSource(grace);
        try { await process.WaitForExitAsync(cleanupCts.Token); }
        catch (OperationCanceledException) { KillTree(process); }
        catch (InvalidOperationException) { }
    }

    private static bool IsRetryable(ProcessResult result) => result.Status is ProcessExecutionStatus.TimedOut or ProcessExecutionStatus.FailedRetryable;

    private static ProcessExecutionStatus ClassifyFailure(string error)
    {
        var transient = new[] { "429", "502", "503", "504", "timed out", "timeout", "temporarily unavailable", "connection reset", "econnreset", "eai_again", "name resolution", "dns" };
        return transient.Any(x => error.Contains(x, StringComparison.OrdinalIgnoreCase))
            ? ProcessExecutionStatus.FailedRetryable
            : ProcessExecutionStatus.FailedPermanent;
    }

    private static void KillTree(Process process)
    {
        try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch { }
    }
}
