using Microsoft.Win32;
using System.Diagnostics;
using System.Security.Principal;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using WindowsCrashDoctor.Models;
using WindowsCrashDoctor.Presentation;
using WindowsCrashDoctor.Services;

namespace WindowsCrashDoctor;

public partial class MainWindow : Window
{
    private readonly bool _autoRun;
    private readonly EngineExtractor _engine = new();
    private readonly PowerShellRunner _powerShell = new();
    private readonly HistoryService _history = new();
    private readonly CrashDoctorReportReader _reportReader = new();
    private readonly SystemMetricsService _metrics;
    private readonly DiagnosticWorkflowService _diagnostics;
    private readonly IntegrationWorkflowService _integrations;
    private readonly DispatcherTimer _metricsTimer;
    private readonly string _outputRoot;
    private readonly List<string> _startupWarnings = new();

    private AppSettings _settings = new();
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
        _diagnostics = new DiagnosticWorkflowService(_engine, _powerShell, _reportReader, _history);
        _integrations = new IntegrationWorkflowService(_engine, _powerShell);
        _outputRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
            "Windows Crash Doctor Results");
        Directory.CreateDirectory(_outputRoot);

        try
        {
            _settings = _history.LoadSettings();
        }
        catch (Exception ex)
        {
            _settings = new AppSettings();
            _startupWarnings.Add("Saved settings could not be loaded: " + ex.Message);
        }

        _metricsTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
        _metricsTimer.Tick += MetricsTimer_Tick;
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        ApplyTheme(_settings.DarkMode);
        AdminStatusText.Text = IsAdministrator()
            ? "App is elevated • normal launches use least privilege"
            : "Standard mode • collection elevates only when needed";

        try
        {
            _engine.EnsureExtracted();
        }
        catch (Exception ex)
        {
            ShowStartupFailure("The diagnostic engine could not be prepared.", ex);
            return;
        }

        RefreshHistory();
        await LoadLatestReportAsync();
        _metricsTimer.Start();
        _ = RefreshIntegrationsAsync();

        if (_startupWarnings.Count > 0)
        {
            DiagnosticStatusText.Text = "Started with a local-state warning";
            foreach (var warning in _startupWarnings)
                AppendLog("WARNING: " + warning);
        }

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
            SetMetric(sample.CpuPercent, CpuValue, CpuBar, SensorCpuValue, SensorCpuBar);
            SetMetric(sample.MemoryPercent, MemoryValue, MemoryBar, SensorMemoryValue, SensorMemoryBar);

            CpuTempValue.Text = FormatTemperature(sample.CpuTemperatureC);
            SensorCpuTemp.Text = CpuTempValue.Text;
            SsdTempValue.Text = FormatTemperature(sample.SsdTemperatureC);
            SensorSsdTemp.Text = SsdTempValue.Text;
            LiveStatusText.Text = sample.Warning is null
                ? "Live • " + DateTime.Now.ToString("h:mm:ss tt")
                : "Live telemetry limited • " + DateTime.Now.ToString("h:mm:ss tt");
            LiveStatusText.ToolTip = sample.Warning;
        }
        catch (Exception ex)
        {
            LiveStatusText.Text = "Live telemetry unavailable";
            LiveStatusText.ToolTip = ex.Message;
            SetMetric(null, CpuValue, CpuBar, SensorCpuValue, SensorCpuBar);
            SetMetric(null, MemoryValue, MemoryBar, SensorMemoryValue, SensorMemoryBar);
        }
        finally
        {
            _metricsBusy = false;
        }
    }

    private async Task RunFullDiagnosisAsync()
    {
        if (_diagnosisRunning) return;
        _diagnosisRunning = true;
        RunDiagnosisButton.IsEnabled = false;
        DiagnosticLog.Clear();
        DiagnosticProgress.Value = 5;
        DiagnosticStatusText.Text = "Preparing diagnostic engine…";
        MainTabs.SelectedIndex = 1;
        SetPage("Diagnostics", "Collecting current-machine evidence and ranking what matters");

        var progress = new Progress<DiagnosticProgressUpdate>(update =>
        {
            DiagnosticProgress.Value = update.Percent;
            DiagnosticStatusText.Text = update.Status;
        });

        try
        {
            AppendLog("Windows Crash Doctor full diagnosis started.");
            AppendLog("Evidence stays local on this PC unless you choose a privacy-reviewed export.");
            var result = await _diagnostics.RunFullDiagnosisAsync(
                _outputRoot,
                eventHours: 12,
                progress,
                AppendLog);

            _latestReport = result.Report;
            _latestEvidencePath = result.EvidencePath;
            _settings.LastEvidencePath = result.EvidencePath;
            UpdateReportUi(result.Report);
            RefreshHistory();

            var partial = result.CollectionStatus?.CompletedWithErrors == true
                ? $" • {result.CollectionStatus.FailureCount} collection gap(s) recorded"
                : string.Empty;
            DiagnosticStatusText.Text =
                $"Complete • {result.Report.Findings.Count} evidence findings • {result.Report.Coverage.Percent:0}% collection coverage{partial}";
            AppendLog("PASS: collection and analysis completed successfully.");
            AppendLog("Report: " + result.MarkdownReportPath);
            MainTabs.SelectedIndex = 0;
            SetPage("System Dashboard", "Fresh evidence from the completed diagnostic run");
        }
        catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            DiagnosticStatusText.Text = "Diagnosis cancelled before elevated collection";
            AppendLog("CANCELLED: Administrator permission was not granted for the evidence collector.");
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

    private async Task LoadLatestReportAsync()
    {
        string? candidate = null;
        try
        {
            if (!string.IsNullOrWhiteSpace(_settings.LastEvidencePath) && Directory.Exists(_settings.LastEvidencePath))
                candidate = _settings.LastEvidencePath;
            else
                candidate = FindLatestCompletedEvidenceDirectory();

            if (candidate is null)
                return;

            var json = Path.Combine(candidate, "crash-doctor-report.json");
            _latestReport = await _reportReader.ReadAsync(json);
            _latestEvidencePath = candidate;
            UpdateReportUi(_latestReport);
        }
        catch (Exception ex)
        {
            HealthHeadline.Text = "Saved report unavailable";
            HealthExplanation.Text = "A previous report exists but could not be safely loaded. Run a new diagnosis or inspect the diagnostic log.";
            DiagnosticStatusText.Text = "Previous report failed validation";
            AppendLog($"WARNING: previous report '{candidate ?? "(unknown)"}' was not loaded: {ex.Message}");
        }
    }

    private string? FindLatestCompletedEvidenceDirectory()
    {
        if (!Directory.Exists(_outputRoot))
            return null;

        return new DirectoryInfo(_outputRoot)
            .GetDirectories("HPProBook-*")
            .OrderByDescending(d => d.LastWriteTimeUtc)
            .Select(d => d.FullName)
            .FirstOrDefault(path => File.Exists(Path.Combine(path, "crash-doctor-report.json")));
    }

    private void UpdateReportUi(CrashDoctorReport report)
    {
        var high = report.Findings.Count(f => f.Severity is "High" or "Critical");
        var medium = report.Findings.Count(f => f.Severity == "Medium");
        HealthHeadline.Text = DiagnosticWorkflowService.GetHealthLabel(report);
        HealthExplanation.Text = high > 0
            ? $"Crash Doctor found {high} high-priority evidence signal{(high == 1 ? "" : "s")}. These are evidence-backed leads, not automatic claims of root cause."
            : medium > 0
                ? $"No critical/high signal in this snapshot. {medium} medium-priority lead{(medium == 1 ? "" : "s")} should be reviewed in a controlled test sequence."
                : "The captured window contains no high-priority signal. Missing evidence is still treated as unknown rather than healthy.";

        FindingCountText.Text = $"{report.Findings.Count} findings • {report.Coverage.Percent:0}% coverage";
        DashboardFindings.ItemsSource = report.Findings.Take(4)
            .Select(DiagnosticFindingViewModel.From)
            .ToList();

        var next = report.Findings.FirstOrDefault(f => f.Severity is "Critical" or "High")
            ?? report.Findings.FirstOrDefault(f => f.Severity == "Medium")
            ?? report.Findings.FirstOrDefault();
        RecommendationTitle.Text = next?.Title ?? "Keep measuring stability";
        RecommendationBody.Text = next?.NextStep
            ?? "No ranked finding was produced in this snapshot. Continue controlled testing and preserve any new freeze evidence.";

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

        DiagnosticLog.Clear();
        DiagnosticStatusText.Text = "Analysing dump…";
        MainTabs.SelectedIndex = 1;
        try
        {
            var result = await _diagnostics.AnalyseDumpAsync(picker.FileName, _outputRoot, AppendLog);
            DiagnosticStatusText.Text = "Dump analysis complete";
            OpenPath(result.MarkdownReportPath);
        }
        catch (Exception ex)
        {
            DiagnosticStatusText.Text = "Dump analysis failed";
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
        var progress = new Progress<SensorCaptureProgress>(update =>
        {
            DeepSensorProgress.Value = update.Percent;
            DeepSensorStatusText.Text = update.Status;
        });

        try
        {
            await _integrations.CaptureSensorsAsync(
                _outputRoot,
                TimeSpan.FromMinutes(30),
                intervalSeconds: 2,
                progress,
                line => Dispatcher.Invoke(() => DeepSensorStatusText.Text = line),
                _sensorCts.Token);
        }
        catch (OperationCanceledException)
        {
            DeepSensorStatusText.Text = "Sensor capture stopped. Samples already written remain available.";
        }
        catch (Exception ex)
        {
            DeepSensorStatusText.Text = "Sensor capture failed";
            MessageBox.Show(this, ex.Message, "Deep sensor capture", MessageBoxButton.OK, MessageBoxImage.Error);
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
            await _integrations.InstallAsync(
                id,
                line => Dispatcher.Invoke(() => IntegrationStatusText.AppendText(line + Environment.NewLine)));
            button.Content = "Ready";
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
            IntegrationStatusText.Text = await _integrations.GetStatusAsync();
        }
        catch (Exception ex)
        {
            IntegrationStatusText.Text = "Provider status unavailable: " + ex.Message;
        }
    }

    private async void RefreshIntegrations_Click(object sender, RoutedEventArgs e) => await RefreshIntegrationsAsync();

    private void RefreshHistory()
    {
        try
        {
            var items = _history.LoadHistory()
                .Select(DiagnosticRunHistoryViewModel.From)
                .ToList();
            HistoryList.ItemsSource = items;
            NoHistoryText.Text = "No diagnostic runs yet.";
            NoHistoryText.Visibility = items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        }
        catch (Exception ex)
        {
            HistoryList.ItemsSource = null;
            NoHistoryText.Text = "Diagnostic history could not be loaded. " + ex.Message;
            NoHistoryText.Visibility = Visibility.Visible;
        }
    }

    private void RefreshHistory_Click(object sender, RoutedEventArgs e) => RefreshHistory();
    private void OpenResultsFolder_Click(object sender, RoutedEventArgs e) => OpenPath(_outputRoot);

    private void ThemeButton_Click(object sender, RoutedEventArgs e)
    {
        var previous = _settings.DarkMode;
        _settings.DarkMode = !previous;
        ApplyTheme(_settings.DarkMode);
        try
        {
            _history.SaveSettings(_settings);
        }
        catch (Exception ex)
        {
            _settings.DarkMode = previous;
            ApplyTheme(previous);
            MessageBox.Show(this, "The theme could not be saved: " + ex.Message, "Windows Crash Doctor", MessageBoxButton.OK, MessageBoxImage.Warning);
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
            resources["PanelBorder"] = BrushFrom("#344054");
            resources["PrimaryText"] = BrushFrom("#F2F4F7");
            resources["SecondaryText"] = BrushFrom("#D0D5DD");
            resources["MutedText"] = BrushFrom("#A7B0C0");
            resources["AccentSoft"] = BrushFrom("#172554");
            resources["GoodSoft"] = BrushFrom("#073B2A");
            ThemeButton.Content = "Light mode";
        }
        else
        {
            resources["WindowBackground"] = BrushFrom("#F3F6FB");
            resources["PanelBackground"] = BrushFrom("#FFFFFF");
            resources["PanelBorder"] = BrushFrom("#D0D5DD");
            resources["PrimaryText"] = BrushFrom("#172033");
            resources["SecondaryText"] = BrushFrom("#475467");
            resources["MutedText"] = BrushFrom("#667085");
            resources["AccentSoft"] = BrushFrom("#EAF1FF");
            resources["GoodSoft"] = BrushFrom("#ECFDF3");
            ThemeButton.Content = "Dark mode";
        }
    }

    private static void SetMetric(
        double? value,
        TextBlock primaryText,
        ProgressBar primaryBar,
        TextBlock sensorText,
        ProgressBar sensorBar)
    {
        var text = value is double metric ? $"{metric:0}%" : "—";
        primaryText.Text = text;
        sensorText.Text = text;
        primaryBar.Value = value ?? 0;
        sensorBar.Value = value ?? 0;
        primaryBar.IsEnabled = value is not null;
        sensorBar.IsEnabled = value is not null;
    }

    private static string FormatTemperature(double? temperature) =>
        temperature is double value ? $"{value:0.#}°C" : "—";

    private static bool IsAdministrator()
    {
        using var identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    private void ShowStartupFailure(string message, Exception ex)
    {
        DiagnosticStatusText.Text = "Startup failed";
        AppendLog("FAILED: " + ex.Message);
        MessageBox.Show(this, message + Environment.NewLine + ex.Message, "Windows Crash Doctor", MessageBoxButton.OK, MessageBoxImage.Error);
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
