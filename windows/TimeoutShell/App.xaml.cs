using System.Windows;
using System.Windows.Threading;

namespace TimeoutShell;

// WPF 入口 · 装配 AppRoot。headless 旁路支持 CI 烟测（TIMEOUT_HEADLESS=1 跳过托盘，5s 后自退）。
public partial class App : Application
{
    private AppRoot? _root;
    private DispatcherTimer? _exitTimer;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        // 中文日志以 UTF-8 输出，避免 Windows 控制台代码页致重定向文件乱码（CI 烟测断言依赖）。
        Console.OutputEncoding = System.Text.Encoding.UTF8;
        bool headless = Environment.GetEnvironmentVariable("TIMEOUT_HEADLESS") == "1";
        string debug = Environment.GetEnvironmentVariable("TIMEOUT_DEBUG") ?? "0";

        _root = new AppRoot(Dispatcher);
        _root.Start(headless);
        Console.WriteLine($"[Timeout] STARTUP_OK 启动完成 (headless={headless}, debug={debug})");

        if (headless)
        {
            // CI 烟测：5 秒后自动退出（exit 0）；若此前崩溃，进程异常退出被 CI 捕获。
            _exitTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
            _exitTimer.Tick += (_, _) =>
            {
                Console.WriteLine("[Timeout] headless 5s 到，正常退出 (exit 0)");
                _root.Dispose();
                Shutdown(0);
            };
            _exitTimer.Start();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _root?.Dispose();
        base.OnExit(e);
    }
}
