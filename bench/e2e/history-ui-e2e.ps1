# History through the real interface: every History control is clicked through UI Automation, retention is
# checked with entries of real ages, and history must survive restarts. Uses the e2e test build with its own
# settings folder and Ctrl+F8 (so an EsyType you have open is never triggered). Dictation types only into the
# test's own window; the interface is driven only inside the test build's own window.
# Your clipboard text is saved before the Copy check and put back afterwards.
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$ModelSource = "D:\EsyAI\EsyType\models\ggml-base.en-q5_1.bin",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio"
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class U {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-62} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

$lad = Join-Path $Work 'localappdata-hui'; $data = Join-Path $lad 'EsyAI\EsyType'; $models = Join-Path $Work 'restart-models'
New-Item -ItemType Directory -Force $data, $models | Out-Null
if (-not (Test-Path (Join-Path $models (Split-Path $ModelSource -Leaf)))) { Copy-Item $ModelSource $models }
Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item   # scratch folder owned by this test
$settingsFile = Join-Path $data 'settings.json'
[ordered]@{ model = 'base'; mic = $null; threads = 0; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; models_dir = $models; start_with_windows = $false } |
  ConvertTo-Json | Set-Content $settingsFile -Encoding ascii   # written like an older version: no history fields
$db = Join-Path $data 'esytype.db'; $py = Join-Path $PSScriptRoot 'history-db.py'; $trace = Join-Path $Work 'history-ui-trace.txt'
$current = Join-Path $Work 'current.f32'; Copy-Item (Join-Path $Audio '1320_5s.f32') $current -Force
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current

function Rows { @(& python -I $py rows $db | ConvertFrom-Json) }
function Seed($text, $days, $app) { if ($app) { & python -I $py seed $db $text $days $app } else { & python -I $py seed $db $text $days } }
function InFiles($word) { & python -I $py contains $db $word; $LASTEXITCODE -eq 0 }
function Saved { Get-Content $settingsFile -Raw | ConvertFrom-Json }

$tf = Join-Path $Work 'history-ui-target.txt'; Set-Content $tf '' -Encoding ascii
$tgt = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$tf`"", '-Kind', 'RichTextBox' -PassThru
Start-Sleep 3; $h = [U]::FindWindow([NullString]::Value, 'esytype-e2e-target')
function Text { for ($i = 0; $i -lt 40; $i++) { try { return [IO.File]::ReadAllText($tf) } catch { Start-Sleep -Milliseconds 25 } }; throw 'read failed' }
function Dictate {
  for ($k = 0; $k -lt 5 -and [U]::GetForegroundWindow() -ne $h; $k++) {
    $fg = [U]::GetForegroundWindow(); $fgPid = 0; [void][U]::GetWindowThreadProcessId($fg, [ref]$fgPid)
    if ($k -gt 0 -and ($fgPid -eq $app.Id -or $fgPid -eq $tgt.Id)) { [U]::Down(0x12); [U]::Up(0x12) }   # Alt tap unlocks SetForegroundWindow; only while our own windows are in front
    [void](New-Object -ComObject WScript.Shell).AppActivate('esytype-e2e-target'); Start-Sleep -Milliseconds 300; [U]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 500
  }
  if ([U]::GetForegroundWindow() -ne $h) { throw 'Test window is not in front; stopping before sending keys.' }
  $before = (Text).Length
  [U]::Down(0x11); [U]::Down(0x77); Start-Sleep -Milliseconds 900; [U]::Up(0x77); [U]::Up(0x11)
  for ($i = 0; $i -lt 1200 -and (Text).Length -eq $before; $i++) { Start-Sleep -Milliseconds 50 }   # up to 60 s, as in the other suites
  Start-Sleep 1.5; (Text).Substring($before).Trim()
}
function Launch([switch]$Hidden) {
  $p = @{ FilePath = $Exe; PassThru = $true; RedirectStandardError = $trace }; if ($Hidden) { $p.ArgumentList = '--minimized' }
  $script:app = Start-Process @p; Start-Sleep 9
  if (-not $Hidden) { $script:root = Get-AppWindow $app.Id 'EsyType' }   # the test build's window, not an installed EsyType's
}
function Quit { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue; Start-Sleep 2 }
# Opens (or re-opens, which reloads) the History tab.
function OpenHistory { Invoke-El (Find-El $root 'Dictation' $CT::Button); Start-Sleep -Milliseconds 400; Invoke-El (Find-El $root 'History' $CT::Button); Start-Sleep 1.2 }
function Items { @(Find-All $root $CT::ListItem | Where-Object { $_.Current.Name -match '\d+ words?' }) }
function ItemFor($text) { Items | Where-Object { $_.Current.Name -like "*$text*" } | Select-Object -First 1 }
function Btn($item, $name) { Find-El $item $name $CT::Button }
# History's privacy switches are in Settings, Data and privacy (since Milestone 3): go there when they are not on screen.
function PrivacyPage { if (-not (Find-El $root 'KEEP HISTORY' $CT::ComboBox -Tries 2)) { Invoke-El (Find-El $root 'Settings' $CT::Button); Start-Sleep 1.2 } }
function Box($label) { PrivacyPage; Find-El $root "$label*" $CT::CheckBox -Like }
function Retention($label) {
  PrivacyPage
  $cb = Find-El $root 'KEEP HISTORY' $CT::ComboBox
  $cb.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand(); Start-Sleep -Milliseconds 400
  $opt = Find-El $cb $label $CT::ListItem; if (-not $opt) { $opt = Find-El $root $label $CT::ListItem }
  $opt.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 300
  try { $cb.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse() } catch {}
}

$userClip = Get-Clipboard -Raw
try {
  # --- 1. Settings from an older version load with History defaults ---------------------------------------
  Launch; OpenHistory
  Check 'Older settings file: History on, 90 days, both switches on' ((Toggled (Box 'Save my dictations')) -and (Toggled (Box 'Note which program')) -and (Toggled (Box 'Keep the original')) -and (Find-El $root 'KEEP HISTORY' $CT::ComboBox).GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value -eq '90 days') ''
  Check 'Older settings file not rewritten just by starting' (-not ((Get-Content $settingsFile -Raw) -match 'history')) ''

  # --- 2. Retention with real ages, applied at start-up; history survives a restart ----------------------
  $d = Dictate; Start-Sleep 1
  Check 'Dictation saved with the app running' ((Rows).Count -eq 1 -and (Rows)[0].final_text -eq $d) "rows=$((Rows).Count) '$d'"
  # Seeded after the dictation: every dictation also applies retention, so this isolates the start-up purge.
  Seed 'Recent entry about apples.' 1 'WINWORD.EXE'; Seed 'Eighty nine days of oranges.' 89; Seed 'Ninety one days of plums.' 91; Seed 'Four hundred days of quinces.' 400
  Quit; Launch -Hidden
  $texts = (Rows).final_text
  Check 'Restart: entries within 90 days survive' ($texts -contains 'Recent entry about apples.' -and $texts -contains 'Eighty nine days of oranges.' -and $texts -contains $d) "rows=$($texts.Count)"
  Check 'Restart: entries older than 90 days removed at start-up' (-not ($texts -contains 'Ninety one days of plums.') -and -not ($texts -contains 'Four hundred days of quinces.')) ''
  Check 'Removed entries are not left in the database files' (-not (InFiles 'plums') -and -not (InFiles 'quinces')) ''
  Quit; Launch

  # --- 3. Expired entries go when History is opened, even without a dictation or restart -----------------
  Seed 'Ninety five days of figs.' 95
  OpenHistory
  Check 'Entry that expired while running is removed when History opens' (-not ((Rows).final_text -contains 'Ninety five days of figs.') -and -not (ItemFor 'figs')) ''
  Check 'List shows every remaining entry' ((Items).Count -eq 3) "shown=$((Items).Count)"

  # --- 4. Search ---------------------------------------------------------------------------------------------
  $search = Find-El $root 'Search history' $CT::Edit
  Set-Val $search 'APPLES'; Start-Sleep 1
  Check 'Search finds matching entries (any case)' ((Items).Count -eq 1 -and (ItemFor 'apples')) "shown=$((Items).Count)"
  Set-Val $search 'no such words'; Start-Sleep 1
  Check 'Search with no match shows a message' ((Items).Count -eq 0 -and (Find-El $root 'Nothing matches "no such words".' $CT::Text) -and (Find-El $root 'Clear search' $CT::Button)) ''
  Set-Val $search ''; Start-Sleep 1

  # --- 5. Copy -------------------------------------------------------------------------------------------------
  Set-Clipboard -Value 'BEFORE COPY'
  Invoke-El (Btn (ItemFor 'apples') 'Copy'); Start-Sleep 0.8
  Check 'Copy puts the entry text on the clipboard' ((Get-Clipboard -Raw) -eq 'Recent entry about apples.') "'$(Get-Clipboard -Raw)'"

  # --- 6. Edit, then undo the edit ----------------------------------------------------------------------------
  Invoke-El (Btn (ItemFor 'apples') 'Edit'); Start-Sleep 0.5
  Set-Val (Find-El $root 'Edit dictation' $CT::Edit) 'Corrected entry about pears.'; Start-Sleep 0.3
  Invoke-El (Find-El $root 'Save' $CT::Button); Start-Sleep 1
  $row = (Rows) | Where-Object { $_.final_text -eq 'Recent entry about apples.' }
  Check 'Edit saves the new text; the inserted text is kept' ($row.edited_text -eq 'Corrected entry about pears.' -and (ItemFor 'pears') -and (ItemFor 'pears').Current.Name -match 'edited') "edited='$($row.edited_text)'"
  Set-Val $search 'pears'; Start-Sleep 1
  Check 'Search finds edited text' ((Items).Count -eq 1) ''
  Set-Val $search ''; Start-Sleep 1
  Invoke-El (Btn (ItemFor 'pears') 'Edit'); Start-Sleep 0.5
  Invoke-El (Find-El $root 'Undo my edits' $CT::Button); Start-Sleep 1
  $row = (Rows) | Where-Object { $_.final_text -eq 'Recent entry about apples.' }
  Check 'Undo my edits restores the inserted text' ($null -eq $row.edited_text -and (ItemFor 'apples') -and -not (InFiles 'pears')) ''

  # --- 7. Delete one entry: Cancel keeps it, OK removes it ----------------------------------------------------
  Invoke-El (Btn (ItemFor 'oranges') 'Delete'); $msg = Answer-Dialog $root 'Cancel'; Start-Sleep 0.8
  Check 'Delete asks first; Cancel keeps the entry' (((Rows).final_text -contains 'Eighty nine days of oranges.') -and $msg -match 'Delete this dictation') "'$msg'"
  Invoke-El (Btn (ItemFor 'oranges') 'Delete'); [void](Answer-Dialog $root 'Delete'); Start-Sleep 1
  Check 'Delete with OK removes it, from the files too' (-not ((Rows).final_text -contains 'Eighty nine days of oranges.') -and -not (ItemFor 'oranges') -and -not (InFiles 'oranges')) "rows=$((Rows).Count)"

  # --- 8. Retention changed in the window ---------------------------------------------------------------------
  Seed 'Forty days of limes.' 40
  Retention '30 days'; $msg = Answer-Dialog $root 'Continue'; Start-Sleep 1
  Check '30 days: asks first, then removes older entries' ((Saved).history_retention_days -eq 30 -and -not ((Rows).final_text -contains 'Forty days of limes.') -and $msg -match '30 days') "setting=$((Saved).history_retention_days) '$msg'"
  Retention 'Until I delete it'; Start-Sleep 1
  Seed 'Five hundred days of kiwis.' 500; Quit; Launch; OpenHistory
  Check 'Until I delete it: old entries kept, also after restart' ((Saved).history_retention_days -eq 0 -and ((Rows).final_text -contains 'Five hundred days of kiwis.') -and (ItemFor 'kiwis')) ''
  Retention '90 days'; [void](Answer-Dialog $root 'Continue'); Start-Sleep 1
  Check 'Back to 90 days removes the 500-day entry' ((Saved).history_retention_days -eq 90 -and -not ((Rows).final_text -contains 'Five hundred days of kiwis.')) ''

  # --- 9. Keep original transcription off (and back on) -------------------------------------------------------
  Invoke-El (Box 'Keep the original'); $msg = Answer-Dialog $root 'Stop keeping originals'; Start-Sleep 1
  Check 'Keep original off: asks, then removes saved originals' (-not (Saved).history_keep_raw -and @((Rows) | Where-Object { $_.raw_text }).Count -eq 0 -and $msg -match 'original') "'$msg'"
  $d2 = Dictate; Start-Sleep 1
  Check 'Keep original off: new entry has no original' ($null -eq (Rows)[-1].raw_text -and (Rows)[-1].final_text -eq $d2) ''
  Invoke-El (Box 'Keep the original'); Start-Sleep 1

  # --- 10. Program names off (and back on) ---------------------------------------------------------------------
  Invoke-El (Box 'Note which program'); Start-Sleep 1
  [void](Dictate); Start-Sleep 1
  Check 'Program names off: new entry has no program name' (-not (Saved).history_record_app -and $null -eq (Rows)[-1].app -and (Rows)[-1].raw_text) "app=$((Rows)[-1].app)"
  Invoke-El (Box 'Note which program'); Start-Sleep 1
  [void](Dictate); Start-Sleep 1
  Check 'Program names on: executable name only' ((Rows)[-1].app -eq 'powershell.exe') "app=$((Rows)[-1].app)"

  # --- 11. History off in the window ----------------------------------------------------------------------------
  $n = (Rows).Count
  Invoke-El (Box 'Save my dictations'); Start-Sleep 1
  $off = Dictate; Start-Sleep 1
  $note = [bool](Find-El $root 'History is off*' $CT::Text -Like)
  Check 'History off: dictation inserted, nothing saved' (-not (Saved).history_enabled -and $off.Length -gt 10 -and (Rows).Count -eq $n) "enabled=$((Saved).history_enabled) inserted=$($off.Length) chars rows=$((Rows).Count)"
  Check 'History off: the page says so' $note ''
  Quit; Launch -Hidden
  [void](Dictate); Start-Sleep 1
  Check 'History off survives a restart' ((Rows).Count -eq $n) "rows=$((Rows).Count)"
  Quit; Launch; OpenHistory
  Invoke-El (Box 'Save my dictations'); Start-Sleep 1
  [void](Dictate); Start-Sleep 1
  Check 'History on again: saving resumes' ((Saved).history_enabled -and (Rows).Count -eq $n + 1) ''

  # --- 12. Delete all ------------------------------------------------------------------------------------------
  OpenHistory
  Invoke-El (Find-El $root 'Delete all history' $CT::Button); $msg = Answer-Dialog $root 'Cancel'; Start-Sleep 0.8
  Check 'Delete all asks first; Cancel deletes nothing' ((Rows).Count -eq $n + 1 -and $msg -match 'cannot be undone') "'$msg'"
  Invoke-El (Find-El $root 'Delete all history' $CT::Button); [void](Answer-Dialog $root 'Delete all'); Start-Sleep 1.5
  $left = @('apples', 'conjurer', 'entrance') | Where-Object { InFiles $_ }
  $other = @(Get-ChildItem $data -File | Where-Object { $_.Name -notmatch '^(settings\.json|esytype\.db(-wal|-shm)?)$' })
  Check 'Delete all: no records left' ((Rows).Count -eq 0 -and (Items).Count -eq 0 -and (Find-El $root 'Nothing here yet' $CT::Text) -and (Find-El $root 'Try it' $CT::Button)) ''
  Check 'Delete all: text not recoverable from the files; no backups' ($left.Count -eq 0 -and $other.Count -eq 0) "found: $($left -join ', ') extra files: $($other.Name -join ', ')"
  Quit; Launch -Hidden
  Check 'Delete all: still empty after a restart' ((Rows).Count -eq 0) ''

  # --- 13. Other settings untouched by all of the above ----------------------------------------------------------
  $s = Saved
  Check 'Model, shortcuts, threads and model folder unchanged' ($s.model -eq 'base' -and $s.ptt -eq 'Ctrl+F8' -and $s.toggle -eq 'Ctrl+F7' -and $s.threads -eq 0 -and $s.models_dir -eq $models -and -not $s.start_with_windows) "models_dir=$($s.models_dir)"
  Check 'No model files written to the default folder' (-not (Test-Path (Join-Path $data 'models\*.bin'))) ''
} finally {
  Get-Process esytype-e2e -ErrorAction SilentlyContinue | Where-Object { $_.Path -like 'D:\AI Projects\*' } | Stop-Process -Force
  Stop-Process -Id $tgt.Id -Force -ErrorAction SilentlyContinue
  [U]::Up(0x77); [U]::Up(0x11); [U]::Up(0x12)
  if ($userClip) { Set-Clipboard -Value $userClip }
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'history-ui-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
