# Samples a running meet-capture process every -Every seconds until it exits: working set, private memory, CPU
# seconds, threads and handles, into -Csv. For memory over a long capture (the probe itself reports CPU, not memory).
param([string]$Csv = "D:\AI Projects\Tools\bench\results\meet-capture\long-memory.csv", [int]$Every = 30)
$p = Get-Process meet-capture -ErrorAction Stop | Select-Object -First 1
'utc,elapsed_s,working_set_mb,private_mb,cpu_s,threads,handles' | Set-Content $Csv -Encoding ascii
while (-not $p.HasExited) {
  $p.Refresh()
  '{0},{1:F0},{2:F1},{3:F1},{4:F2},{5},{6}' -f (Get-Date).ToUniversalTime().ToString('o'), ((Get-Date) - $p.StartTime).TotalSeconds,
    ($p.WorkingSet64 / 1MB), ($p.PrivateMemorySize64 / 1MB), $p.TotalProcessorTime.TotalSeconds, $p.Threads.Count, $p.HandleCount |
    Add-Content $Csv -Encoding ascii
  Start-Sleep -Seconds $Every
}
