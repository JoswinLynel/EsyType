# EsyMeet 8.2: the "Meeting detected" prompt, end to end. A program of our own uses the microphone (meet-capture.exe,
# from bench/meet-capture), and only the test build counts it as a meeting app (ESYTYPE_TEST_MEET_EXE). Checks: the prompt
# appears after about 5 s and names the app; it never takes the keyboard; Not now holds for that call; a dictation during
# the call types normally; a new call prompts again; Start transcription opens EsyMeet; an unanswered prompt fades after
# 30 s; a short use never prompts; "Detect meetings" off means no prompt; a program not on the list never prompts.
# Keys go only to the test's own window. Every microphone file the meeting program writes is deleted at once.
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$Meet = "D:\AI Projects\Tools\bench\meet-target\release\meet-capture.exe"
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech, UIAutomationClient, UIAutomationTypes
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Mt {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
  public static void Tap(byte v) { Down(v); Up(v); }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-62} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

$lad = Join-Path $Work 'localappdata-meeting'; $data = Join-Path $lad 'EsyAI\EsyType'
if (Test-Path $lad) { Remove-Item $lad -Recurse -Force }
New-Item -ItemType Directory -Force $data | Out-Null
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false } |
  ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
$db = Join-Path $data 'esytype.db'; $current = Join-Path $Work 'meeting.f32'; $scratch = Join-Path $Work 'meeting-capture'
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current

$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer; $voice.SelectVoice('Microsoft Hazel Desktop')
function Say($text) {
  $wav = Join-Path $Work 'meeting-say.wav'
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
  for ($i = 0; $i -lt 40 -and $h -eq [IntPtr]::Zero; $i++) { Start-Sleep -Milliseconds 250; $h = [Mt]::FindWindow([NullString]::Value, $title) }
  if ($h -eq [IntPtr]::Zero) { throw "Test window '$title' did not appear." }
  [pscustomobject]@{ P = $p; H = $h; F = $f }
}
function Text { for ($i = 0; $i -lt 40; $i++) { try { return ([IO.File]::ReadAllText($own.F)) -replace "`r", '' } catch { Start-Sleep -Milliseconds 25 } } }
function Front {
  for ($k = 0; $k -lt 8 -and [Mt]::GetForegroundWindow() -ne $own.H; $k++) {
    $fg = 0; [void][Mt]::GetWindowThreadProcessId([Mt]::GetForegroundWindow(), [ref]$fg)
    if ($k -gt 0 -and $fg -in @($own.P.Id, $app.Id)) { [Mt]::Tap(0x12) }
    [Mt]::SetForegroundWindow($own.H) | Out-Null; Start-Sleep -Milliseconds 400
  }
  if ([Mt]::GetForegroundWindow() -ne $own.H) {
    $fg = 0; [void][Mt]::GetWindowThreadProcessId([Mt]::GetForegroundWindow(), [ref]$fg)
    throw "Test window is not in front (front: process $fg $((Get-Process -Id $fg -ErrorAction SilentlyContinue).ProcessName)); no keys sent."
  }
}
function Rows { @(& python -I -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); [print(r[0]) for r in c.execute('select final_text from transcripts order by id')]" $db) }
function Launch([bool]$meetApp, [bool]$window = $false) {
  if ($meetApp) { $env:ESYTYPE_TEST_MEET_EXE = 'meet-capture.exe' } else { Remove-Item Env:ESYTYPE_TEST_MEET_EXE -ErrorAction SilentlyContinue }
  $a = @{}; if (-not $window) { $a.ArgumentList = '--minimized' }
  $script:app = Start-Process $Exe @a -PassThru -RedirectStandardError (Join-Path $Work 'meeting-trace.txt'); Start-Sleep 9
}
# The "meeting": our own program holding the microphone for $seconds.
function Meeting([int]$seconds) { Start-Process $Meet -ArgumentList $seconds, "`"$scratch`"" -PassThru -WindowStyle Hidden }
function EndMeeting($m) {
  if ($m) { Stop-Process -Id $m.Id -Force -ErrorAction SilentlyContinue; Start-Sleep 1 }
  Remove-Item (Join-Path $scratch 'mic.f32') -ErrorAction SilentlyContinue
}
function Prompt { Get-TopWindows 'EsyMeet' @($app.Id) | Select-Object -First 1 }
function PromptText { $p = Prompt; if ($p) { for ($i = 0; $i -lt 10; $i++) { $t = (Find-All $p $CT::Text | ForEach-Object { $_.Current.Name }) -join ' '; if ($t) { return $t }; Start-Sleep -Milliseconds 200 } } }
# Waits until the prompt is shown (or hidden), up to $seconds; returns the seconds it took, or $null.
function WaitPrompt([double]$seconds, [bool]$shown = $true) {
  $t0 = Get-Date
  while (((Get-Date) - $t0).TotalSeconds -lt $seconds) { if ([bool](Prompt) -eq $shown) { return ((Get-Date) - $t0).TotalSeconds }; Start-Sleep -Milliseconds 250 }
  $null
}
function PromptButton($name) { $p = Prompt; if ($p) { Find-El $p $name $CT::Button -Tries 15 } }

$own = Window 'esytype-meeting-own'
Launch $true
$m = $null
try {
  Front
  # 1. A meeting starts: the prompt appears after about 5 s and names the app
  $m = Meeting 300; $t0 = Get-Date
  $took = WaitPrompt 20
  $after = ((Get-Date) - $t0).TotalSeconds
  Check 'A meeting app on the microphone: the prompt appears' ([bool]$took) ("after {0:N1} s" -f $after)
  Check 'Not before 5 s of microphone use' ($after -ge 4.5) ("{0:N1} s" -f $after)
  $txt = PromptText
  Check 'It says "Meeting detected" and names the app' ($txt -match 'Meeting detected' -and $txt -match 'Test meeting' -and $txt -match 'transcribing') "'$txt'"
  # 2. It never takes the keyboard
  $before = Text
  Front; foreach ($k in 0x51, 0x57, 0x45) { [Mt]::Tap($k) }; Start-Sleep 0.8
  Check 'The prompt does not take the keyboard' ([Mt]::GetForegroundWindow() -eq $own.H -and (Text) -eq "$($before)qwe") "'$(Text)'"
  # 3. Not now: gone, and quiet for the rest of this call
  Invoke-El (PromptButton 'Not now'); Start-Sleep 1
  Check 'Not now hides the prompt' (-not (Prompt)) ''
  Check 'Not now holds for the rest of the call' ($null -eq (WaitPrompt 9)) ''
  # 4. A dictation during the call types normally, and no prompt comes back
  Set-Content "$($own.F).clear" ''; Start-Sleep 0.5
  Say 'Dictation still works during the meeting.'
  $n = (Rows).Count
  Front; try { [Mt]::Down(0x11); [Mt]::Down(0x77); Start-Sleep -Milliseconds 900 } finally { [Mt]::Up(0x77); [Mt]::Up(0x11) }
  for ($i = 0; $i -lt 240 -and (Rows).Count -eq $n; $i++) { Start-Sleep -Milliseconds 250 }; Start-Sleep 0.7
  Check 'A dictation during the call types normally' ((Text) -match 'during the meeting') "'$(Text)'"
  Check '... and brings no prompt' (-not (Prompt)) ''
  # 5. The call ends; a new one prompts again
  EndMeeting $m; Start-Sleep 2
  $m = Meeting 300
  Check 'A new call prompts again' ([bool](WaitPrompt 20)) ''
  # 6. Start transcription: the prompt goes and EsyMeet opens
  Invoke-El (PromptButton 'Start transcription'); Start-Sleep 2
  Check 'Start transcription hides the prompt' (-not (Prompt)) ''
  $root = Get-AppWindow $app.Id 'EsyType'
  $page = (Find-All $root $CT::Text | ForEach-Object { $_.Current.Name }) -join ' '
  Check '... and opens the EsyMeet page' ($page -match 'EsyMeet') ''
  try { $root.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() } catch {}   # closing hides it to the tray
  Start-Sleep 1
  # 7. An unanswered prompt fades after 30 s
  EndMeeting $m; Start-Sleep 2
  $m = Meeting 300
  $shown = WaitPrompt 20
  $t0 = Get-Date; $gone = WaitPrompt 40 $false; $lasted = ((Get-Date) - $t0).TotalSeconds
  Check 'An unanswered prompt fades after about 30 s' ($shown -and $gone -and $lasted -ge 27 -and $lasted -le 34) ("stayed {0:N1} s" -f $lasted)
  Check '... and does not come back during that call' ($null -eq (WaitPrompt 8)) ''
  # 8. A short use (a sound check, a voice search) never prompts
  EndMeeting $m; Start-Sleep 2
  $m = Meeting 3
  Check 'A 3-second use of the microphone never prompts' ($null -eq (WaitPrompt 10)) ''
  EndMeeting $m
  # 9. Detect meetings off: no prompt; back on: prompts (EsyType restarted with its window open, for Settings)
  Stop-Process -Id $app.Id -Force; Start-Sleep 1
  Launch $true $true
  $root = Get-AppWindow $app.Id 'EsyType'
  Open-Settings $root 'Meetings'
  Invoke-El (Find-El $root 'Detect meetings' $CT::Button); Start-Sleep 1
  $s = Get-Content (Join-Path $data 'settings.json') -Raw | ConvertFrom-Json
  Check 'Settings > Meetings: Detect meetings switches off and is saved' ($s.meet_detect -eq $false) ''
  $m = Meeting 300
  Check 'Detection off: no prompt' ($null -eq (WaitPrompt 10)) ''
  Invoke-El (Find-El $root 'Detect meetings' $CT::Button); Start-Sleep 1
  Close-Settings $root -Allow @($own.P.Id)
  Check 'Detection back on: the ongoing call prompts' ([bool](WaitPrompt 15)) ''
  Invoke-El (PromptButton 'Not now'); Start-Sleep 0.5
  EndMeeting $m; $m = $null
  # 10. A program not on the list never prompts
  Stop-Process -Id $app.Id -Force; Start-Sleep 1
  Launch $false
  $m = Meeting 300
  Check 'A program not on the meeting list never prompts' ($null -eq (WaitPrompt 12)) ''
} catch {
  "STOPPED: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
} finally {
  EndMeeting $m
  if ($app) { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue }
  if ($own) { Stop-Process -Id $own.P.Id -Force -ErrorAction SilentlyContinue }
  foreach ($k in 0x11, 0x77) { [Mt]::Up($k) }
  Remove-Item Env:ESYTYPE_TEST_MEET_EXE -ErrorAction SilentlyContinue
  Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue   # the meeting program's scratch audio
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'meeting-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
