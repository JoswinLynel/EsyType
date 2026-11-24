# Clean mode end to end: phrases are spoken by Windows' built-in text-to-speech (no download), recognised by the
# real speech engine in the e2e test build, cleaned and inserted into the test's own window. Checks the inserted
# text, History (mode, original and final text), the pill's Original button and the Verbatim switch in the window.
# Uses its own settings and Ctrl+F8; types only into its own window; your clipboard text is put back.
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e"
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech, UIAutomationClient, UIAutomationTypes
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class C {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-58} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

$lad = Join-Path $Work 'localappdata-clean'; $data = Join-Path $lad 'EsyAI\EsyType'
New-Item -ItemType Directory -Force $data | Out-Null; Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force
$settingsFile = Join-Path $data 'settings.json'
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false } | ConvertTo-Json | Set-Content $settingsFile -Encoding ascii
$db = Join-Path $data 'esytype.db'; $py = Join-Path $PSScriptRoot 'history-db.py'; $current = Join-Path $Work 'current.f32'
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current
$userClip = Get-Clipboard -Raw

# Speech: Windows text-to-speech at 16 kHz mono, converted to raw 32-bit float for the test build.
$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer
try { $voice.SelectVoice('Microsoft Hazel Desktop') } catch {}
function Say($text) {
  $wav = Join-Path $Work 'clean-say.wav'
  $fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
  $voice.SetOutputToWaveFile($wav, $fmt); $voice.Speak($text); $voice.SetOutputToNull()
  $b = [IO.File]::ReadAllBytes($wav)
  $at = 12; while ([Text.Encoding]::ASCII.GetString($b, $at, 4) -ne 'data') { $at += 8 + [BitConverter]::ToInt32($b, $at + 4) }
  $n = [BitConverter]::ToInt32($b, $at + 4) / 2; $f = New-Object float[] ($n + 8000)   # half a second of silence after
  for ($k = 0; $k -lt $n; $k++) { $f[$k] = [BitConverter]::ToInt16($b, $at + 8 + 2 * $k) / 32768.0 }
  $out = New-Object byte[] ($f.Length * 4); [Buffer]::BlockCopy($f, 0, $out, 0, $out.Length); [IO.File]::WriteAllBytes($current, $out)
}

$tf = Join-Path $Work 'clean-target.txt'; Set-Content $tf '' -Encoding ascii
$tgt = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$tf`"", '-Kind', 'RichTextBox', '-Title', 'esytype-clean-target' -PassThru
Start-Sleep 3; $h = [C]::FindWindow([NullString]::Value, 'esytype-clean-target')
function Text { for ($i = 0; $i -lt 40; $i++) { try { return [IO.File]::ReadAllText($tf) } catch { Start-Sleep -Milliseconds 25 } } }
function Rows { $r = & python -I $py rows $db | ConvertFrom-Json; @($r | Where-Object { $_ }) }
function Dictate($phrase) {
  Say $phrase
  Set-Content "$tf.clear" '' ; Start-Sleep -Milliseconds 400   # the test window empties itself
  for ($k = 0; $k -lt 8 -and [C]::GetForegroundWindow() -ne $h; $k++) {
    $fgPid = 0; [void][C]::GetWindowThreadProcessId([C]::GetForegroundWindow(), [ref]$fgPid)
    if ($k -gt 0 -and $fgPid -in @($tgt.Id, $app.Id)) { [C]::Down(0x12); [C]::Up(0x12) }
    [void](New-Object -ComObject WScript.Shell).AppActivate('esytype-clean-target'); [C]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400
  }
  if ([C]::GetForegroundWindow() -ne $h) { throw 'Test window is not in front; no keys sent.' }
  $n = (Rows).Count
  try { [C]::Down(0x11); [C]::Down(0x77); Start-Sleep -Milliseconds 900 } finally { [C]::Up(0x77); [C]::Up(0x11) }
  for ($i = 0; $i -lt 60 -and (Rows).Count -eq $n; $i++) { Start-Sleep -Milliseconds 250 }
  Start-Sleep -Milliseconds 400
  [pscustomobject]@{ Inserted = (Text).Trim(); Row = (Rows | Select-Object -Last 1) }
}
function Pill { Get-TopWindows 'EsyType recording' @($app.Id) | Select-Object -First 1 }

$app = Start-Process $Exe -PassThru -RedirectStandardError (Join-Path $Work 'clean-trace.txt'); Start-Sleep 9
try {
  # 1. Scratch that
  $r = Dictate 'I want tea. Scratch that. I want coffee.'
  Check 'Scratch that: earlier sentence and command removed' ($r.Inserted -match 'coffee' -and $r.Inserted -notmatch 'tea|scratch') "'$($r.Inserted)' (heard: '$($r.Row.raw_text)')"
  Check 'History: mode clean, original kept, final = inserted' ($r.Row.mode -eq 'clean' -and $r.Row.raw_text -match 'scratch' -and $r.Row.final_text -eq $r.Inserted) "final='$($r.Row.final_text)'"
  # With Undo on (the default) the pill offers "Use original", which swaps the text in place; the clipboard stays.
  $p = Pill; $orig = if ($p) { Find-El $p 'Use original' $CT::Button }
  Check 'Pill offers Use original' ([bool]$orig) ''
  $clip = "USER-CLIPBOARD-$(Get-Random)"; Set-Clipboard -Value $clip   # copied now, during EsyType's hold: it must stay
  if ($orig) { Invoke-El $orig; Start-Sleep 2 }
  Check 'Use original puts back what was heard; clipboard kept' ((Text).Trim() -eq $r.Row.raw_text.Trim() -and (Wait-Clipboard $clip)) "'$((Text).Trim())'"

  # 2. Fillers and numbers
  $r = Dictate 'Um, the ticket costs twenty five pounds, and prices rose ten percent.'
  Check 'Numbers: money and percent as digits' ($r.Inserted.Contains([string][char]0xA3 + '25') -and $r.Inserted -match '10%')   # [char]0xA3 is the pound sign: Windows PowerShell misreads it in a UTF-8 script "'$($r.Inserted)' (heard: '$($r.Row.raw_text)')"
  Check 'Filler removed' ($r.Inserted -notmatch '\b[Uu]m\b') ''
  $r = Dictate 'We meet at three thirty pm on the fifth of March, with three guests.'
  Check 'Time, date, small count' ($r.Inserted -match '3[:.]30' -and $r.Inserted -match '5 March' -and $r.Inserted -match 'three guests') "'$($r.Inserted)' (heard: '$($r.Row.raw_text)')"

  # 3. New paragraph
  $r = Dictate 'Dear Sam. New paragraph. Thanks for the call.'
  Check 'New paragraph becomes a blank line' ($r.Row.final_text -match "Sam\.\n\nThanks" -and ($r.Inserted -replace "`r", '') -match "Sam\.\n\nThanks") "final='$($r.Row.final_text -replace "`n", '\n')'"

  # 4. Verbatim, switched in the window
  $root = Get-AppWindow $app.Id 'EsyType'   # the test build's window, not an installed EsyType's
  Invoke-El (Find-El $root 'Style' $CT::Button); Start-Sleep 1   # Clean or Verbatim is on the Style page since the Mac design
  $radio = Find-El $root 'Verbatim*' $CT::RadioButton -Like
  if ($radio) { $radio.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep 1 }
  Check 'Window switch saves Verbatim' ((Get-Content $settingsFile -Raw | ConvertFrom-Json).text_mode -eq 'verbatim') ''
  $r = Dictate 'I want tea. Scratch that. I want coffee.'
  Check 'Verbatim inserts exactly what was heard' ($r.Inserted -eq $r.Row.raw_text -and $r.Row.mode -eq 'verbatim' -and $r.Inserted -match 'tea') "'$($r.Inserted)'"
} finally {
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue; Stop-Process -Id $tgt.Id -Force -ErrorAction SilentlyContinue
  [C]::Up(0x77); [C]::Up(0x11); [C]::Up(0x12)
  if ($userClip) { Set-Clipboard -Value $userClip }
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'clean-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
