param(
  [int]$Delta = -600,
  [string]$ProcessName = "dsm_helper"
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinScroll2 {
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
[WinScroll2]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 250
$client = New-Object WinScroll2+RECT
[WinScroll2]::GetClientRect($h, [ref]$client) | Out-Null
$origin = New-Object WinScroll2+POINT
[WinScroll2]::ClientToScreen($h, [ref]$origin) | Out-Null
$cx = $origin.X + [int](($client.Right - $client.Left) / 2)
$cy = $origin.Y + [int](($client.Bottom - $client.Top) / 2)
[WinScroll2]::SetCursorPos($cx, $cy) | Out-Null
Start-Sleep -Milliseconds 100
[WinScroll2]::mouse_event(0x0800, 0, 0, [uint32]([int64]4294967296 + $Delta), [UIntPtr]::Zero)
Write-Output "SCROLLED $Delta"
