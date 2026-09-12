using System.Diagnostics;
using System.Text;

namespace WindowsCrashDoctor.Services;

public sealed record ProcessResult(int ExitCode, string StandardOutput, string StandardError);

public sealed class PowerShellRunner
{
    private const int MaxCapturedCharacters = 8 * 1024 * 1024;
    private static readonly TimeSpan DefaultTimeout = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan MaximumTimeout = TimeSpan.FromHours(2);

    public Task<ProcessResult> RunFileAsync(
        string scriptPath,
        IEnumerable<string>? arguments = null,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default,
        TimeSpan? timeout = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(scriptPath);
        var psi = CreatePowerShellStartInfo(redirectOutput: true);
        psi.ArgumentList.Add("-File");
        psi.ArgumentList.Add(scriptPath);
        AddArguments(psi, arguments);
        return RunRedirectedAsync(psi, onOutput, cancellationToken, ValidateTimeout(timeout));
    }

    public Task<ProcessResult> RunCommandAsync(
        string command,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default,
        TimeSpan? timeout = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(command);
        var psi = CreatePowerShellStartInfo(redirectOutput: true);
        psi.ArgumentList.Add("-Command");
        psi.ArgumentList.Add(command);
        return RunRedirectedAsync(psi, onOutput, cancellationToken, ValidateTimeout(timeout));
    }

    public async Task<int> RunFileElevatedAsync(
        string scriptPath,
        IEnumerable<string>? arguments = null,
        CancellationToken cancellationToken = default,
        TimeSpan? timeout = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(scriptPath);
        var effectiveTimeout = ValidateTimeout(timeout);
        var psi = CreatePowerShellStartInfo(redirectOutput: false);
        psi.UseShellExecute = true;
        psi.Verb = "runas";
        psi.CreateNoWindow = false;
        psi.ArgumentList.Add("-File");
        psi.ArgumentList.Add(scriptPath);
        AddArguments(psi, arguments);

        using var process = new Process { StartInfo = psi };
        if (!process.Start())
            throw new InvalidOperationException("Could not start the elevated diagnostic collector.");

        using var timeoutCts = new CancellationTokenSource(effectiveTimeout);
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutCts.Token);
        try
        {
            await process.WaitForExitAsync(linkedCts.Token);
            return process.ExitCode;
        }
        catch (OperationCanceledException) when (timeoutCts.IsCancellationRequested && !cancellationToken.IsCancellationRequested)
        {
            TryKill(process);
            throw new TimeoutException($"Elevated PowerShell exceeded the {effectiveTimeout.TotalMinutes:0.#}-minute timeout.");
        }
        catch
        {
            if (cancellationToken.IsCancellationRequested)
                TryKill(process);
            throw;
        }
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
        if (arguments is null)
            return;

        foreach (var argument in arguments)
            psi.ArgumentList.Add(argument ?? throw new ArgumentException("PowerShell arguments cannot contain null values.", nameof(arguments)));
    }

    private static TimeSpan ValidateTimeout(TimeSpan? timeout)
    {
        var value = timeout ?? DefaultTimeout;
        if (value <= TimeSpan.Zero || value > MaximumTimeout)
            throw new ArgumentOutOfRangeException(nameof(timeout), $"Timeout must be greater than zero and no more than {MaximumTimeout.TotalHours:0} hours.");
        return value;
    }

    private static async Task<ProcessResult> RunRedirectedAsync(
        ProcessStartInfo psi,
        Action<string>? onOutput,
        CancellationToken cancellationToken,
        TimeSpan timeout)
    {
        using var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
        var stdout = new StringBuilder();
        var stderr = new StringBuilder();

        if (!process.Start())
            throw new InvalidOperationException($"Could not start {psi.FileName}.");

        using var timeoutCts = new CancellationTokenSource(timeout);
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutCts.Token);
        using var registration = linkedCts.Token.Register(() => TryKill(process));

        async Task PumpAsync(StreamReader reader, StringBuilder destination, bool error)
        {
            while (true)
            {
                var line = await reader.ReadLineAsync(linkedCts.Token);
                if (line is null)
                    break;

                AppendBounded(destination, line);
                onOutput?.Invoke(error ? $"ERROR: {line}" : line);
            }
        }

        var stdoutTask = PumpAsync(process.StandardOutput, stdout, error: false);
        var stderrTask = PumpAsync(process.StandardError, stderr, error: true);
        try
        {
            await process.WaitForExitAsync(linkedCts.Token);
            await Task.WhenAll(stdoutTask, stderrTask);
        }
        catch (OperationCanceledException) when (timeoutCts.IsCancellationRequested && !cancellationToken.IsCancellationRequested)
        {
            throw new TimeoutException($"PowerShell exceeded the {timeout.TotalMinutes:0.#}-minute timeout.");
        }

        cancellationToken.ThrowIfCancellationRequested();
        return new ProcessResult(process.ExitCode, stdout.ToString(), stderr.ToString());
    }

    private static void AppendBounded(StringBuilder destination, string line)
    {
        if (destination.Length >= MaxCapturedCharacters)
            return;

        var remaining = MaxCapturedCharacters - destination.Length;
        if (line.Length + Environment.NewLine.Length <= remaining)
        {
            destination.AppendLine(line);
            return;
        }

        if (remaining > 0)
            destination.Append(line.AsSpan(0, Math.Min(line.Length, remaining)));
    }

    private static void TryKill(Process process)
    {
        try
        {
            if (!process.HasExited)
                process.Kill(entireProcessTree: true);
        }
        catch
        {
            // Cancellation/timeout is already observable to the caller; cleanup must not replace that error.
        }
    }
}
