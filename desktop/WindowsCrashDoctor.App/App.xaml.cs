using System.Windows;

namespace WindowsCrashDoctor;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var autoRun = e.Args.Any(a => string.Equals(a, "--run-diagnostics", StringComparison.OrdinalIgnoreCase));
        var window = new MainWindow(autoRun);
        MainWindow = window;
        window.Show();
    }
}
