using System.Windows;
using WindowsCrashDoctor.Services;

namespace WindowsCrashDoctor;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        if (e.Args.Any(a => string.Equals(a, "--self-test", StringComparison.OrdinalIgnoreCase)))
        {
            Shutdown(DesktopSelfTest.Run());
            return;
        }

        var autoRun = e.Args.Any(a => string.Equals(a, "--run-diagnostics", StringComparison.OrdinalIgnoreCase));
        var window = new MainWindow(autoRun);
        MainWindow = window;
        window.Show();
    }
}
