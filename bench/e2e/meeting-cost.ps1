# EsyMeet 8.2: what the meeting watcher costs. Runs the test build idle in the tray for -Seconds with "Detect meetings"
# on, then off, and reports the CPU time of EsyType's whole process tree (WebView2 processes included) for each.
param([int]$Seconds = 180, [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe", [string]$Work = "D:\AI Projects\Tools\e2e")
$ErrorActionPreference = 'Stop'
$lad = Join-Path $Work 'localappdata-meetcost'; $data = Join-Path $lad 'EsyAI\EsyType'
function Tree([int]$root) {
  $all = Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId
  $ids = @($root); $grew = $true
  while ($grew) { $grew = $false; foreach ($p in $all) { if ($p.ParentProcessId -in $ids -and $p.ProcessId -notin $ids) { $ids += [int]$p.ProcessId; $grew = $true } } }
  $ids
}
function Cpu([int[]]$ids) { ($ids | ForEach-Object { (Get-Process -Id $_ -ErrorAction SilentlyContinue).TotalProcessorTime.TotalSeconds } | Measure-Object -Sum).Sum }
foreach ($on in $true, $false) {
  if (Test-Path $lad) { Remove-Item $lad -Recurse -Force }
  New-Item -ItemType Directory -Force $data | Out-Null
  [ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false; meet_detect = $on } |
    ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
  $env:LOCALAPPDATA = $lad
  $app = Start-Process $Exe -ArgumentList '--minimized' -PassThru; Start-Sleep 15   # past start-up and the model load
  $ids = Tree $app.Id; $c0 = Cpu $ids; Start-Sleep $Seconds; $c1 = Cpu $ids
  Stop-Process -Id $app.Id -Force; Start-Sleep 2
  "detect meetings {0}: {1:N2} s of CPU in {2} s ({3:N3}% of one core)" -f $(if ($on) { 'on ' } else { 'off' }), ($c1 - $c0), $Seconds, (($c1 - $c0) / $Seconds * 100)
}
