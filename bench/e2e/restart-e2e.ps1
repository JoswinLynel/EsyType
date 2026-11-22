# Restart and persistence: settings and model folder survive a restart, a Windows-style start (--minimized)
# stays in the tray with no window, and dictation works after each start. Also checks spacing between
# consecutive dictations. Injected audio; types only into this script's own window.
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$ModelSource = "D:\EsyAI\EsyType\models\ggml-base.en-q5_1.bin",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio"
)
$ErrorActionPreference = 'Stop'
# These older scripts use Ctrl+Space and look windows up by title: they need the installed EsyType closed.
if (Get-Process esytype -ErrorAction SilentlyContinue) { throw 'Quit your EsyType from its tray icon first: this test uses Ctrl+Space and the EsyType window title.' }
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class S {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
  public static string Fg() { var h = GetForegroundWindow(); uint pid; GetWindowThreadProcessId(h, out pid); var b = new System.Text.StringBuilder(256); GetWindowText(h, b, 256); string name = ""; try { name = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch {} return "'" + b + "' (" + name + ", visible=" + IsWindowVisible(h) + ")"; }
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-52} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

# Settings with non-default values and a model folder that is NOT the default, so persistence is visible.
$lad = Join-Path $Work 'localappdata-restart'; $models = Join-Path $Work 'restart-models'
New-Item -ItemType Directory -Force (Join-Path $lad 'EsyAI\EsyType'), $models | Out-Null
Copy-Item $ModelSource $models -Force
$settingsFile = Join-Path $lad 'EsyAI\EsyType\settings.json'
$settings = '{"model":"base","mic":null,"threads":3,"ptt":"Ctrl+Space","toggle":"Ctrl+Shift+Space","models_dir":"' + ($models -replace '\\', '\\') + '","start_with_windows":false}'
Set-Content $settingsFile $settings -Encoding ascii
$current = Join-Path $Work 'current.f32'; Copy-Item (Join-Path $Audio '1320_5s.f32') $current -Force
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current

$tf = Join-Path $Work 'restart-target.txt'; Set-Content $tf '' -Encoding ascii
$tgt = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$tf`"", '-Kind', 'RichTextBox' -PassThru
Start-Sleep 3; $h = [S]::FindWindow([NullString]::Value, 'esytype-e2e-target')
function Text { for ($i = 0; $i -lt 40; $i++) { try { return [IO.File]::ReadAllText($tf) } catch { Start-Sleep -Milliseconds 25 } }; throw 'read failed' }
function Dictate {
  if ([S]::GetForegroundWindow() -ne $h) { [void](New-Object -ComObject WScript.Shell).AppActivate('esytype-e2e-target'); Start-Sleep -Milliseconds 300; [S]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 300 }
  if ([S]::GetForegroundWindow() -ne $h) { throw "Test window is not in front (foreground: $([S]::Fg())); stopping before sending keys." }
  $before = (Text).Length
  [S]::Down(0x11); [S]::Down(0x20); Start-Sleep -Milliseconds 900; [S]::Up(0x20); [S]::Up(0x11)
  for ($i = 0; $i -lt 100 -and (Text).Length -eq $before; $i++) { Start-Sleep -Milliseconds 100 }
  Start-Sleep 1; (Text).Substring($before)
}
function Launch($args2) {
  $p = @{ FilePath = $Exe; PassThru = $true; RedirectStandardError = (Join-Path $Work 'restart-trace.txt') }
  if ($args2) { $p.ArgumentList = $args2 }
  $a = Start-Process @p; Start-Sleep 9
  $script:main = [S]::FindWindow([NullString]::Value, 'EsyType'); $a
}

try {
  # 1. Normal start: window shown, dictation works, consecutive dictations are spaced
  $app = Launch @()
  Check 'Normal start shows the main window' ([S]::IsWindowVisible($main)) ''
  $one = Dictate; $two = Dictate
  Check 'Dictation works (model from the custom folder)' ($one.Trim().Length -gt 20) "'$($one.Trim())'"
  Check 'Second dictation into the same window starts with a space' ($two.StartsWith(' ') -and -not $one.StartsWith(' ')) "first '$($one.Substring(0,6))…', second '$($two.Substring(0,6))…'"
  Stop-Process -Id $app.Id -Force; Start-Sleep 2

  # 2. Restart as Windows would at login: --minimized
  $app = Launch @('--minimized')
  "   foreground after login-style start: $([S]::Fg())"
  Check 'Login-style start (--minimized): no window shown' (-not $app.HasExited -and -not [S]::IsWindowVisible($main)) "running: $(-not $app.HasExited)"
  $three = Dictate
  Check 'Dictation works after restart, from the tray' ($three.Trim().Length -gt 20) "'$($three.Trim())'"
  Check 'First dictation after a restart has no leading space' (-not $three.StartsWith(' ')) ''
  $after = Get-Content $settingsFile -Raw | ConvertFrom-Json
  Check 'Settings unchanged across restarts' ($after.threads -eq 3 -and $after.models_dir -eq $models -and $after.model -eq 'base') "threads=$($after.threads) models_dir=$($after.models_dir)"
  Check 'No model files appeared in the default folder' (-not (Test-Path (Join-Path $lad 'EsyAI\EsyType\models\*.bin'))) ''
} finally {
  Get-Process esytype-e2e -ErrorAction SilentlyContinue | Where-Object { $_.Path -like 'D:\AI Projects\*' } | Stop-Process -Force
  Stop-Process -Id $tgt.Id -Force -ErrorAction SilentlyContinue
  [S]::Up(0x20); [S]::Up(0x11)
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'restart-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
