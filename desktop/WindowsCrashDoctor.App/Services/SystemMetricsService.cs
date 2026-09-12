using System.Runtime.InteropServices;
using System.Text.Json;

namespace WindowsCrashDoctor.Services;

public sealed record SystemMetrics(
    double? CpuPercent,
    double? MemoryPercent,
    double? CpuTemperatureC,
    double? SsdTemperatureC,
    string? Warning);

public sealed class SystemMetricsService
{
    private readonly PowerShellRunner _powerShell;
    private ulong _previousIdle;
    private ulong _previousKernel;
    private ulong _previousUser;
    private bool _hasCpuBaseline;
    private double? _cpuTemperature;
    private double? _ssdTemperature;
    private string? _temperatureWarning;
    private DateTime _lastTemperatureRefresh = DateTime.MinValue;

    public SystemMetricsService(PowerShellRunner powerShell) => _powerShell = powerShell;

    public async Task<SystemMetrics> GetAsync(CancellationToken cancellationToken = default)
    {
        var warnings = new List<string>();
        var cpu = GetCpuPercent();
        var memory = GetMemoryPercent();
        if (cpu is null) warnings.Add(_hasCpuBaseline ? "CPU usage unavailable." : "CPU usage baseline pending.");
        if (memory is null) warnings.Add("Memory usage unavailable.");

        if ((DateTime.UtcNow - _lastTemperatureRefresh).TotalSeconds >= 10)
        {
            _lastTemperatureRefresh = DateTime.UtcNow;
            await RefreshTemperaturesAsync(cancellationToken);
        }
        if (!string.IsNullOrWhiteSpace(_temperatureWarning)) warnings.Add(_temperatureWarning);

        return new SystemMetrics(
            cpu,
            memory,
            _cpuTemperature,
            _ssdTemperature,
            warnings.Count == 0 ? null : string.Join(" ", warnings.Distinct(StringComparer.Ordinal)));
    }

    private async Task RefreshTemperaturesAsync(CancellationToken cancellationToken)
    {
        var command = @"
$errors = New-Object System.Collections.Generic.List[string]
$cpu = $null
try {
  $t = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | Select-Object -First 1
  if ($t -and $t.CurrentTemperature) { $cpu = [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1) }
} catch { $errors.Add('CPU temperature unavailable: ' + $_.Exception.Message) }
$ssd = $null
try {
  $ssd = Get-PhysicalDisk | Get-StorageReliabilityCounter -ErrorAction Stop | Where-Object { $_.Temperature -gt 0 } | Select-Object -First 1 -ExpandProperty Temperature
} catch { $errors.Add('SSD temperature unavailable: ' + $_.Exception.Message) }
[pscustomobject]@{ Cpu = $cpu; Ssd = $ssd; Warning = ($errors -join '; ') } | ConvertTo-Json -Compress
";

        try
        {
            var result = await _powerShell.RunCommandAsync(
                command,
                cancellationToken: cancellationToken,
                options: new ProcessRunOptions(TimeSpan.FromSeconds(15), OperationId: "live-temperatures"));
            if (!result.Succeeded || string.IsNullOrWhiteSpace(result.StandardOutput))
            {
                _cpuTemperature = null;
                _ssdTemperature = null;
                _temperatureWarning = result.FailureReason ?? "Temperature providers did not return data.";
                return;
            }

            using var doc = JsonDocument.Parse(result.StandardOutput.Trim());
            var root = doc.RootElement;
            _cpuTemperature = root.TryGetProperty("Cpu", out var cpuElement) && cpuElement.ValueKind == JsonValueKind.Number
                ? cpuElement.GetDouble()
                : null;
            _ssdTemperature = root.TryGetProperty("Ssd", out var ssdElement) && ssdElement.ValueKind == JsonValueKind.Number
                ? ssdElement.GetDouble()
                : null;
            _temperatureWarning = root.TryGetProperty("Warning", out var warningElement) && warningElement.ValueKind == JsonValueKind.String
                ? NullIfWhiteSpace(warningElement.GetString())
                : null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _cpuTemperature = null;
            _ssdTemperature = null;
            _temperatureWarning = "Temperature telemetry failed: " + ex.Message;
        }
    }

    private double? GetCpuPercent()
    {
        if (!GetSystemTimes(out var idle, out var kernel, out var user)) return null;
        var idleNow = ToUInt64(idle);
        var kernelNow = ToUInt64(kernel);
        var userNow = ToUInt64(user);

        if (!_hasCpuBaseline)
        {
            _previousIdle = idleNow;
            _previousKernel = kernelNow;
            _previousUser = userNow;
            _hasCpuBaseline = true;
            return null;
        }

        var idleDelta = idleNow - _previousIdle;
        var kernelDelta = kernelNow - _previousKernel;
        var userDelta = userNow - _previousUser;
        var total = kernelDelta + userDelta;
        _previousIdle = idleNow;
        _previousKernel = kernelNow;
        _previousUser = userNow;
        if (total == 0) return null;
        return Math.Clamp(100.0 * (total - idleDelta) / total, 0, 100);
    }

    private static double? GetMemoryPercent()
    {
        var status = new MemoryStatusEx();
        return GlobalMemoryStatusEx(status) ? status.MemoryLoad : null;
    }

    private static string? NullIfWhiteSpace(string? value) => string.IsNullOrWhiteSpace(value) ? null : value;
    private static ulong ToUInt64(FileTime time) => ((ulong)time.High << 32) | time.Low;

    [StructLayout(LayoutKind.Sequential)]
    private struct FileTime { public uint Low; public uint High; }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetSystemTimes(out FileTime idleTime, out FileTime kernelTime, out FileTime userTime);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private sealed class MemoryStatusEx
    {
        public uint Length = (uint)Marshal.SizeOf<MemoryStatusEx>();
        public uint MemoryLoad;
        public ulong TotalPhysical;
        public ulong AvailablePhysical;
        public ulong TotalPageFile;
        public ulong AvailablePageFile;
        public ulong TotalVirtual;
        public ulong AvailableVirtual;
        public ulong AvailableExtendedVirtual;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx([In, Out] MemoryStatusEx buffer);
}
