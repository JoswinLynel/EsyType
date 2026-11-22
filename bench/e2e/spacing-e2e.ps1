# Spacing before dictated text: text typed by hand ending in a word, a full stop, a comma, a space or a line break;
# an empty box; after EsyType's own dictation; consecutive dictations; an app whose text cannot be read (no space
# unless continuing EsyType's own dictation: never a doubled space); then Notepad (a test file tab), Word (a new
# document, closed unsaved) and Chrome (test profile). Typing goes only into windows this test opened.
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio",
  [string[]]$Apps = @('notepad', 'word', 'chrome')
)
$ErrorActionPreference = 'Stop'
$Apps = @($Apps | ForEach-Object { $_ -split ',' })
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public static class Sp2 {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  public static string Title(IntPtr h) { var b = new StringBuilder(512); GetWindowText(h, b, 512); return b.ToString(); }
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-58} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }
$lad = Join-Path $Work 'localappdata-spacing'; $data = Join-Path $lad 'EsyAI\EsyType'
New-Item -ItemType Directory -Force $data | Out-Null; Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; undo_shortcut = 'Ctrl+F9'; paste_last_shortcut = 'Ctrl+F10'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false } |
  ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
$db = Join-Path $data 'esytype.db'; $py = Join-Path $PSScriptRoot 'history-db.py'; $trace = Join-Path $Work 'spacing-trace.txt'
$current = Join-Path $Work 'current.f32'; Copy-Item (Join-Path $Audio '6930_5s.f32') $current -Force
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current
$userClip = Get-Clipboard -Raw
$E = 'Congratulations were poured in upon the princess everywhere during her journey.'
$script:testPids = @()
# ConvertFrom-Json (PowerShell 5.1) passes a JSON list down the pipe as one item: assign first, then enumerate.
function Count { if (-not (Test-Path $db)) { return 0 }; $r = & python -I $py rows $db | ConvertFrom-Json; @($r | Where-Object { $_ }).Count }
function Front($h) {
  for ($k = 0; $k -lt 8 -and [Sp2]::GetForegroundWindow() -ne $h; $k++) {
    $fgPid = 0; [void][Sp2]::GetWindowThreadProcessId([Sp2]::GetForegroundWindow(), [ref]$fgPid)
    if ($k -gt 0 -and $fgPid -in (@($app.Id) + $script:testPids)) { [Sp2]::Down(0x12); [Sp2]::Up(0x12) }   # only while a test window is in front
    [void](New-Object -ComObject WScript.Shell).AppActivate([Sp2]::Title($h)); [Sp2]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400
  }
  if ([Sp2]::GetForegroundWindow() -ne $h) {
    $fg = 0; [void][Sp2]::GetWindowThreadProcessId([Sp2]::GetForegroundWindow(), [ref]$fg)
    throw "'$([Sp2]::Title($h))' is not in front (front: $((Get-Process -Id $fg -ErrorAction SilentlyContinue).ProcessName)); no keys sent."
  }
}
function Send-Text($h, $keys) { if ($keys) { Front $h; [System.Windows.Forms.SendKeys]::SendWait($keys); Start-Sleep -Milliseconds 400 } }
function Dictate($h) {
  Front $h; $n = Count
  try { [Sp2]::Down(0x11); [Sp2]::Down(0x77); Start-Sleep -Milliseconds 900 } finally { [Sp2]::Up(0x77); [Sp2]::Up(0x11) }
  for ($i = 0; $i -lt 240 -and (Count) -eq $n; $i++) { Start-Sleep -Milliseconds 250 }
  [void](Wait-Clipboard $script:marker)   # the paste is fully finished
}
function Own($kind) {
  $title = "esytype-spacing-$kind"; $f = Join-Path $Work "$title.txt"; Set-Content $f '' -Encoding ascii
  $p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$f`"", '-Kind', $kind, '-Title', $title -PassThru
  Start-Sleep 3; $script:testPids += $p.Id
  [pscustomobject]@{ P = $p; H = [Sp2]::FindWindow([NullString]::Value, $title); F = $f }
}
function Read($w) { Start-Sleep -Milliseconds 300; for ($i = 0; $i -lt 40; $i++) { try { return [IO.File]::ReadAllText($w.F) } catch { Start-Sleep -Milliseconds 25 } } }
function Clear-Box($w) { Set-Content "$($w.F).clear" ''; Start-Sleep 0.6 }
function Show($s) { "'" + ($s -replace "`r`n|`r|`n", '\n') + "'" }

$script:marker = "USER-CLIPBOARD-$(Get-Random)"; Set-Clipboard -Value $script:marker
$app = Start-Process $Exe -ArgumentList '--minimized' -PassThru -RedirectStandardError $trace; Start-Sleep 9
$own = $null; $opq = $null
try {
  # --- 1. A text box whose text EsyType can read --------------------------------------------------------------
  $own = Own 'TextBox'
  $cases = @(
    @('typed word', 'Shopping list', "Shopping list $E"),
    @('typed full stop', 'Done.', "Done. $E"),
    @('typed comma', 'Well,', "Well, $E"),
    @('typed space', 'Note: ', "Note: $E"),
    @('typed line break', 'Line one{ENTER}', "Line one`r`n$E"),
    @('empty box', '', $E)
  )
  foreach ($c in $cases) {
    Clear-Box $own; Send-Text $own.H $c[1]; Dictate $own.H
    $got = Read $own
    Check "Text box, $($c[0]): one space where needed" ($got -eq $c[2]) (Show $got)
  }
  Clear-Box $own; Dictate $own.H; Dictate $own.H
  $got = Read $own; Check 'Text box, two dictations in a row: one space between' ($got -eq "$E $E") (Show $got)
  Clear-Box $own; Dictate $own.H; Send-Text $own.H ' '; Dictate $own.H
  $got = Read $own; Check 'Text box, space typed after a dictation: not doubled' ($got -eq "$E $E") (Show $got)
  Stop-Process -Id $own.P.Id -Force; $own = $null

  # --- 2. An app whose text cannot be read ---------------------------------------------------------------------
  $opq = Own 'Opaque'
  Send-Text $opq.H 'Shopping list'; Dictate $opq.H
  $got = Read $opq; Check 'Unreadable app, after typed text: no space added (cannot know)' ($got -eq "Shopping list$E") (Show $got)
  Dictate $opq.H
  $got = Read $opq; Check 'Unreadable app, after its own dictation: one space' ($got -eq "Shopping list$E $E") (Show $got)
  Send-Text $opq.H ' '; Dictate $opq.H
  $got = Read $opq; Check 'Unreadable app, space typed after a dictation: not doubled' ($got -eq "Shopping list$E $E $E") (Show $got)
  # $opq stays open until the real apps have started: closing it would hand the foreground back to another program,
  # and Word (started through automation) is then not allowed to come to the front.
  $read = @(Get-Content $trace | Where-Object { $_ -match 'before the cursor' })
  Check 'Trace: unreadable app reported as "cannot read"' (@(($read | Select-Object -Last 3) -match "cannot read").Count -eq 3) (($read | Select-Object -Last 3) -join " / ")

  # --- 3. Real apps -----------------------------------------------------------------------------------------------
  if ('notepad' -in $Apps) {
    $nf = Join-Path $Work ("esytype-spacing-{0:HHmmss}.txt" -f (Get-Date)); Set-Content $nf '' -Encoding ascii; $nn = Split-Path $nf -Leaf
    Start-Process notepad.exe -ArgumentList "`"$nf`"" | Out-Null
    $w = $null; for ($i = 0; $i -lt 40 -and -not $w; $i++) { Start-Sleep -Milliseconds 100; $w = Get-TopWindows "$nn*" | Select-Object -First 1 }
    $nh = [IntPtr]$w.Current.NativeWindowHandle; $script:testPids += $w.Current.ProcessId
    Front $nh; if (-not ([Sp2]::Title($nh) -like "$nn*")) { throw 'Our Notepad tab is not the active tab; no keys sent.' }
    Send-Text $nh 'Shopping list'; Dictate $nh; Dictate $nh
    $doc = $w.FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition($UA::ControlTypeProperty, $CT::Document)))
    $got = ([string]$doc.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(-1)).TrimEnd()
    Check 'Notepad: typed text, then two dictations' ($got -eq "Shopping list $E $E") (Show $got)
    "   Notepad tab '$nn' left open (unsaved test file in $Work)."
  }
  if ('word' -in $Apps) {
    if (Get-Process WINWORD -ErrorAction SilentlyContinue) { Check 'Word: not run (Word is open; the test starts its own)' $false '' }
    else {
      if ($opq) { Front $opq.H }   # a test window in front, so Word may take the foreground
      $word = New-Object -ComObject Word.Application; $word.Visible = $true
      $wd = $word.Documents.Add(); Start-Sleep 3; $wd.Activate(); $word.Activate(); $wh = [IntPtr]$wd.ActiveWindow.Hwnd
      $wpid = 0; [void][Sp2]::GetWindowThreadProcessId($wh, [ref]$wpid); $script:testPids += $wpid
      Send-Text $wh 'Shopping list'; Dictate $wh; Dictate $wh
      $got = $null; for ($k = 0; $k -lt 10 -and $null -eq $got; $k++) { try { $got = $wd.Content.Text.TrimEnd() } catch { Start-Sleep 0.5 } }
      Check 'Word: typed text, then two dictations' ($got -eq "Shopping list $E $E") (Show $got)
    }
  }
  if ('chrome' -in $Apps) {
    $prof = Join-Path $Work 'chrome-profile'; $chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
    Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Start-Sleep 1
    $page = Join-Path $Work 'chrome-spacing-target.html'
    Set-Content $page '<!doctype html><title>esytype-spacing-chrome</title><textarea aria-label=esytype-spacing-area autofocus style="width:90vw;height:60vh;font:16px sans-serif"></textarea>' -Encoding ascii
    Start-Process $chrome -ArgumentList "--user-data-dir=`"$prof`"", '--force-renderer-accessibility', '--no-first-run', '--no-default-browser-check', '--new-window', ([Uri]$page).AbsoluteUri | Out-Null
    $cw = $null
    for ($i = 0; $i -lt 40 -and -not $cw; $i++) {
      Start-Sleep -Milliseconds 500
      $mine = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" } | ForEach-Object { [int]$_.ProcessId })
      $cw = Get-TopWindows 'esytype-spacing-chrome*' $mine | Select-Object -First 1   # only this test's own Chrome
    }
    $ch = [IntPtr]$cw.Current.NativeWindowHandle; $script:testPids += $cw.Current.ProcessId; Start-Sleep 1
    Send-Text $ch 'Shopping list'; Dictate $ch; Dictate $ch
    $area = $null; for ($i = 0; $i -lt 20 -and -not $area; $i++) { $area = $cw.FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition($UA::NameProperty, 'esytype-spacing-area'))); if (-not $area) { Start-Sleep -Milliseconds 500 } }
    $got = ([string]$area.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value).TrimEnd()
    Check 'Chrome: typed text, then two dictations' ($got -eq "Shopping list $E $E") (Show $got)
    Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  }
} catch {
  "STOPPED: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
} finally {
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
  foreach ($w in $own, $opq) { if ($w) { Stop-Process -Id $w.P.Id -Force -ErrorAction SilentlyContinue } }
  if ($wd) { try { $wd.Close(0); if ($word.Documents.Count -eq 0) { $word.Quit() } } catch {}; if ($wpid) { Start-Sleep 2; Stop-Process -Id $wpid -Force -ErrorAction SilentlyContinue } }   # the test's own Word only
  [Sp2]::Up(0x77); [Sp2]::Up(0x11); [Sp2]::Up(0x12)
  if ($userClip) { Set-Clipboard -Value $userClip }
}
Get-Content $trace | Where-Object { $_ -match 'before the cursor|inserted' }
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'spacing-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
