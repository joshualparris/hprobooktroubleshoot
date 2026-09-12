using System.Diagnostics;
using System.Text;

namespace WindowsCrashDoctor.Services;

public sealed record ProcessResult(int ExitCode, string StandardOutput, string StandardError);

public sealed class PowerShellRunner
{
    public async Task<ProcessResult> RunFileAsync(
        string scriptPath,
        IEnumerable<string>? arguments = null,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default)
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
        psi.ArgumentList.Add("-File");
        psi.ArgumentList.Add(scriptPath);

        if (arguments is not null)
        {
            foreach (var argument in arguments)
                psi.ArgumentList.Add(argument);
        }

        return await RunAsync(psi, onOutput, cancellationToken);
    }

    public async Task<ProcessResult> RunCommandAsync(
        string command,
        Action<string>? onOutput = null,
        CancellationToken cancellationToken = default)
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
        psi.ArgumentList.Add("-Command");
        psi.ArgumentList.Add(command);
        return await RunAsync(psi, onOutput, cancellationToken);
    }

    private static async Task<ProcessResult> RunAsync(
        ProcessStartInfo psi,
        Action<string>? onOutput,
        CancellationToken cancellationToken)
    {
        using var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
        var stdout = new StringBuilder();
        var stderr = new StringBuilder();

        if (!process.Start())
            throw new InvalidOperationException($"Could not start {psi.FileName}.");

        using var registration = cancellationToken.Register(() =>
        {
            try
            {
                if (!process.HasExited)
                    process.Kill(entireProcessTree: true);
            }
            catch
            {
            }
        });

        async Task PumpAsync(StreamReader reader, StringBuilder destination, bool error)
        {
            while (true)
            {
                var line = await reader.ReadLineAsync(cancellationToken);
                if (line is null) break;
                destination.AppendLine(line);
                onOutput?.Invoke(error ? $"ERROR: {line}" : line);
            }
        }

        var stdoutTask = PumpAsync(process.StandardOutput, stdout, false);
        var stderrTask = PumpAsync(process.StandardError, stderr, true);
        await process.WaitForExitAsync(cancellationToken);
        await Task.WhenAll(stdoutTask, stderrTask);

        return new ProcessResult(process.ExitCode, stdout.ToString(), stderr.ToString());
    }
}
