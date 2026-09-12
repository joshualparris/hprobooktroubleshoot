using System.Windows;

namespace WindowsCrashDoctor;

public partial class MainWindow
{
    protected override void OnContentRendered(EventArgs e)
    {
        base.OnContentRendered(e);
        if (!_metricsBusy)
        {
            SetPercentMetric(CpuValue, SensorCpuValue, CpuBar, SensorCpuBar, null);
            SetPercentMetric(MemoryValue, SensorMemoryValue, MemoryBar, SensorMemoryBar, null);
            LiveStatusText.Text = "Waiting for live sample";
        }
    }

    protected override void OnClosed(EventArgs e)
    {
        _metricsTimer.Stop();
        if (_sensorCts is not null)
        {
            _sensorCts.Cancel();
            _sensorCts.Dispose();
            _sensorCts = null;
        }
        base.OnClosed(e);
    }
}
