param(
    # Path to the built executable.  The VS solution defaults to a
    # platform/Configuration directory layout (e.g. x64\Release).
    [string]$Executable = "x64\\Release\\iron.exe",
    [string]$Telemetry = "sample.telemetry"
)

# Resolve the executable path if the default location does not exist
if (-not (Test-Path $Executable)) {
    $candidate = Get-ChildItem -Path . -Recurse -Filter iron.exe |
        Where-Object { $_.FullName -like '*Release*' } |
        Select-Object -First 1
    if ($candidate) { $Executable = $candidate.FullName }
}

# Helper function using PrintWindow to capture overlay window
# PowerShell 7 does not automatically reference System.Drawing.Common when
# compiling inline C#. Resolve the DLL path explicitly so Add-Type can find it.
$drawingDll = Join-Path (Split-Path (Get-Command pwsh).Source) 'System.Drawing.Common.dll'
if (-not (Test-Path $drawingDll)) {
    $drawingDll = Join-Path ([System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'System.Drawing.Common.dll'
}
Add-Type -Path $drawingDll
Add-Type -ReferencedAssemblies $drawingDll -Language CSharp @"
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
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
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
    public static IntPtr Find(string title) {
        return FindWindow(null, title);
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
    $hwnd = [ScreenGrab]::Find($name)
    if ($hwnd -ne [IntPtr]::Zero) {
        Capture-Window -hwnd $hwnd -path "screenshots/$name.png"
    } else {
        Write-Host "Window not found: $name"
    }
}

Stop-Process $proc -Force

$refMap = @{ 'OverlayRelative'='relative.png'; 'OverlayDDU'='ddu.png'; 'OverlayInputs'='inputs.png'; 'OverlayStandings'='standings.png' }
$failed = $false
foreach($name in $overlayNames) {
    $ref = $refMap[$name]
    $refPath = Join-Path $PSScriptRoot "..\\..\\$ref"
    $shot = "screenshots/$name.png"
    if (-not (Test-Path $shot)) {
        Write-Host "Missing screenshot for $name"
        $failed = $true
        continue
    }
    if (Test-Path $refPath) {
        $h1 = (Get-FileHash $refPath -Algorithm SHA256).Hash
        $h2 = (Get-FileHash $shot -Algorithm SHA256).Hash
        if($h1 -ne $h2) {
            Write-Host "Image mismatch for $name"
            $failed = $true
        }
    }
}
if($failed) { exit 1 }
