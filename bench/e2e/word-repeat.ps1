# Repeats the Word part of undo-apps-e2e.ps1 (dictate, check the text, Undo, History, clipboard) many times, in four
# conditions: normal; with a background program reading the clipboard anonymously (clipboard-reactor.py); slow (all
# cores kept busy at below-normal priority, and the test's own Word at the lowest, so Word is starved but EsyType's
# speech step is not); slow with the background reader. Refuses to start while Word is open.
param([int]$Normal = 10, [int]$Reader = 5, [int]$Slow = 5, [int]$SlowReader = 5, [string]$Work = "D:\AI Projects\Tools\e2e")
$ErrorActionPreference = 'Stop'
if (Get-Process WINWORD -ErrorAction SilentlyContinue) { throw 'Word is open. Close it first: this test starts its own Word.' }
$test = Join-Path $PSScriptRoot 'undo-apps-e2e.ps1'; $trace = Join-Path $Work 'undo-apps-trace.txt'
function Stop-Helpers { Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'cpu-load|clipboard-reactor|multiprocessing' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } }
$summary = @()
try {
  foreach ($cond in @(@('normal', $Normal), @('reader', $Reader), @('slow', $Slow), @('slow+reader', $SlowReader))) {
    $name, $n = $cond
    if ($n -le 0) { continue }
    if ($name -match 'slow') {
      $load = Start-Process python -ArgumentList '-I', "`"$(Join-Path $PSScriptRoot 'cpu-load.py')`"", 8, 3600 -PassThru -NoNewWindow
      $load.PriorityClass = 'BelowNormal'; Start-Sleep 2   # children inherit it
    }
    if ($name -match 'reader') { Start-Process python -ArgumentList '-I', "`"$(Join-Path $PSScriptRoot 'clipboard-reactor.py')`"", 180, 3600, "`"$(Join-Path $Work 'reactor-log.txt')`"" -NoNewWindow | Out-Null }
    $pass = 0; $skipped = 0
    for ($i = 1; $i -le $n; $i++) {
      $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $test, '-Apps', 'word'); if ($name -match 'slow') { $a += '-SlowWord' }
      $ErrorActionPreference = 'Continue'; $out = & powershell.exe @a 2>&1 | Out-String; $ErrorActionPreference = 'Stop'
      if ($out -match 'not in front; no keys sent') { "{0,-12} run {1,2}: NOT RUN (Word was not in front; the test sent no keys)" -f $name, $i; $skipped++; continue }
      $ok = $out -match '4 of 4 checks passed'; if ($ok) { $pass++ }
      $t = (Get-Content $trace | Where-Object { $_ -match 'taken|refused|inserted' }) -replace '^\[\d+\] ', '' -join '; '
      "{0,-12} run {1,2}: {2}  {3}" -f $name, $i, $(if ($ok) { 'PASS' } else { 'FAIL' }), $t
      if (-not $ok) { ($out -split "`n" | Where-Object { $_ -match 'FAIL|STOPPED' }) | ForEach-Object { "    $_".TrimEnd() } }
    }
    $summary += "{0}: {1} of {2} passed{3}" -f $name, $pass, ($n - $skipped), $(if ($skipped) { " ($skipped not run)" })
    Stop-Helpers; Start-Sleep 2
  }
} finally { Stop-Helpers }
"`n" + ($summary -join "`n")
