param(
  [Parameter(Mandatory=$true)][int]$X,
  [Parameter(Mandatory=$true)][int]$Y,
  [string]$ProcessName = "dsm_helper"
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinTap2 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  public struct POINT { public int X; public int Y; }
}
"@

$proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $proc) { Write-Output "WINDOW_NOT_FOUND"; exit 1 }
$h = $proc.MainWindowHandle
[WinTap2]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 250
$origin = New-Object WinTap2+POINT
[WinTap2]::ClientToScreen($h, [ref]$origin) | Out-Null
$sx = $origin.X + $X
$sy = $origin.Y + $Y
[WinTap2]::SetCursorPos($sx, $sy) | Out-Null
Start-Sleep -Milliseconds 120
[WinTap2]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 60
[WinTap2]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Write-Output "TAPPED client($X,$Y) -> screen($sx,$sy)"
