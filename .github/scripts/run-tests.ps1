param(
    [string]$Executable = "build\\Release\\iRon.exe",
    [string]$Telemetry = "sample.telemetry"
)

# Helper function using PrintWindow to capture overlay window
Add-Type @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public class ScreenGrab {
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool PrintWindow(IntPtr hwnd, IntPtr hDC, uint nFlags);
    [DllImport("user32.dll")]
    static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [StructLayout(LayoutKind.Sequential)]
    struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    public static Bitmap Capture(IntPtr hwnd) {
        RECT rc; GetWindowRect(hwnd, out rc);
        var bmp = new Bitmap(rc.Right - rc.Left, rc.Bottom - rc.Top, PixelFormat.Format32bppArgb);
        using(var g = Graphics.FromImage(bmp)) {
            IntPtr hdc = g.GetHdc();
            PrintWindow(hwnd, hdc, 0);
            g.ReleaseHdc(hdc);
        }
        return bmp;
    }
}
"@

function Capture-Window {
    param([IntPtr]$hwnd, [string]$path)
    $img = [ScreenGrab]::Capture($hwnd)
    $img.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
}

$ErrorActionPreference = 'Stop'

$overlayNames = @('OverlayRelative','OverlayDDU','OverlayInputs','OverlayStandings')

New-Item -ItemType Directory -Force -Path screenshots | Out-Null

$proc = Start-Process $Executable -ArgumentList "--test $Telemetry" -PassThru
Start-Sleep -Seconds 5

foreach($name in $overlayNames) {
    $hwnd = (Get-Process | Where-Object { $_.MainWindowTitle -eq $name }).MainWindowHandle
    if($hwnd -ne 0) {
        Capture-Window -hwnd $hwnd -path "screenshots/$name.png"
    }
}

Stop-Process $proc -Force

$refMap = @{ 'OverlayRelative'='relative.png'; 'OverlayDDU'='ddu.png'; 'OverlayInputs'='inputs.png'; 'OverlayStandings'='standings.png' }
$failed = $false
foreach($name in $overlayNames) {
    $ref = $refMap[$name]
    $refPath = Join-Path $PSScriptRoot "..\\..\\$ref"
    $shot = "screenshots/$name.png"
    if(Test-Path $refPath -and Test-Path $shot) {
        $h1 = (Get-FileHash $refPath -Algorithm SHA256).Hash
        $h2 = (Get-FileHash $shot -Algorithm SHA256).Hash
        if($h1 -ne $h2) {
            Write-Host "Image mismatch for $name"
            $failed = $true
        }
    }
}
if($failed) { exit 1 }
