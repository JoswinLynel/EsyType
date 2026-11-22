# History: dictations are saved after insertion with the privacy settings respected, nothing is saved when
# history is off, and a corrupt, newer or locked database never stops dictation. Injected audio; types only
# into this script's own window. Uses Ctrl+F8 so it never triggers an EsyType you have running. Needs Python 3 (sqlite3 module) to inspect the database.
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$ModelSource = "D:\EsyAI\EsyType\models\ggml-base.en-q5_1.bin",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio"
)
$ErrorActionPreference = 'Stop'
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class H {
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

$lad = Join-Path $Work 'localappdata-history'; $data = Join-Path $lad 'EsyAI\EsyType'; $models = Join-Path $Work 'restart-models'
New-Item -ItemType Directory -Force $data, $models | Out-Null
if (-not (Test-Path (Join-Path $models (Split-Path $ModelSource -Leaf)))) { Copy-Item $ModelSource $models }
Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force # scratch folder owned by this test
$db = Join-Path $data 'esytype.db'; $py = Join-Path $PSScriptRoot 'history-db.py'; $trace = Join-Path $Work 'history-trace.txt'
$current = Join-Path $Work 'current.f32'
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current

function Settings($enabled, $recordApp, $keepRaw) {
  [ordered]@{ model = 'base'; mic = $null; threads = 0; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; models_dir = $models; start_with_windows = $false
    history_enabled = $enabled; history_retention_days = 90; history_record_app = $recordApp; history_keep_raw = $keepRaw } |
    ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
}
function Rows { @(& python -I $py rows $db | ConvertFrom-Json) }
function Contains($word) { & python -I $py contains $db $word; $LASTEXITCODE -eq 0 }

$tf = Join-Path $Work 'history-target.txt'; Set-Content $tf '' -Encoding ascii
$tgt = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$tf`"", '-Kind', 'RichTextBox' -PassThru
Start-Sleep 3; $h = [H]::FindWindow([NullString]::Value, 'esytype-e2e-target')
function Text { for ($i = 0; $i -lt 40; $i++) { try { return [IO.File]::ReadAllText($tf) } catch { Start-Sleep -Milliseconds 25 } }; throw 'read failed' }
# Returns the inserted text and the seconds from key release to the text appearing.
function Dictate($clip) {
  Copy-Item (Join-Path $Audio $clip) $current -Force
  for ($k = 0; $k -lt 5 -and [H]::GetForegroundWindow() -ne $h; $k++) { [void](New-Object -ComObject WScript.Shell).AppActivate('esytype-e2e-target'); Start-Sleep -Milliseconds 300; [H]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 500 }
  if ([H]::GetForegroundWindow() -ne $h) { throw 'Test window is not in front; stopping before sending keys.' }
  $before = (Text).Length
  [H]::Down(0x11); [H]::Down(0x77); Start-Sleep -Milliseconds 900; [H]::Up(0x77); [H]::Up(0x11)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  for ($i = 0; $i -lt 1200 -and (Text).Length -eq $before; $i++) { Start-Sleep -Milliseconds 50 }
  $secs = $sw.Elapsed.TotalSeconds; Start-Sleep 1
  $fgPid = 0; [void][H]::GetWindowThreadProcessId([H]::GetForegroundWindow(), [ref]$fgPid)
  [pscustomobject]@{ Text = (Text).Substring($before).Trim(); Seconds = [Math]::Round($secs, 2); Front = (Get-Process -Id $fgPid -ErrorAction SilentlyContinue).ProcessName }
}
function Launch { $script:run++; $script:trace = Join-Path $Work "history-trace-$($script:run).txt"; $script:app = Start-Process $Exe -ArgumentList '--minimized' -PassThru -RedirectStandardError $trace; Start-Sleep 9 } # tray only: no window to take focus; one log per start
function Quit { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue; Start-Sleep 2 }

try {
  # 1. Defaults: saved after insertion, with program name and original transcription
  Settings $true $true $true; Launch
  $a = Dictate '1320_5s.f32'; $b = Dictate '1320_5s.f32'; Start-Sleep 1
  $r = Rows
  Check 'History on: both dictations saved' ($r.Count -eq 2) "rows=$($r.Count)"
  Check 'Saved text is exactly what was inserted' ($r.Count -eq 2 -and $r[0].final_text -eq $a.Text -and $r[1].final_text -eq $b.Text) "'$($r[0].final_text)'"
  Check 'Program recorded as executable name only' ($r[0].app -eq 'powershell.exe') "app=$($r[0].app)"
  Check 'Original transcription kept; details recorded' ($r[0].raw_text -and $r[0].mode -eq 'clean' -and $r[0].model -eq 'base' -and $r[0].audio_ms -gt 4000 -and $r[0].outcome -eq 'pasted' -and $r[0].word_count -gt 5) "outcome=$($r[0].outcome) audio_ms=$($r[0].audio_ms) words=$($r[0].word_count)"
  $other = @(Get-ChildItem $data -Recurse -File | Where-Object { $_.Name -notmatch '^(settings\.json|esytype\.db(-wal|-shm)?)$' })
  Check 'No audio or other files written' ($other.Count -eq 0) ($other.Name -join ', ')
  $baseline = $a.Seconds
  Quit

  # 2. History off: dictation works, nothing is written
  Settings $false $true $true; Launch
  $c = Dictate '6930_5s.f32'; Start-Sleep 1
  $words = @(($c.Text.ToLower() -replace "[^a-z ]", ' ') -split '\s+' | Where-Object { $_.Length -ge 5 -and $a.Text.ToLower() -notmatch $_ })
  Check 'History off: dictation still inserted' ($c.Text.Length -gt 10) "'$($c.Text)'"
  Check 'History off: no new entry' ((Rows).Count -eq 2) "rows=$((Rows).Count)"
  $leaked = @($words | Where-Object { Contains $_ })
  Check 'History off: none of its words in the database files' ($words.Count -gt 0 -and $leaked.Count -eq 0) "checked $($words -join ' '); found: $($leaked -join ' ')"
  Quit

  # 3. App tracking and original transcription off
  Settings $true $false $false; Launch
  $d = Dictate '6930_5s.f32'; Start-Sleep 1
  $last = (Rows)[-1]
  Check 'Tracking off: no program name, no original kept' ((Rows).Count -eq 3 -and $null -eq $last.app -and $null -eq $last.raw_text -and $last.final_text -eq $d.Text) "app=$($last.app) raw=$($last.raw_text)"
  Quit

  # 4. Corrupt database: dictation works, the file is left as it was
  Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force
  [IO.File]::WriteAllBytes($db, [byte[]](1..4096 | ForEach-Object { $_ % 251 }))
  $hash = (Get-FileHash $db).Hash
  Settings $true $true $true; Launch
  $e = Dictate '1320_5s.f32'
  Check 'Corrupt database: dictation still inserted' ($e.Text.Length -gt 10) "$($e.Seconds) s"
  Check 'Corrupt database: file untouched' ((Get-FileHash $db).Hash -eq $hash) ''
  Quit
  Check 'Corrupt database: reason logged' ((Get-Content $trace -Raw) -match 'history:') ((Select-String 'history:' $trace | Select-Object -First 1).Line)

  # 5. Database from a newer EsyType: left untouched
  Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force
  & python -I $py newer $db; $hash = (Get-FileHash $db).Hash
  Launch
  $f = Dictate '1320_5s.f32'
  Check 'Newer database: dictation still inserted' ($f.Text.Length -gt 10) "$($f.Seconds) s"
  Check 'Newer database: file untouched' ((Get-FileHash $db).Hash -eq $hash) ''
  Quit

  # 6. Database locked by another program while dictating
  Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force
  Launch
  $lock = Start-Process python -ArgumentList '-I', "`"$py`"", 'lock', "`"$db`"", '20' -PassThru -NoNewWindow; Start-Sleep 2   # 20 s: longer than the database library's 5 s wait; no window that could take focus
  $g = Dictate '1320_5s.f32'
  Check 'Locked database: dictation inserted without delay' ($g.Text.Length -gt 10 -and $g.Seconds -lt $baseline + 1.5) "$($g.Seconds) s (unlocked: $baseline s; in front afterwards: $($g.Front))"
  $lock.WaitForExit(); Start-Sleep 5
  $i = Dictate '1320_5s.f32'; Start-Sleep 1
  Check 'Locked database: saving resumes after the lock is released' ((Rows).Count -eq 1 -and $i.Text.Length -gt 10) "rows=$((Rows).Count)"
  Quit
  Check 'Locked database: failure logged' ((Get-Content $trace -Raw) -match 'history:.*lock') ((Select-String 'history:' $trace | Select-Object -First 1).Line)

  # 7. Database file made read-only (e.g. by a backup tool or permissions)
  Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force
  Launch; Quit   # creates a valid database
  Set-ItemProperty $db -Name IsReadOnly -Value $true; $hash = (Get-FileHash $db).Hash
  Launch
  $k = Dictate '1320_5s.f32'
  Check 'Read-only database: dictation still inserted' ($k.Text.Length -gt 10) "$($k.Seconds) s"
  Quit
  Check 'Read-only database: file unchanged, reason logged' ((Get-FileHash $db).Hash -eq $hash -and (Get-Content $trace -Raw) -match 'history:') ((Select-String 'history:' $trace | Select-Object -First 1).Line)
  Set-ItemProperty $db -Name IsReadOnly -Value $false
} finally {
  if (Test-Path $db) { Set-ItemProperty $db -Name IsReadOnly -Value $false }
  Get-Process esytype-e2e -ErrorAction SilentlyContinue | Where-Object { $_.Path -like 'D:\AI Projects\*' } | Stop-Process -Force
  Stop-Process -Id $tgt.Id -Force -ErrorAction SilentlyContinue
  [H]::Up(0x77); [H]::Up(0x11)
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'history-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
