# Scratchpad end to end, in the test build's own window: write a note (autosave), dictate into it (Clean and a
# snippet apply, clipboard untouched), Undo the dictation, restart (the note is still there), export .txt and .md,
# delete with confirmation, delete all, and a broken database (warning, writing still possible).
# Test build with its own settings: Ctrl+F8 dictate, Ctrl+F9 Undo. Exports go to a test folder.
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio"
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type -AssemblyName System.Speech
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Sp {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-58} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

$lad = Join-Path $Work 'localappdata-pad'; $data = Join-Path $lad 'EsyAI\EsyType'; $exports = Join-Path $Work 'pad-exports'
New-Item -ItemType Directory -Force $data, $exports | Out-Null
Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force; Get-ChildItem $exports | Remove-Item -Force
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; undo_shortcut = 'Ctrl+F9'; paste_last_shortcut = 'Ctrl+F10'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false } |
  ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
$db = Join-Path $data 'esytype.db'; $current = Join-Path $Work 'current.f32'; $trace = Join-Path $Work 'pad-trace.txt'
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current; $env:ESYTYPE_EXPORT_DIR = $exports
$userClip = Get-Clipboard -Raw; $marker = "USER-CLIPBOARD-$(Get-Random)"; Set-Clipboard -Value $marker

$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer; $voice.SelectVoice('Microsoft Hazel Desktop')
function Say($text) {
  $wav = Join-Path $Work 'pad-say.wav'
  $fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
  $voice.SetOutputToWaveFile($wav, $fmt); $voice.Speak($text); $voice.SetOutputToNull()
  $b = [IO.File]::ReadAllBytes($wav); $at = 12; while ([Text.Encoding]::ASCII.GetString($b, $at, 4) -ne 'data') { $at += 8 + [BitConverter]::ToInt32($b, $at + 4) }
  $n = [BitConverter]::ToInt32($b, $at + 4) / 2; $f = New-Object float[] ($n + 8000)
  for ($k = 0; $k -lt $n; $k++) { $f[$k] = [BitConverter]::ToInt16($b, $at + 8 + 2 * $k) / 32768.0 }
  $o = New-Object byte[] ($f.Length * 4); [Buffer]::BlockCopy($f, 0, $o, 0, $o.Length); [IO.File]::WriteAllBytes($current, $o)
}
function Notes { $r = & python -I -c "import sqlite3,json,sys; c=sqlite3.connect(sys.argv[1]); print(json.dumps([r[0] for r in c.execute('select body from scratchpad_notes order by updated_at desc')]))" $db | ConvertFrom-Json; ,@($r | Where-Object { $_ -ne $null }) }   # always a list, even of one
function Launch {
  $script:app = Start-Process $Exe -PassThru -RedirectStandardError $trace; Start-Sleep 9
  $script:root = Get-AppWindow $app.Id 'EsyType'; $script:h = [IntPtr]$root.Current.NativeWindowHandle
  Invoke-El (Find-El $root 'Scratchpad' $CT::Button); Start-Sleep 1
}
function Box { Find-El $root 'Note' $CT::Edit }
function BoxText { ([string](Box).GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value) -replace "`r", '' }
function Front {
  for ($k = 0; $k -lt 6 -and [Sp]::GetForegroundWindow() -ne $h; $k++) { [Sp]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400 }
  if ([Sp]::GetForegroundWindow() -ne $h) { throw 'The test build window is not in front; no keys sent.' }
}
function Keys($vk) { try { [Sp]::Down(0x11); [Sp]::Down($vk); Start-Sleep -Milliseconds 80 } finally { [Sp]::Up($vk); [Sp]::Up(0x11) } }
function Dictate($phrase) {
  Say $phrase; Front; (Box).SetFocus(); Start-Sleep 0.4
  $before = BoxText
  try { [Sp]::Down(0x11); [Sp]::Down(0x77); Start-Sleep -Milliseconds 900 } finally { [Sp]::Up(0x77); [Sp]::Up(0x11) }
  WaitChange $before
}
# Waits (up to 20 s) for the note's text to change, then for autosave.
function WaitChange($before) { for ($i = 0; $i -lt 240 -and (BoxText) -eq $before; $i++) { Start-Sleep -Milliseconds 250 }; Start-Sleep 1.5 }

try {
  Launch
  # 1. Write a note: autosaved
  Set-Val (Box) 'Shopping list'; Start-Sleep 1.5
  Check 'Typed note autosaved' ((Notes)[0] -eq 'Shopping list') "db: '$((Notes)[0])'"

  # 2. Dictate into it: inserted at the cursor, cleaned, saved; clipboard untouched
  Dictate 'Um, we need milk and twenty five pounds of flour.'
  $t = BoxText
  Check 'Dictation goes into the note, cleaned' ($t -match '^Shopping list' -and $t -match 'milk' -and $t -match '25' -and $t -notmatch '\bUm\b') "'$t'"
  Check 'One space between the typed text and the dictation' ($t -match '^Shopping list [A-Z]') "'$t'"
  Start-Sleep 1
  Check 'Dictated note autosaved; clipboard untouched' ((Notes)[0] -eq $t -and (Wait-Clipboard $marker)) ''

  # 3. EsyType's Undo removes the dictation from the note
  $before = BoxText; Front; Keys 0x78; WaitChange $before
  Check 'Undo removes the dictation from the note' ((BoxText).Trim() -eq 'Shopping list') "'$(BoxText)'"
  Start-Sleep 1
  Check 'Undone text autosaved' ((Notes)[0].Trim() -eq 'Shopping list') ''

  # 4. Restart: the note is still there (with a snippet added while closed)
  Stop-Process -Id $app.Id -Force; Start-Sleep 2
  & python -I (Join-Path $PSScriptRoot 'seed-snippet.py') $db 'my address' '1 High Street\nLondon'
  Launch
  $item = Find-El $root 'Shopping list*' $CT::Button -Like -Tries 15
  Check 'Note listed after a restart' ([bool]$item) ''
  if ($item) { Invoke-El $item; Start-Sleep 1 }
  Check 'Note opens with its text' ((BoxText).Trim() -eq 'Shopping list') "'$(BoxText)'"

  # 5. A snippet into a new note
  Invoke-El (Find-El $root 'New note' $CT::Button); Start-Sleep 0.5
  Dictate 'My address.'
  Start-Sleep 1
  Check 'Snippet text goes into a new note and is saved' ((BoxText).Trim() -eq "1 High Street`nLondon" -and (Notes).Count -eq 2) "'$((BoxText) -replace "`n", '\n')'"

  # 6. Export
  Invoke-El (Find-El $root 'Export .txt' $CT::Button); Start-Sleep 1; Invoke-El (Find-El $root 'Export .md' $CT::Button); Start-Sleep 1
  $files = @(Get-ChildItem $exports)
  Check 'Export .txt and .md' ($files.Count -eq 2 -and ($files | Where-Object Extension -eq '.md') -and (Get-Content ($files | Where-Object Extension -eq '.txt').FullName -Raw) -match 'High Street') (($files.Name) -join ', ')

  # 7. Delete asks first; Cancel keeps, OK removes; Delete all
  Invoke-El (Find-El $root 'Delete' $CT::Button); $m = Answer-Dialog $root 'Cancel'; Start-Sleep 0.8
  Check 'Delete asks; Cancel keeps the note' ((Notes).Count -eq 2 -and $m -match 'cannot be undone') "'$m'"
  Invoke-El (Find-El $root 'Delete' $CT::Button); [void](Answer-Dialog $root 'Delete'); Start-Sleep 1
  Check 'Delete with OK removes it' ((Notes).Count -eq 1) "notes=$((Notes).Count)"
  Invoke-El (Find-El $root 'Delete all notes' $CT::Button); $m = Answer-Dialog $root 'Delete all notes'; Start-Sleep 1
  Check 'Delete all asks, then removes every note' ((Notes).Count -eq 0 -and $m -match 'cannot be undone') "'$m'"
  Stop-Process -Id $app.Id -Force; Start-Sleep 2

  # 8. Broken database: warning, writing still possible
  Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force
  [IO.File]::WriteAllBytes($db, [byte[]](1..4096 | ForEach-Object { $_ % 251 }))
  Launch
  Check 'Broken database: the page says notes cannot be saved' ([bool](Find-El $root 'Notes cannot be saved*' $CT::Text -Like)) ''
  Set-Val (Box) 'Still writable'; Start-Sleep 1
  Check 'Broken database: text stays in the window' ((BoxText) -eq 'Still writable') ''
} catch {
  "STOPPED: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
} finally {
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
  foreach ($k in 0x11, 0x77, 0x78) { [Sp]::Up($k) }
  if ($userClip) { Set-Clipboard -Value $userClip }
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'scratchpad-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
