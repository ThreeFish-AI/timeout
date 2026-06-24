using System.Runtime.InteropServices;
using TimeoutEngine;
using TimeoutEngine.Win32;

namespace TimeoutShell.Adapters;

// ISystemStateProvider · 空闲检测（GetLastInputInfo + GetTickCount64，64 位回绕见 Win32IdleProbe）
// + 睡眠标志（PowerEventBridge 置位）。对齐 macOS SystemSensors + NSWorkspace 睡眠观察者。
public sealed class WindowsSystemState : ISystemStateProvider
{
    private volatile bool _isAsleep;
    public bool IsAsleep => _isAsleep;

    /// <summary>由 PowerEventBridge 在 Suspend/Resume 时置位。</summary>
    internal void SetAsleep(bool asleep) => _isAsleep = asleep;

    public double IdleSeconds()
    {
        var info = new LASTINPUTINFO { cbSize = (uint)Marshal.SizeOf<LASTINPUTINFO>() };
        if (!NativeMethods.GetLastInputInfo(ref info)) return 0;
        ulong now = NativeMethods.GetTickCount64();
        return Win32IdleProbe.ComputeIdleSeconds(info.dwTime, now);
    }
}
