# History with real applications: injected speech is dictated into Notepad (a new scratch tab), Word (a new
# document, closed unsaved) and Chrome (a separate test profile, local text area), then the History entries are
# checked: the text matches what arrived, and only the executable name is recorded, never a window title.
# Uses the e2e test build with its own settings and Ctrl+F8. Keys are sent only while the intended window is in
# front. It never closes anything it did not open.
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$ModelSource = "D:\EsyAI\EsyType\models\ggml-base.en-q5_1.bin",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio"
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public static class R {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  public static string Title(IntPtr h) { var b = new StringBuilder(512); GetWindowText(h, b, 512); return b.ToString(); }
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
}
"@
$UA = [System.Windows.Automation.AutomationElement]; $CT = [System.Windows.Automation.ControlType]
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-58} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

$lad = Join-Path $Work 'localappdata-apps'; $data = Join-Path $lad 'EsyAI\EsyType'; $models = Join-Path $Work 'restart-models'
New-Item -ItemType Directory -Force $data, $models | Out-Null
if (-not (Test-Path (Join-Path $models (Split-Path $ModelSource -Leaf)))) { Copy-Item $ModelSource $models }
Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; models_dir = $models; start_with_windows = $false } | ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
$db = Join-Path $data 'esytype.db'; $py = Join-Path $PSScriptRoot 'history-db.py'
$current = Join-Path $Work 'current.f32'; Copy-Item (Join-Path $Audio '6930_10s.f32') $current -Force
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current
$userClip = Get-Clipboard -Raw

function Dictate($h) {
  for ($k = 0; $k -lt 5 -and [R]::GetForegroundWindow() -ne $h; $k++) { [void](New-Object -ComObject WScript.Shell).AppActivate([R]::Title($h)); Start-Sleep -Milliseconds 300; [R]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 500 }
  if ([R]::GetForegroundWindow() -ne $h) { throw "Target '$([R]::Title($h))' is not in front; no keys sent." }
  try { [R]::Down(0x11); [R]::Down(0x77); Start-Sleep -Milliseconds 900 } finally { [R]::Up(0x77); [R]::Up(0x11) }
  Start-Sleep 5   # transcription and insertion of a 10 s clip, plus the history save
}
function Last { $r = & python -I $py rows $db | ConvertFrom-Json; $r | Select-Object -Last 1 }   # PowerShell 5.1 returns a JSON array as one object
function Report($name, $arrived, $exe, $title) {
  $e = Last
  Check "$name`: text arrived and was saved identically" ($arrived.Length -gt 20 -and $e.final_text -eq $arrived) "'$($e.final_text)'"
  Check "$name`: program recorded as $exe" ($e.app -eq $exe) "app=$($e.app)"
  $json = $e | ConvertTo-Json -Compress
  Check "$name`: window title not stored anywhere" (-not $title -or $json -notlike "*$title*") "title '$title'"
}

$app = Start-Process $Exe -ArgumentList '--minimized' -PassThru -RedirectStandardError (Join-Path $Work 'history-apps-trace.txt'); Start-Sleep 9
try {
  # Notepad: a new uniquely named scratch file, opened as its own tab
  $nf = Join-Path $Work ("esytype-history-{0:yyyyMMdd-HHmmss}.txt" -f (Get-Date)); Set-Content $nf '' -Encoding ascii; $nn = Split-Path $nf -Leaf
  Start-Process notepad.exe -ArgumentList "`"$nf`"" | Out-Null; Start-Sleep 3
  $nw = Get-TopWindows "*$nn*" | Select-Object -First 1
  $nh = [IntPtr]$nw.Current.NativeWindowHandle
  [void](New-Object -ComObject WScript.Shell).AppActivate([R]::Title($nh)); Start-Sleep -Milliseconds 400
  $doc = $nw.FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition($UA::ControlTypeProperty, $CT::Document))); $doc.SetFocus()
  if (-not ([R]::Title($nh) -like "*$nn*")) { throw 'Our Notepad tab is not the active tab' }
  # Notepad with many restored tabs can leave keyboard focus on the tab strip; make sure the text area has it.
  for ($i = 0; $i -lt 10 -and $UA::FocusedElement.Current.ControlType -ne $CT::Document; $i++) { Start-Sleep -Milliseconds 300; $doc.SetFocus() }
  if ($UA::FocusedElement.Current.ControlType -ne $CT::Document) { throw 'Notepad text area does not have keyboard focus; no keys sent.' }
  # A tab opened seconds ago in a Notepad window with many restored tabs ignored the paste in 2 of 4 runs (19 Nov
  # 2026); the same tab accepted it once settled. Let it settle, as a person would.
  Start-Sleep 5
  Dictate $nh
  $got = ([string]$doc.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(-1)).Trim()
  Report 'Notepad' $got 'Notepad.exe' $nn
  "   Notepad tab '$nn' left open for you to inspect (scratch file in $Work)."

  # Word: its own new document
  $word = New-Object -ComObject Word.Application; $word.Visible = $true
  $wd = $word.Documents.Add(); Start-Sleep 3; $wd.Activate(); $word.Activate(); $wh = [IntPtr]$wd.ActiveWindow.Hwnd
  $wtitle = [R]::Title($wh)
  Dictate $wh
  Report 'Word' ($wd.Content.Text.Trim()) 'WINWORD.EXE' $wtitle
  $wd.Close(0); $wd = $null; if ($word.Documents.Count -eq 0) { $word.Quit() }

  # Chrome: separate test profile, local page
  $prof = Join-Path $Work 'chrome-profile'; $page = Join-Path $Work 'chrome-history-target.html'
  Set-Content $page '<!doctype html><title>esytype-history-chrome</title><textarea aria-label=esytype-history-area autofocus style="width:90vw;height:60vh;font:16px sans-serif"></textarea>' -Encoding ascii
  # Close test-profile windows from earlier runs (only Chrome processes started with this test's own profile).
  Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Start-Sleep 1
  Start-Process 'C:\Program Files\Google\Chrome\Application\chrome.exe' -ArgumentList "--user-data-dir=`"$prof`"", '--force-renderer-accessibility', '--no-first-run', '--no-default-browser-check', '--new-window', ([Uri]$page).AbsoluteUri | Out-Null
  $ch = [IntPtr]::Zero
  for ($i = 0; $i -lt 30 -and $ch -eq [IntPtr]::Zero; $i++) {
    Start-Sleep -Milliseconds 500
    $e = Get-TopWindows 'esytype-history-chrome*' | Select-Object -First 1
    if ($e) { $ch = [IntPtr]$e.Current.NativeWindowHandle }
  }
  if ($ch -eq [IntPtr]::Zero) { throw 'Chrome test window not found' }
  Start-Sleep 1; Dictate $ch
  $area = $null   # the page's text box, not the address bar; Chrome exposes page content a moment after asked
  for ($i = 0; $i -lt 20 -and -not $area; $i++) { $area = $UA::FromHandle($ch).FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition($UA::NameProperty, 'esytype-history-area'))); if (-not $area) { Start-Sleep -Milliseconds 500 } }
  Report 'Chrome' (([string]$area.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value).Trim()) 'chrome.exe' 'esytype-history-chrome'
  "   Chrome test-profile window left open; close it when done."
} finally {
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
  if ($wd) { try { $wd.Close(0); if ($word.Documents.Count -eq 0) { $word.Quit() } } catch {} }   # the test's own Word document only
  [R]::Up(0x77); [R]::Up(0x11)
  if ($userClip) { Set-Clipboard -Value $userClip }
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'history-apps-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
