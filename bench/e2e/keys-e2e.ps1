# Single-key push to talk, hands-free by double tap, the maximum recording length and sounds, end to end in the test's
# own window (milestone E). Test build with its own settings: Right Ctrl is the push-to-talk key, start and stop sounds
# on. Keys are sent only while the test's own window is in front. Also: the Language choice is off for an English-only
# model (Settings > Speech).
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e"
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech, UIAutomationClient, UIAutomationTypes
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Ky {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static void RDown() { keybd_event(0xA3, 0x1D, 1, UIntPtr.Zero); } public static void RUp() { keybd_event(0xA3, 0x1D, 3, UIntPtr.Zero); }
  public static void Tap(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); keybd_event(v, 0, 2, UIntPtr.Zero); }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-58} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

$lad = Join-Path $Work 'localappdata-keys'; $data = Join-Path $lad 'EsyAI\EsyType'
New-Item -ItemType Directory -Force $data | Out-Null; Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force
function Settings([bool]$doubleTap) {
  [ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; ptt_key = 'RightCtrl'; double_tap = $doubleTap; sound_start = $true; sound_stop = $true
    models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false } | ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
}
$db = Join-Path $data 'esytype.db'; $current = Join-Path $Work 'keys.f32'; $trace = Join-Path $Work 'keys-trace.txt'
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current

$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer; $voice.SelectVoice('Microsoft Hazel Desktop')
function Say($text) {
  $wav = Join-Path $Work 'keys-say.wav'
  $fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
  $voice.SetOutputToWaveFile($wav, $fmt); $voice.Speak($text); $voice.SetOutputToNull()
  $b = [IO.File]::ReadAllBytes($wav); $at = 12; while ([Text.Encoding]::ASCII.GetString($b, $at, 4) -ne 'data') { $at += 8 + [BitConverter]::ToInt32($b, $at + 4) }
  $n = [BitConverter]::ToInt32($b, $at + 4) / 2; $f = New-Object float[] ($n + 8000)
  for ($k = 0; $k -lt $n; $k++) { $f[$k] = [BitConverter]::ToInt16($b, $at + 8 + 2 * $k) / 32768.0 }
  $o = New-Object byte[] ($f.Length * 4); [Buffer]::BlockCopy($f, 0, $o, 0, $o.Length); [IO.File]::WriteAllBytes($current, $o)
}
function Window($title) {
  $f = Join-Path $Work "$title.txt"; Set-Content $f '' -Encoding ascii
  $p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$f`"", '-Kind', 'RichTextBox', '-Title', $title -PassThru
  $h = [IntPtr]::Zero
  for ($i = 0; $i -lt 40 -and $h -eq [IntPtr]::Zero; $i++) { Start-Sleep -Milliseconds 250; $h = [Ky]::FindWindow([NullString]::Value, $title) }
  if ($h -eq [IntPtr]::Zero) { throw "Test window '$title' did not appear." }
  [pscustomobject]@{ P = $p; H = $h; F = $f }
}
function Text { for ($i = 0; $i -lt 40; $i++) { try { return ([IO.File]::ReadAllText($own.F)) -replace "`r", '' } catch { Start-Sleep -Milliseconds 25 } } }
function Front {
  $h = $own.H
  for ($k = 0; $k -lt 8 -and [Ky]::GetForegroundWindow() -ne $h; $k++) {
    $fg = 0; [void][Ky]::GetWindowThreadProcessId([Ky]::GetForegroundWindow(), [ref]$fg)
    if ($k -gt 0 -and $fg -in @($own.P.Id, $app.Id)) { [Ky]::Tap(0x12) }
    [Ky]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400
  }
  if ([Ky]::GetForegroundWindow() -ne $h) {
    $fg = 0; [void][Ky]::GetWindowThreadProcessId([Ky]::GetForegroundWindow(), [ref]$fg)
    throw "Test window is not in front (front: process $fg $((Get-Process -Id $fg -ErrorAction SilentlyContinue).ProcessName)); no keys sent."
  }
}
function Rows { @(& python -I -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); [print(r[0]) for r in c.execute('select final_text from transcripts order by id')]" $db) }
function WaitRow($n, [int]$seconds = 60) { for ($i = 0; $i -lt $seconds * 4 -and (Rows).Count -le $n; $i++) { Start-Sleep -Milliseconds 250 }; Start-Sleep -Milliseconds 700; (Rows).Count -gt $n }
function Pill { Get-TopWindows 'EsyType recording' @($app.Id) | Select-Object -First 1 }
function PillText { $p = Pill; if ($p) { for ($i = 0; $i -lt 10; $i++) { $t = (Find-All $p $CT::Text | ForEach-Object { $_.Current.Name }) -join ' '; if ($t) { return $t }; Start-Sleep -Milliseconds 200 } } }
function Hold([int]$ms) { Front; try { [Ky]::RDown(); Start-Sleep -Milliseconds $ms } finally { [Ky]::RUp() } }
function Launch([string]$extra) {
  $a = @{}; if ($extra) { $a.ArgumentList = $extra }; $script:app = Start-Process $Exe @a -PassThru -RedirectStandardError $trace; Start-Sleep 9
}

$own = Window 'esytype-keys-own'
Settings $true; $env:ESYTYPE_TEST_MAX_SECONDS = '7'
Launch '--minimized'
try {
  # 1. Hold Right Ctrl: dictates and types into the window in front
  Say 'Holding the right control key works.'
  $n = (Rows).Count; Hold 1500
  $ok = WaitRow $n
  Check 'Hold Right Ctrl: dictates and types it' ($ok -and (Text) -match 'right control') "'$(Text)'"

  # 2. A short tap records nothing, and the key does nothing else (Right Ctrl + Q types a plain q)
  Set-Content "$($own.F).clear" ''; Start-Sleep 0.5
  $n = (Rows).Count
  Front; [Ky]::RDown(); Start-Sleep -Milliseconds 60; [Ky]::Tap(0x51); Start-Sleep -Milliseconds 60; [Ky]::RUp()
  Start-Sleep 1.5   # two taps would start hands-free: wait out the double-tap time
  $none = -not (WaitRow $n 4)
  Check 'A short tap records nothing' $none "rows $((Rows).Count)"
  Check 'Right Ctrl is swallowed: Q arrives as a plain q' ((Text) -eq 'q') "'$(Text)'"

  # 3. Two quick taps: hands-free; it keeps listening after the key is up; one tap stops and types
  Set-Content "$($own.F).clear" ''; Start-Sleep 0.5
  Say 'Two taps make it hands free.'
  $n = (Rows).Count
  Front; [Ky]::RDown(); Start-Sleep -Milliseconds 80; [Ky]::RUp(); Start-Sleep -Milliseconds 150; [Ky]::RDown(); Start-Sleep -Milliseconds 80; [Ky]::RUp()
  Start-Sleep 1.2
  $label = PillText
  Check 'Double tap: the pill says Hands-free' ($label -match 'Hands-free') "'$label'"
  Start-Sleep 2
  Check 'Hands-free keeps listening after the key is up' ((Rows).Count -eq $n -and (Pill)) "rows $((Rows).Count)"
  Hold 80
  $ok = WaitRow $n
  Check 'One tap stops hands-free and types it' ($ok -and (Text) -match 'hands.?free') "'$(Text)'"

  # 4. The maximum length (7 s in this test) stops a forgotten hands-free dictation and types it
  Set-Content "$($own.F).clear" ''; Start-Sleep 0.5
  Say 'This one stops by itself.'
  $n = (Rows).Count; $t0 = Get-Date
  Front; [Ky]::RDown(); Start-Sleep -Milliseconds 80; [Ky]::RUp(); Start-Sleep -Milliseconds 150; [Ky]::RDown(); Start-Sleep -Milliseconds 80; [Ky]::RUp()
  $ok = WaitRow $n 40; $took = ((Get-Date) - $t0).TotalSeconds
  Check 'Maximum length stops it and types it' ($ok -and $took -ge 6.5 -and (Text) -match 'by itself') ("after {0:N1} s: '{1}'" -f $took, (Text))
  Check 'Sounds on: no audio errors in the trace' (-not (Select-String -Path $trace -Pattern 'panick' -Quiet)) ''
  Stop-Process -Id $app.Id -Force; Start-Sleep 1.5

  # 5. Double tap switched off: two taps record nothing
  Settings $false
  Launch ''
  $n = (Rows).Count
  Front; [Ky]::RDown(); Start-Sleep -Milliseconds 80; [Ky]::RUp(); Start-Sleep -Milliseconds 150; [Ky]::RDown(); Start-Sleep -Milliseconds 80; [Ky]::RUp()
  Check 'Double tap off: two taps record nothing' (-not (WaitRow $n 4)) "rows $((Rows).Count)"

  # 6. Settings > Speech: Language and Translate are off for an English-only model
  $root = Get-AppWindow $app.Id 'EsyType'
  Open-Settings $root 'Speech'
  $lang = Find-El $root 'Language' $CT::ComboBox
  Check 'Language choice is off for Base (English only)' ($lang -and -not $lang.Current.IsEnabled) "enabled=$($lang.Current.IsEnabled)"
  Open-Settings $root 'Shortcuts'
  $key = Find-El $root 'Push to talk on one key' $CT::ComboBox
  Check 'Shortcuts shows the one-key choice' ([bool]$key) ''
} catch {
  "STOPPED: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
} finally {
  if ($app) { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue }
  if ($own) { Stop-Process -Id $own.P.Id -Force -ErrorAction SilentlyContinue }
  [Ky]::RUp()
  Remove-Item Env:ESYTYPE_TEST_MAX_SECONDS -ErrorAction SilentlyContinue
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'keys-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
