using System.Runtime.InteropServices;
using System.Text.Json;

namespace WindowsCrashDoctor.Services;

public sealed record SystemMetrics(double CpuPercent, double MemoryPercent, double? CpuTemperatureC, double? SsdTemperatureC);

public sealed class SystemMetricsService
{
    private readonly PowerShellRunner _powerShell;
    private ulong _previousIdle;
    private ulong _previousKernel;
    private ulong _previousUser;
    private bool _hasCpuBaseline;
    private double? _cpuTemperature;
    private double? _ssdTemperature;
    private DateTime _lastTemperatureRefresh = DateTime.MinValue;

    public SystemMetricsService(PowerShellRunner powerShell) => _powerShell = powerShell;

    public async Task<SystemMetrics> GetAsync(CancellationToken cancellationToken = default)
    {
        var cpu = GetCpuPercent();
        var memory = GetMemoryPercent();

        if ((DateTime.UtcNow - _lastTemperatureRefresh).TotalSeconds >= 10)
        {
            _lastTemperatureRefresh = DateTime.UtcNow;
            try
            {
                var command = @"
$cpu = $null
try {
  $t = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | Select-Object -First 1
  if ($t -and $t.CurrentTemperature) { $cpu = [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1) }
} catch {}
$ssd = $null
try {
  $ssd = Get-PhysicalDisk | Get-StorageReliabilityCounter -ErrorAction Stop | Where-Object { $_.Temperature -gt 0 } | Select-Object -First 1 -ExpandProperty Temperature
} catch {}
[pscustomobject]@{ Cpu = $cpu; Ssd = $ssd } | ConvertTo-Json -Compress
";
                var result = await _powerShell.RunCommandAsync(command, cancellationToken: cancellationToken);
                if (result.ExitCode == 0 && !string.IsNullOrWhiteSpace(result.StandardOutput))
                {
                    using var doc = JsonDocument.Parse(result.StandardOutput.Trim());
                    if (doc.RootElement.TryGetProperty("Cpu", out var cpuElement) && cpuElement.ValueKind == JsonValueKind.Number)
                        _cpuTemperature = cpuElement.GetDouble();
                    if (doc.RootElement.TryGetProperty("Ssd", out var ssdElement) && ssdElement.ValueKind == JsonValueKind.Number)
                        _ssdTemperature = ssdElement.GetDouble();
                }
            }
            catch
            {
            }
        }

        return new SystemMetrics(cpu, memory, _cpuTemperature, _ssdTemperature);
    }

    private double GetCpuPercent()
    {
        if (!GetSystemTimes(out var idle, out var kernel, out var user)) return 0;
        var idleNow = ToUInt64(idle);
        var kernelNow = ToUInt64(kernel);
        var userNow = ToUInt64(user);

        if (!_hasCpuBaseline)
        {
            _previousIdle = idleNow;
            _previousKernel = kernelNow;
            _previousUser = userNow;
            _hasCpuBaseline = true;
            return 0;
        }

        var idleDelta = idleNow - _previousIdle;
        var kernelDelta = kernelNow - _previousKernel;
        var userDelta = userNow - _previousUser;
        var total = kernelDelta + userDelta;
        _previousIdle = idleNow;
        _previousKernel = kernelNow;
        _previousUser = userNow;
        if (total == 0) return 0;
        return Math.Clamp(100.0 * (total - idleDelta) / total, 0, 100);
    }

    private static double GetMemoryPercent()
    {
        var status = new MemoryStatusEx();
        return GlobalMemoryStatusEx(status) ? status.MemoryLoad : 0;
    }

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
