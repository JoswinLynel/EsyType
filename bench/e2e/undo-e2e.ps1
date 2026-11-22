# Undo last dictation end to end, in the test's own window (a rich text box, whose Ctrl+Z removes a paste in one
# step): Undo from the pill and from the shortcut removes exactly the last dictation; refusals send nothing (typed
# since, another window in front, older than 60 s, a "copied" dictation); Restore original; Paste last; {cursor};
# the user's clipboard is kept. Test build with its own settings: Ctrl+F8 to dictate, Ctrl+F9 Undo, Ctrl+F10 Paste last.
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e"
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech, UIAutomationClient, UIAutomationTypes
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Un {
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
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-58} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

$lad = Join-Path $Work 'localappdata-undo'; $data = Join-Path $lad 'EsyAI\EsyType'
New-Item -ItemType Directory -Force $data | Out-Null; Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; undo_shortcut = 'Ctrl+F9'; paste_last_shortcut = 'Ctrl+F10'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false } |
  ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
$db = Join-Path $data 'esytype.db'; $current = Join-Path $Work 'current.f32'; $trace = Join-Path $Work 'undo-trace.txt'
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current
$userClip = Get-Clipboard -Raw

$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer; $voice.SelectVoice('Microsoft Hazel Desktop')
function Say($text) {
  $wav = Join-Path $Work 'undo-say.wav'
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
  for ($i = 0; $i -lt 40 -and $h -eq [IntPtr]::Zero; $i++) { Start-Sleep -Milliseconds 250; $h = [Un]::FindWindow([NullString]::Value, $title) }
  if ($h -eq [IntPtr]::Zero) { throw "Test window '$title' did not appear." }
  [pscustomobject]@{ P = $p; H = $h; F = $f }
}
function Text($w) { for ($i = 0; $i -lt 40; $i++) { try { return ([IO.File]::ReadAllText($w.F)) -replace "`r", '' } catch { Start-Sleep -Milliseconds 25 } } }
function Front($h) {
  for ($k = 0; $k -lt 8 -and [Un]::GetForegroundWindow() -ne $h; $k++) {
    $fg = 0; [void][Un]::GetWindowThreadProcessId([Un]::GetForegroundWindow(), [ref]$fg)
    if ($k -gt 0 -and $fg -in @($own.P.Id, $other.P.Id, $app.Id)) { [Un]::Down(0x12); [Un]::Up(0x12) }
    [Un]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400
  }
  if ([Un]::GetForegroundWindow() -ne $h) {
    $fg = 0; [void][Un]::GetWindowThreadProcessId([Un]::GetForegroundWindow(), [ref]$fg)
    throw "Test window is not in front (front: process $fg $((Get-Process -Id $fg -ErrorAction SilentlyContinue).ProcessName); wanted window $h); no keys sent."
  }
}
function Rows { $r = & python -I -c "import sqlite3,json,sys; c=sqlite3.connect(sys.argv[1]); print(json.dumps([dict(zip(('final_text','raw_text','edited_text','undone'),r)) for r in c.execute('select final_text,raw_text,edited_text,undone from transcripts order by id')]))" $db | ConvertFrom-Json; @($r | Where-Object { $_ }) }
function Dictate($w, $phrase, [scriptblock]$during) {
  Say $phrase; Front $w.H
  $n = (Rows).Count
  try { [Un]::Down(0x11); [Un]::Down(0x77); Start-Sleep -Milliseconds 900 } finally { [Un]::Up(0x77); [Un]::Up(0x11) }
  if ($during) { & $during }
  for ($i = 0; $i -lt 240 -and (Rows).Count -eq $n; $i++) { Start-Sleep -Milliseconds 250 }
  Start-Sleep -Milliseconds 500
}
function Shortcut($vk) { try { [Un]::Down(0x11); [Un]::Down($vk); Start-Sleep -Milliseconds 80 } finally { [Un]::Up($vk); [Un]::Up(0x11) }; Start-Sleep 1.5 }
function Pill { Get-TopWindows 'EsyType recording' @($app.Id) | Select-Object -First 1 }
function PillButton($name) { $p = Pill; if ($p) { Find-El $p $name $CT::Button -Tries 15 } }   # the pill's accessibility tree builds when first asked
function PillText { $p = Pill; if ($p) { for ($i = 0; $i -lt 10; $i++) { $t = (Find-All $p $CT::Text | ForEach-Object { $_.Current.Name }) -join ' '; if ($t) { return $t }; Start-Sleep -Milliseconds 200 } } }
function Mark { $script:marker = "USER-CLIPBOARD-$(Get-Random)"; Set-Clipboard -Value $script:marker }

# Seed a snippet with {cursor} (the app creates the database on first start).
$app = Start-Process $Exe -ArgumentList '--minimized' -PassThru; Start-Sleep 8; Stop-Process -Id $app.Id -Force; Start-Sleep 1
& python -I (Join-Path $PSScriptRoot 'seed-snippet.py') $db 'my sign off' 'Dear Sam,
{cursor}
Jo'

$own = Window 'esytype-undo-own'; $other = Window 'esytype-undo-other'
$app = Start-Process $Exe -ArgumentList '--minimized' -PassThru -RedirectStandardError $trace; Start-Sleep 9
try {
  # 1. Undo from the pill removes exactly the last dictation
  Dictate $own 'The first sentence stays.'
  $first = Text $own
  Mark; Dictate $own 'The second sentence goes.'
  $btn = PillButton 'Undo'
  Check 'Pill offers Undo after a dictation' ([bool]$btn) "'$(PillText)'"
  if ($btn) { Invoke-El $btn; Start-Sleep 1.5 }
  Check 'Undo (pill) removes exactly the last dictation' ((Text $own) -eq $first) "'$(Text $own)'"
  Check 'History marks it undone; clipboard kept' ((Rows)[-1].undone -eq 1 -and (Wait-Clipboard $marker)) "undone=$((Rows)[-1].undone)"

  # 2. Undo from the shortcut
  Dictate $own 'Another sentence goes too.'
  Front $own.H; Shortcut 0x78
  Check 'Undo (shortcut) removes it' ((Text $own) -eq $first) "'$(Text $own)'"

  # 3. Paste last brings it back
  Front $own.H; Shortcut 0x79
  Check 'Paste last pastes it again' ((Text $own) -match 'Another sentence goes') "'$(Text $own)'"
  Set-Content "$($own.F).clear" ''; Start-Sleep 0.5

  # 4. Refused: typed since
  Dictate $own 'This one stays put.'
  Front $own.H; [Un]::Tap(0x51); Start-Sleep 1   # the "user" types q
  $before = Text $own
  Shortcut 0x78
  Check 'Refused after typing since; nothing sent' ((Text $own) -eq $before -and (PillText) -match 'typed or clicked') "'$(PillText)'"

  # 5. Refused: another window in front
  Dictate $own 'Another one stays put.'
  $before = Text $own
  Front $other.H; Shortcut 0x78
  Check 'Refused with another window in front' ((Text $own) -eq $before -and (Text $other) -eq '' -and (PillText) -match 'window') "'$(PillText)'"

  # 6. Refused: a dictation that was copied (window changed during transcription)
  Dictate $own 'This is copied.' { Front $other.H }
  $before = Text $own
  Front $own.H; Shortcut 0x78
  Check 'Refused for a copied dictation' ((Text $own) -eq $before -and (PillText) -match 'not typed|no recent dictation') "'$(PillText)'"

  # 7. Restore original: Clean removed a filler; Use original puts back what was heard
  Set-Content "$($own.F).clear" ''; Start-Sleep 0.5
  Mark; Dictate $own 'Um, I want tea.'
  $clean = Text $own
  $use = PillButton 'Use original'
  Check 'Pill offers Use original after Clean changed the text' ([bool]$use) "'$(PillText)' (inserted '$clean')"
  if ($use) { Invoke-El $use; Start-Sleep 2.5 }
  $raw = (Rows)[-1].raw_text
  Check 'Use original replaces the text with what was heard' ((Text $own).Trim() -eq $raw.Trim() -and $raw -ne $clean.Trim()) "now '$(Text $own)', heard '$raw'"
  Check 'History shows the original; clipboard kept' ((Rows)[-1].edited_text -eq $raw -and (Wait-Clipboard $marker)) ''

  # 8. {cursor} in a snippet
  Set-Content "$($own.F).clear" ''; Start-Sleep 0.5
  Dictate $own 'My sign off.'
  Front $own.H; [Un]::Tap(0x51); Start-Sleep 0.8   # type q where the caret is
  Check '{cursor} puts the caret at the marker' ((Text $own).TrimStart() -eq "Dear Sam,`nq`nJo")   # a leading space separates consecutive dictations "'$((Text $own) -replace "`n", '\n')'"

  # 9. Refused: older than 60 seconds
  Set-Content "$($own.F).clear" ''; Start-Sleep 0.5
  Dictate $own 'This will be too old.'
  $before = Text $own
  Start-Sleep 62
  Front $own.H; Shortcut 0x78
  Check 'Refused after 60 seconds' ((Text $own) -eq $before -and (PillText) -match '60 seconds') "'$(PillText)'"
} catch {
  "STOPPED: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
} finally {
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
  foreach ($w in $own, $other) { if ($w) { Stop-Process -Id $w.P.Id -Force -ErrorAction SilentlyContinue } }
  foreach ($k in 0x11, 0x12, 0x77, 0x78, 0x79) { [Un]::Up($k) }
  if ($userClip) { Set-Clipboard -Value $userClip }
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'undo-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
