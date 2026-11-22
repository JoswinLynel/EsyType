# Measures how Word reads the clipboard when it pastes (see clipboard-probe.py), in a Word instance and new document
# this script starts and closes unsaved. Refuses to run while Word is already open, so your documents are never touched.
#   -Reps   pastes to measure      -Hold   ms the dictation is kept after Word's first request
#   -Load   busy processes running meanwhile (0 = normal PC; imitates a slow PC)
param([int]$Reps = 10, [int]$Hold = 250, [int]$Load = 0, [int]$Pre = 150, [int]$Markers = 1, [int]$Reoffer = 0, [switch]$Starve, [string]$Work = "D:\AI Projects\Tools\e2e")
$ErrorActionPreference = 'Stop'
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Wp {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}
"@
if (Get-Process WINWORD -ErrorAction SilentlyContinue) { throw 'Word is open. Close it first: this test starts its own Word.' }
$probe = Join-Path $PSScriptRoot 'clipboard-probe.py'
$userClip = Get-Clipboard -Raw
$dictation = 'Congratulations were poured in upon the princess everywhere during her journey.'
$burn = $null; $rows = @()
$word = New-Object -ComObject Word.Application; $word.Visible = $true
try {
  $wd = $word.Documents.Add(); Start-Sleep 3; $wd.Activate(); $word.Activate(); $wh = [IntPtr]$wd.ActiveWindow.Hwnd
  # -Starve: this test's own Word runs at the lowest priority, so with -Load it gets little CPU (a very slow PC)
  $wpidW = 0; [void][Wp]::GetWindowThreadProcessId($wh, [ref]$wpidW)
  if ($Starve) { $wpid = 0; [void][Wp]::GetWindowThreadProcessId($wh, [ref]$wpid); (Get-Process -Id $wpid).PriorityClass = 'Idle' }
  if ($Load -gt 0) { $burn = Start-Process python -ArgumentList '-I', "`"$(Join-Path $PSScriptRoot 'cpu-load.py')`"", $Load, ($Reps * 12 + 20) -PassThru -NoNewWindow; Start-Sleep 2 }
  for ($i = 1; $i -le $Reps; $i++) {
    for ($k = 0; $k -lt 10; $k++) { try { $wd.Content.Text = ''; break } catch { Start-Sleep -Milliseconds 500 } }; Start-Sleep 0.5
    for ($k = 0; $k -lt 6 -and [Wp]::GetForegroundWindow() -ne $wh; $k++) { [Wp]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [Wp]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero); [Wp]::SetForegroundWindow($wh) | Out-Null; Start-Sleep -Milliseconds 400 }
    $marker = "USER-CLIPBOARD-$(Get-Random)"
    $r = & python -I $probe ([int64]$wh) $dictation $marker $Hold 4000 $Pre $Markers $Reoffer | ConvertFrom-Json
    Start-Sleep 1
    $got = $null; for ($k = 0; $k -lt 10 -and $null -eq $got; $k++) { try { $got = $wd.Content.Text.Trim() } catch { Start-Sleep -Milliseconds 500 } }   # Word refuses COM calls while busy
    $req = @($r.requests | Where-Object { $_.phase -ne 'before' })
    $rows += [pscustomobject]@{
      Rep = $i; Got = $(if ($got -eq $dictation) { 'dictation' } elseif ($got -like 'USER-CLIPBOARD-*') { 'USER CLIPBOARD' } elseif ($got) { "other: $got" } else { 'nothing' })
      Before = (@($r.requests | Where-Object { $_.phase -eq 'before' }) | ForEach-Object { "offer+$($_.ms)ms(pid $($_.opener_pid))" }) -join ' '
      Requests = ($req | Where-Object phase -ne 're-offered' | ForEach-Object { "$($_.phase)@$($_.ms)ms$(if ($_.opener_pid -ne $wpidW) { "(pid $($_.opener_pid))" })" }) -join ' '
      Idle = $r.idle_ms; Restored = $r.restored_ms; Error = $r.error
    }
    $rows[-1] | Format-Table -HideTableHeaders | Out-String | ForEach-Object Trim
  }
} finally {
  if ($burn) { Stop-Process -Id $burn.Id -Force -ErrorAction SilentlyContinue; Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -like '*cpu-load.py*' -or $_.ParentProcessId -eq $burn.Id } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } }
  try { $wd.Close(0) } catch {}
  try { if ($word.Documents.Count -eq 0) { $word.Quit() } } catch {}
  if ($wpidW) { Start-Sleep 2; Stop-Process -Id $wpidW -Force -ErrorAction SilentlyContinue }   # only the Word this script started, if it would not close
  if ($userClip) { Set-Clipboard -Value $userClip }
}
$rows | ConvertTo-Json | Set-Content (Join-Path $Work "word-probe-hold$Hold-load$Load-pre$Pre-m$Markers-r$Reoffer.json")
"Word pid: $(@(Get-Process WINWORD -ErrorAction SilentlyContinue).Id -join ',')" 
"`nHold $Hold ms, load $Load : dictation {0} of {1}; user clipboard pasted {2}; read after restore {3}"  -f @($rows | Where-Object Got -eq 'dictation').Count, $Reps, @($rows | Where-Object Got -eq 'USER CLIPBOARD').Count, @($rows | Where-Object Requests -match 'restored').Count
