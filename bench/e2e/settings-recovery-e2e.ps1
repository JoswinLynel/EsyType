# A damaged settings.json, in the test build with its own profile: one value of the wrong type (only it resets,
# the rest are kept, a banner names it, the original is copied aside, the file itself is not touched until a save,
# dictation still works with the kept shortcut); a file that is not JSON (defaults, banner, copy kept); Dismiss.
# The test build never changes the Windows startup entry (apply_autostart is disabled in test builds).
param([string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe", [string]$Work = "D:\AI Projects\Tools\e2e",
      [string]$Audio = "D:\AI Projects\Tools\bench\audio")
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Sr {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-62} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

$lad = Join-Path $Work 'localappdata-recovery'; $data = Join-Path $lad 'EsyAI\EsyType'; New-Item -ItemType Directory -Force $data | Out-Null
$file = Join-Path $data 'settings.json'
$current = Join-Path $Work 'current.f32'; Copy-Item (Join-Path $Audio '6930_5s.f32') $current -Force
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current
$userClip = Get-Clipboard -Raw
function Copies { @(Get-ChildItem $data -Filter 'settings.damaged-*.json') }
function Launch { $script:app = Start-Process $Exe -PassThru -RedirectStandardError (Join-Path $Work 'recovery-trace.txt'); Start-Sleep 9; $script:root = Get-AppWindow $app.Id 'EsyType'; $script:h = [IntPtr]$root.Current.NativeWindowHandle }
function Quit { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue; Start-Sleep 2 }
# The banner's sentence is split into several text pieces; join everything after its start.
function BannerText { for ($k = 0; $k -lt 12; $k++) { $t = (Find-All $root $CT::Text | ForEach-Object { $_.Current.Name }) -join ' '; if ($t -match 'could not be read') { return $t }; if ($t -match 'Welcome back') { return }; Start-Sleep -Milliseconds 250 } }   # waits for the page   # the window's text, if the banner is there

try {
  # 1. One value of the wrong type
  Get-ChildItem $data -Filter 'settings*' | Remove-Item -Force
  $one = '{"model":"base","threads":"3","ptt":"Ctrl+F8","toggle":"Ctrl+F7","undo_shortcut":"Ctrl+F9","paste_last_shortcut":"Ctrl+F10","models_dir":"' + ((Join-Path $Work 'restart-models') -replace '\\', '\\') + '","start_with_windows":false,"history_enabled":false}'
  [IO.File]::WriteAllText($file, $one)
  Launch
  $b = BannerText
  Check 'One bad value: banner names only that setting' ($b -match 'reset to their defaults:\s+Processor threads\s*\.') ''
  Check 'One bad value: original copied aside, unchanged' ((Copies).Count -eq 1 -and [IO.File]::ReadAllText((Copies)[0].FullName) -eq $one) "$((Copies).Name)"
  Check 'One bad value: settings.json not rewritten at start' ([IO.File]::ReadAllText($file) -eq $one) ''
  Check 'One bad value: kept values in use (sidebar shows the model)' ([bool](Find-El $root 'Local*Base*' $CT::Button -Like -Tries 20)) ''
  # dictation with the kept shortcut (Ctrl+F8) into a new Scratchpad note
  Invoke-El (Find-El $root 'Scratchpad' $CT::Button); Start-Sleep 1; Invoke-El (Find-El $root 'New note' $CT::Button); Start-Sleep 0.8; $box = Find-El $root 'Note' $CT::Edit
  for ($k = 0; $k -lt 6 -and [Sr]::GetForegroundWindow() -ne $h; $k++) { [Sr]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400 }
  if ([Sr]::GetForegroundWindow() -ne $h) { throw 'The test build window is not in front; no keys sent.' }
  $box.SetFocus(); Start-Sleep 0.4
  try { [Sr]::Down(0x11); [Sr]::Down(0x77); Start-Sleep -Milliseconds 900 } finally { [Sr]::Up(0x77); [Sr]::Up(0x11) }
  $typed = ''; for ($i = 0; $i -lt 240 -and -not $typed; $i++) { Start-Sleep -Milliseconds 250; $typed = [string]$box.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }
  Check 'One bad value: dictation works with the kept shortcut' ($typed -match 'Congratulations') "'$typed'"
  Invoke-El (Find-El $root 'Dismiss' $CT::Button); Start-Sleep 1
  Check 'Dismiss hides the banner' (-not (BannerText)) ''
  Quit

  # 2. Not JSON at all
  Get-ChildItem $data -Filter 'settings*' | Remove-Item -Force
  [IO.File]::WriteAllText($file, '{"model":"base",')
  Launch
  $b = BannerText
  Check 'Not JSON: banner says defaults are in use' ($b -match 'Your settings file could not be read, so EsyType is using default settings') ''
  Check 'Not JSON: original copied aside' ((Copies).Count -eq 1 -and [IO.File]::ReadAllText((Copies)[0].FullName) -eq '{"model":"base",') "$((Copies).Name)"
  Check 'Not JSON: Show in folder offered' ([bool](Find-El $root 'Show in folder' $CT::Button)) ''
  Quit

  # 3. A good file: no banner, no copy
  Get-ChildItem $data -Filter 'settings*' | Remove-Item -Force
  [IO.File]::WriteAllText($file, ($one -replace '"threads":"3"', '"threads":0'))
  Launch
  Check 'Good file: no banner, no copy' (-not (BannerText) -and (Copies).Count -eq 0) ''
  Quit
} catch {
  "STOPPED: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
} finally {
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
  foreach ($k in 0x11, 0x77) { [Sr]::Up($k) }
  if ($userClip) { Set-Clipboard -Value $userClip }
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'recovery-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
