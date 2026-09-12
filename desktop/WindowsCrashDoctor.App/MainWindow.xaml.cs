using Microsoft.Win32;
using System.Diagnostics;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using WindowsCrashDoctor.Models;
using WindowsCrashDoctor.Presentation;
using WindowsCrashDoctor.Services;

namespace WindowsCrashDoctor;

public partial class MainWindow : Window
{
    private readonly bool _autoRun;
    private readonly EngineExtractor _engine;
    private readonly PowerShellRunner _powerShell;
    private readonly HistoryService _history;
    private readonly CrashDoctorReportReader _reportReader;
    private readonly DiagnosticWorkflowService _workflow;
    private readonly IntegrationService _integrations;
    private readonly SystemMetricsService _metrics;
    private readonly RedactionService _redaction = new();
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
        _engine = new EngineExtractor();
        _powerShell = new PowerShellRunner();
        _history = new HistoryService();
        _reportReader = new CrashDoctorReportReader(_engine);
        _workflow = new DiagnosticWorkflowService(
            _engine,
            _powerShell,
            _history,
            _reportReader,
            new PreflightService(),
            new FingerprintService(),
            new RunComparisonService(),
            new ReportEnrichmentService());
        _integrations = new IntegrationService(_engine, _powerShell);
        _metrics = new SystemMetricsService(_powerShell);
        _settings = _history.LoadSettings();
        _outputRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
            "Windows Crash Doctor Results");
        Directory.CreateDirectory(_outputRoot);

        // The original 1080px minimum made the app unnecessarily unusable on smaller laptops.
        MinWidth = 760;
        MinHeight = 560;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        ConfigureAccessibility();

        _metricsTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
        _metricsTimer.Tick += MetricsTimer_Tick;
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        ApplyTheme(_settings.DarkMode);
        AdminStatusText.Text = "Standard-user desktop • collector elevates only when needed";
        try
        {
            _engine.EnsureExtracted();
            await InitialiseV2Async();
            RefreshHistory();
            await LoadLatestReportAsync();
            _metricsTimer.Start();
            _ = RefreshIntegrationsAsync();

            if (!string.IsNullOrWhiteSpace(_history.StartupWarning))
                AppendLog("PERSISTENCE WARNING: " + _history.StartupWarning);

            if (_autoRun)
                await RunFullDiagnosisAsync();
            else
                RunDiagnosisButton.Focus();
        }
        catch (Exception ex)
        {
            var safe = _redaction.RedactForLog(ex.Message);
            DiagnosticStatusText.Text = "Startup is degraded: " + safe;
            AppendLog("STARTUP WARNING: " + safe);
            MessageBox.Show(this, safe, "Windows Crash Doctor startup", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void ConfigureAccessibility()
    {
        KeyboardNavigation.SetTabNavigation(this, KeyboardNavigationMode.Continue);
        KeyboardNavigation.SetDirectionalNavigation(this, KeyboardNavigationMode.Contained);

        AutomationProperties.SetName(RunDiagnosisButton, "Run full Windows Crash Doctor diagnosis");
        AutomationProperties.SetName(DiagnosticLog, "Live diagnostic log");
        AutomationProperties.SetName(DeepSensorButton, "Start or stop deep sensor log");
        AutomationProperties.SetName(HistoryList, "Diagnostic history");
        AutomationProperties.SetName(IntegrationStatusText, "Integration provider status");
        AutomationProperties.SetName(DashboardFindings, "Latest diagnostic findings");
        AutomationProperties.SetLiveSetting(DiagnosticStatusText, AutomationLiveSetting.Polite);
        AutomationProperties.SetLiveSetting(LiveStatusText, AutomationLiveSetting.Polite);
        AutomationProperties.SetLiveSetting(DeepSensorStatusText, AutomationLiveSetting.Polite);
    }

    private async void MetricsTimer_Tick(object? sender, EventArgs e)
    {
        if (_metricsBusy) return;
        _metricsBusy = true;
        try
        {
            var sample = await _metrics.GetAsync();
            SetPercentMetric(CpuValue, SensorCpuValue, CpuBar, SensorCpuBar, sample.CpuPercent);
            SetPercentMetric(MemoryValue, SensorMemoryValue, MemoryBar, SensorMemoryBar, sample.MemoryPercent);

            CpuTempValue.Text = sample.CpuTemperatureC is double cpuTemp ? $"{cpuTemp:0.#}°C" : "—";
            SensorCpuTemp.Text = CpuTempValue.Text;
            SsdTempValue.Text = sample.SsdTemperatureC is double ssdTemp ? $"{ssdTemp:0.#}°C" : "—";
            SensorSsdTemp.Text = SsdTempValue.Text;
            LiveStatusText.Text = string.IsNullOrWhiteSpace(sample.Warning)
                ? "Live • " + DateTime.Now.ToString("h:mm:ss tt")
                : "Live telemetry limited • " + _redaction.RedactForLog(sample.Warning);
        }
        catch (Exception ex)
        {
            LiveStatusText.Text = "Live telemetry unavailable • " + _redaction.RedactForLog(ex.Message);
        }
        finally
        {
            _metricsBusy = false;
        }
    }

    private static void SetPercentMetric(
        TextBlock primary,
        TextBlock sensor,
        ProgressBar primaryBar,
        ProgressBar sensorBar,
        double? value)
    {
        var text = value is double percent ? $"{percent:0}%" : "—";
        primary.Text = text;
        sensor.Text = text;
        primaryBar.Value = value ?? 0;
        sensorBar.Value = value ?? 0;
        primaryBar.ToolTip = value is null ? "Metric unavailable" : null;
        sensorBar.ToolTip = value is null ? "Metric unavailable" : null;
    }

    private async Task RunFullDiagnosisAsync()
    {
        if (_diagnosisRunning) return;

        _diagnosisRunning = true;
        RunDiagnosisButton.IsEnabled = false;
        DiagnosticLog.Clear();
        DiagnosticProgress.Value = 5;
        DiagnosticStatusText.Text = "Running preflight…";
        MainTabs.SelectedIndex = 1;
        SetPage("Diagnostics", "Preflight → collect → analyse → compare → persist → export safely");

        try
        {
            AppendLog("Windows Crash Doctor diagnosis started.");
            AppendLog("Evidence stays local on this PC unless you choose to export it.");
            var progress = new Progress<DiagnosticWorkflowProgress>(update =>
            {
                DiagnosticProgress.Value = Math.Clamp(update.Percent, 0, 100);
                DiagnosticStatusText.Text = update.Status;
            });

            var result = await _workflow.RunFullDiagnosisAsync(
                _outputRoot,
                eventHours: 12,
                progress,
                AppendLog);

            _latestReport = result.Report;
            _latestEvidencePath = result.EvidencePath;
            _latestComparison = result.Comparison;
            _latestPreflight = result.Preflight;
            _settings.LastEvidencePath = result.EvidencePath;

            UpdateReportUi(result.Report);
            ApplyV2DashboardSummary();
            RefreshHistory();
            DiagnosticProgress.Value = 100;
            DiagnosticStatusText.Text = result.Warnings.Count == 0
                ? $"Complete • {result.Report.Findings.Count} findings • {result.Report.Coverage.Percent:0}% coverage • {TimeSpan.FromMilliseconds(result.RunHistory.DurationMs):g}"
                : $"Complete with {result.Warnings.Count} warning(s) • {result.Report.Findings.Count} findings";
            AppendLog("PASS: collection, analysis, fingerprinting and comparison completed.");
            AppendLog("CHANGE SUMMARY: " + result.RunHistory.ComparisonSummary);
            foreach (var warning in result.Warnings)
                AppendLog("WARNING: " + warning);
            AppendLog("Report: " + result.RunHistory.ReportPath);

            MainTabs.SelectedIndex = 0;
            SetPage("System Dashboard", "Fresh evidence plus change detection from the previous comparable run");
        }
        catch (Exception ex)
        {
            DiagnosticStatusText.Text = "Diagnosis did not complete";
            AppendLog("FAILED: " + ex.Message);
            MessageBox.Show(this, _redaction.RedactForLog(ex.Message), "Windows Crash Doctor", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            RunDiagnosisButton.IsEnabled = true;
            _diagnosisRunning = false;
        }
    }

    private async Task LoadLatestReportAsync()
    {
        if (string.IsNullOrWhiteSpace(_settings.LastEvidencePath) || !Directory.Exists(_settings.LastEvidencePath))
            return;

        try
        {
            var candidate = Path.GetFullPath(_settings.LastEvidencePath);
            var json = Path.Combine(candidate, "crash-doctor-report.json");
            _latestReport = await _reportReader.ReadAsync(json);
            _latestEvidencePath = candidate;
            _latestComparison = _latestReport.Comparison;
            UpdateReportUi(_latestReport);
            ApplyV2DashboardSummary();
        }
        catch (Exception ex)
        {
            DiagnosticStatusText.Text = "Previous report could not be loaded: " + _redaction.RedactForLog(ex.Message);
            AppendLog("REPORT WARNING: " + ex.Message);
        }
    }

    private void UpdateReportUi(CrashDoctorReport report)
    {
        var high = report.Findings.Count(f => f.Severity is "High" or "Critical");
        var medium = report.Findings.Count(f => f.Severity == "Medium");
        var health = DiagnosticWorkflowService.GetHealthLabel(report);

        HealthHeadline.Text = health;
        HealthExplanation.Text = high > 0
            ? $"Crash Doctor found {high} high-priority evidence signal{(high == 1 ? "" : "s")}. These are leads backed by captured evidence, not automatic claims of root cause."
            : medium > 0
                ? $"No critical/high signal in this snapshot. {medium} medium-priority lead{(medium == 1 ? "" : "s")} should be reviewed in a controlled test sequence."
                : "The captured window contains no high-priority signal. Missing evidence is still treated as unknown rather than healthy.";

        FindingCountText.Text = $"{report.Findings.Count} findings • {report.Coverage.Percent:0}% coverage";
        DashboardFindings.ItemsSource = report.Findings.Take(4).Select(DiagnosticFindingViewModel.From).ToList();

        var next = report.Findings.FirstOrDefault(f => f.Severity is "Critical" or "High")
            ?? report.Findings.FirstOrDefault(f => f.Severity == "Medium")
            ?? report.Findings.FirstOrDefault();
        if (next is not null)
        {
            RecommendationTitle.Text = next.ComparisonState is "NEW" or "WORSENED" ? $"{next.ComparisonState}: {next.Title}" : next.Title;
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
            var safe = _redaction.RedactForLog(line);
            DiagnosticLog.AppendText($"[{DateTime.Now:HH:mm:ss}] {safe}{Environment.NewLine}");
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
            var output = Path.Combine(_outputRoot, $"Dump-{DateTime.UtcNow:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}"[..37]);
            Directory.CreateDirectory(output);
            DiagnosticLog.Clear();
            DiagnosticStatusText.Text = "Analysing dump…";
            MainTabs.SelectedIndex = 1;
            var result = await _powerShell.RunFileAsync(
                _engine.CrashDoctorPath,
                new[] { "-DumpPath", picker.FileName, "-OutputDirectory", output },
                AppendLog,
                options: new ProcessRunOptions(TimeSpan.FromMinutes(2), OperationId: "dump-analysis"));
            if (!result.Succeeded) throw new InvalidOperationException($"Dump analysis ended as {result.Status}: {result.FailureReason}");
            DiagnosticStatusText.Text = $"Dump analysis complete • {result.Duration:g}";
            OpenPath(Path.Combine(output, "crash-doctor-dump-report.md"));
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, _redaction.RedactForLog(ex.Message), "Dump analysis", MessageBoxButton.OK, MessageBoxImage.Error);
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
            var install = await _integrations.InstallAsync(
                "librehardwaremonitor",
                line => Dispatcher.Invoke(() => DeepSensorStatusText.Text = _redaction.RedactForLog(line)),
                _sensorCts.Token);
            if (!install.Succeeded)
                throw new InvalidOperationException($"LibreHardwareMonitor provider preparation ended as {install.Status}.");

            var output = Path.Combine(_outputRoot, $"sensor-{DateTime.Now:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}.jsonl");
            DeepSensorStatusText.Text = "Recording deep sensor telemetry for 30 minutes…";
            var sensorTask = _integrations.CaptureSensorsAsync(
                output,
                durationMinutes: 30,
                intervalSeconds: 2,
                line => Dispatcher.Invoke(() => DeepSensorStatusText.Text = _redaction.RedactForLog(line)),
                _sensorCts.Token);

            for (var second = 0; second < 1800 && !sensorTask.IsCompleted; second++)
            {
                await Task.Delay(1000, _sensorCts.Token);
                DeepSensorProgress.Value = Math.Min(99, 100.0 * second / 1800.0);
                var remaining = TimeSpan.FromSeconds(1800 - second).ToString(@"mm\:ss");
                DeepSensorStatusText.Text = $"Recording… {remaining} remaining • {Path.GetFileName(output)}";
            }

            var result = await sensorTask;
            if (!result.Succeeded)
                throw new InvalidOperationException($"Deep sensor capture ended as {result.Status}.");
            DeepSensorProgress.Value = 100;
            DeepSensorStatusText.Text = $"Complete: {output}";
        }
        catch (OperationCanceledException)
        {
            DeepSensorStatusText.Text = "Sensor capture stopped. Samples already written remain available.";
        }
        catch (Exception ex)
        {
            DeepSensorStatusText.Text = "Sensor capture failed: " + _redaction.RedactForLog(ex.Message);
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
            var result = await _integrations.InstallAsync(
                id,
                line => Dispatcher.Invoke(() => IntegrationStatusText.AppendText(_redaction.RedactForLog(line) + Environment.NewLine)));
            button.Content = result.Succeeded ? "Ready" : "Retry";
            await RefreshIntegrationsAsync();
        }
        catch (Exception ex)
        {
            button.Content = "Retry";
            IntegrationStatusText.AppendText($"{id}: {_redaction.RedactForLog(ex.Message)}{Environment.NewLine}");
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
            var result = await _integrations.GetStatusAsync();
            IntegrationStatusText.Text = string.IsNullOrWhiteSpace(result.StandardOutput)
                ? $"Provider status is not available ({result.Status})."
                : _redaction.RedactForLog(result.StandardOutput.Trim());
        }
        catch (Exception ex)
        {
            IntegrationStatusText.Text = "Provider status unavailable: " + _redaction.RedactForLog(ex.Message);
        }
    }

    private async void RefreshIntegrations_Click(object sender, RoutedEventArgs e) => await RefreshIntegrationsAsync();

    private void RefreshHistory()
    {
        try
        {
            var items = _history.LoadHistory();
            HistoryList.ItemsSource = items;
            NoHistoryText.Text = items.Count == 0 ? "No diagnostic runs yet." : string.Empty;
            NoHistoryText.Visibility = items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        }
        catch (Exception ex)
        {
            HistoryList.ItemsSource = null;
            NoHistoryText.Text = "History database unavailable: " + _redaction.RedactForLog(ex.Message);
            NoHistoryText.Visibility = Visibility.Visible;
        }
    }

    private void RefreshHistory_Click(object sender, RoutedEventArgs e) => RefreshHistory();
    private void OpenResultsFolder_Click(object sender, RoutedEventArgs e) => OpenPath(_outputRoot);

    private void ThemeButton_Click(object sender, RoutedEventArgs e)
    {
        _settings.DarkMode = !_settings.DarkMode;
        ApplyTheme(_settings.DarkMode);
        try
        {
            _history.SaveSettings(_settings);
        }
        catch (Exception ex)
        {
            var safe = _redaction.RedactForLog(ex.Message);
            DiagnosticStatusText.Text = "Theme changed for this session; settings could not be saved: " + safe;
            AppendLog("SETTINGS WARNING: " + safe);
        }
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
    private void DiagnosticsNav_Click(object sender, RoutedEventArgs e) { MainTabs.SelectedIndex = 1; SetPage("Diagnostics", "Preflight, collect, analyse, fingerprint and compare evidence"); }
    private void SensorsNav_Click(object sender, RoutedEventArgs e) { MainTabs.SelectedIndex = 2; SetPage("Live Sensors", "Watch load and temperature behaviour before a freeze"); }
    private void HistoryNav_Click(object sender, RoutedEventArgs e) { MainTabs.SelectedIndex = 3; SetPage("Diagnostic History", "SQLite-backed runs and change summaries"); RefreshHistory(); }
    private void IntegrationsNav_Click(object sender, RoutedEventArgs e) { MainTabs.SelectedIndex = 4; SetPage("Integrations", "Optional providers with bounded retries and explicit health states"); _ = RefreshIntegrationsAsync(); }
    private void SettingsNav_Click(object sender, RoutedEventArgs e) { MainTabs.SelectedIndex = 5; SetPage("Settings", "Appearance, evidence storage and privacy"); }
}
