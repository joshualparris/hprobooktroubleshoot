using System.Diagnostics;
using System.Text.Json;

namespace WindowsCrashDoctor.Services;

public static class DesktopSelfTest
{
    public static int Run()
    {
        var temp = Path.Combine(Path.GetTempPath(), "WindowsCrashDoctorDesktopSelfTest-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(temp);

        try
        {
            var engine = new EngineExtractor();
            engine.EnsureExtracted();

            foreach (var required in new[]
            {
                engine.CollectorPath,
                engine.CrashDoctorPath,
                engine.TelemetryPath,
                engine.IntegrationManagerPath,
                engine.VersionPath
            })
            {
                if (!File.Exists(required))
                    throw new InvalidOperationException($"Embedded engine self-test missing required file: {required}");
            }

            File.WriteAllText(Path.Combine(temp, "sensors.csv"),
                "Date,Time,\"Physical Memory Load [%]\",\"Total CPU Usage [%]\",\"CPU Package [C]\",\"Total Activity [%]\"\r\n" +
                "12.9.2026,15:16:14.000,91,42,48,12\r\n" +
                "12.9.2026,15:16:16.000,92,100,52,60\r\n" +
                "12.9.2026,15:16:18.000,90,35,46,18\r\n");

            var powershell = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                "WindowsPowerShell", "v1.0", "powershell.exe");
            if (!File.Exists(powershell))
                powershell = "powershell.exe";

            var psi = new ProcessStartInfo(powershell)
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };
            psi.ArgumentList.Add("-NoProfile");
            psi.ArgumentList.Add("-ExecutionPolicy");
            psi.ArgumentList.Add("Bypass");
            psi.ArgumentList.Add("-File");
            psi.ArgumentList.Add(engine.CrashDoctorPath);
            psi.ArgumentList.Add("-EvidencePath");
            psi.ArgumentList.Add(temp);
            psi.ArgumentList.Add("-OutputDirectory");
            psi.ArgumentList.Add(temp);

            using var process = Process.Start(psi) ?? throw new InvalidOperationException("Could not start Windows PowerShell for packaged-engine self-test.");
            if (!process.WaitForExit(60_000))
            {
                process.Kill(true);
                throw new TimeoutException("Packaged-engine self-test timed out.");
            }
            var stdout = process.StandardOutput.ReadToEnd();
            var stderr = process.StandardError.ReadToEnd();
            if (process.ExitCode != 0)
                throw new InvalidOperationException($"Packaged engine returned {process.ExitCode}. {stdout} {stderr}");

            var reportPath = Path.Combine(temp, "crash-doctor-report.json");
            if (!File.Exists(reportPath))
                throw new InvalidOperationException("Packaged engine did not create crash-doctor-report.json.");

            using var report = JsonDocument.Parse(File.ReadAllText(reportPath));
            if (!report.RootElement.TryGetProperty("Telemetry", out var telemetry) ||
                !telemetry.TryGetProperty("Sensor", out var sensor) ||
                !sensor.TryGetProperty("Available", out var available) ||
                !available.GetBoolean())
                throw new InvalidOperationException("Packaged engine did not load embedded telemetry analysis.");

            if (!report.RootElement.TryGetProperty("Product", out _))
                throw new InvalidOperationException("Packaged engine report is missing product/build provenance.");

            return 0;
        }
        catch (Exception ex)
        {
            try { File.WriteAllText(Path.Combine(temp, "SELF-TEST-FAILED.txt"), ex.ToString()); } catch { }
            return 1;
        }
        finally
        {
            try { Directory.Delete(temp, true); } catch { }
        }
    }
}
