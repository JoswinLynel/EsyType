# Screenshots of every page of the test build's own window, for checking the layout by eye: each sidebar page, a
# confirmation dialog, and optionally a page zoom (-Zoom 1.5 or 2, test builds only) and window width (-Width).
# Uses its own empty test profile, so the empty states show (-Seeded: filled lists). Nothing else on screen is touched.
# -Setup: the eight first-run steps instead, on a profile with no model (served by model-server.py from the files
# already in firstrun-serve, so nothing comes from the internet).
param([double]$Zoom = 1, [int]$Width = 980, [int]$Height = 720, [string]$Out = "D:\AI Projects\Tools\e2e\shots", [switch]$Setup, [switch]$Seeded, [int]$Port = 8767, [ValidateSet('system', 'dark', 'light')][string]$Theme = 'system',
      [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe", [string]$Work = "D:\AI Projects\Tools\e2e")
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Shot {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool r);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[Shot]::SetProcessDPIAware() | Out-Null
$lad = Join-Path $Work 'localappdata-shots'; $data = Join-Path $lad 'EsyAI\EsyType'; New-Item -ItemType Directory -Force $data, $Out | Out-Null
Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force
$server = $null
if ($Setup) {
  $lad = Join-Path $Work 'localappdata-shots-setup'; if (Test-Path $lad) { Remove-Item $lad -Recurse -Force }; New-Item -ItemType Directory -Force (Join-Path $lad 'EsyAI\EsyType') | Out-Null
  $server = Start-Process python -ArgumentList '-I', "`"$(Join-Path $PSScriptRoot 'model-server.py')`"", "`"$(Join-Path $Work 'firstrun-serve')`"", $Port, '--rate', 4000000 -PassThru -WindowStyle Hidden
  $env:ESYTYPE_MODEL_BASE_URL = "http://127.0.0.1:$Port"
} else {
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; undo_shortcut = 'Ctrl+F9'; paste_last_shortcut = 'Ctrl+F10'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false; theme = $Theme } |
  ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
  # -Seeded: filled lists, from the profile polish-e2e.ps1 leaves behind
  if ($Seeded) { Copy-Item (Join-Path $Work 'localappdata-polish\EsyAI\EsyType\esytype.db') $data }
}
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_ZOOM = "$Zoom"
$tag = "z$($Zoom)-w$Width" + $(if ($Seeded) { '-seeded' } else { '' }) + $(if ($Theme -ne 'system') { "-$Theme" } else { '' })
$app = Start-Process $Exe -PassThru -RedirectStandardError (Join-Path $Work 'shots-trace.txt'); Start-Sleep 9
try {
  $root = Get-AppWindow $app.Id 'EsyType'; $h = [IntPtr]$root.Current.NativeWindowHandle
  $scale = [Shot]::GetDpiForWindow($h) / 96.0   # -Width and -Height are in the window's own (logical) pixels
  [Shot]::MoveWindow($h, 40, 40, [int]($Width * $scale), [int]($Height * $scale), $true) | Out-Null; Start-Sleep 1
  function Snap($name) {
    [Shot]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 700
    $r = New-Object Shot+RECT; [Shot]::GetWindowRect($h, [ref]$r) | Out-Null
    $bmp = New-Object Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
    [Drawing.Graphics]::FromImage($bmp).CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $Out "$tag-$name.png"), [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  }
  if ($Setup) {
    $n = 0
    foreach ($b in 'Get started', 'Continue', 'Download Base', 'Continue', 'Continue', 'Continue', 'Continue', '') {
      $n++; Snap "setup-$n"
      if ($n -eq 4) { Start-Sleep 20; Snap 'setup-4-verified' }
      if ($b) { Invoke-El (Find-El $root $b $CT::Button); Start-Sleep 2.5 }
    }
    "screenshots in $Out ($tag-setup-*.png)"; return
  }
  foreach ($p in 'Dictation', 'EsyMeet*', 'Insights', 'History', 'Dictionary', 'Snippets', 'Style', 'Scratchpad') {
    Invoke-El (Find-El $root $p $CT::Button -Like); Start-Sleep 1.2; Snap ($p.TrimEnd('*').ToLower())
  }
  # the Settings panel, every section, and the Delete all dialog (cancelled)
  foreach ($sec in 'General', 'Shortcuts', 'Recording', 'Speech', 'Models', 'History & Privacy', 'Permissions', 'About') {
    Open-Settings $root $sec; Snap ('settings-' + ($sec.ToLower() -replace '[^a-z]+', '-'))
  }
  Open-Settings $root 'History & Privacy'
  Invoke-El (Find-El $root 'Delete all EsyType data' $CT::Button); Start-Sleep 1; Snap 'dialog-delete-all'
  [void](Answer-Dialog $root 'Cancel')
  Close-Settings $root
  # a confirmation dialog: write a note, then Delete
  Invoke-El (Find-El $root 'Scratchpad' $CT::Button); Start-Sleep 1
  Set-Val (Find-El $root 'Note' $CT::Edit) 'Shopping list'; Start-Sleep 1.5
  Invoke-El (Find-El $root 'Delete' $CT::Button); Start-Sleep 0.8; Snap 'dialog'
  [void](Answer-Dialog $root 'Cancel')
  "screenshots in $Out ($tag-*.png)"
} finally {
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
  if ($server) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
}
