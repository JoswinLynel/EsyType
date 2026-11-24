# Settings and data management end to end (Phase 5, Milestone 3), in the test build with its own profile; exports
# and backups go to the test's own folder, never your Downloads. Covers: History export (all and searched, CSV and
# JSON); the Data and privacy section (sizes, moved History switches, internet use); settings export and import (the
# change list, this PC's microphone kept, unreadable and unknown values named); backup; Delete all EsyType data
# (models kept); restore (counts shown, everything back, dictation uses the restored Dictionary); Undo restore; a
# damaged and a newer backup refused with nothing changed; a forced failure mid-restore puts the data back; Delete all
# with the models (in a copied model folder) opens the first-run wizard. Files are chosen in Windows' own file picker,
# typed into only while that picker (opened by the test build) is in front.
param([string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe", [string]$Work = "D:\AI Projects\Tools\e2e",
      [string]$Audio = "D:\AI Projects\Tools\bench\audio")
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Dm {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
  public static void Down(byte v) { keybd_event(v, (byte)MapVirtualKey(v, 0), 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, (byte)MapVirtualKey(v, 0), 2, UIntPtr.Zero); }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-62} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

$lad = Join-Path $Work 'localappdata-data'; $data = Join-Path $lad 'EsyAI\EsyType'; $db = Join-Path $data 'esytype.db'
$exports = Join-Path $Work 'data-exports'; $py = Join-Path $PSScriptRoot 'data-seed.py'
$current = Join-Path $Work 'current.f32'; Copy-Item (Join-Path $Audio '6930_5s.f32') $current -Force
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current; $env:ESYTYPE_EXPORT_DIR = $exports
$userClip = Get-Clipboard -Raw
$app = $null

function Launch { $script:app = Start-Process $Exe -PassThru -RedirectStandardError (Join-Path $Work 'data-trace.txt'); Start-Sleep 9; $script:root = Get-AppWindow $app.Id 'EsyType'; $script:h = [IntPtr]$root.Current.NativeWindowHandle }
function Quit { if ($app) { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue; Start-Sleep 2 } }
function Settings { Get-Content (Join-Path $data 'settings.json') -Raw | ConvertFrom-Json }
function Counts { $c = & python -I $py counts $db | ConvertFrom-Json; "$($c.transcripts)/$($c.dictionary)/$($c.snippets)/$($c.scratchpad_notes)" }
function Texts { (Find-All $root $CT::Text | ForEach-Object { $_.Current.Name }) -join ' ' }
function Has([string]$pattern, [int]$Seconds = 5) { for ($i = 0; $i -lt $Seconds * 4; $i++) { if ((Texts) -match $pattern) { return $true }; Start-Sleep -Milliseconds 250 }; $false }
function Click([string]$name) { Invoke-El (Find-El $root $name $CT::Button -Like); Start-Sleep -Milliseconds 800 }   # -Like: names may end in an ellipsis
function Page([string]$name) { if ($name -eq 'Settings') { Open-Settings $root 'History & Privacy'; Start-Sleep 0.4; return }; Close-Settings $root; Invoke-El (Find-El $root $name $CT::Button); Start-Sleep 1.2 }
function Newest([string]$filter) { Get-ChildItem $exports -Filter $filter | Sort-Object LastWriteTime | Select-Object -Last 1 }
# The dialog's text (title, body and list), then presses $button.
function Dialog([string]$button) {
  for ($i = 0; $i -lt 40; $i++) {
    $b = Find-El $root $button $CT::Button -Tries 1
    if ($b) { $t = (@(Find-All $root $CT::Text) + @(Find-All $root $CT::ListItem) | ForEach-Object { $_.Current.Name }) -join ' '; Invoke-El $b; Start-Sleep 1.5; return $t }   # list lines are list items
    Start-Sleep -Milliseconds 150
  }
  throw "no dialog with a '$button' button"
}
# Chooses $path in Windows' file picker, opened by the test build's window.
function Pick([string]$path) {
  $dlg = $null; for ($i = 0; $i -lt 20 -and -not $dlg; $i++) { $dlg = Find-El $root 'Open' $CT::Window -Tries 1; Start-Sleep -Milliseconds 250 }
  if (-not $dlg) { throw 'The file picker did not open.' }
  $dh = [IntPtr]$dlg.Current.NativeWindowHandle
  for ($k = 0; $k -lt 8 -and [Dm]::GetForegroundWindow() -ne $dh; $k++) { [Dm]::SetForegroundWindow($dh) | Out-Null; Start-Sleep -Milliseconds 400 }
  if ([Dm]::GetForegroundWindow() -ne $dh) { throw 'The file picker is not in front; nothing typed.' }
  [System.Windows.Forms.SendKeys]::SendWait(($path -replace '[+^%~(){}]', '{$0}')); Start-Sleep 0.3; [System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep 2
}
function Fresh([string]$modelsDir) {
  if (Test-Path $lad) { Remove-Item $lad -Recurse -Force }
  New-Item -ItemType Directory -Force $data | Out-Null
  [ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; undo_shortcut = 'Ctrl+F9'; paste_last_shortcut = 'Ctrl+F10'; models_dir = $modelsDir; start_with_windows = $false; setup_done = $true; mic = 'Desk microphone' } |
    ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
}

try {
  if (Test-Path $exports) { Remove-Item $exports -Recurse -Force }; New-Item -ItemType Directory -Force $exports | Out-Null
  Fresh (Join-Path $Work 'restart-models')
  Launch; Quit                                  # creates the database
  & python -I $py seed $db
  Launch
  # ---- History export ----
  Page 'History'
  Click 'Export CSV'; Click 'Export JSON'
  $csv = Newest '*.csv'; $json = Newest '*.json'
  $rows = @(Get-Content $csv.FullName | Select-Object -Skip 1)
  Check 'History export CSV: header and both dictations' ($rows.Count -eq 2 -and (Get-Content $csv.FullName -First 1) -match 'time,text,inserted,original') $csv.Name
  $list = Get-Content $json.FullName -Raw | ConvertFrom-Json   # assigned first: PowerShell 5.1 passes a JSON list on as one item
  Check 'History export JSON: both dictations' (@($list).Count -eq 2) $json.Name
  Set-Val (Find-El $root 'Search history' $CT::Edit) 'kiwis'; Start-Sleep 1.5
  Check 'Export says it saves only the search results' (Has 'the 1 dictation matching your search') ''
  Click 'Export CSV'
  Check 'Searched export has only the match' (@(Get-Content (Newest '*.csv').FullName | Select-Object -Skip 1).Count -eq 1) ''
  Check 'History page links to the privacy settings' ([bool](Find-El $root 'Privacy settings')) ''
  # ---- Data and privacy ----
  Page 'Settings'
  $t = Texts
  Check 'Data and privacy: sizes shown' ($t -match 'Speech models \S\s+60 MB' -and $t -match 'notes \S\s+\d+ KB') ''
  Check 'Data and privacy: History switches moved here' ([bool](Find-El $root 'Save my dictations*' $CT::CheckBox -Like)) ''
  Check 'Data and privacy: internet use names the one address' ($t -match 'huggingface\.co/ggerganov/whisper\.cpp \(version 5359861\)') ''
  # ---- settings export and import ----
  Click 'Export settings'
  $exp = Newest 'EsyType settings*.json'
  Check 'Settings export: an EsyType settings file' ($exp -and (Get-Content $exp.FullName -Raw | ConvertFrom-Json).esytype_settings -eq 1) "$($exp.Name)"
  $edited = Join-Path $exports 'edited-settings.json'; & python -I $py edit-settings $exp.FullName $edited
  Click 'Import settings*'; Pick $edited
  $msg = Dialog 'Apply'
  Check 'Import lists exactly the two changes' ($msg -match 'Change 2 settings' -and $msg -match 'Hold-to-talk shortcut: Ctrl\+F8 . Ctrl\+F6' -and $msg -match 'Clean or Verbatim: clean . verbatim') $msg
  Check 'Import names what it leaves (microphone, unreadable, unknown)' ($msg -match 'Microphone \(kept: it belongs to this PC\)' -and $msg -match 'Processor threads \(could not be read\)' -and $msg -match 'from_the_future \(not known') ''
  $st = Settings
  Check 'Import applied; microphone kept' ($st.ptt -eq 'Ctrl+F6' -and $st.text_mode -eq 'verbatim' -and $st.mic -eq 'Desk microphone' -and $st.threads -eq 0) "$($st.ptt) $($st.text_mode) $($st.mic)"
  # ---- backup ----
  Click 'Back up now'
  $bk = Newest '*.esytype-backup'
  Check 'Back up now: one .esytype-backup file' ($bk -and $bk.Length -gt 0) "$($bk.Name)"
  # ---- delete all (models kept) ----
  Click 'Delete all EsyType data'
  $msg = Dialog 'Delete everything'
  $st = Settings
  Check 'Delete all: lists what goes and what stays' ($msg -match 'cannot be undone' -and $msg -match 'Kept: backups and exports') ''
  Check 'Delete all: everything gone, settings to defaults' ((Counts) -eq '0/0/0/0' -and $st.text_mode -eq 'clean' -and $st.mic -eq $null) "$(Counts) $($st.text_mode)"
  Check 'Delete all: models kept, no wizard, backup untouched' ((Test-Path (Join-Path $Work 'restart-models\ggml-base.en-q5_1.bin')) -and ([bool](Find-El $root 'General' $CT::Button -Tries 3) -or [bool](Find-El $root 'Dictation' $CT::Button)) -and -not ((Texts) -match 'Step \d of 8') -and (Test-Path $bk.FullName)) ''
  # ---- restore ----
  Page 'Settings'
  Click 'Restore from a backup*'; Pick $bk.FullName
  $msg = Dialog 'Restore'
  Check 'Restore: asks first, showing what the backup holds' ($msg -match 'Restore the backup from' -and $msg -match '2 dictations, 1 dictionary entry, 1 snippet, 1 note') ''
  $st = Settings
  Check 'Restore: everything back, settings from the backup' ((Counts) -eq '2/1/1/1' -and $st.ptt -eq 'Ctrl+F6' -and $st.text_mode -eq 'verbatim' -and $st.mic -eq $null) "$(Counts) $($st.ptt) $($st.text_mode)"
  Check 'Restore: safety copy made' (@(Get-ChildItem (Join-Path $data 'before-restore') -Filter '*.esytype-backup').Count -eq 1) ''
  Page 'Dictation'
  $box = Find-El $root 'Practice area' $CT::Edit
  for ($k = 0; $k -lt 8 -and [Dm]::GetForegroundWindow() -ne $h; $k++) { [Dm]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400 }
  if ([Dm]::GetForegroundWindow() -ne $h) { throw 'The test build window is not in front; no keys sent.' }
  $box.SetFocus(); Start-Sleep 0.4
  try { [Dm]::Down(0x11); [Dm]::Down(0x75); Start-Sleep -Milliseconds 900 } finally { [Dm]::Up(0x75); [Dm]::Up(0x11) }
  $typed = ''; for ($i = 0; $i -lt 240 -and -not $typed; $i++) { Start-Sleep -Milliseconds 250; $typed = [string]$box.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }
  Check 'Restored shortcut and Dictionary used by dictation' ($typed -match 'Princesa') "'$typed'"
  # ---- undo restore ----
  Page 'Settings'
  Click 'Undo restore'
  [void](Dialog 'Undo restore')
  Check 'Undo restore: back to the data before the restore' ((Counts) -eq '0/0/0/0' -and (Settings).text_mode -eq 'clean') "$(Counts)"
  # ---- refused files ----
  $cut = Join-Path $exports 'damaged.esytype-backup'; $b = [IO.File]::ReadAllBytes($bk.FullName); [IO.File]::WriteAllBytes($cut, $b[0..([int]($b.Length / 2))])
  Click 'Restore from a backup*'; Pick $cut
  Check 'Damaged backup refused, nothing changed' ((Has 'not an EsyType backup, or it is damaged') -and (Counts) -eq '0/0/0/0' -and -not (Find-El $root 'Restore' $CT::Button -Tries 1)) ''
  $newer = Join-Path $exports 'newer.esytype-backup'; & python -I $py newer $bk.FullName $newer
  Click 'Restore from a backup*'; Pick $newer
  Check 'Newer backup refused, nothing changed' ((Has 'made by a newer version of EsyType') -and (Counts) -eq '0/0/0/0') ''
  Check 'Refused files leave nothing behind' (-not (Test-Path (Join-Path $data 'restore-pending.esytype-backup'))) ''
  Quit
  # ---- a failure half-way puts the data back ----
  & python -I $py seed $db
  $env:ESYTYPE_TEST_RESTORE_FAIL = '1'; Launch; Remove-Item Env:ESYTYPE_TEST_RESTORE_FAIL
  Page 'Settings'
  Click 'Restore from a backup*'; Pick $bk.FullName
  [void](Dialog 'Restore')
  Check 'Failure mid-restore: data put back, and said so' ((Has 'your data was put back as it was') -and (Counts) -eq '2/1/1/1') "$(Counts)"
  Quit

  # ---- delete all with the models (a copied model folder) ----
  $copy = Join-Path $Work 'data-models'; New-Item -ItemType Directory -Force $copy | Out-Null
  Copy-Item (Join-Path $Work 'restart-models\ggml-base.en-q5_1.bin') $copy -Force
  Fresh $copy
  Launch
  Page 'Settings'
  Click 'Delete all EsyType data'; Start-Sleep 1
  Invoke-El (Find-El $root 'Also delete the downloaded speech models*' $CT::CheckBox -Like); Start-Sleep 0.5
  [void](Dialog 'Delete everything')
  Check 'Delete all with models: model gone, wizard opens' (-not (Test-Path (Join-Path $copy 'ggml-base.en-q5_1.bin')) -and (Has 'Speak\. It types\.' 8)) ''
  Check 'Delete all with models: the shared test models untouched' (Test-Path (Join-Path $Work 'restart-models\ggml-base.en-q5_1.bin')) ''
  Quit
} catch {
  "STOPPED: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
} finally {
  if ($app) { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue }
  foreach ($k in 0x11, 0x75) { [Dm]::Up($k) }
  if ($userClip) { Set-Clipboard -Value $userClip }
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'data-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
