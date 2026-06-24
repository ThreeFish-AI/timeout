namespace TimeoutEngine.Win32;

// MARK: - 空闲检测（纯函数，64 位 tick 回绕处理）
// 镜像文档 §4：GetLastInputInfo（32 位 tick）+ GetTickCount64（64 位，避 49.7 天回绕）。
// 纯函数 ComputeIdleSeconds 把回绕数学从 Windows 运行时下沉到 net8.0 可测。

/// <summary>系统空闲时长计算。GetLastInputInfo.dwTime 是 32 位 GetTickCount 值（49.7 天回绕）；
/// 用 GetTickCount64 的低 32 位与之做 uint 减法（自动回绕），只要空闲 < 49.7 天即正确。</summary>
public static class Win32IdleProbe
{
    /// <summary>计算空闲秒数。
    /// <param name="lastInputTick">GetLastInputInfo 返回的 dwTime（32 位 tick）。</param>
    /// <param name="nowTick64">GetTickCount64 返回的 64 位毫秒值。</param></summary>
    public static double ComputeIdleSeconds(uint lastInputTick, ulong nowTick64)
    {
        uint nowLow = (uint)(nowTick64 & 0xFFFFFFFFUL);
        uint idleTicks = nowLow - lastInputTick;   // uint 减法自动处理 32 位回绕
        return idleTicks / 1000.0;
    }
}
