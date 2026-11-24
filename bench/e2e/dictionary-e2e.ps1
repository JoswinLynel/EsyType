# Dictionary end to end: the Dictionary page is driven through UI Automation (add, duplicate, edit, delete, search,
# export, import through the real file picker, delete all), spoken phrases from Windows' built-in voice go through
# the real speech engine (correction, exact spelling, Clean and Verbatim), and a History edit offers "Add to
# dictionary". Test build with its own settings, Ctrl+F8, its own window; exports go to a test folder.
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e"
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech, UIAutomationClient, UIAutomationTypes
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class D {
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

$lad = Join-Path $Work 'localappdata-dict'; $data = Join-Path $lad 'EsyAI\EsyType'; $exports = Join-Path $Work 'dict-exports'
New-Item -ItemType Directory -Force $data, $exports | Out-Null
Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force; Get-ChildItem $exports | Remove-Item -Force
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false } | ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
$db = Join-Path $data 'esytype.db'; $py = Join-Path $PSScriptRoot 'history-db.py'; $current = Join-Path $Work 'current.f32'
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current; $env:ESYTYPE_EXPORT_DIR = $exports
$userClip = Get-Clipboard -Raw

$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer; $voice.SelectVoice('Microsoft Hazel Desktop')
function Say($text) {
  $wav = Join-Path $Work 'dict-say.wav'
  $fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
  $voice.SetOutputToWaveFile($wav, $fmt); $voice.Speak($text); $voice.SetOutputToNull()
  $b = [IO.File]::ReadAllBytes($wav); $at = 12; while ([Text.Encoding]::ASCII.GetString($b, $at, 4) -ne 'data') { $at += 8 + [BitConverter]::ToInt32($b, $at + 4) }
  $n = [BitConverter]::ToInt32($b, $at + 4) / 2; $f = New-Object float[] ($n + 8000)
  for ($k = 0; $k -lt $n; $k++) { $f[$k] = [BitConverter]::ToInt16($b, $at + 8 + 2 * $k) / 32768.0 }
  $o = New-Object byte[] ($f.Length * 4); [Buffer]::BlockCopy($f, 0, $o, 0, $o.Length); [IO.File]::WriteAllBytes($current, $o)
}
$tf = Join-Path $Work 'dict-target.txt'; Set-Content $tf '' -Encoding ascii
$tgt = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$tf`"", '-Kind', 'RichTextBox', '-Title', 'esytype-dict-target' -PassThru
Start-Sleep 3; $h = [D]::FindWindow([NullString]::Value, 'esytype-dict-target')
function Rows { $r = & python -I $py rows $db | ConvertFrom-Json; @($r | Where-Object { $_ }) }
function Dictate($phrase) {
  Say $phrase; Set-Content "$tf.clear" ''; Start-Sleep -Milliseconds 400
  for ($k = 0; $k -lt 8 -and [D]::GetForegroundWindow() -ne $h; $k++) {
    $fg = 0; [void][D]::GetWindowThreadProcessId([D]::GetForegroundWindow(), [ref]$fg)
    if ($k -gt 0 -and $fg -in @($tgt.Id, $app.Id)) { [D]::Down(0x12); [D]::Up(0x12) }
    [void](New-Object -ComObject WScript.Shell).AppActivate('esytype-dict-target'); [D]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400
  }
  if ([D]::GetForegroundWindow() -ne $h) { throw 'Test window is not in front; no keys sent.' }
  $n = (Rows).Count
  try { [D]::Down(0x11); [D]::Down(0x77); Start-Sleep -Milliseconds 900 } finally { [D]::Up(0x77); [D]::Up(0x11) }
  for ($i = 0; $i -lt 60 -and (Rows).Count -eq $n; $i++) { Start-Sleep -Milliseconds 250 }
  Start-Sleep -Milliseconds 400
  [pscustomobject]@{ Inserted = ([IO.File]::ReadAllText($tf)).Trim(); Row = (Rows | Select-Object -Last 1) }
}
function Entries { $r = & python -I -c "import sqlite3,json,sys; c=sqlite3.connect(sys.argv[1]); print(json.dumps([dict(zip(('kind','term','replacement','uses'),r)) for r in c.execute('select kind,term,replacement,uses from dictionary order by term_key')]))" $db | ConvertFrom-Json; @($r | Where-Object { $_ }) }
function Btn($name, $within) { Find-El $(if ($within) { $within } else { $root }) $name $CT::Button }
function Field($name) { $f = Find-El $root $name $CT::Edit; if (-not $f) { throw "No field '$name'; fields: " + ((Find-All $root $CT::Edit | ForEach-Object { $_.Current.Name }) -join ' | ') + '; buttons: ' + ((Find-All $root $CT::Button | ForEach-Object { $_.Current.Name }) -join ' | ') }; $f }
function Items { @(Find-All $root $CT::ListItem | Where-Object { $_.Current.Name -match 'used \d+ time' }) }
function Item($text) { Items | Where-Object { $_.Current.Name -like "*$text*" } | Select-Object -First 1 }
function Status { (Find-All $root $CT::Text | Where-Object { $_.Current.Name -match '^(Added|Imported|Saved|Dictionary cleared|.*already in the dictionary)' } | Select-Object -Last 1).Current.Name }

$app = Start-Process $Exe -PassThru -RedirectStandardError (Join-Path $Work 'dict-trace.txt'); Start-Sleep 9
$root = Get-AppWindow $app.Id 'EsyType'   # the test build's window, not an installed EsyType's
try {
  # --- page: add, duplicate, edit, search, delete -----------------------------------------------------------
  Invoke-El (Btn 'Dictionary'); Start-Sleep 1
  Set-Val (Field 'Word or name, spelled as you want it') 'PostgreSQL'; Start-Sleep 0.3; Invoke-El (Btn 'Add'); Start-Sleep 1
  Invoke-El (Btn 'Correction'); Start-Sleep 0.5
  Set-Val (Field 'When I say') 'Tori'; Set-Val (Field 'Write') 'Tauri'; Start-Sleep 0.3; Invoke-El (Btn 'Add'); Start-Sleep 1
  Set-Val (Field 'When I say') 'superbase'; Set-Val (Field 'Write') 'Supabase'; Start-Sleep 0.3; Invoke-El (Btn 'Add'); Start-Sleep 1
  $e = Entries
  Check 'Add word and corrections' ($e.Count -eq 3 -and ($e | Where-Object { $_.term -eq 'Tori' }).replacement -eq 'Tauri' -and (Items).Count -eq 3) "entries=$($e.Count) shown=$((Items).Count)"
  Set-Val (Field 'When I say') 'TORI'; Set-Val (Field 'Write') 'Something'; Start-Sleep 0.3; Invoke-El (Btn 'Add'); Start-Sleep 1
  Check 'Duplicate blocked with a message' ((Entries).Count -eq 3 -and (Status) -match 'already') "'$(Status)'"
  Invoke-El (Btn 'Edit' (Item 'superbase')); Start-Sleep 0.5
  $row = Item 'superbase'; if (-not $row) { $row = $root }
  Set-Val (Find-El $root 'Write' $CT::Edit) 'Supabase' # unchanged write, change the heard form
  $heard = @(Find-All $root $CT::Edit | Where-Object { $_.Current.Name -eq 'When I say' })[-1]; Set-Val $heard 'super base'; Start-Sleep 0.3
  Invoke-El (@(Find-All $root $CT::Button | Where-Object { $_.Current.Name -eq 'Save' })[0]); Start-Sleep 1
  Check 'Edit an entry' ((Entries).term -contains 'super base' -and -not ((Entries).term -contains 'superbase')) (((Entries).term) -join ', ')
  Set-Val (Field 'Search dictionary') 'tau'; Start-Sleep 0.6
  Check 'Search' ((Items).Count -eq 1 -and (Item 'Tauri')) "shown=$((Items).Count)"
  Set-Val (Field 'Search dictionary') ''; Start-Sleep 0.6

  # --- spoken: correction and spelling in Clean, then Verbatim -------------------------------------------
  $r = Dictate 'The app is built with Tauri and Rust. Our database runs on PostgreSQL.'
  Check 'Clean: correction applied (heard Tori)' ($r.Inserted -match '\bTauri\b' -and $r.Inserted -notmatch '\bTori\b') "'$($r.Inserted)' (heard '$($r.Row.raw_text)')"
  Check 'Clean: word spelled exactly' ($r.Inserted -cmatch 'PostgreSQL') ''
  $uses = (Entries | Where-Object { $_.term -eq 'Tori' }).uses
  Check 'Use counted' ($uses -ge 1) "uses=$uses"
  Invoke-El (Btn 'Style'); Start-Sleep 1   # Clean or Verbatim is on the Style page since the Mac design
  (Find-El $root 'Verbatim*' $CT::RadioButton -Like).GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep 1
  $r = Dictate 'The app is built with Tauri and Rust.'
  Check 'Verbatim: dictionary still applied' ($r.Inserted -match '\bTauri\b' -and $r.Row.mode -eq 'verbatim') "'$($r.Inserted)'"

  # --- learn from a History edit -------------------------------------------------------------------------
  $r = Dictate 'Mrs Nguyen asked about the invoice.'
  Invoke-El (Btn 'History'); Start-Sleep 1.5
  $item = @(Find-All $root $CT::ListItem | Where-Object { $_.Current.Name -match 'invoice' })[0]
  Invoke-El (Btn 'Edit' $item); Start-Sleep 0.5
  $heardName = ($r.Inserted -split ' ')[1]
  Set-Val (Find-El $root 'Edit dictation' $CT::Edit) ($r.Inserted -replace [regex]::Escape($heardName), 'Nguyenova'); Start-Sleep 0.3
  Invoke-El (Btn 'Save'); Start-Sleep 1
  $offer = Find-El $root 'Add' $CT::Button
  Check 'History edit offers a correction' ([bool]$offer) "heard '$heardName' -> 'Nguyenova'"
  if ($offer) { Invoke-El $offer; Start-Sleep 1 }
  Check 'Offer adds it to the dictionary' ((Entries | Where-Object { $_.replacement -eq 'Nguyenova' }).term -eq $heardName) ''

  # --- export, delete all, import through the file picker -------------------------------------------------
  Invoke-El (Btn 'Dictionary'); Start-Sleep 1
  Invoke-El (Btn 'Export CSV'); Start-Sleep 1; Invoke-El (Btn 'Export JSON'); Start-Sleep 1
  $csv = Join-Path $exports 'EsyType dictionary.csv'; $json = Join-Path $exports 'EsyType dictionary.json'
  Check 'Export CSV and JSON' ((Test-Path $csv) -and (Test-Path $json) -and (Get-Content $csv -Raw) -match 'correction,Tori,Tauri') ((Get-ChildItem $exports).Name -join ', ')
  $before = (Entries).Count
  Invoke-El (Btn 'Delete all'); $msg = Answer-Dialog $root 'Delete all *' -Like; Start-Sleep 1   # the button names the count
  Check 'Delete all asks, then empties the dictionary' ((Entries).Count -eq 0 -and $msg -match 'can.t be undone') "'$msg'"
  Check 'Exports hold only your own entries (no built-in names)' ((Get-Content $csv -Raw) -notmatch 'ChatGPT|Supabase,|GitHub') ''

  # --- built-in product names (Verbatim is still on): kept apart from the dictionary, switchable -----------------
  Check 'Built-in list shown on the page' ([bool](Find-El $root 'Show the list (*names)' $null -Like)) ''
  $r = Dictate "I'm using ChatGPT to transcribe certain things."
  Check 'Built-in: corrected after Delete all; History keeps what was heard' ($r.Inserted -cmatch '\bChatGPT\b' -and $r.Row.raw_text -cnotmatch 'ChatGPT') "'$($r.Inserted)' (heard '$($r.Row.raw_text)')"
  Invoke-El (Find-El $root 'Correct common product names' -Tries 10); Start-Sleep 1.5
  $saved = (Get-Content (Join-Path $data 'settings.json') -Raw | ConvertFrom-Json).builtin_vocabulary
  $r = Dictate "I'm using ChatGPT to transcribe certain things."
  Check 'Built-in switched off: saved, and no longer corrects' ($saved -eq $false -and $r.Inserted -cnotmatch '\bChatGPT\b') "setting $saved; '$($r.Inserted)'"
  Invoke-El (Find-El $root 'Correct common product names' -Tries 10); Start-Sleep 1.5
  Check 'Built-in switched back on' ((Get-Content (Join-Path $data 'settings.json') -Raw | ConvertFrom-Json).builtin_vocabulary -eq $true) ''
  Invoke-El (Btn 'Import'); Start-Sleep 2
  # The picker belongs to the test build or its WebView2 helper processes; never to another program.
  $mine = @($app.Id) + @(Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $app.Id } | ForEach-Object { [int]$_.ProcessId })
  $dlg = Find-El $root 'Open' $CT::Window
  if (-not $dlg) { $dlg = Get-TopWindows 'Open' $mine | Select-Object -First 1 }
  if ($dlg) {
    # Windows' picker exposes its controls only as unlabelled panes, but opens with the file-name box focused:
    # type the full path and press Enter, only while the focused window belongs to the test build.
    Add-Type -AssemblyName System.Windows.Forms
    $dh = [IntPtr]$dlg.Current.NativeWindowHandle
    for ($k = 0; $k -lt 8 -and [D]::GetForegroundWindow() -ne $dh; $k++) {
      $fg = 0; [void][D]::GetWindowThreadProcessId([D]::GetForegroundWindow(), [ref]$fg)
      if ($fg -in ($mine + $tgt.Id)) { [D]::Down(0x12); [D]::Up(0x12) }   # only while a test window is in front
      [D]::SetForegroundWindow($dh) | Out-Null; Start-Sleep -Milliseconds 400
    }
    if ([D]::GetForegroundWindow() -ne $dh) { throw 'The file picker is not in front; nothing typed.' }
    [System.Windows.Forms.SendKeys]::SendWait($csv); Start-Sleep 0.3; [System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep 2
  }
  $preview = Answer-Dialog $root 'Import'; Start-Sleep 1.5   # the preview: nothing changes until Import
  Check 'Import restores every entry' ((Entries).Count -eq $before -and (Status) -match "Imported $before") "'$(Status)'"
} catch {
  "STOPPED: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
} finally {
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue; Stop-Process -Id $tgt.Id -Force -ErrorAction SilentlyContinue
  [D]::Up(0x77); [D]::Up(0x11); [D]::Up(0x12)
  if ($userClip) { Set-Clipboard -Value $userClip }
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'dictionary-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
