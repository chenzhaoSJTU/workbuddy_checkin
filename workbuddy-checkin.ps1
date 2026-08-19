# WorkBuddy Check-in Script v4
# ============================================
# Purpose: daily WorkBuddy check-in via UI mouse click simulation
# Status: coordinates are stale (WorkBuddy V5.3.13 UI changed), will likely fail
#         Use API script instead: wb_checkin_api.py (scheduled at 00:10)
#         This script kept only as 00:05 fallback attempt
# ============================================

# ============================================
# 运行方式（Run instructions）:
#   从 PowerShell 直接运行:
#     powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\wangy\workbuddy-checkin.ps1
#   从 WSL 运行:
#     /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\wangy\workbuddy-checkin.ps1'
#   通过定时任务触发:
#     Start-ScheduledTask -TaskName 'WorkBuddyDailyCheckin'
# ============================================
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);
    [DllImport("user32.dll")]
    public static extern IntPtr SetActiveWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool IsZoomed(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const uint WM_LBUTTONDOWN = 0x0201;
    public const uint WM_LBUTTONUP = 0x0202;
    public const int SW_RESTORE = 9;
    public const int SW_SHOW = 5;
    public const int SW_MAXIMIZE = 3;
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    public const byte VK_MENU = 0x12;
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const uint SWP_SHOWWINDOW = 0x0040;
    public const uint SWP_NOSIZE = 0x0001;
    public const uint SWP_NOZORDER = 0x0004;
    public static readonly IntPtr HWND_TOP = new IntPtr(0);
}
"@

# ============================================
# Enable DPI awareness at the very start so ALL window API calls
# use the same coordinate system (physical pixels) throughout.
# Without this, SetProcessDPIAware called later in Take-Screenshot
# would change how GetWindowRect/SetWindowPos interpret coordinates,
# causing window position drift between retry attempts.
[Win32]::SetProcessDPIAware() | Out-Null

# Click coordinates (PHYSICAL pixels, 2240x1400 screen @150% DPI)
# Converted from virtual by multiplying by 1.5 (e.g. 72 virt = 108 phys)
# NOTE: WorkBuddy V5.3.13 UI has changed - these coords are stale!
$MENU_X = 108
$MENU_Y = 1287
$CLAIM_X = 121
$CLAIM_Y = 1195
$CHECKIN_X = 429
$CHECKIN_Y = 633

# Max retry attempts (3: first try, second with restart, third fresh window)
$MAX_ATTEMPTS = 3

# ============================================================
# Functions
# ============================================================

# Open-or-find WorkBuddy window. Returns (hwnd, $restarted).
# If window is broken (off-screen/minimized), kills process and relaunches.
# On relaunch sets $restarted = $true so menu gets only 1 click.
function Find-Or-Launch-WorkBuddy {
    param([string]$workbuddyPath)

    $process = Get-Process | Where-Object { $_.MainWindowTitle -eq "WorkBuddy" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    $restarted = $false

    if (-not $process) {
        Write-Host "WorkBuddy not running. Launching..." -ForegroundColor Yellow
        if (Test-Path $workbuddyPath) {
            Start-Process -FilePath $workbuddyPath
            $maxWait = 30
            $waited = 0
            while ($waited -lt $maxWait) {
                Start-Sleep -Seconds 2
                $process = Get-Process | Where-Object { $_.MainWindowTitle -eq "WorkBuddy" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
                if ($process) {
                    Write-Host "    WorkBuddy window appeared after ${waited}s" -ForegroundColor Green
                    break
                }
                $waited += 2
            }
            if (-not $process) {
                Write-Host "[Error] WorkBuddy did not start within $maxWait seconds" -ForegroundColor Red
                return $null, $false
            }
        } else {
            Write-Host "[Error] WorkBuddy not found at $workbuddyPath" -ForegroundColor Red
            return $null, $false
        }
    }

    $hwnd = $process.MainWindowHandle
    Write-Host "Found WorkBuddy window: Handle = $hwnd" -ForegroundColor Green

    # Detect broken window: off-screen at (-21000,-21000) or tiny size
    # ShowWindow/SetWindowPos silently fail on broken windows.
    # Only fix: kill process, relaunch, wait for fresh window.
    $winRect = New-Object Win32+RECT
    [Win32]::GetWindowRect($hwnd, [ref]$winRect) | Out-Null
    $winW = $winRect.Right - $winRect.Left
    $winH = $winRect.Bottom - $winRect.Top

    if ($winRect.Left -lt -100 -or $winRect.Top -lt -100 -or $winW -lt 100 -or $winH -lt 100) {
        Write-Host "    Window is in broken state (off-screen/minimized). Restarting WorkBuddy..." -ForegroundColor Yellow

        Get-Process -Name "WorkBuddy" -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "    Killing PID: $($_.Id)" -ForegroundColor Yellow
            $_.Kill()
        }
        Start-Sleep -Seconds 8

        Write-Host "    Relaunching WorkBuddy..." -ForegroundColor Yellow
        Start-Process -FilePath $workbuddyPath
        $process = $null

        $maxWait = 45
        $waited = 0
        while ($waited -lt $maxWait) {
            Start-Sleep -Seconds 2
            $process = Get-Process | Where-Object { $_.MainWindowTitle -eq "WorkBuddy" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
            if ($process) { break }
            $waited += 2
        }
        if (-not $process) {
            Write-Host "[Error] WorkBuddy did not restart within $maxWait seconds" -ForegroundColor Red
            return $null, $false
        }
        $hwnd = $process.MainWindowHandle
        Write-Host "    WorkBuddy restarted, new handle: $hwnd" -ForegroundColor Green
        Start-Sleep -Seconds 10
        $restarted = $true
    }

    return $hwnd, $restarted
}

# Check user idle time via GetLastInputInfo.
# Script waits if idle < 15s to avoid foreground lock conflicts.
function Get-IdleSeconds {
    $lii = New-Object Win32+LASTINPUTINFO
    $lii.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($lii)
    [Win32]::GetLastInputInfo([ref]$lii) | Out-Null
    $tickNow = [Environment]::TickCount
    if ($tickNow -lt $lii.dwTime) { $tickNow = $tickNow + [uint32]::MaxValue + 1 }
    return [math]::Round(($tickNow - $lii.dwTime) / 1000.0)
}

# Foreground guard: verify WorkBuddy is actually in front.
# If false, skip clicks (better to fail than to click wrong window).
function Assert-Foreground {
    param([IntPtr]$hwnd)
    Start-Sleep -Milliseconds 500
    $fg = [Win32]::GetForegroundWindow()
    if ($fg -eq $hwnd) { return $true }
    Write-Host "    [WARN] Foreground is NOT WorkBuddy (fg=$fg). Click targets would be wrong!" -ForegroundColor Red
    return $false
}

# Maximize + activate window, bring to foreground.
# Uses Alt-trick + multiple SetForegroundWindow to bypass Windows foreground lock.
# Note: foreground lock blocks activation when user is actively using the machine.
function Activate-Window {
    param([IntPtr]$hwnd)
    # Always un-maximize, set fixed position (physical), then re-maximize
    [Win32]::ShowWindow($hwnd, [Win32]::SW_RESTORE) | Out-Null
    Start-Sleep -Milliseconds 300
    [Win32]::SetWindowPos($hwnd, [Win32]::HWND_TOP, 0, 0, 2240, 1327, [Win32]::SWP_SHOWWINDOW) | Out-Null
    Start-Sleep -Milliseconds 300
    [Win32]::ShowWindow($hwnd, [Win32]::SW_MAXIMIZE) | Out-Null
    Start-Sleep -Milliseconds 200
    [Win32]::BringWindowToTop($hwnd) | Out-Null
    Start-Sleep -Milliseconds 100
    [Win32]::keybd_event([Win32]::VK_MENU, 0, 0, [UIntPtr]::Zero)
    [Win32]::keybd_event([Win32]::VK_MENU, 0, [Win32]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 100
    [Win32]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 300
    [Win32]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 300
    [Win32]::BringWindowToTop($hwnd) | Out-Null
    Start-Sleep -Milliseconds 200
    [Win32]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 300
    [Win32]::SetActiveWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 200
}

# Mouse click helper: SetCursorPos + left-button down/up.
# IMPORTANT: pipe SetCursorPos to Out-Null or its bool return leaks into pipeline!
function Do-Click {
    param([int]$x, [int]$y, [string]$label)
    [Win32]::SetCursorPos($x, $y) | Out-Null
    Start-Sleep -Milliseconds 150
    [Win32]::mouse_event([Win32]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 80
    [Win32]::mouse_event([Win32]::MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
    Write-Host "    $label clicked ($x, $y)" -ForegroundColor Green
}

# Full-screen screenshot (physical 2240x1400).
# Saves to %USERPROFILE%\workbuddy-checkin-screenshots\.
function Take-Screenshot {
    param([string]$dir)
    Start-Sleep -Seconds 2
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $screens = [System.Windows.Forms.Screen]::AllScreens
    $bounds = [System.Drawing.Rectangle]::Empty
    foreach ($s in $screens) {
        $bounds = [System.Drawing.Rectangle]::Union($bounds, $s.Bounds)
    }
    $bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    $file = Join-Path $dir "checkin_$(Get-Date -Format 'yyyyMMdd_HHmmss').png"
    $bitmap.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    return $file
}

# Convert Windows path to WSL path: C:\... -> /mnt/c/...
# Used to pass screenshot to wsl.exe tesseract.
function Convert-To-WslPath {
    param([string]$winPath)
    $winPath = [string]$winPath
    $drive = $winPath.Substring(0,1).ToLower()
    $rest = $winPath.Substring(2) -replace '\\', '/'
    return "/mnt/$drive$rest"
}

# Log-based verification: check WorkBuddy's main.log for check-in status.
# Much more reliable than OCR (tesseract Chinese recognition is flaky).
# The log records [Checkin] fetchCheckinStatus success with today_checked_in
# and [Checkin] claimDailyCheckin success with credit/streak_days.
function Verify-Checkin {
    param([string]$screenshotFile)
    $logPath = "$env:LOCALAPPDATA\WorkBuddy\logs\main.log"
    Write-Host "    Verifying via log: $logPath" -ForegroundColor Gray
    try {
        if (-not (Test-Path $logPath)) {
            Write-Host "    [WARN] Log file not found" -ForegroundColor Yellow
            return $false
        }
        # Read the last 50 lines of the log (covers current run)
        $lines = Get-Content $logPath -Tail 50 -Encoding UTF8
        $found = $false
        foreach ($line in $lines) {
            if ($line -match '\[Checkin\]') {
                Write-Host "    Log: $line" -ForegroundColor Gray
                # Check for claimDailyCheckin success (most recent run)
                if ($line -match 'claimDailyCheckin success') {
                    # Extract credit and streak from the JSON line
                    $creditMatch = $null; $streakMatch = $null
                    if ($line -match '"credit":(\d+)') { $creditMatch = $Matches[1] }
                    if ($line -match '"streak_days":(\d+)') { $streakMatch = $Matches[1] }
                    if ($creditMatch -and $streakMatch) {
                        Write-Host "    [PASS] Claim success: credit=$creditMatch streak=$streakMatch" -ForegroundColor Green
                        $found = $true
                        break
                    }
                }
                # Check for today_checked_in = true
                if ($line -match '"today_checked_in":true') {
                    Write-Host "    [PASS] Already checked in today" -ForegroundColor Green
                    $found = $true
                    break
                }
            }
        }
        if (-not $found) {
            Write-Host "    [FAIL] No check-in confirmation found in log" -ForegroundColor Yellow
            # Fallback: try OCR as last resort
            Write-Host "    Falling back to OCR verification..." -ForegroundColor Gray
            return Verify-Checkin-OCR -screenshotFile $screenshotFile
        }
        return $true
    } catch {
        Write-Host "    [WARN] Log verification failed: $_" -ForegroundColor Yellow
        Write-Host "    Falling back to OCR verification..." -ForegroundColor Gray
        return Verify-Checkin-OCR -screenshotFile $screenshotFile
    }
}

# OCR verification fallback (via WSL tesseract)
function Verify-Checkin-OCR {
    param([string]$screenshotFile)
    $wslPath = Convert-To-WslPath $screenshotFile
    Write-Host "    OCR verifying: $wslPath" -ForegroundColor Gray
    try {
        $oldEnc = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $ocrOutput = & wsl.exe tesseract $wslPath stdout -l chi_sim+eng 2>$null
        } finally {
            [Console]::OutputEncoding = $oldEnc
        }
    } catch {
        Write-Host "    [Warning] WSL/tesseract not available, skipping OCR verification" -ForegroundColor Yellow
        return $false
    }
    # Success markers (Unicode codepoints to avoid PS 5.1 ANSI encoding issues)
    $markers = @(
        [char]0x5DF2 + [char]0x9886,           # yi ling
        [char]0x7D2F + [char]0x8BA1 + [char]0x9886 + [char]0x53D6,  # lei ji ling qu
        [char]0x901A + [char]0x7528 + [char]0x79EF + [char]0x5206,  # tong yong ji fen
        [char]0x7B7E + [char]0x5230 + [char]0x6210 + [char]0x529F,  # qian dao cheng gong
        [char]0x5DF2 + [char]0x7B7E + [char]0x5230                 # yi qian dao
    )
    $matched = $false
    foreach ($m in $markers) {
        if ($ocrOutput -match $m) {
            $matched = $true
            Write-Host "    OCR matched: $m" -ForegroundColor Green
            break
        }
    }
    if (-not $matched) {
        if (-not $ocrOutput) {
            Write-Host "    OCR output EMPTY - tesseract may have failed on the file" -ForegroundColor Yellow
        } else {
            $first5 = ($ocrOutput -split "`n" | Select-Object -First 5) -join ' | '
            Write-Host "    OCR no success marker. First lines: $first5" -ForegroundColor Gray
        }
    }
    return $matched
}

# Press Escape key (to dismiss dialogs).
function Press-Escape {
    [Win32]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 50
    [Win32]::keybd_event(0x1B, 0, [Win32]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
}

# Single check-in attempt: activate window -> click menu -> check-in -> claim -> screenshot.
# Click flow (coords are stale, need re-measurement):
#   1. Bottom-left avatar (~72, 858) - opens user menu
#   2. Menu check-in button (~286, 422)
#   3. Claim now button (~81, 797)
# On restart: menu gets 1 click instead of 2.
# Returns $null if foreground guard aborts (no clicks sent).
function Run-CheckinAttempt {
    param(
        [IntPtr]$hwnd,
        [string]$screenshotDir
    )
    $attemptLabel = "(normal)"
    Write-Host "[Attempt] Activating window $attemptLabel..." -ForegroundColor Yellow
    Activate-Window -hwnd $hwnd
    if (-not (Assert-Foreground -hwnd $hwnd)) {
        Write-Host "    [ABORT] Skipping all clicks -- foreground is not WorkBuddy. User is likely using the machine." -ForegroundColor Red
        return $null
    }
    Write-Host "    Window activated and in foreground" -ForegroundColor Green
    # Step 1: click user menu (single click, regardless of attempt)
    Write-Host "[1/4] Clicking user menu ($MENU_X, $MENU_Y)..." -ForegroundColor Yellow
    Do-Click -x $MENU_X -y $MENU_Y -label "User menu"
    Write-Host "    Waiting 3 seconds for menu..." -ForegroundColor Gray
    Start-Sleep -Seconds 3
    # Step 2: reactivate and click check-in button
    Write-Host "[2/4] Re-activating window and clicking check-in ($CHECKIN_X, $CHECKIN_Y)..." -ForegroundColor Yellow
    [Win32]::BringWindowToTop($hwnd) | Out-Null
    Start-Sleep -Milliseconds 200
    [Win32]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 200
    Do-Click -x $CHECKIN_X -y $CHECKIN_Y -label "Check-in button"
    Start-Sleep -Seconds 1
    # Step 3: click claim now
    Write-Host "[3/4] Clicking claim now ($CLAIM_X, $CLAIM_Y)..." -ForegroundColor Yellow
    Do-Click -x $CLAIM_X -y $CLAIM_Y -label "Claim now button"
    Start-Sleep -Seconds 1
    # Step 4: take verification screenshot
    Write-Host "[4/4] Taking verification screenshot..." -ForegroundColor Yellow
    $screenshot = Take-Screenshot -dir $screenshotDir
    Write-Host "    Screenshot saved: $screenshot" -ForegroundColor Green
    return $screenshot
}

# ============================================================
# Main
# ============================================================

Write-Host "=== WorkBuddy Auto Check-in v4 ===" -ForegroundColor Cyan
Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

$workbuddyPath = "C:\Program Files\WorkBuddy\WorkBuddy.exe"
$screenshotDir = "$env:USERPROFILE\workbuddy-checkin-screenshots"

# Step 0: find or launch WorkBuddy (once; retries reuse the same window)
$result = Find-Or-Launch-WorkBuddy -workbuddyPath $workbuddyPath
$hwnd = $result[0]

if (-not $hwnd) {
    Write-Host "[FATAL] Could not get WorkBuddy window. Exiting." -ForegroundColor Red
    exit 1
}

# Retry loop (up to 3 times)
# Each attempt: idle wait -> activate -> click -> screenshot -> OCR verify
# On 2nd failure: kill WorkBuddy and relaunch for fresh window
$success = $false
for ($attempt = 1; $attempt -le $MAX_ATTEMPTS; $attempt++) {
    Write-Host ""
    Write-Host "====== Attempt $attempt / $MAX_ATTEMPTS ======" -ForegroundColor Cyan

    # Step 1: wait for user to be idle (15s no input) to avoid foreground lock
    $idle = Get-IdleSeconds
    if ($idle -lt 15) {
        Write-Host "[Wait] User is active (idle ${idle}s). Waiting for idle... (max 90s)" -ForegroundColor Yellow
        $waitedForIdle = 0
        while ($waitedForIdle -lt 90) {
            Start-Sleep -Seconds 5
            $idle = Get-IdleSeconds
            if ($idle -ge 15) {
                Write-Host "    User idle now (${idle}s). Proceeding." -ForegroundColor Green
                break
            }
            $waitedForIdle += 5
        }
        if ($idle -lt 15) {
            Write-Host "    [WARN] User still active after 90s. Attempting anyway (foreground guard will protect)." -ForegroundColor Yellow
        }
    }

    # Step 2: execute check-in click sequence
    $screenshot = Run-CheckinAttempt -hwnd $hwnd -screenshotDir $screenshotDir

    Write-Host ""
    Write-Host "[Verify] Running log self-check..." -ForegroundColor Yellow

    # Step 3: OCR verify screenshot
    $verified = $false
    if ($screenshot) {
        $verified = Verify-Checkin -screenshotFile $screenshot
    } else {
        Write-Host "[Verify] SKIP -- no screenshot (foreground guard aborted clicks)" -ForegroundColor Gray
    }

    if ($verified) {
        Write-Host "[Verify] PASS -- check-in success confirmed! (continuing to next attempt)" -ForegroundColor Green
        $success = $true
        # Don't break; continue to run all 3 attempts for coordinate consistency check
    }

    if ($success) {
        Write-Host "    (Skipping FAIL/retry - already succeeded)" -ForegroundColor Gray
    } else {
        Write-Host "[Verify] FAIL -- success marker not found." -ForegroundColor Red
    }

    if (-not $success -and $attempt -lt $MAX_ATTEMPTS) {
        # Press Escape to dismiss any dialogs, wait 3s, then retry
        Write-Host "[Retry] Pressing Escape to dismiss dialogs, waiting 3s before retry..." -ForegroundColor Yellow
        Press-Escape
        Start-Sleep -Seconds 1
        Press-Escape
        Start-Sleep -Seconds 2

        # On 2nd failure: kill WorkBuddy and relaunch (broken window fix)
        if ($attempt -eq 2) {
            Write-Host "[Retry] 2nd failure -- restarting WorkBuddy for fresh attempt..." -ForegroundColor Yellow
            Get-Process -Name "WorkBuddy" -ErrorAction SilentlyContinue | ForEach-Object {
                Write-Host "    Killing PID: $($_.Id)" -ForegroundColor Yellow
                $_.Kill()
            }
            Start-Sleep -Seconds 8
            Start-Process -FilePath $workbuddyPath

            $maxWait = 45
            $waited = 0
            $process = $null
            while ($waited -lt $maxWait) {
                Start-Sleep -Seconds 2
                $process = Get-Process | Where-Object { $_.MainWindowTitle -eq "WorkBuddy" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
                if ($process) { break }
                $waited += 2
            }
            if ($process) {
                $hwnd = $process.MainWindowHandle
                Write-Host "    WorkBuddy restarted, new handle: $hwnd" -ForegroundColor Green
                Start-Sleep -Seconds 10
            } else {
                Write-Host "    [Error] WorkBuddy did not restart. Aborting." -ForegroundColor Red
                break
            }
        }
    }
}

Write-Host ""
# Step 4: final result
# Exit code: 0 = success, 1 = failure
if ($success) {
    Write-Host "=== Check-in SUCCESS ===" -ForegroundColor Green
    exit 0
} else {
    Write-Host "=== Check-in FAILED after $MAX_ATTEMPTS attempts ===" -ForegroundColor Red
    Write-Host "Last screenshot: $screenshot" -ForegroundColor Yellow
    Write-Host "Manual verification recommended." -ForegroundColor Yellow
    exit 1
}