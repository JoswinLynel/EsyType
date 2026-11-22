# Slow pasting programs, with and without a background program that reads the clipboard anonymously right after
# every change (-Reactor; clipboard-reactor.py). 'LatePaste' reads the clipboard once, late (a slow or starved
# program); EsyType must hand it the dictation, not count the background read as the paste, and put the user's
# clipboard back, every time. 'SlowPaste' and 'DeferredPaste' read twice with a long gap: reported, not required.
# Test build with its own settings and Ctrl+F8; keys only while the test's own window is in front.
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio",
  [int]$Reps = 3,
  [string[]]$Cases = @('TextBox:0', 'LatePaste:600', 'LatePaste:1500', 'SlowPaste:600', 'DeferredPaste:600', 'CopyDuring:0'),
  [switch]$Reactor
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uia.ps1')
$Cases = @($Cases | ForEach-Object { $_ -split "," })   # also when passed as one string through -File
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Sl {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-52} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }
$lad = Join-Path $Work 'localappdata-slow'; $data = Join-Path $lad 'EsyAI\EsyType'
New-Item -ItemType Directory -Force $data | Out-Null; Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; undo_shortcut = 'Ctrl+F9'; paste_last_shortcut = 'Ctrl+F10'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false } |
  ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
$db = Join-Path $data 'esytype.db'; $py = Join-Path $PSScriptRoot 'history-db.py'; $trace = Join-Path $Work 'slowpaste-trace.txt'
$current = Join-Path $Work 'current.f32'; Copy-Item (Join-Path $Audio '6930_5s.f32') $current -Force
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current
$userClip = Get-Clipboard -Raw
$expected = 'Congratulations were poured in upon the princess everywhere during her journey.'
# ConvertFrom-Json (PowerShell 5.1) passes a JSON list down the pipe as one item: assign first, then enumerate.
function Rows { if (-not (Test-Path $db)) { return @() }; $r = & python -I $py rows $db | ConvertFrom-Json; @($r | Where-Object { $_ }) }
function Front($w) {
  for ($k = 0; $k -lt 8 -and [Sl]::GetForegroundWindow() -ne $w.H; $k++) {
    $fgPid = 0; [void][Sl]::GetWindowThreadProcessId([Sl]::GetForegroundWindow(), [ref]$fgPid)
    if ($k -gt 0 -and $fgPid -in @($w.P.Id, $app.Id)) { [Sl]::Down(0x12); [Sl]::Up(0x12) }   # only while a test window is in front
    [Sl]::SetForegroundWindow($w.H) | Out-Null; Start-Sleep -Milliseconds 400
  }
  if ([Sl]::GetForegroundWindow() -ne $w.H) { throw 'The test window is not in front; no keys sent.' }
}
function Read($w) { for ($i = 0; $i -lt 40; $i++) { try { return ([IO.File]::ReadAllText($w.F)).Trim() } catch { Start-Sleep -Milliseconds 25 } } }

$reactorLog = Join-Path $Work 'reactor-log.txt'; Set-Content $reactorLog '' -Encoding ascii; $react = $null
if ($Reactor) { $react = Start-Process python -ArgumentList '-I', "`"$(Join-Path $PSScriptRoot 'clipboard-reactor.py')`"", 180, 900, "`"$reactorLog`"" -PassThru -NoNewWindow }
$app = Start-Process $Exe -ArgumentList '--minimized' -PassThru -RedirectStandardError $trace; Start-Sleep 9
$win = $null
try {
  foreach ($case in $Cases) {
    $kind, $delay = $case -split ':'
    $title = "esytype-slow-$kind-$delay"; $f = Join-Path $Work "$title.txt"; Set-Content $f '' -Encoding ascii
    $p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$f`"", '-Kind', $(if ($kind -eq 'CopyDuring') { 'TextBox' } else { $kind }), '-Title', $title, '-Delay', $delay -PassThru
    Start-Sleep 3; $win = [pscustomobject]@{ P = $p; H = [Sl]::FindWindow([NullString]::Value, $title); F = $f }
    for ($i = 1; $i -le $Reps; $i++) {
      Set-Content "$f.clear" ''; Start-Sleep 0.5
      $marker = "USER-CLIPBOARD-$(Get-Random)"; Set-Clipboard -Value $marker
      Front $win; $n = (Rows).Count
      try { [Sl]::Down(0x11); [Sl]::Down(0x77); Start-Sleep -Milliseconds 900 } finally { [Sl]::Up(0x77); [Sl]::Up(0x11) }
      for ($k = 0; $k -lt 240 -and (Rows).Count -eq $n; $k++) { Start-Sleep -Milliseconds 250 }
      if ($kind -eq 'CopyDuring') {
        # The user copies something while EsyType still holds the dictation: their new copy must stay.
        $newer = "COPIED-DURING-THE-PASTE-$(Get-Random)"; Set-Clipboard -Value $newer; Start-Sleep 4
        $got = Read $win
        Check "Copy during the paste, run $($i): text inserted; your new copy kept" ($got -eq $expected -and (Get-Clipboard -Raw) -eq $newer) "clipboard='$(Get-Clipboard -Raw)'"
        continue
      }
      Start-Sleep -Milliseconds ([int]$delay + 1200)
      $got = Read $win; $e = (Rows)[-1]
      $name = "$kind $delay ms$(if ($Reactor) { ' +reader' }), run $i"
      if ($kind -in 'SlowPaste', 'DeferredPaste') {
        "{0,-52} INFO  got '{1}', outcome {2}, clipboard back: {3}" -f $name, $got, $e.outcome, (Wait-Clipboard $marker)
        continue
      }
      Check "$name`: dictation inserted, not the clipboard" ($got -eq $expected) "'$got'"
      Check "$name`: outcome pasted; your clipboard back" ($e.outcome -eq 'pasted' -and (Wait-Clipboard $marker)) "outcome=$($e.outcome) clipboard='$(Get-Clipboard -Raw)'"
    }
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; $win = $null
  }
} catch {
  "STOPPED: $($_.Exception.Message)"
} finally {
  if ($win) { Stop-Process -Id $win.P.Id -Force -ErrorAction SilentlyContinue }
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
  if ($react) { Stop-Process -Id $react.Id -Force -ErrorAction SilentlyContinue }
  [Sl]::Up(0x77); [Sl]::Up(0x11)
  if ($userClip) { Set-Clipboard -Value $userClip }
}
Get-Content $trace | Where-Object { $_ -match 'taken|refused|inserted' }
if ($Reactor) { "background reader: $(@(Get-Content $reactorLog | Where-Object { $_ -match 'Congratulations' }).Count) reads got the dictation" }
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'slowpaste-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
