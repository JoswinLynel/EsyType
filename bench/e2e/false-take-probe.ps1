# Looks for false "taken" signals: pastes into a test window that cannot paste (a label), so any request for the
# text after the paste key comes from some other program. Uses clipboard-probe.py with EsyType's timing and
# markers. Only this script's own window gets keys.
param([int]$Reps = 20, [string]$Work = "D:\AI Projects\Tools\e2e")
$ErrorActionPreference = 'Stop'
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Fp {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}
"@
$probe = Join-Path $PSScriptRoot 'clipboard-probe.py'; $userClip = Get-Clipboard -Raw
$f = Join-Path $Work 'false-take.txt'; Set-Content $f '' -Encoding ascii
$p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$f`"", '-Kind', 'None', '-Title', 'esytype-false-take' -PassThru
Start-Sleep 3; $h = [Fp]::FindWindow([NullString]::Value, 'esytype-false-take')
$n = 0; $names = @{}
try {
  for ($i = 1; $i -le $Reps; $i++) {
    for ($k = 0; $k -lt 6 -and [Fp]::GetForegroundWindow() -ne $h; $k++) { [Fp]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [Fp]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero); [Fp]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400 }
    $r = & python -I $probe ([int64]$h) 'probe text' "USER-CLIPBOARD-$(Get-Random)" 250 1500 150 1 | ConvertFrom-Json
    $after = @($r.requests | Where-Object { $_.phase -eq 'dictation' })
    if ($after) { $n++; foreach ($a in $after) { $who = if ($a.opener_pid) { (Get-Process -Id $a.opener_pid -ErrorAction SilentlyContinue).ProcessName } else { 'no window' }; $names[$who] = 1 + [int]$names[$who] } }
    "{0,2}: {1}" -f $i, $(if ($r.error) { $r.error } else { (($r.requests | ForEach-Object { "$($_.phase)@$($_.ms)ms(pid $($_.opener_pid))" }) -join ' ') })
    Start-Sleep 1
  }
} finally {
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  if ($userClip) { Set-Clipboard -Value $userClip }
}
"`nFalse 'taken' requests in {0} of {1} pastes; from: {2}" -f $n, $Reps, (($names.GetEnumerator() | ForEach-Object { "$($_.Key) x$($_.Value)" }) -join ', ')
