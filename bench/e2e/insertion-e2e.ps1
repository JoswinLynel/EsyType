# Insertion outcomes: EsyType must report "pasted" only when the target program actually took the text, put the
# user's clipboard back every time, warn and offer Copy when the text was not taken, and record the true outcome
# (pasted, typed, copied, failed) in History. Then the real apps: Notepad (a new scratch tab), Word (a new
# document, closed unsaved), Chrome and ChatGPT (separate test profile; the ChatGPT message is never sent).
# Uses the e2e test build with its own settings and Ctrl+F8. Keys are sent only while the intended window is in
# front. Nothing the test did not open is closed or changed; your clipboard text is put back at the end.
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio",
  [string[]]$Apps = @('notepad', 'word', 'chrome', 'chatgpt')
)
$ErrorActionPreference = 'Stop'
$Apps = @($Apps | ForEach-Object { $_ -split ',' })   # also when passed as one string through -File
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public static class I {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  public static string Title(IntPtr h) { var b = new StringBuilder(512); GetWindowText(h, b, 512); return b.ToString(); }
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
}
"@
$UA = [System.Windows.Automation.AutomationElement]; $CT = [System.Windows.Automation.ControlType]
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-60} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

$lad = Join-Path $Work 'localappdata-ins'; $data = Join-Path $lad 'EsyAI\EsyType'
New-Item -ItemType Directory -Force $data | Out-Null; Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false } | ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
$db = Join-Path $data 'esytype.db'; $py = Join-Path $PSScriptRoot 'history-db.py'; $trace = Join-Path $Work 'insertion-trace.txt'
$current = Join-Path $Work 'current.f32'; Copy-Item (Join-Path $Audio '6930_5s.f32') $current -Force
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current
$userClip = Get-Clipboard -Raw
$expected = 'Congratulations were poured in upon the princess everywhere during her journey.'

function Last { $r = & python -I $py rows $db | ConvertFrom-Json; $r | Select-Object -Last 1 }
function Count { if (-not (Test-Path $db)) { return 0 }; $r = & python -I $py rows $db | ConvertFrom-Json; @($r | Where-Object { $_ }).Count }
function Front($h) {
  for ($k = 0; $k -lt 8 -and [I]::GetForegroundWindow() -ne $h; $k++) {
    $fgPid = 0; [void][I]::GetWindowThreadProcessId([I]::GetForegroundWindow(), [ref]$fgPid)
    $ours = @($own, $none, $other | Where-Object { $_ } | ForEach-Object { $_.P.Id }) + $app.Id + $script:testPids
    if ($k -gt 0 -and $fgPid -in $ours) { [I]::Down(0x12); [I]::Up(0x12) }   # Alt tap lets Windows hand over focus; only while a test window is in front
    [void](New-Object -ComObject WScript.Shell).AppActivate([I]::Title($h)); [I]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400
  }
  if ([I]::GetForegroundWindow() -ne $h) { throw "'$([I]::Title($h))' is not in front; no keys sent." }
}
# Holds Ctrl+F8 with $h in front, optionally running $during while EsyType transcribes, then waits for the result.
function Dictate($h, [scriptblock]$during) {
  Front $h
  $n = Count
  try { [I]::Down(0x11); [I]::Down(0x77); Start-Sleep -Milliseconds 900 } finally { [I]::Up(0x77); [I]::Up(0x11) }
  if ($during) { & $during }
  # Finished when its History entry exists: that is written after insertion, the clipboard and the pill are done.
  for ($i = 0; $i -lt 240 -and (Count) -eq $n; $i++) { Start-Sleep -Milliseconds 250 }
  Start-Sleep -Milliseconds 500
}
function OwnWindow($kind, $title) {
  $f = Join-Path $Work "$title.txt"; Set-Content $f '' -Encoding ascii
  $p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$f`"", '-Kind', $kind, '-Title', $title -PassThru
  Start-Sleep 3
  [pscustomobject]@{ P = $p; H = [I]::FindWindow([NullString]::Value, $title); F = $f }
}
function Read($w) { for ($i = 0; $i -lt 40; $i++) { try { return ([IO.File]::ReadAllText($w.F)).Trim() } catch { Start-Sleep -Milliseconds 25 } } }
# The test build's own pill (an EsyType you have open has one with the same title).
function Pill { Get-TopWindows 'EsyType recording' @($app.Id) | Select-Object -First 1 }
function Saved($name, $outcome, $got) {
  $e = Last
  Check "$name`: History outcome '$outcome'" ($e.outcome -eq $outcome -and $e.final_text -eq $expected) "outcome=$($e.outcome)"
  Check "$name`: your clipboard put back" (Wait-Clipboard $script:marker) "clipboard='$(Get-Clipboard -Raw)'"
}
function Mark { $script:marker = "USER-CLIPBOARD-$(Get-Random)"; Set-Clipboard -Value $script:marker }

$app = Start-Process $Exe -ArgumentList '--minimized' -PassThru -RedirectStandardError $trace; Start-Sleep 9
$own = $null; $none = $null; $other = $null; $script:testPids = @()
try {
  # --- 1. Confirmed paste ------------------------------------------------------------------------------------
  $own = OwnWindow 'RichTextBox' 'esytype-e2e-own'
  Mark; Dictate $own.H
  Check 'Own window: text inserted' ((Read $own) -eq $expected) "'$(Read $own)'"
  Saved 'Own window' 'pasted'
  Check 'Own window: target confirmed it took the text' ((Get-Content $trace -Raw) -match 'text taken by the target') ''

  # --- 2. Program that does not take the text: warning, Copy offered, clipboard untouched ---------------------
  $none = OwnWindow 'None' 'esytype-e2e-none'
  Mark; Dictate $none.H
  $p = Pill
  $copy = if ($p) { $p.FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition($UA::NameProperty, 'Copy'))) }
  $label = if ($p) { ($p.FindAll('Descendants', (New-Object System.Windows.Automation.PropertyCondition($UA::ControlTypeProperty, $CT::Text))) | ForEach-Object { $_.Current.Name }) -join ' ' }
  Check 'No text field: pill warns "Not typed" and offers Copy' ($p -and $copy -and $label -match 'Not typed') "'$label'"
  Saved 'No text field' 'failed'
  if ($copy) { $copy.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep 1 }
  Check 'No text field: Copy puts the dictation on the clipboard' ((Get-Clipboard -Raw) -eq $expected) "'$(Get-Clipboard -Raw)'"

  # --- 3. Typed: clipboard holds more than EsyType will copy, so it types and leaves the clipboard alone -------
  $big = 'B' * 34000000   # 68 MB as Unicode, above the 64 MB snapshot limit
  [System.Windows.Forms.Clipboard]::SetText($big); $script:marker = $null
  $before = (Read $own).Length
  Dictate $own.H
  Check 'Large clipboard: text typed instead' ((Read $own).Substring($before).Trim() -eq $expected) ''
  $e = Last; $len = ([System.Windows.Forms.Clipboard]::GetText()).Length
  Check 'Large clipboard: History outcome typed; clipboard untouched' ($e.outcome -eq 'typed' -and $len -eq $big.Length) "outcome=$($e.outcome) clipboard length=$len"
  $big = $null; [GC]::Collect()

  # --- 4. Focus moves away during transcription: nothing typed, text copied --------------------------------
  $other = OwnWindow 'TextBox' 'esytype-e2e-other'
  Mark; $before = Read $own
  Dictate $own.H { Front $other.H }
  Check 'Window changed: nothing typed in either window' ((Read $own) -eq $before -and (Read $other) -eq '') ''
  $e = Last
  Check 'Window changed: History outcome copied, text on clipboard' ($e.outcome -eq 'copied' -and (Get-Clipboard -Raw) -eq $expected) "outcome=$($e.outcome) clipboard='$(Get-Clipboard -Raw)'"

  # --- 5. Real applications -----------------------------------------------------------------------------------
  if ('word' -in $Apps) {
    $word = New-Object -ComObject Word.Application; $word.Visible = $true
    $wd = $word.Documents.Add(); Start-Sleep 3; $wd.Activate(); $word.Activate(); $wh = [IntPtr]$wd.ActiveWindow.Hwnd
    $wpid = 0; [void][I]::GetWindowThreadProcessId($wh, [ref]$wpid); $script:testPids += $wpid   # the Word instance this test started
    Mark; Dictate $wh
    Check 'Word: text inserted' ($wd.Content.Text.Trim() -eq $expected) "'$($wd.Content.Text.Trim())'"
    Saved 'Word' 'pasted'
    $wd.Close(0); $wd = $null; if ($word.Documents.Count -eq 0) { $word.Quit() }
  }
  if ('chrome' -in $Apps -or 'chatgpt' -in $Apps) {
    $prof = Join-Path $Work 'chrome-profile'; $chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
    # Only Chrome processes started with this test's own profile are closed.
    Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Start-Sleep 1
    function ChromeWindow($titleLike, $url) {
      Start-Process $chrome -ArgumentList "--user-data-dir=`"$prof`"", '--force-renderer-accessibility', '--no-first-run', '--no-default-browser-check', '--new-window', $url | Out-Null
      # Only a window owned by a Chrome process started with this test's own profile. Matching by title alone picked
      # the owner's ChatGPT desktop app on 19 Nov 2026 and pasted test text into its message box.
      for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 500
        $mine = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" } | ForEach-Object { [int]$_.ProcessId })
        $e = Get-TopWindows $titleLike $mine | Select-Object -First 1
        if ($e) { $script:testPids += $e.Current.ProcessId; return $e }
      }
    }
  }
  if ('chrome' -in $Apps) {
    $page = Join-Path $Work 'chrome-insert-target.html'
    Set-Content $page '<!doctype html><title>esytype-insert-chrome</title><textarea aria-label=esytype-insert-area autofocus style="width:90vw;height:60vh;font:16px sans-serif"></textarea>' -Encoding ascii
    $cw = ChromeWindow 'esytype-insert-chrome*' ([Uri]$page).AbsoluteUri
    Start-Sleep 1; Mark; Dictate ([IntPtr]$cw.Current.NativeWindowHandle)
    $area = $null; for ($i = 0; $i -lt 20 -and -not $area; $i++) { $area = $cw.FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition($UA::NameProperty, 'esytype-insert-area'))); if (-not $area) { Start-Sleep -Milliseconds 500 } }
    $got = ([string]$area.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value).Trim()
    Check 'Chrome: text inserted' ($got -eq $expected) "'$got'"
    Saved 'Chrome' 'pasted'
  }
  if ('chatgpt' -in $Apps) {
    # Logged-out ChatGPT in the test profile. The text goes into the message box and is NEVER sent.
    $gw = ChromeWindow '*ChatGPT*' 'https://chatgpt.com/'
    if (-not $gw) { Check 'ChatGPT: page opened' $false 'window not found (network, consent page or sign-in wall)' }
    else {
      Start-Sleep 6; Mark; Dictate ([IntPtr]$gw.Current.NativeWindowHandle)
      $box = $gw.FindAll('Descendants', [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { $_.Current.Name -like '*princess*' -or ($_.Current.ControlType -in $CT::Edit, $CT::Document -and $(try { $_.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(500) -like '*princess*' } catch { $false })) } | Select-Object -First 1
      $png = Join-Path $Work 'chatgpt-insert.png'
      $b = New-Object System.Drawing.Bitmap ([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width), ([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
      [System.Drawing.Graphics]::FromImage($b).CopyFromScreen(0, 0, 0, 0, $b.Size); $b.Save($png)
      Check 'ChatGPT: text in the message box (not sent)' ([bool]$box) "screenshot $png"
      Saved 'ChatGPT' 'pasted'
    }
  }
  if ('notepad' -in $Apps) {
    $nf = Join-Path $Work ("esytype-insert-{0:HHmmss}.txt" -f (Get-Date)); Set-Content $nf '' -Encoding ascii; $nn = Split-Path $nf -Leaf
    Start-Process notepad.exe -ArgumentList "`"$nf`"" | Out-Null
    $w = $null; for ($i = 0; $i -lt 40 -and -not $w; $i++) { Start-Sleep -Milliseconds 100; $w = Get-TopWindows "$nn*" | Select-Object -First 1 }
    $nh = [IntPtr]$w.Current.NativeWindowHandle
    Mark; Front $nh
    if (-not ([I]::Title($nh) -like "$nn*")) { throw 'Our Notepad tab is not the active tab; no keys sent.' }
    Dictate $nh   # immediately: the case that failed before
    $doc = $w.FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition($UA::ControlTypeProperty, $CT::Document)))
    $got = ([string]$doc.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(-1)).Trim()
    Check 'Notepad (just-opened tab): text inserted' ($got -eq $expected) "'$got'"
    Saved 'Notepad' 'pasted'
    "   Notepad scratch tab '$nn' left open (unsaved test file in $Work)."
  }
} finally {
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
  foreach ($w in $own, $none, $other) { if ($w) { Stop-Process -Id $w.P.Id -Force -ErrorAction SilentlyContinue } }
  if ($wd) { try { $wd.Close(0); if ($word.Documents.Count -eq 0) { $word.Quit() } } catch {} }   # the test's own Word document only
  [I]::Up(0x77); [I]::Up(0x11); [I]::Up(0x12)
  if ($userClip) { Set-Clipboard -Value $userClip }
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'insertion-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
