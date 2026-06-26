using GiveMeABreakEngine;

namespace GiveMeABreakShell.Adapters;

// IOverlayController · Phase 1 占位（不显示真遮罩；Phase 2 攻坚全屏遮罩）。
// 仅维护 IsShown 语义 + 日志，保证装配闭环可跑、SideEffects 分发不缺失。
public sealed class NoopOverlayController : IOverlayController
{
    public bool IsShown { get; private set; }

    public void Show(DateTimeOffset restDeadline)
    {
        IsShown = true;
        Console.WriteLine($"[GiveMeABreak][overlay] (no-op) 进入休息，截止 {restDeadline:O}");
    }

    public void Dismiss()
    {
        IsShown = false;
        Console.WriteLine("[GiveMeABreak][overlay] (no-op) 退出休息");
    }
}
