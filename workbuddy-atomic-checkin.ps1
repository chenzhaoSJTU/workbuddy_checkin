# WorkBuddy atomic check-in v3 - ASCII only
# ============================================
# Purpose: minimal WorkBuddy check-in via UI mouse click
# NOTE: HWND and PID are hardcoded - must match current WorkBuddy process!
#       Coordinates are stale (V5.3.13 UI changed), will likely fail.
# NOTE: Run this script via:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File workbuddy-atomic-checkin.ps1
# ============================================

# Win32 API declarations (C# embedded code)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WB3 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, int e);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
    public const uint WM_SYSCOMMAND = 0x0112;
    public const uint SC_RESTORE = 0xF120;
    public const int SW_RESTORE = 9;
    public const uint LEFTDOWN = 0x0002, LEFTUP = 0x0004;

    // Mouse click helper: move cursor to (x,y) and left-click
    public static void Click(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(200);
        mouse_event(LEFTDOWN, 0, 0, 0, 0);
        System.Threading.Thread.Sleep(100);
        mouse_event(LEFTUP, 0, 0, 0, 0);
    }
}
"@

# ============================================
# HARDCODED values - must update before each run!
# Get current values with:
#   Get-Process -Name WorkBuddy | Where-Object { $_.MainWindowHandle -ne 0 }
# ============================================
$h = [IntPtr]21891738       # WorkBuddy main window HWND
$log = @()                  # Debug log array

# Verify WorkBuddy process exists
$proc = Get-Process -Id 17140 -ErrorAction SilentlyContinue
if (-not $proc) { Write-Output "ERROR: WorkBuddy main process (17140) not found"; exit 1 }

# Step 1: Restore window from minimized state
# SendMessage WM_SYSCOMMAND SC_RESTORE = restore from taskbar
# ShowWindow SW_RESTORE = restore minimized window
[WB3]::SendMessage($h, [WB3]::WM_SYSCOMMAND, [IntPtr]0xF120, [IntPtr]::Zero) | Out-Null
Start-Sleep -Milliseconds 400
[WB3]::ShowWindow($h, [WB3]::SW_RESTORE) | Out-Null
Start-Sleep -Milliseconds 400
$log += "Step1 restored, minimized=" + [WB3]::IsIconic($h)

# Step 2: Force foreground activation via AttachThreadInput
# AttachThreadInput merges the calling thread's input state with the
# target window's thread, bypassing Windows foreground lock.
$fg = [WB3]::GetForegroundWindow()
$fgThread = 0; $myThread = 0
[WB3]::GetWindowThreadProcessId($fg, [ref]$fgThread) | Out-Null
[WB3]::GetWindowThreadProcessId($h, [ref]$myThread) | Out-Null
[WB3]::AttachThreadInput($fgThread, $myThread, $true) | Out-Null
[WB3]::SetForegroundWindow($h) | Out-Null
[WB3]::AttachThreadInput($fgThread, $myThread, $false) | Out-Null
$fg2 = [WB3]::GetForegroundWindow()
$log += "Step2 foreground hwnd=" + $h + " current=" + $fg2 + " ok=" + ($fg2 -eq $h)

# Step 3: Click user menu at bottom-left (72, 858)
# NOTE: these coordinates are for 1493x933 virtual screen @150% DPI
# WorkBuddy V5.3.13 UI has changed - these coords are stale!
$log += "Step3 clicking user menu (72,858)"
[WB3]::Click(72, 858)
Start-Sleep -Seconds 5

# Step 4: Click check-in button in the menu (286, 422)
$log += "Step4 clicking checkin (286,422)"
[WB3]::Click(286, 422)
Start-Sleep -Seconds 2

# Step 5: Click claim now button (81, 797)
$log += "Step5 clicking claim (81,797)"
[WB3]::Click(81, 797)
Start-Sleep -Seconds 2

# Output debug log
$log | ForEach-Object { Write-Output $_ }
Write-Output "=== DONE, check main.log today_checked_in ==="