using Microsoft.Win32;
using System.Diagnostics;
using System.IO.Compression;
using System.Security.Principal;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using WindowsCrashDoctor.Models;
using WindowsCrashDoctor.Services;

namespace WindowsCrashDoctor;

public partial class MainWindow : Window
{
    private readonly bool _autoRun;
    private readonly EngineExtractor _engine = new();
    private readonly PowerShellRunner _powerShell = new();
    private readonly HistoryService _history = new();
    private readonly SystemMetricsService _metrics;
    private readonly DispatcherTimer _metricsTimer;
    private readonly string _outputRoot;
    private AppSettings _settings;
    private CrashDoctorReport? _latestReport;
    private string? _latestEvidencePath;
    private bool _metricsBusy;
    private bool _diagnosisRunning;
    private CancellationTokenSource? _sensorCts;

    public MainWindow(bool autoRun)
    {
        InitializeComponent();
        _autoRun = autoRun;
        _metrics = new SystemMetricsService(_powerShell);
        _settings = _history.LoadSettings();
        _outputRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
            "Windows Crash Doctor Results");
        Directory.CreateDirectory(_outputRoot);

        _metricsTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
        _metricsTimer.Tick += MetricsTimer_Tick;
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        ApplyTheme(_settings.DarkMode);
        AdminStatusText.Text = IsAdministrator() ? "Administrator mode" : "Standard mode • elevates only when needed";
        _engine.EnsureExtracted();
        RefreshHistory();
        await LoadLatestReportAsync();
        _metricsTimer.Start();
        _ = RefreshIntegrationsAsync();

        if (_autoRun)
            await RunFullDiagnosisAsync();
    }

    private async void MetricsTimer_Tick(object? sender, EventArgs e)
    {
        if (_metricsBusy) return;
        _metricsBusy = true;
        try
        {
            var sample = await _metrics.GetAsync();
            CpuValue.Text = $"{sample.CpuPercent:0}%";
            SensorCpuValue.Text = CpuValue.Text;
            CpuBar.Value = sample.CpuPercent;
            SensorCpuBar.Value = sample.CpuPercent;

            MemoryValue.Text = $"{sample.MemoryPercent:0}%";
            SensorMemoryValue.Text = MemoryValue.Text;
            MemoryBar.Value = sample.MemoryPercent;
            SensorMemoryBar.Value = sample.MemoryPercent;

            CpuTempValue.Text = sample.CpuTemperatureC is double cpuTemp ? $"{cpuTemp:0.#}°C" : "—";
            SensorCpuTemp.Text = CpuTempValue.Text;
            SsdTempValue.Text = sample.SsdTemperatureC is double ssdTemp ? $"{ssdTemp:0.#}°C" : "—";
            SensorSsdTemp.Text = SsdTempValue.Text;
            LiveStatusText.Text = "Live • " + DateTime.Now.ToString("h:mm:ss tt");
        }
        catch
        {
            LiveStatusText.Text = "Live telemetry limited";
        }
        finally
        {
            _metricsBusy = false;
        }
    }

    private static bool IsAdministrator()
    {
        using var identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    private void RelaunchElevated(string? argument = null)
    {
        var executable = Environment.ProcessPath
            ?? throw new InvalidOperationException("Unable to locate the Windows Crash Doctor executable.");
        var psi = new ProcessStartInfo(executable)
        {
            UseShellExecute = true,
            Verb = "runas",
            Arguments = argument ?? string.Empty
        };
        try
        {
            Process.Start(psi);
            Application.Current.Shutdown();
        }
        catch
        {
            MessageBox.Show(this,
                "The diagnostic run was not started because Administrator permission was not granted.",
                "Windows Crash Doctor",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }
    }

    private async Task RunFullDiagnosisAsync()
    {
        if (_diagnosisRunning) return;
        if (!IsAdministrator())
        {
            RelaunchElevated("--run-diagnostics");
            return;
        }

        _diagnosisRunning = true;
        RunDiagnosisButton.IsEnabled = false;
        DiagnosticLog.Clear();
        DiagnosticProgress.Value = 5;
        DiagnosticStatusText.Text = "Preparing diagnostic engine…";
        MainTabs.SelectedIndex = 1;
        SetPage("Diagnostics", "Collecting current-machine evidence and ranking what matters");

        try
        {
            _engine.EnsureExtracted();
            AppendLog("Windows Crash Doctor full diagnosis started.");
            AppendLog("Evidence stays local on this PC unless you choose to export it.");

            DiagnosticProgress.Value = 15;
            DiagnosticStatusText.Text = "Collecting Windows, firmware, storage and power evidence…";
            var before = Directory.GetDirectories(_outputRoot, "HPProBook-*").ToHashSet(StringComparer.OrdinalIgnoreCase);
            var collect = await _powerShell.RunFileAsync(
                _engine.CollectorPath,
                new[] { "-OutputRoot", _outputRoot, "-EventHours", "12" },
                AppendLog);
            if (collect.ExitCode != 0)
                throw new InvalidOperationException("The diagnostic collector returned an error. See the live log for details.");

            DiagnosticProgress.Value = 62;
            DiagnosticStatusText.Text = "Analysing the new evidence snapshot…";
            var snapshots = new DirectoryInfo(_outputRoot)
                .GetDirectories("HPProBook-*")
                .OrderByDescending(d => d.LastWriteTimeUtc)
                .ToList();
            var snapshot = snapshots.FirstOrDefault(d => !before.Contains(d.FullName)) ?? snapshots.FirstOrDefault();
            if (snapshot is null)
                throw new InvalidOperationException("The collector completed but no diagnostic snapshot folder was found.");

            _latestEvidencePath = snapshot.FullName;
            var analyse = await _powerShell.RunFileAsync(
                _engine.CrashDoctorPath,
                new[] { "-EvidencePath", snapshot.FullName, "-OutputDirectory", snapshot.FullName },
                AppendLog);
            if (analyse.ExitCode != 0)
                throw new InvalidOperationException("Crash Doctor could not analyse the evidence snapshot.");

            DiagnosticProgress.Value = 88;
            DiagnosticStatusText.Text = "Building dashboard and history…";
            var reportPath = Path.Combine(snapshot.FullName, "crash-doctor-report.json");
            _latestReport = await ReadReportAsync(reportPath);
            _settings.LastEvidencePath = snapshot.FullName;
            _history.SaveSettings(_settings);

            var health = GetHealthLabel(_latestReport);
            _history.AddHistory(new DiagnosticRunHistory
            {
                RanAt = DateTimeOffset.Now,
                Status = "Completed",
                HealthLabel = health,
                EvidencePath = snapshot.FullName,
                Model = _latestReport.Inventory.Model ?? "Unknown device",
                HighCount = _latestReport.Findings.Count(f => f.Severity is "High" or "Critical"),
                MediumCount = _latestReport.Findings.Count(f => f.Severity == "Medium"),
                FindingCount = _latestReport.Findings.Count,
                CoveragePercent = _latestReport.Coverage.Percent
            });

            UpdateReportUi(_latestReport);
            RefreshHistory();
            DiagnosticProgress.Value = 100;
            DiagnosticStatusText.Text = $"Complete • {_latestReport.Findings.Count} evidence findings • {_latestReport.Coverage.Percent:0}% collection coverage";
            AppendLog("PASS: collection and analysis completed successfully.");
            AppendLog($"Report: {Path.Combine(snapshot.FullName, "crash-doctor-report.md")}");

            MainTabs.SelectedIndex = 0;
            SetPage("System Dashboard", "Fresh evidence from the completed diagnostic run");
        }
        catch (Exception ex)
        {
            DiagnosticStatusText.Text = "Diagnosis did not complete";
            AppendLog("FAILED: " + ex.Message);
            MessageBox.Show(this, ex.Message, "Windows Crash Doctor", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            RunDiagnosisButton.IsEnabled = true;
            _diagnosisRunning = false;
        }
    }

    private static async Task<CrashDoctorReport> ReadReportAsync(string reportPath)
    {
        if (!File.Exists(reportPath))
            throw new FileNotFoundException("Crash Doctor JSON report was not created.", reportPath);
        await using var stream = File.OpenRead(reportPath);
        return await JsonSerializer.DeserializeAsync<CrashDoctorReport>(stream, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        }) ?? throw new InvalidOperationException("Crash Doctor JSON report was empty or invalid.");
    }

    private async Task LoadLatestReportAsync()
    {
        try
        {
            string? candidate = null;
            if (!string.IsNullOrWhiteSpace(_settings.LastEvidencePath) && Directory.Exists(_settings.LastEvidencePath))
                candidate = _settings.LastEvidencePath;
            else
                candidate = new DirectoryInfo(_outputRoot).GetDirectories("HPProBook-*")
                    .OrderByDescending(d => d.LastWriteTimeUtc)
                    .Select(d => d.FullName)
                    .FirstOrDefault(path => File.Exists(Path.Combine(path, "crash-doctor-report.json")));

            if (candidate is null) return;
            var json = Path.Combine(candidate, "crash-doctor-report.json");
            if (!File.Exists(json)) return;
            _latestReport = await ReadReportAsync(json);
            _latestEvidencePath = candidate;
            UpdateReportUi(_latestReport);
        }
        catch
        {
        }
    }

    private static string GetHealthLabel(CrashDoctorReport report)
    {
        if (report.Findings.Any(f => f.Severity == "Critical")) return "Critical evidence detected";
        if (report.Findings.Any(f => f.Severity == "High")) return "Needs attention";
        if (report.Findings.Any(f => f.Severity == "Medium")) return "Review recommended";
        return "No high-priority signal detected";
    }

    private void UpdateReportUi(CrashDoctorReport report)
    {
        var high = report.Findings.Count(f => f.Severity is "High" or "Critical");
        var medium = report.Findings.Count(f => f.Severity == "Medium");
        var health = GetHealthLabel(report);

        HealthHeadline.Text = health;
        HealthExplanation.Text = high > 0
            ? $"Crash Doctor found {high} high-priority evidence signal{(high == 1 ? "" : "s")}. These are leads backed by captured evidence, not automatic claims of root cause."
            : medium > 0
                ? $"No critical/high signal in this snapshot. {medium} medium-priority lead{(medium == 1 ? "" : "s")} should be reviewed in a controlled test sequence."
                : "The captured window contains no high-priority signal. Missing evidence is still treated as unknown rather than healthy.";

        FindingCountText.Text = $"{report.Findings.Count} findings • {report.Coverage.Percent:0}% coverage";
        DashboardFindings.ItemsSource = report.Findings.Take(4).ToList();

        var next = report.Findings.FirstOrDefault(f => f.Severity is "Critical" or "High")
            ?? report.Findings.FirstOrDefault(f => f.Severity == "Medium")
            ?? report.Findings.FirstOrDefault();
        if (next is not null)
        {
            RecommendationTitle.Text = next.Title;
            RecommendationBody.Text = next.NextStep;
        }
        else
        {
            RecommendationTitle.Text = "Keep measuring stability";
            RecommendationBody.Text = "No ranked finding was produced in this snapshot. Continue controlled testing and preserve any new freeze evidence.";
        }

        MachineModelText.Text = report.Inventory.Model ?? "Unknown device";
        BiosText.Text = report.Inventory.BIOS ?? "Unknown";
        RamText.Text = report.Inventory.PhysicalMemoryGiB is double ram ? $"{ram:0.##} GiB" : "Unknown";
    }

    private void AppendLog(string line)
    {
        Dispatcher.Invoke(() =>
        {
            DiagnosticLog.AppendText($"[{DateTime.Now:HH:mm:ss}] {line}{Environment.NewLine}");
            DiagnosticLog.ScrollToEnd();
        });
    }

    private async void RunFullDiagnosis_Click(object sender, RoutedEventArgs e) => await RunFullDiagnosisAsync();

    private void OpenLatestReport_Click(object sender, RoutedEventArgs e)
    {
        if (_latestEvidencePath is null)
        {
            MessageBox.Show(this, "Run a diagnosis first.", "Windows Crash Doctor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var report = Path.Combine(_latestEvidencePath, "crash-doctor-report.md");
        OpenPath(File.Exists(report) ? report : _latestEvidencePath);
    }

    private async void AnalyseDump_Click(object sender, RoutedEventArgs e)
    {
        var picker = new OpenFileDialog
        {
            Title = "Choose a Windows dump file",
            Filter = "Windows dump files (*.dmp;*.mdmp)|*.dmp;*.mdmp|All files (*.*)|*.*"
        };
        if (picker.ShowDialog(this) != true) return;

        try
        {
            _engine.EnsureExtracted();
            var output = Path.Combine(_outputRoot, "Dump-" + DateTime.Now.ToString("yyyyMMdd-HHmmss"));
            Directory.CreateDirectory(output);
            DiagnosticLog.Clear();
            DiagnosticStatusText.Text = "Analysing dump…";
            MainTabs.SelectedIndex = 1;
            var result = await _powerShell.RunFileAsync(
                _engine.CrashDoctorPath,
                new[] { "-DumpPath", picker.FileName, "-OutputDirectory", output },
                AppendLog);
            if (result.ExitCode != 0) throw new InvalidOperationException("Dump analysis failed. See the diagnostic log.");
            DiagnosticStatusText.Text = "Dump analysis complete";
            OpenPath(Path.Combine(output, "crash-doctor-dump-report.md"));
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Dump analysis", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async void DeepSensorButton_Click(object sender, RoutedEventArgs e)
    {
        if (_sensorCts is not null)
        {
            _sensorCts.Cancel();
            return;
        }

        _sensorCts = new CancellationTokenSource();
        DeepSensorButton.Content = "Stop sensor log";
        DeepSensorStatusText.Text = "Installing/checking LibreHardwareMonitor…";
        DeepSensorProgress.Value = 2;

        try
        {
            _engine.EnsureExtracted();
            var install = await _powerShell.RunFileAsync(
                _engine.IntegrationManagerPath,
                new[] { "-Action", "install", "-Id", "librehardwaremonitor" },
                line => Dispatcher.Invoke(() => DeepSensorStatusText.Text = line),
                _sensorCts.Token);
            if (install.ExitCode != 0)
                throw new InvalidOperationException("LibreHardwareMonitor provider could not be prepared.");

            var output = Path.Combine(_outputRoot, $"sensor-{DateTime.Now:yyyyMMdd-HHmmss}.jsonl");
            DeepSensorStatusText.Text = "Recording deep sensor telemetry for 30 minutes…";
            var sensorTask = _powerShell.RunFileAsync(
                _engine.IntegrationManagerPath,
                new[] { "-Action", "sensors", "-DurationMinutes", "30", "-IntervalSeconds", "2", "-OutputPath", output },
                line => Dispatcher.Invoke(() => DeepSensorStatusText.Text = line),
                _sensorCts.Token);

            for (var second = 0; second < 1800 && !sensorTask.IsCompleted; second++)
            {
                await Task.Delay(1000, _sensorCts.Token);
                DeepSensorProgress.Value = Math.Min(99, 100.0 * second / 1800.0);
                var remaining = TimeSpan.FromSeconds(1800 - second).ToString(@"mm\:ss");
                DeepSensorStatusText.Text = $"Recording… {remaining} remaining • {Path.GetFileName(output)}";
            }

            var result = await sensorTask;
            if (result.ExitCode != 0)
                throw new InvalidOperationException("Deep sensor capture ended with an error.");
            DeepSensorProgress.Value = 100;
            DeepSensorStatusText.Text = $"Complete: {output}";
        }
        catch (OperationCanceledException)
        {
            DeepSensorStatusText.Text = "Sensor capture stopped. Samples already written remain available.";
        }
        catch (Exception ex)
        {
            DeepSensorStatusText.Text = "Sensor capture failed: " + ex.Message;
        }
        finally
        {
            _sensorCts.Dispose();
            _sensorCts = null;
            DeepSensorButton.Content = "Start 30-min Deep Sensor Log";
        }
    }

    private async void InstallIntegration_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button || button.Tag is not string id) return;
        button.IsEnabled = false;
        button.Content = "Working…";
        try
        {
            _engine.EnsureExtracted();
            var result = await _powerShell.RunFileAsync(
                _engine.IntegrationManagerPath,
                new[] { "-Action", "install", "-Id", id },
                line => Dispatcher.Invoke(() => IntegrationStatusText.AppendText(line + Environment.NewLine)));
            button.Content = result.ExitCode == 0 ? "Ready" : "Retry";
            await RefreshIntegrationsAsync();
        }
        catch (Exception ex)
        {
            button.Content = "Retry";
            IntegrationStatusText.AppendText($"{id}: {ex.Message}{Environment.NewLine}");
        }
        finally
        {
            button.IsEnabled = true;
        }
    }

    private async Task RefreshIntegrationsAsync()
    {
        try
        {
            _engine.EnsureExtracted();
            var result = await _powerShell.RunFileAsync(_engine.IntegrationManagerPath, new[] { "-Action", "status" });
            IntegrationStatusText.Text = string.IsNullOrWhiteSpace(result.StandardOutput)
                ? "Provider status is not available yet."
                : result.StandardOutput.Trim();
        }
        catch (Exception ex)
        {
            IntegrationStatusText.Text = "Provider status unavailable: " + ex.Message;
        }
    }

    private async void RefreshIntegrations_Click(object sender, RoutedEventArgs e) => await RefreshIntegrationsAsync();

    private void RefreshHistory()
    {
        var items = _history.LoadHistory();
        HistoryList.ItemsSource = items;
        NoHistoryText.Visibility = items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void RefreshHistory_Click(object sender, RoutedEventArgs e) => RefreshHistory();
    private void OpenResultsFolder_Click(object sender, RoutedEventArgs e) => OpenPath(_outputRoot);

    private void ExportLatestBundle_Click(object sender, RoutedEventArgs e)
    {
        if (_latestEvidencePath is null || !Directory.Exists(_latestEvidencePath))
        {
            MessageBox.Show(this, "There is no completed diagnostic run to export yet.", "Windows Crash Doctor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var answer = MessageBox.Show(this,
            "Diagnostic bundles can contain usernames, device identifiers, event logs and other private information. Create a local ZIP anyway?",
            "Export diagnostic bundle",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);
        if (answer != MessageBoxResult.Yes) return;

        try
        {
            var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            var zip = Path.Combine(desktop, $"WindowsCrashDoctor-{DateTime.Now:yyyyMMdd-HHmmss}.zip");
            ZipFile.CreateFromDirectory(_latestEvidencePath, zip, CompressionLevel.Optimal, includeBaseDirectory: true);
            OpenPath(desktop);
            MessageBox.Show(this, $"Created:\n{zip}", "Export complete", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Export failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void ThemeButton_Click(object sender, RoutedEventArgs e)
    {
        _settings.DarkMode = !_settings.DarkMode;
        ApplyTheme(_settings.DarkMode);
        _history.SaveSettings(_settings);
    }

    private static Brush BrushFrom(string hex) => (Brush)new BrushConverter().ConvertFromString(hex)!;

    private void ApplyTheme(bool dark)
    {
        var resources = Application.Current.Resources;
        if (dark)
        {
            resources["WindowBackground"] = BrushFrom("#0B1020");
            resources["PanelBackground"] = BrushFrom("#121A2B");
            resources["PanelBorder"] = BrushFrom("#253047");
            resources["PrimaryText"] = BrushFrom("#F2F4F7");
            resources["SecondaryText"] = BrushFrom("#A7B0C0");
            resources["MutedText"] = BrushFrom("#738099");
            resources["AccentSoft"] = BrushFrom("#172554");
            resources["GoodSoft"] = BrushFrom("#073B2A");
            ThemeButton.Content = "Light mode";
        }
        else
        {
            resources["WindowBackground"] = BrushFrom("#F3F6FB");
            resources["PanelBackground"] = BrushFrom("#FFFFFF");
            resources["PanelBorder"] = BrushFrom("#E4EAF2");
            resources["PrimaryText"] = BrushFrom("#172033");
            resources["SecondaryText"] = BrushFrom("#667085");
            resources["MutedText"] = BrushFrom("#98A2B3");
            resources["AccentSoft"] = BrushFrom("#EAF1FF");
            resources["GoodSoft"] = BrushFrom("#ECFDF3");
            ThemeButton.Content = "Dark mode";
        }
    }

    private static void OpenPath(string path)
    {
        if (!File.Exists(path) && !Directory.Exists(path)) return;
        Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
    }

    private void SetPage(string title, string subtitle)
    {
        PageTitle.Text = title;
        PageSubtitle.Text = subtitle;
    }

    private void DashboardNav_Click(object sender, RoutedEventArgs e) { MainTabs.SelectedIndex = 0; SetPage("System Dashboard", "Live health and the latest diagnostic evidence"); }
    private void DiagnosticsNav_Click(object sender, RoutedEventArgs e) { MainTabs.SelectedIndex = 1; SetPage("Diagnostics", "Collect and analyse current-machine evidence"); }
    private void SensorsNav_Click(object sender, RoutedEventArgs e) { MainTabs.SelectedIndex = 2; SetPage("Live Sensors", "Watch load and temperature behaviour before a freeze"); }
    private void HistoryNav_Click(object sender, RoutedEventArgs e) { MainTabs.SelectedIndex = 3; SetPage("Diagnostic History", "Compare previous runs without losing the evidence trail"); RefreshHistory(); }
    private void IntegrationsNav_Click(object sender, RoutedEventArgs e) { MainTabs.SelectedIndex = 4; SetPage("Integrations", "Optional open-source diagnostic providers with explicit safety boundaries"); _ = RefreshIntegrationsAsync(); }
    private void SettingsNav_Click(object sender, RoutedEventArgs e) { MainTabs.SelectedIndex = 5; SetPage("Settings", "Appearance, evidence storage and privacy"); }
}
