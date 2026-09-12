using System.Diagnostics;
using System.IO.Compression;
using System.Text.Json;

namespace WindowsCrashDoctor.Services;

public static class DesktopSelfTest
{
    public static int Run()
    {
        var temp = Path.Combine(Path.GetTempPath(), "WindowsCrashDoctorDesktopSelfTest-" + Guid.NewGuid().ToString("N"));
        var errorPath = Path.Combine(Path.GetTempPath(), "WindowsCrashDoctor-selftest-error.txt");
        Directory.CreateDirectory(temp);

        try
        {
            if (File.Exists(errorPath)) File.Delete(errorPath);

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

            using (var report = JsonDocument.Parse(File.ReadAllText(reportPath)))
            {
                if (!report.RootElement.TryGetProperty("Telemetry", out var telemetry) ||
                    !telemetry.TryGetProperty("Sensor", out var sensor) ||
                    !sensor.TryGetProperty("Available", out var available) ||
                    !available.GetBoolean())
                    throw new InvalidOperationException("Packaged engine did not load embedded telemetry analysis.");

                if (!report.RootElement.TryGetProperty("Product", out var product) ||
                    !product.TryGetProperty("EngineVersion", out var engineVersion) ||
                    engineVersion.GetString() != EngineExtractor.EngineVersion)
                    throw new InvalidOperationException("Packaged engine report is missing matching product/build provenance.");
            }

            RunPrivacyExportSelfTest(temp);
            return 0;
        }
        catch (Exception ex)
        {
            try { File.WriteAllText(errorPath, ex.ToString()); } catch { }
            return 1;
        }
        finally
        {
            try { Directory.Delete(temp, true); } catch { }
        }
    }

    private static void RunPrivacyExportSelfTest(string tempRoot)
    {
        var source = Path.Combine(tempRoot, "privacy-source");
        Directory.CreateDirectory(source);

        const string bitLockerFixture = "111111-222222-333333-444444-555555-666666-777777-888888";
        File.WriteAllText(Path.Combine(source, "report.txt"),
            $"User: person@example.com\nPath: C:\\Users\\Joshua\\Desktop\\report.txt\nRecovery: {bitLockerFixture}\nPassword=do-not-export\n");
        File.WriteAllText(Path.Combine(source, "private-key.txt"),
            "-----BEGIN PRIVATE KEY-----\nnot-a-real-key\n-----END PRIVATE KEY-----");
        File.WriteAllBytes(Path.Combine(source, "raw.evtx"), new byte[] { 1, 2, 3, 4 });

        var service = new PrivacyExportService();
        var plan = service.CreatePlan(source);
        if (plan.IncludedCount != 1 || plan.ExcludedCount != 2 || plan.RedactedFileCount != 1)
            throw new InvalidOperationException($"Privacy export plan was unexpected: include={plan.IncludedCount}, exclude={plan.ExcludedCount}, redacted={plan.RedactedFileCount}.");

        var zipPath = Path.Combine(tempRoot, "privacy-export.zip");
        var result = service.Export(plan, zipPath);
        if (result.IncludedCount != 1 || result.ExcludedCount != 2 || result.TotalRedactions < 4)
            throw new InvalidOperationException("Privacy export result did not preserve the preview policy/redactions.");

        using var archive = ZipFile.OpenRead(zipPath);
        if (archive.GetEntry("raw.evtx") is not null || archive.GetEntry("private-key.txt") is not null)
            throw new InvalidOperationException("Privacy export included a high-risk artefact that should have been excluded.");
        if (archive.GetEntry("export-manifest.json") is null)
            throw new InvalidOperationException("Privacy export did not include export-manifest.json.");

        var reportEntry = archive.GetEntry("report.txt")
            ?? throw new InvalidOperationException("Privacy export omitted the expected report derivative.");
        using var reader = new StreamReader(reportEntry.Open());
        var exportedText = reader.ReadToEnd();
        if (exportedText.Contains("person@example.com", StringComparison.OrdinalIgnoreCase) ||
            exportedText.Contains(bitLockerFixture, StringComparison.Ordinal) ||
            exportedText.Contains("do-not-export", StringComparison.Ordinal))
            throw new InvalidOperationException("Privacy export left a known sensitive fixture unredacted.");
        if (!exportedText.Contains("[REDACTED_EMAIL]", StringComparison.Ordinal) ||
            !exportedText.Contains("[REDACTED_BITLOCKER_RECOVERY_PASSWORD]", StringComparison.Ordinal) ||
            !exportedText.Contains("[REDACTED_SECRET]", StringComparison.Ordinal))
            throw new InvalidOperationException("Privacy export did not emit expected redaction markers.");
    }
}
