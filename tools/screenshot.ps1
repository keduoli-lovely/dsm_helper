param(
  [string]$Out = "$env:TEMP\dsm_shot.png",
  [int]$Width = 432,
  [int]$Height = 963,
  [string]$ProcessName = "dsm_helper",
  [switch]$NoResize
)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinShot2 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int x, int y, int w, int h, bool repaint);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  public struct POINT { public int X; public int Y; }
}
"@

$proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $proc) { Write-Output "WINDOW_NOT_FOUND"; exit 1 }
$h = $proc.MainWindowHandle

[WinShot2]::ShowWindow($h, 9) | Out-Null
if (-not $NoResize) { [WinShot2]::MoveWindow($h, 40, 20, $Width, $Height, $true) | Out-Null }
[WinShot2]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 1100

$client = New-Object WinShot2+RECT
[WinShot2]::GetClientRect($h, [ref]$client) | Out-Null
$origin = New-Object WinShot2+POINT
[WinShot2]::ClientToScreen($h, [ref]$origin) | Out-Null
$w = $client.Right - $client.Left
$hgt = $client.Bottom - $client.Top
if ($w -le 0 -or $hgt -le 0) { Write-Output "BAD_CLIENT_RECT"; exit 1 }

$bmp = New-Object System.Drawing.Bitmap($w, $hgt)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($origin.X, $origin.Y, 0, 0, $bmp.Size)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "SAVED $Out ${w}x${hgt}"
