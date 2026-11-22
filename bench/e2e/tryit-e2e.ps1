# Dictation into EsyType's own window: the "Try it" box on the Dictation page (and, once built, the Scratchpad).
# The test build's main window is brought forward and its text box focused; speech is injected; the box's text is
# read back through UI Automation. Types only into the test build's own window.
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio",
  [switch]$Toggle
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Tr {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-58} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }
$lad = Join-Path $Work 'localappdata-tryit'; $data = Join-Path $lad 'EsyAI\EsyType'
New-Item -ItemType Directory -Force $data | Out-Null
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; undo_shortcut = 'Ctrl+F9'; paste_last_shortcut = 'Ctrl+F10'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false } |
  ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
Copy-Item (Join-Path $Audio '6930_5s.f32') (Join-Path $Work 'current.f32') -Force
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = Join-Path $Work 'current.f32'
$userClip = Get-Clipboard -Raw; $marker = "USER-CLIPBOARD-$(Get-Random)"; Set-Clipboard -Value $marker
$expected = 'Congratulations were poured in upon the princess everywhere during her journey.'
$trace = Join-Path $Work 'tryit-trace.txt'
$app = Start-Process $Exe -PassThru -RedirectStandardError $trace; Start-Sleep 9
try {
  $root = Get-AppWindow $app.Id 'EsyType'; $h = [IntPtr]$root.Current.NativeWindowHandle
  $box = Find-El $root 'Practice area' $CT::Edit
  for ($k = 0; $k -lt 6 -and [Tr]::GetForegroundWindow() -ne $h; $k++) { [Tr]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400 }
  if ([Tr]::GetForegroundWindow() -ne $h) { throw 'The test build window is not in front; no keys sent.' }
  $box.SetFocus(); Start-Sleep 0.5
  if ($Toggle) {
    # Ctrl+F7 to start, again to stop
    foreach ($i in 1, 2) { try { [Tr]::Down(0x11); [Tr]::Down(0x76); Start-Sleep -Milliseconds 80 } finally { [Tr]::Up(0x76); [Tr]::Up(0x11) }; Start-Sleep -Milliseconds 900 }
  } else {
    try { [Tr]::Down(0x11); [Tr]::Down(0x77); Start-Sleep -Milliseconds 900 } finally { [Tr]::Up(0x77); [Tr]::Up(0x11) }
  }
  Start-Sleep 6
  $got = ([string]$box.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value).Trim()
  Check 'Try it box receives the dictation' ($got -eq $expected) "'$got'"
  Check 'Clipboard untouched' (Wait-Clipboard $marker) ''
} catch {
  "STOPPED: $($_.Exception.Message)"
} finally {
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
  [Tr]::Up(0x77); [Tr]::Up(0x11)
  if ($userClip) { Set-Clipboard -Value $userClip }
}
Get-Content $trace | Where-Object { $_ -match '^\[' -and $_ -notmatch 'HotKey' }
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
