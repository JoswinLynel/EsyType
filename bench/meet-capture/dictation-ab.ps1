# EsyMeet plan 8.1: dictation time with and without a capture running, in alternating blocks (off, on, off, on by
# default), each -Reps dictations through threads-probe.ps1 (test build, its own test window, 4 threads, clip 6930_10s).
# During an "on" block meet-capture records into a scratch folder; its microphone file is deleted afterwards.
param([string[]]$Order = @('off', 'on', 'off', 'on'), [int]$Reps = 5, [string]$Csv = "D:\AI Projects\Tools\bench\results\meet-capture\dictation-ab.csv",
      [string]$Capture = "D:\AI Projects\Tools\bench\meet-target\release\meet-capture.exe", [string]$Scratch = "D:\AI Projects\Tools\bench\results\meet-capture\ab-scratch")
$ErrorActionPreference = 'Stop'
$probe = Join-Path $PSScriptRoot '..\e2e\threads-probe.ps1'
foreach ($o in @($Order | ForEach-Object { $_ -split ',' })) {
  $cap = $null
  if ($o -eq 'on') {
    if (Test-Path $Scratch) { Remove-Item $Scratch -Recurse -Force }
    $cap = Start-Process $Capture -ArgumentList 600, "`"$Scratch`"" -PassThru -WindowStyle Hidden
    Start-Sleep 2
  }
  try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $probe -Threads 4 -Reps $Reps -Label "capture-$o" -Csv $Csv 2>&1 | Select-Object -Last 1
    if ($cap -and $cap.HasExited) { "capture stopped early (exit $($cap.ExitCode))" }
  } finally {
    if ($cap) { Stop-Process -Id $cap.Id -Force -ErrorAction SilentlyContinue; Start-Sleep 1; Remove-Item (Join-Path $Scratch 'mic.f32') -ErrorAction SilentlyContinue }
  }
}
