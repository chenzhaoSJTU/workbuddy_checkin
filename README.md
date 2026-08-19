# WorkBuddy Daily Check-in

通过鼠标模拟点击完成 WorkBuddy 每日签到（积分/加油站）。

## 功能

脚本自动完成以下流程：
1. 查找或启动 WorkBuddy 窗口
2. 最大化并激活窗口
3. 点击左下角菜单键 → 签到按钮 → 立即领取
4. 截图保存到 `%USERPROFILE%\workbuddy-checkin-screenshots\`
5. 通过 WorkBuddy 日志验证签到结果（`main.log`）

## 签到保障机制

脚本通过 **3 重保障** 确保签到成功：

| 层 | 机制 | 说明 |
|----|------|------|
| 1 | **3 次重试** | 每次失败后按 Esc 关闭弹窗，最多重试 3 次 |
| 2 | **自动重启** | 第 2 次失败后杀死 WorkBuddy 进程重新启动，用干净窗口做第 3 次尝试 |
| 3 | **日志验证** | 读取 WorkBuddy 的 `main.log`，确认 `today_checked_in=true` 或 `claimDailyCheckin success` 才判定为成功 |

## 坐标说明

当前坐标基于 **2240×1400 物理像素 @150% DPI**（虚拟分辨率 1493×933）。

| 元素 | 虚拟坐标 | 物理坐标 |
|------|----------|----------|
| 左下角菜单键 | (72, 858) | (108, 1287) |
| 签到按钮 | (286, 422) | (429, 633) |
| 立即领取 | (81, 797) | (121, 1195) |

**⚠️ 如果屏幕分辨率或 DPI 缩放改变，需要重新测量坐标。**

## 如何重新测量坐标

1. 打开 WorkBuddy，鼠标悬停到目标按钮上
2. 在 PowerShell 中执行：
   ```powershell
   Add-Type -AssemblyName System.Windows.Forms
   [System.Windows.Forms.Cursor]::Position
   ```
3. 输出 `{X=72, Y=858}` 这样的坐标
4. 更新脚本中的 `$MENU_X`, `$MENU_Y` 等变量

> 注意：PowerShell 非 DPI 感知时返回的是**虚拟坐标**，脚本开头已调用 `SetProcessDPIAware()`，所以坐标统一使用**物理像素**。如果重新测量，请将虚拟坐标 ×1.5 转为物理坐标写入脚本。

## 运行方式

```powershell
# 从 PowerShell 直接运行
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\wangy\workbuddy-checkin.ps1

# 从 WSL 运行
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\wangy\workbuddy-checkin.ps1'

# 通过定时任务触发
Start-ScheduledTask -TaskName 'WorkBuddyDailyCheckin'
```

## 退出码

| 退出码 | 含义 |
|--------|------|
| 0 | 签到成功（日志验证通过） |
| 1 | 签到失败（3 次尝试后仍未成功，可查看截图手动确认） |