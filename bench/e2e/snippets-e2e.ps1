# Snippets end to end: the Snippets page through UI Automation (add in both modes, validation, duplicate, edit,
# search, export, delete all, import through the real file picker); spoken phrases from Windows' built-in voice go
# through the real speech engine (whole-dictation and anywhere snippets, a trigger inside a longer sentence left
# alone, Verbatim). Test build with its own settings, Ctrl+F8, its own window; exports go to a test folder.
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

$lad = Join-Path $Work 'localappdata-snip'; $data = Join-Path $lad 'EsyAI\EsyType'; $exports = Join-Path $Work 'snip-exports'
New-Item -ItemType Directory -Force $data, $exports | Out-Null
Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force; Get-ChildItem $exports | Remove-Item -Force
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false } | ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
$db = Join-Path $data 'esytype.db'; $py = Join-Path $PSScriptRoot 'history-db.py'; $current = Join-Path $Work 'current.f32'
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current; $env:ESYTYPE_EXPORT_DIR = $exports
$userClip = Get-Clipboard -Raw

$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer; $voice.SelectVoice('Microsoft Hazel Desktop')
function Say($text) {
  $wav = Join-Path $Work 'snip-say.wav'
  $fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
  $voice.SetOutputToWaveFile($wav, $fmt); $voice.Speak($text); $voice.SetOutputToNull()
  $b = [IO.File]::ReadAllBytes($wav); $at = 12; while ([Text.Encoding]::ASCII.GetString($b, $at, 4) -ne 'data') { $at += 8 + [BitConverter]::ToInt32($b, $at + 4) }
  $n = [BitConverter]::ToInt32($b, $at + 4) / 2; $f = New-Object float[] ($n + 8000)
  for ($k = 0; $k -lt $n; $k++) { $f[$k] = [BitConverter]::ToInt16($b, $at + 8 + 2 * $k) / 32768.0 }
  $o = New-Object byte[] ($f.Length * 4); [Buffer]::BlockCopy($f, 0, $o, 0, $o.Length); [IO.File]::WriteAllBytes($current, $o)
}
$tf = Join-Path $Work 'snip-target.txt'; Set-Content $tf '' -Encoding ascii
$tgt = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$tf`"", '-Kind', 'RichTextBox', '-Title', 'esytype-snip-target' -PassThru
Start-Sleep 3; $h = [D]::FindWindow([NullString]::Value, 'esytype-snip-target')
function Rows { $r = & python -I $py rows $db | ConvertFrom-Json; @($r | Where-Object { $_ }) }
function Dictate($phrase) {
  Say $phrase; Set-Content "$tf.clear" ''; Start-Sleep -Milliseconds 400
  for ($k = 0; $k -lt 8 -and [D]::GetForegroundWindow() -ne $h; $k++) {
    $fg = 0; [void][D]::GetWindowThreadProcessId([D]::GetForegroundWindow(), [ref]$fg)
    if ($k -gt 0 -and $fg -in @($tgt.Id, $app.Id)) { [D]::Down(0x12); [D]::Up(0x12) }
    [void](New-Object -ComObject WScript.Shell).AppActivate('esytype-snip-target'); [D]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400
  }
  if ([D]::GetForegroundWindow() -ne $h) { throw 'Test window is not in front; no keys sent.' }
  $n = (Rows).Count
  try { [D]::Down(0x11); [D]::Down(0x77); Start-Sleep -Milliseconds 900 } finally { [D]::Up(0x77); [D]::Up(0x11) }
  for ($i = 0; $i -lt 60 -and (Rows).Count -eq $n; $i++) { Start-Sleep -Milliseconds 250 }
  Start-Sleep -Milliseconds 400
  [pscustomobject]@{ Inserted = ([IO.File]::ReadAllText($tf)).Trim(); Row = (Rows | Select-Object -Last 1) }
}
function Entries { $r = & python -I -c "import sqlite3,json,sys; c=sqlite3.connect(sys.argv[1]); print(json.dumps([dict(zip(('trigger','body','mode','uses'),r)) for r in c.execute('select trigger,body,mode,uses from snippets order by trigger_key')]))" $db | ConvertFrom-Json; @($r | Where-Object { $_ }) }
function Btn($name, $within) { Find-El $(if ($within) { $within } else { $root }) $name $CT::Button }
function Field($name) { $f = Find-El $root $name $CT::Edit; if (-not $f) { throw "No field '$name'; fields: " + ((Find-All $root $CT::Edit | ForEach-Object { $_.Current.Name }) -join ' | ') + '; buttons: ' + ((Find-All $root $CT::Button | ForEach-Object { $_.Current.Name }) -join ' | ') }; $f }
function Items { @(Find-All $root $CT::ListItem | Where-Object { $_.Current.Name -match 'used \d+ time' }) }
function Item($text) { Items | Where-Object { $_.Current.Name -like "*$text*" } | Select-Object -First 1 }
function Status { (Find-All $root $CT::Text | Where-Object { $_.Current.Name -match '^(Added|Imported|Saved|Snippets cleared|A snippet for|A trigger used)' } | Select-Object -Last 1).Current.Name }
function AddSnippet($trigger, $body, $anywhere) {
  Set-Val (Field 'Trigger') $trigger; Set-Val (Field 'Snippet text') $body
  if ($anywhere) { Invoke-El (Find-El $root 'Anywhere*' $CT::RadioButton -Like) } else { Invoke-El (Find-El $root 'Whole dictation*' $CT::RadioButton -Like) }
  Start-Sleep 0.3; Invoke-El (Btn 'Add snippet'); Start-Sleep 1
}
$date = (Get-Date).ToString('d MMMM yyyy', [Globalization.CultureInfo]::InvariantCulture)
$sig = "Kind regards,`nJo Smith`n{date}"; $sigOut = "Kind regards,`nJo Smith`n$date"
$app = Start-Process $Exe -PassThru -RedirectStandardError (Join-Path $Work 'snip-trace.txt'); Start-Sleep 9
$root = Get-AppWindow $app.Id 'EsyType'   # the test build's window, not an installed EsyType's
try {
  # --- page --------------------------------------------------------------------------------------------------
  Invoke-El (Btn 'Snippets'); Start-Sleep 1
  AddSnippet 'my email signature' $sig $false
  AddSnippet 'meeting link' 'https://meet.example.com/jo' $true
  $e = Entries
  Check 'Add whole-dictation and anywhere snippets' ($e.Count -eq 2 -and ($e | Where-Object { $_.trigger -eq 'meeting link' }).mode -eq 'anywhere' -and ($e | Where-Object { $_.trigger -eq 'my email signature' }).body -eq $sig) "entries=$($e.Count)"
  AddSnippet 'link' 'x' $true
  Check 'One-word anywhere trigger refused' ((Entries).Count -eq 2 -and (Status) -match 'two words') "'$(Status)'"
  AddSnippet 'My Email Signature!' 'other' $false
  Check 'Duplicate trigger refused' ((Entries).Count -eq 2 -and (Status) -match 'already exists') "'$(Status)'"
  Set-Val (Field 'Search snippets') 'meet'; Start-Sleep 0.6
  Check 'Search' ((Items).Count -eq 1) "shown=$((Items).Count)"
  Set-Val (Field 'Search snippets') ''; Start-Sleep 0.6

  # --- spoken ------------------------------------------------------------------------------------------------
  $r = Dictate 'My email signature.'
  Check 'Whole dictation: signature inserted with date' (($r.Inserted -replace "`r", '') -eq $sigOut) "'$($r.Inserted -replace "`n", '\n')' (heard '$($r.Row.raw_text)')"
  Check 'History: heard and inserted text kept' ($r.Row.raw_text -match 'signature' -and $r.Row.final_text -eq $sigOut) ''
  $r = Dictate 'Please send my email signature to Sam.'
  Check 'Trigger inside a longer sentence left alone' ($r.Inserted -notmatch 'Kind regards' -and $r.Inserted -match 'signature') "'$($r.Inserted)'"
  $r = Dictate 'Please join the meeting link today.'
  Check 'Anywhere: link inserted in the sentence' ($r.Inserted -match 'https://meet\.example\.com/jo' -and $r.Inserted -match 'today') "'$($r.Inserted)' (heard '$($r.Row.raw_text)')"
  $uses = (Entries | Where-Object { $_.trigger -eq 'my email signature' }).uses
  Check 'Use counted' ($uses -ge 1) "uses=$uses"
  Invoke-El (Btn 'Dictation'); Start-Sleep 0.5
  (Find-El $root 'Verbatim*' $CT::RadioButton -Like).GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep 1
  $r = Dictate 'My email signature.'
  Check 'Verbatim: snippet still applied' (($r.Inserted -replace "`r", '') -eq $sigOut -and $r.Row.mode -eq 'verbatim') ''

  # --- edit, export, delete all, import ------------------------------------------------------------------------
  Invoke-El (Btn 'Snippets'); Start-Sleep 1
  Invoke-El (Btn 'Edit' (Item 'meeting link')); Start-Sleep 0.5
  $boxes = @(Find-All $root $CT::Edit | Where-Object { $_.Current.Name -eq 'Snippet text' })
  Set-Val $boxes[-1] 'https://meet.example.com/new'; Start-Sleep 0.3
  Invoke-El (@(Find-All $root $CT::Button | Where-Object { $_.Current.Name -eq 'Save' })[0]); Start-Sleep 1
  Check 'Edit a snippet' ((Entries | Where-Object { $_.trigger -eq 'meeting link' }).body -eq 'https://meet.example.com/new') ''
  Invoke-El (Btn 'Export CSV'); Start-Sleep 1; Invoke-El (Btn 'Export JSON'); Start-Sleep 1
  $csv = Join-Path $exports 'EsyType snippets.csv'; $json = Join-Path $exports 'EsyType snippets.json'
  Check 'Export CSV and JSON' ((Test-Path $csv) -and (Test-Path $json)) ((Get-ChildItem $exports).Name -join ', ')
  $before = (Entries).Count
  Invoke-El (Btn 'Delete all'); $msg = Answer-Dialog $root 'Delete all'; Start-Sleep 1
  Check 'Delete all asks, then empties' ((Entries).Count -eq 0 -and $msg -match 'cannot be undone') "'$msg'"
  Invoke-El (Btn 'Import'); Start-Sleep 2
  $mine = @($app.Id) + @(Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $app.Id } | ForEach-Object { [int]$_.ProcessId })
  $dlg = Find-El $root 'Open' $CT::Window
  if ($dlg) {
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
  $back = Entries
  Check 'Import restores every snippet, line breaks intact' ($back.Count -eq $before -and ($back | Where-Object { $_.trigger -eq 'my email signature' }).body -eq $sig) "'$(Status)'"
} catch {
  "STOPPED: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
} finally {
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue; Stop-Process -Id $tgt.Id -Force -ErrorAction SilentlyContinue
  [D]::Up(0x77); [D]::Up(0x11); [D]::Up(0x12)
  if ($userClip) { Set-Clipboard -Value $userClip }
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'snippets-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
