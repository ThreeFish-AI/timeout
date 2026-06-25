using System.Windows.Controls;
using H.NotifyIcon;
using GiveMeABreakEngine;
using GiveMeABreakShell.Autostart;
using Drawing = System.Drawing;

namespace GiveMeABreakShell.Tray;

// 托盘控制器 · H.NotifyIcon TaskbarIcon。对齐 macOS StatusItemController 菜单项集。
// 注：CI 无 explorer shell，托盘不显示；headless 烟测跳过本类实例化。真机真 icon 留验收。
public sealed class TrayController : IDisposable
{
    private readonly TaskbarIcon _icon;
    private readonly LiveGiveMeABreakEngine _engine;

    public TrayController(LiveGiveMeABreakEngine engine, Action openSettings)
    {
        _engine = engine;
        _icon = new TaskbarIcon
        {
            ToolTipText = "Give me a break",
            Icon = Drawing.SystemIcons.Application,   // 占位 icon（真 icon 留真机验收）
            ContextMenu = BuildMenu(openSettings),
        };
    }

    private ContextMenu BuildMenu(Action openSettings)
    {
        var menu = new ContextMenu();
        var status = new MenuItem { Header = "Give me a break（运行中）", IsEnabled = false };
        var restNow = new MenuItem { Header = "立即休息" };
        restNow.Click += (_, _) => _engine.ForceRestNow();
        var settings = new MenuItem { Header = "设置…（Phase 1 占位）" };
        settings.Click += (_, _) => openSettings();
        var autostart = new MenuItem { Header = "开机自启", IsCheckable = true, IsChecked = RegistryAutostart.IsEnabled() };
        autostart.Click += (_, _) =>
        {
            if (autostart.IsChecked) RegistryAutostart.Enable(Environment.ProcessPath!);
            else RegistryAutostart.Disable();
        };
        var quit = new MenuItem { Header = "退出" };
        quit.Click += (_, _) =>
        {
            Dispose();
            System.Windows.Application.Current.Shutdown();
        };

        menu.Items.Add(status);
        menu.Items.Add(restNow);
        menu.Items.Add(settings);
        menu.Items.Add(autostart);
        menu.Items.Add(new Separator());
        menu.Items.Add(quit);
        return menu;
    }

    public void UpdateStatus(string text) => _icon.ToolTipText = text;

    public void Dispose() => _icon.Dispose();
}
