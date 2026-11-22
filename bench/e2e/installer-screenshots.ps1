# Screenshots of each page of the "EsyType Test" installer and uninstaller (test product only, installed to a test
# folder): for checking the pages by eye. Each page is moved on with the standard button message (BM_CLICK) sent to
# the installer's own controls; no keys are sent. The "Run" box on the last page is unticked so nothing starts.
param([string]$Setup = "D:\AI Projects\Tools\e2e\installers\EsyType Test_0.2.1_x64-setup.exe", [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$Out = "D:\AI Projects\Tools\e2e\shots")
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Is {
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageW(IntPtr h, uint m, IntPtr w, string l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageW(IntPtr h, uint m, IntPtr w, System.Text.StringBuilder l);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[Is]::SetProcessDPIAware() | Out-Null
New-Item -ItemType Directory -Force $Out | Out-Null
$dir = Join-Path $Work 'install-test\shots'
$uninstKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\EsyType Test'
if (Test-Path $uninstKey) { throw 'EsyType Test is already installed; run installer-e2e.ps1 (which cleans up) first.' }

function Snap($w, $name) {
  $h = [IntPtr]$w.Current.NativeWindowHandle; [Is]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 600
  $r = New-Object Is+RECT; [Is]::GetWindowRect($h, [ref]$r) | Out-Null
  $bmp = New-Object Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
  [Drawing.Graphics]::FromImage($bmp).CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
  $bmp.Save((Join-Path $Out "installer-$name.png"), [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $name
}
function Click($e) { [void][Is]::PostMessage([IntPtr]$e.Current.NativeWindowHandle, 0xF5, [IntPtr]::Zero, [IntPtr]::Zero); Start-Sleep 1.5 }
function Ticked($e) { [Is]::SendMessage([IntPtr]$e.Current.NativeWindowHandle, 0xF0, [IntPtr]::Zero, [IntPtr]::Zero) -eq 1 }
function Wait-Window($pattern, $after) {
  for ($i = 0; $i -lt 40; $i++) { $w = Get-TopWindows $pattern | Where-Object { $_.Current.ProcessId -notin $after } | Select-Object -First 1; if ($w) { return $w }; Start-Sleep -Milliseconds 500 }
  throw "No window like '$pattern'."
}

$saved = @()
try {
  # Installer: every page in turn. On the folder page the test folder is typed into the box (WM_SETTEXT); on the last
  # page the "Run" box is unticked.
  $before = @(Get-Process | ForEach-Object Id)
  Start-Process $Setup | Out-Null
  $w = Wait-Window 'EsyType Test Setup*' $before
  for ($n = 1; $n -le 8; $n++) {
    # The folder page (it has Browse...): its box is a classic Edit control, found by class, set and read back.
    if (Find-El $w 'Browse...' $null -Tries 1) {
      $edit = @($w.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition($UA::ClassNameProperty, 'Edit'))) | Where-Object { -not $_.Current.IsOffscreen })[0]
      if (-not $edit) { throw 'No folder box found; stopped before installing.' }
      $he = [IntPtr]$edit.Current.NativeWindowHandle
      [void][Is]::SendMessageW($he, 0x000C, [IntPtr]::Zero, $dir); Start-Sleep 0.3   # WM_SETTEXT
      $sb = New-Object System.Text.StringBuilder 1024; [void][Is]::SendMessageW($he, 0x000D, [IntPtr]1024, $sb)   # WM_GETTEXT
      if ($sb.ToString() -ne $dir) { throw "The folder box shows '$sb', not the test folder; stopped before installing." }
    }
    $finish = Find-El $w 'Finish' $null -Tries 1
    if ($finish) {
      $run = Find-El $w 'Run EsyType Test' $null -Tries 1
      if ($run -and (Ticked $run)) { [void][Is]::SendMessage([IntPtr]$run.Current.NativeWindowHandle, 0xF5, [IntPtr]::Zero, [IntPtr]::Zero) }
      $saved += Snap $w "$n-finished"; Click $finish; break
    }
    $next = @('Install', 'Next >' | ForEach-Object { Find-El $w $_ $null -Tries 1 } | Where-Object { $_ -and $_.Current.IsEnabled })[0]
    if (-not $next) { if (++$waits -gt 60) { throw 'The installer stopped moving on.' }; Start-Sleep 1; $n--; continue }   # installing: wait for the next page
    $saved += Snap $w "$n-$($next.Current.Name -replace '[^A-Za-z]', '')"
    Click $next
  }
  for ($i = 0; $i -lt 20 -and -not (Test-Path $uninstKey); $i++) { Start-Sleep -Milliseconds 500 }

  # Uninstaller: confirm page with the delete-data box, then finish
  $before = @(Get-Process | ForEach-Object Id)
  Start-Process ((Get-ItemProperty $uninstKey).UninstallString.Trim('"')) | Out-Null
  $w = Wait-Window 'EsyType Test Uninstall*' $before
  $saved += Snap $w '3-uninstall'
  $box = Find-El $w 'Also delete*' $null -Like
  [void][Is]::SendMessage([IntPtr]$box.Current.NativeWindowHandle, 0xF5, [IntPtr]::Zero, [IntPtr]::Zero)
  Click (Find-El $w 'Uninstall' $null)
  for ($i = 0; $i -lt 60 -and -not (Find-El $w 'Finish' $null -Tries 1) -and -not (Find-El $w 'Close' $null -Tries 1); $i++) { Start-Sleep -Milliseconds 500 }
  $saved += Snap $w '4-uninstalled'
  $b = @('Finish', 'Close' | ForEach-Object { Find-El $w $_ $null -Tries 1 } | Where-Object { $_ })[0]; Click $b
} finally {
  Start-Sleep 2
  "installed after: $(Test-Path $uninstKey); startup value left: $([bool](Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'EsyType Test' -ErrorAction SilentlyContinue))"
  if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
  "saved: $($saved -join ', ') in $Out"
}
