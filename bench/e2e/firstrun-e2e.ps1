# First-run setup end to end, in the test build with its own empty profile. Models come from a local, throttled
# server (model-server.py) serving files already on this PC: nothing is downloaded from the internet.
# Covers: the wizard opens even when started minimized; every step; Back; the History switch; the recommendation;
# server not running (error, Retry); a damaged file (rejected, removed); speed and time left; Cancel and resume;
# Verified; the microphone test; shortcut capture (refused keys, Esc, the 20-second restore, Ctrl+F8 used for real);
# Try it; Finish hides to the tray; a restart opens the normal window; Run setup again keeps data; an existing
# user's profile never sees the wizard. Keys go only to the test build's own window, and only while it is in front.
# Never presses Ctrl+Space (your installed EsyType holds it).
param([string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe", [string]$Work = "D:\AI Projects\Tools\e2e",
      [string]$Audio = "D:\AI Projects\Tools\bench\audio", [int]$Port = 8766)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Fr {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
  // With the hardware scan code, as a real keyboard sends it (the browser's key code comes from it).
  public static void DownS(byte v) { keybd_event(v, (byte)MapVirtualKey(v, 0), 0, UIntPtr.Zero); } public static void UpS(byte v) { keybd_event(v, (byte)MapVirtualKey(v, 0), 2, UIntPtr.Zero); }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-62} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

$lad = Join-Path $Work 'localappdata-firstrun'; $data = Join-Path $lad 'EsyAI\EsyType'
$models = Join-Path $data 'models'; $serve = Join-Path $Work 'firstrun-serve'; $realBase = Join-Path $Work 'restart-models\ggml-base.en-q5_1.bin'
$current = Join-Path $Work 'current.f32'; Copy-Item (Join-Path $Audio '6930_5s.f32') $current -Force
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current; $env:ESYTYPE_MODEL_BASE_URL = "http://127.0.0.1:$Port"
$userClip = Get-Clipboard -Raw
$server = $null; $app = $null

function Launch([switch]$Minimized) {
  $a = @(); if ($Minimized) { $a = @('--minimized') }
  $script:app = if ($a) { Start-Process $Exe -ArgumentList $a -PassThru -RedirectStandardError (Join-Path $Work 'firstrun-trace.txt') } else { Start-Process $Exe -PassThru -RedirectStandardError (Join-Path $Work 'firstrun-trace.txt') }
  Start-Sleep 8; $script:root = Get-AppWindow $app.Id 'EsyType'; $script:h = [IntPtr]$root.Current.NativeWindowHandle
}
function Quit { if ($app) { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue; Start-Sleep 2 } }
function Serve([int]$Rate = 0) {
  if ($server) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue; Start-Sleep 1 }
  $script:server = Start-Process python -ArgumentList '-I', "`"$(Join-Path $PSScriptRoot 'model-server.py')`"", "`"$serve`"", $Port, '--rate', $Rate -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $Work 'firstrun-server.txt')
  Start-Sleep 2
}
function Settings { Get-Content (Join-Path $data 'settings.json') -Raw | ConvertFrom-Json }
function Texts { (@(Find-All $root $CT::Text) + @(Find-All $root $CT::ListItem) | ForEach-Object { $_.Current.Name }) -join ' ' }   # list items carry their text as a name
function Has([string]$pattern, [int]$Seconds = 5) { for ($i = 0; $i -lt $Seconds * 4; $i++) { if ((Texts) -match $pattern) { return $true }; Start-Sleep -Milliseconds 250 }; $false }
function Click([string]$name, [switch]$Like) { Invoke-El (Find-El $root $name $CT::Button -Like:$Like); Start-Sleep -Milliseconds 700 }
function Front { for ($k = 0; $k -lt 8 -and [Fr]::GetForegroundWindow() -ne $h; $k++) { [Fr]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400 }
  if ([Fr]::GetForegroundWindow() -ne $h) { throw 'The test build window is not in front; no keys sent.' } }
# -NoScan: injected keys without a scan code (as remote desktops send them), which the capture handles separately.
function Keys([byte[]]$vks, [switch]$NoScan) {
  Front
  try { foreach ($v in $vks) { if ($NoScan) { [Fr]::Down($v) } else { [Fr]::DownS($v) } }; Start-Sleep -Milliseconds 150 }
  finally { foreach ($v in $vks[($vks.Count - 1)..0]) { if ($NoScan) { [Fr]::Up($v) } else { [Fr]::UpS($v) } } }
  Start-Sleep -Milliseconds 600
}
function Capture([string]$which, [byte[]]$vks, [switch]$NoScan) {
  Click "Change $which shortcut"
  if (-not (Find-El $root "Press the new $which shortcut" -Tries 15)) { throw "no capture box for $which" }
  Keys $vks -NoScan:$NoScan
}
function Rows { $db = Join-Path $data 'esytype.db'; if (Test-Path $db) { [int](python -I -c "import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute('select count(*) from transcripts').fetchone()[0])" $db) } else { 0 } }

try {
  # ---- A new user ----
  if (Test-Path $lad) { Remove-Item $lad -Recurse -Force }
  New-Item -ItemType Directory -Force $serve | Out-Null
  $junk = New-Object byte[] 2000000; (New-Object Random 7).NextBytes($junk); [IO.File]::WriteAllBytes((Join-Path $serve 'ggml-base.en-q5_1.bin'), $junk)
  Launch -Minimized
  Check 'Started minimized on a new PC: the wizard is shown' ([Fr]::IsWindowVisible($h) -and (Has 'Speak\. It types\.')) ''
  Check 'New profile: no settings file written just by starting' (-not (Test-Path (Join-Path $data 'settings.json'))) ''
  Click 'Get started'
  Check 'Privacy step: local promise and SHA-256 named' ((Has 'Private by design') -and (Texts) -match 'SHA-256') ''
  $hist = Find-El $root 'Keep a History of dictations on this PC' $CT::CheckBox
  Invoke-El $hist; Start-Sleep 1; $off = (Settings).history_enabled
  Invoke-El $hist; Start-Sleep 1
  Check 'History switch saves (off, then on again)' ($off -eq $false -and (Settings).history_enabled -eq $true) ''
  Check 'First save records setup as not done' ((Settings).setup_done -eq $false) ''
  Click 'Continue'
  Check 'Name step (Mac design): asks what to call you, can be skipped' ((Has 'What should EsyType call you\?') -and [bool](Find-El $root 'Skip' $CT::Button)) ''
  Click 'Continue'
  Check 'Theme step: Follow Windows, Dark or Light' ((Has 'Light or dark\?') -and [bool](Find-El $root 'Follow Windows')) ''
  Click 'Continue'
  Check 'Model step: Base recommended, this PC shown' ((Has 'Base is recommended for this PC') -and (Texts) -match 'AVX2') ''
  Click 'Back'
  Check 'Back returns to the theme step' (Has 'Light or dark\?') ''
  Click 'Continue'; Click 'Download Base'
  # server not running
  Check 'Server not running: the reason in words and Retry' ((Has 'Could not reach the download server' 10) -and [bool](Find-El $root 'Retry' $CT::Button)) ''
  # a damaged file
  Serve; Click 'Retry'
  Check 'Damaged file: rejected with a clear message' (Has 'failed its integrity check' 15) ''
  Check 'Damaged file: removed from the model folder' (-not (Get-ChildItem $models -ErrorAction SilentlyContinue | Where-Object Name -like 'ggml-base*')) "$((Get-ChildItem $models -ErrorAction SilentlyContinue).Name)"
  # the real file, throttled: speed, time left, Cancel, resume
  Copy-Item $realBase (Join-Path $serve 'ggml-base.en-q5_1.bin') -Force
  Serve -Rate 6000000; Click 'Retry'
  Check 'Download shows speed and time left' (Has 'MB/s .* left' 8) ((Texts) -replace '.*(\d+%[^A-Z]*).*', '$1')
  Click 'Cancel download'
  Check 'Cancel: says so, partial file kept for resuming' ((Has 'cancelled' 5) -and (Test-Path (Join-Path $models 'ggml-base.en-q5_1.bin.partial'))) ''
  Click 'Retry'
  Check 'Download finishes and shows Verified' (Has 'Verified' 40) ''
  Check 'Retry resumed from the partial file (Range request)' ((Get-Content (Join-Path $Work 'firstrun-server.txt')) -match 'range=bytes=[1-9]') ''
  Check 'Downloaded file matches the original' ((Get-FileHash (Join-Path $models 'ggml-base.en-q5_1.bin')).Hash -eq (Get-FileHash $realBase).Hash) ''
  Click 'Continue'
  # microphone
  Click 'Test microphone'
  Check 'Microphone test: "We heard you" (test audio)' (Has 'We heard you' 8) ''
  Click 'Continue'
  # shortcut: your installed EsyType holds Ctrl+Space, so the test build cannot register it
  Check 'Shortcut step: default held elsewhere is reported' (Has 'could not be registered') ''
  Capture 'Hold to talk' 0x10, 0x41 -NoScan   # Shift+A, without scan codes
  Check 'Capture refuses Shift+A (no scan code), with a reason' ((Texts) -match 'Shift with a key types capitals' -and -not (Find-El $root 'Use this' $CT::Button).Current.IsEnabled) "focus: $([System.Windows.Automation.AutomationElement]::FocusedElement.Current.Name) | $((Texts) -replace '.*(Your shortcut.{0,200}).*', '$1')"
  Keys 0x1B                            # Esc cancels
  Check 'Esc ends the capture, shortcut unchanged' (-not (Find-El $root 'Press the new Hold to talk shortcut' -Tries 3) -and (Settings).ptt -eq 'Ctrl+Space') ''
  Click 'Change Hold to talk shortcut'; Start-Sleep 23
  Check 'Capture left alone: restored after 20 s, with a message' ((Has 'timed out' 3) -and -not (Find-El $root 'Press the new Hold to talk shortcut' -Tries 2)) ''
  Capture 'Hold to talk' 0x11, 0x77   # Ctrl+F8, with scan codes
  Click 'Use this'
  Capture 'Start / stop' 0x11, 0x76   # Ctrl+F7
  Click 'Use this'; Start-Sleep 1
  $st = Settings
  Check 'Captured shortcuts saved (Ctrl+F8, Ctrl+F7); warning gone' ($st.ptt -eq 'Ctrl+F8' -and $st.toggle -eq 'Ctrl+F7' -and -not ((Texts) -match 'could not be registered')) "$($st.ptt) / $($st.toggle)"
  Click 'Continue'
  # Try it with the captured shortcut
  $box = Find-El $root 'Practice area' $CT::Edit
  Front; $box.SetFocus(); Start-Sleep 0.4
  try { [Fr]::Down(0x11); [Fr]::Down(0x77); Start-Sleep -Milliseconds 900 } finally { [Fr]::Up(0x77); [Fr]::Up(0x11) }
  $typed = ''; for ($i = 0; $i -lt 240 -and -not $typed; $i++) { Start-Sleep -Milliseconds 250; $typed = [string]$box.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }
  Check 'Try it: dictation with Ctrl+F8 lands in the box' ($typed -match 'Congratulations') "'$typed'"
  Check 'Try it: time taken shown' (Has 'typed in' 5) ''
  Click 'Continue'
  Check 'Ready: summary shows the new shortcut' ((Texts) -match "You're ready" -and [bool](Find-El $root 'Ctrl+F8')) ''
  Click 'Finish'; Start-Sleep 1
  Check 'Finish: window hidden to the tray, setup_done saved' (-not [Fr]::IsWindowVisible($h) -and (Settings).setup_done -eq $true) ''
  Quit
  Launch
  Check 'Restart: the normal window, no wizard' ([bool](Find-El $root 'Dictation' $CT::Button -Tries 15) -and -not ((Texts) -match 'Step \d+ of 10')) ''
  # Run setup again keeps data
  $before = Rows; $settingsBefore = Get-Content (Join-Path $data 'settings.json') -Raw
  Open-Settings $root 'About'; Click 'Run setup again'
  Check 'Run setup again opens the wizard' (Has 'Speak\. It types\.') ''
  foreach ($i in 1..9) { Click $(if ($i -eq 1) { 'Get started' } elseif ($i -eq 5) { 'Use Base' } else { 'Continue' }) }
  Click 'Finish'; Start-Sleep 1
  Check 'Run setup again: History and settings kept' ((Rows) -eq $before -and $before -ge 1 -and (Get-Content (Join-Path $data 'settings.json') -Raw) -eq $settingsBefore) "rows $before -> $(Rows)"
  Quit

  # ---- An existing user (a model installed, a settings file from before setup existed) ----
  Remove-Item $lad -Recurse -Force; New-Item -ItemType Directory -Force $data | Out-Null
  $old = [ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; undo_shortcut = 'Ctrl+F9'; paste_last_shortcut = 'Ctrl+F10'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false; history_retention_days = 30 }
  $old | ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
  $oldText = Get-Content (Join-Path $data 'settings.json') -Raw
  Launch -Minimized
  Check 'Existing user, started minimized: no window shown' (-not [Fr]::IsWindowVisible($h)) ''
  Check 'Existing user: settings file not rewritten by starting' ((Get-Content (Join-Path $data 'settings.json') -Raw) -eq $oldText) ''
  Quit
  Launch
  Check 'Existing user, window opened: the normal window' ([bool](Find-El $root 'Dictation' $CT::Button -Tries 15) -and -not ((Texts) -match 'Step \d+ of 10')) ''
  Invoke-El (Find-El $root 'Style' $CT::Button); Start-Sleep 1
  (Find-El $root 'Verbatim*' $CT::RadioButton -Like).GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep 1   # any change saves
  $st = Settings
  Check 'Existing user: first save records setup done, keeps the rest' ($st.setup_done -eq $true -and $st.text_mode -eq 'verbatim' -and $st.ptt -eq 'Ctrl+F8' -and $st.history_retention_days -eq 30 -and $st.models_dir -eq $old.models_dir) ''
  Quit
} catch {
  "STOPPED: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
} finally {
  if ($app) { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue }
  if ($server) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
  foreach ($k in 0x10, 0x11, 0x41, 0x76, 0x77) { [Fr]::Up($k) }
  if ($userClip) { Set-Clipboard -Value $userClip }
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'firstrun-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
