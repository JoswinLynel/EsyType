# Real-microphone end-to-end test: plays recorded natural speech through the laptop speakers into the real
# microphone while the dictation shortcut is held, then checks what arrived in each target application.
# Keys are only sent while the intended window is in front. It opens its own Notepad tab, Word document and a
# Chrome window with a separate test profile; it never closes anything it did not open.
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",   # test build without ESYTYPE_TEST_AUDIO = real microphone
  [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$ModelSource = "D:\EsyAI\EsyType\models\ggml-base.en-q5_1.bin",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio",
  [string[]]$Targets = @('own', 'notepad', 'word', 'chrome', 'chatgpt', 'wrongwindow', 'missingmic'),
  # Inject the clip as the recording instead of playing it through the speakers (for testing insertion into apps).
  [switch]$Inject
)
$ErrorActionPreference = 'Stop'
# These older scripts use Ctrl+Space and look windows up by title: they need the installed EsyType closed.
if (Get-Process esytype -ErrorAction SilentlyContinue) { throw 'Quit your EsyType from its tray icon first: this test uses Ctrl+Space and the EsyType window title.' }
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public static class M {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  public static string Title(IntPtr h) { var b = new StringBuilder(512); GetWindowText(h, b, 512); return b.ToString(); }
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
}
"@
. (Join-Path $PSScriptRoot 'wer.ps1')
$clips = Get-Content (Join-Path $Audio 'clips.json') -Raw | ConvertFrom-Json
$speech = @($clips | Where-Object { $_.target_s -eq 15 })   # about 14 s of natural read speech, two speakers
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-50} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

# --- EsyType test build, real microphone, isolated settings (start with Windows off) ---
function StartApp($mic) {
  $lad = Join-Path $Work 'localappdata-mic'; $m = Join-Path $lad 'EsyAI\EsyType\models'
  New-Item -ItemType Directory -Force $m | Out-Null; Copy-Item $ModelSource $m -Force
  $micJson = if ($mic) { '"' + $mic + '"' } else { 'null' }
  Set-Content (Join-Path $lad 'EsyAI\EsyType\settings.json') ('{"model":"base","mic":' + $micJson + ',"threads":0,"ptt":"Ctrl+Space","toggle":"Ctrl+Shift+Space","start_with_windows":false}') -Encoding ascii
  $env:LOCALAPPDATA = $lad
  if ($Inject -and -not $mic) { $env:ESYTYPE_TEST_AUDIO = Join-Path $Work 'current.f32' } else { Remove-Item Env:ESYTYPE_TEST_AUDIO -ErrorAction SilentlyContinue }
  $script:app = Start-Process $Exe -PassThru -RedirectStandardError (Join-Path $Work 'realmic-trace.txt')
  Start-Sleep 9
  $script:pill = [M]::FindWindow([NullString]::Value, 'EsyType recording')
}
# Plays a WAV through the default speakers and waits for it to finish (ffplay's console chatter is discarded).
function Play($wav) { Start-Process ffplay -ArgumentList '-nodisp', '-autoexit', '-loglevel', 'quiet', "`"$wav`"" -WindowStyle Hidden -Wait }
function WaitIdle { $q = 0; $t = [Diagnostics.Stopwatch]::StartNew(); while ($q -lt 3 -and $t.Elapsed.TotalSeconds -lt 40) { if ([M]::IsWindowVisible($script:pill)) { $q = 0 } else { $q++ }; Start-Sleep -Milliseconds 100 } }
function Resources { $ids = @($app.Id) + @(Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $app.Id } | ForEach-Object ProcessId); $p = $ids | ForEach-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }; [pscustomobject]@{ Mb = ($p | Measure-Object WorkingSet64 -Sum).Sum / 1MB; Cpu = ($p | ForEach-Object { $_.TotalProcessorTime.TotalSeconds } | Measure-Object -Sum).Sum } }

# Holds Ctrl+Space while the clip plays from the speakers, only if $h is in front. Returns seconds from release to idle.
function Dictate($h, $clip) {
  if ([M]::GetForegroundWindow() -ne $h) { [void](New-Object -ComObject WScript.Shell).AppActivate([M]::Title($h)); Start-Sleep -Milliseconds 300; [M]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400 }
  if ([M]::GetForegroundWindow() -ne $h) { throw "Target '$([M]::Title($h))' is not in front; no keys sent." }
  $wav = Join-Path $Audio $clip.file
  if ($Inject) { Copy-Item ($wav -replace '\.wav$', '.f32') (Join-Path $Work 'current.f32') -Force }
  [M]::Down(0x11); [M]::Down(0x20); Start-Sleep -Milliseconds 500        # microphone opens before speech starts
  $r0 = Resources
  try { if ($Inject) { Start-Sleep -Milliseconds 800 } else { Play $wav } } finally { Start-Sleep -Milliseconds 400; [M]::Up(0x20); [M]::Up(0x11) }   # keys always released
  $sw = [Diagnostics.Stopwatch]::StartNew(); WaitIdle; $r1 = Resources
  $script:lastCpu = ($r1.Cpu - $r0.Cpu) / ($clip.duration_s + 0.4 + $sw.Elapsed.TotalSeconds); $script:lastMb = $r1.Mb
  $sw.Elapsed.TotalSeconds
}
function Report($name, $clip, $got, $secs) {
  $w = Wer $clip.reference $got
  Check "$name ($($clip.file), $([math]::Round($clip.duration_s)) s)" ($got.Length -gt 20 -and $w -le 25) ("WER {0}%, idle {1:N1} s after release, {2:N1} cores avg, {3:N0} MB | '{4}'" -f $w, $secs, $script:lastCpu, $script:lastMb, ($got.Substring(0, [Math]::Min(70, $got.Length))))
}

StartApp $null
try {
  # --- own test window ---------------------------------------------------------------------------------
  if ('own' -in $Targets -or 'wrongwindow' -in $Targets) {
    $tf = Join-Path $Work 'mic-target.txt'; Set-Content $tf '' -Encoding ascii
    $tgt = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$tf`"", '-Kind', 'RichTextBox' -PassThru
    Start-Sleep 3; $own = [M]::FindWindow([NullString]::Value, 'esytype-e2e-target')
    function OwnText { for ($i = 0; $i -lt 40; $i++) { try { return ([IO.File]::ReadAllText($tf)).Trim() } catch { Start-Sleep -Milliseconds 25 } } }
  }
  if ('own' -in $Targets) {
    foreach ($c in $speech) {
      Set-Clipboard -Value 'KEEP ME'
      $before = OwnText; $s = Dictate $own $c; $after = OwnText
      Report 'Own window' $c ($after.Substring([Math]::Min($before.Length, $after.Length)).Trim()) $s
      Check '  clipboard preserved' ((Get-Clipboard -Raw) -eq 'KEEP ME') ''
    }
  }
  if ('wrongwindow' -in $Targets) {
    $c = $speech[0]; Set-Clipboard -Value 'BEFORE'; $before = OwnText
    [M]::SetForegroundWindow($own) | Out-Null; Start-Sleep -Milliseconds 400
    [M]::Down(0x11); [M]::Down(0x20); Start-Sleep -Milliseconds 500
    $other = Start-Process powershell.exe -ArgumentList '-NoExit', '-Command', '$Host.UI.RawUI.WindowTitle=''esytype-e2e-other''' -PassThru
    try { Play (Join-Path $Audio $c.file) } finally { [M]::Up(0x20); [M]::Up(0x11) }; WaitIdle
    Check 'Wrong window: nothing typed into the original window' ((OwnText) -eq $before) ''
    $clip = Get-Clipboard -Raw
    Check 'Wrong window: transcript placed on clipboard' ($clip -ne 'BEFORE' -and $clip.Length -gt 20) "'$($clip.Substring(0, [Math]::Min(60, $clip.Length)))'"
    Stop-Process -Id $other.Id -Force -ErrorAction SilentlyContinue
  }

  # --- Notepad: a dedicated tab ------------------------------------------------------------------------
  if ('notepad' -in $Targets) {
    $nf = Join-Path $Work ("esytype-notepad-{0:yyyyMMdd-HHmmss}.txt" -f (Get-Date)); Set-Content $nf '' -Encoding ascii; $nn = Split-Path $nf -Leaf   # fresh tab every run
    Start-Process notepad.exe -ArgumentList "`"$nf`"" | Out-Null; Start-Sleep 3
    $nw = [System.Windows.Automation.AutomationElement]::RootElement.FindAll('Children', [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { $_.Current.Name -like "*$nn*" } | Select-Object -First 1
    $nh = [IntPtr]$nw.Current.NativeWindowHandle
    [void](New-Object -ComObject WScript.Shell).AppActivate([M]::Title($nh)); Start-Sleep -Milliseconds 400
    $nw.FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Document))).SetFocus()   # caret in the text, not the toolbar
    function NoteText { $d = $nw.FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Document))); ([string]$d.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(-1)).Trim() }
    foreach ($c in $speech) {
      Set-Clipboard -Value 'KEEP ME'
      if (-not ([M]::Title($nh) -like "*$nn*")) { throw 'Our Notepad tab is not the active tab' }
      $before = NoteText; $s = Dictate $nh $c; $after = NoteText
      Report 'Notepad' $c ($after.Substring([Math]::Min($before.Length, $after.Length)).Trim()) $s
      Check '  clipboard preserved' ((Get-Clipboard -Raw) -eq 'KEEP ME') ''
    }
    "   Notepad tab '$nn' left open for you to inspect; it is a scratch file in $Work."
  }

  # --- Word: a new document in its own instance -----------------------------------------------------------
  if ('word' -in $Targets) {
    $word = New-Object -ComObject Word.Application; $word.Visible = $true
    $doc = $word.Documents.Add(); Start-Sleep 3
    $doc.Activate(); $word.Activate(); $wh = [IntPtr]$doc.ActiveWindow.Hwnd
    foreach ($c in $speech) {
      Set-Clipboard -Value 'KEEP ME'
      $before = $doc.Content.Text.Trim(); $s = Dictate $wh $c; $after = $doc.Content.Text.Trim()
      Report 'Word' $c ($after.Substring([Math]::Min($before.Length, $after.Length)).Trim()) $s
      Check '  clipboard preserved' ((Get-Clipboard -Raw) -eq 'KEEP ME') ''
    }
    $doc.Close(0)                                  # our document only, without saving
    if ($word.Documents.Count -eq 0) { $word.Quit() }
    $doc = $null
  }

  # --- Chrome (separate test profile): a local text area, then ChatGPT -----------------------------------
  if ('chrome' -in $Targets -or 'chatgpt' -in $Targets) {
    $prof = Join-Path $Work 'chrome-profile'
    $page = Join-Path $Work 'chrome-target.html'
    Set-Content $page '<!doctype html><title>esytype-chrome-target</title><textarea id=t autofocus style="width:90vw;height:60vh;font:16px sans-serif"></textarea>' -Encoding ascii
    $chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
    Start-Process $chrome -ArgumentList "--user-data-dir=`"$prof`"", '--no-first-run', '--no-default-browser-check', '--new-window', ([Uri]$page).AbsoluteUri | Out-Null   # encodes the space in "AI Projects"
    Start-Sleep 5
    $ch = [IntPtr]::Zero
    for ($i = 0; $i -lt 20 -and $ch -eq [IntPtr]::Zero; $i++) {
      $e = [System.Windows.Automation.AutomationElement]::RootElement.FindAll('Children', [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { $_.Current.Name -like 'esytype-chrome-target*' } | Select-Object -First 1
      if ($e) { $ch = [IntPtr]$e.Current.NativeWindowHandle } else { Start-Sleep -Milliseconds 500 }
    }
    if ($ch -eq [IntPtr]::Zero) { throw 'Chrome test window not found' }
    function AreaText { $e = [System.Windows.Automation.AutomationElement]::FromHandle($ch).FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit))); ([string]$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value).Trim() }
    if ('chrome' -in $Targets) {
      foreach ($c in $speech) {
        Set-Clipboard -Value 'KEEP ME'
        $before = AreaText; $s = Dictate $ch $c; $after = AreaText
        Report 'Chrome text area' $c ($after.Substring([Math]::Min($before.Length, $after.Length)).Trim()) $s
        Check '  clipboard preserved' ((Get-Clipboard -Raw) -eq 'KEEP ME') ''
      }
    }
    if ('chatgpt' -in $Targets) {
      # Logged-out ChatGPT in the test profile. The text is inserted into the message box and NEVER sent.
      Start-Process $chrome -ArgumentList "--user-data-dir=`"$prof`"", 'https://chatgpt.com/' | Out-Null
      Start-Sleep 10
      $cg = [System.Windows.Automation.AutomationElement]::RootElement.FindAll('Children', [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { $_.Current.Name -like '*ChatGPT*Google Chrome*' } | Select-Object -First 1
      if (-not $cg) { Check 'ChatGPT page opened' $false 'window not found (sign-in wall, consent page or network)' }
      else {
        $cgh = [IntPtr]$cg.Current.NativeWindowHandle
        $c = $speech[0]
        $s = Dictate $cgh $c
        $png = Join-Path $Work 'chatgpt-after-dictation.png'
        $b = New-Object System.Drawing.Bitmap ([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width), ([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
        [System.Drawing.Graphics]::FromImage($b).CopyFromScreen(0, 0, 0, 0, $b.Size); $b.Save($png)
        Check 'ChatGPT: dictation completed (inspect screenshot)' $true "screenshot $png; message NOT sent"
      }
    }
    "   Chrome test profile windows left open for you to inspect; close them when done."
  }
} finally {
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
  if ($tgt) { Stop-Process -Id $tgt.Id -Force -ErrorAction SilentlyContinue }
  if ($doc) { try { $doc.Close(0); if ($word.Documents.Count -eq 0) { $word.Quit() } } catch {} }   # the test's own Word document only
}

# --- Chosen microphone missing: falls back to the Windows default and still works -------------------------
if ('missingmic' -in $Targets) {
  StartApp 'Microphone That Does Not Exist'
  try {
    $tf2 = Join-Path $Work 'mic-target2.txt'; Set-Content $tf2 '' -Encoding ascii
    $tgt2 = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$tf2`"", '-Kind', 'RichTextBox' -PassThru
    Start-Sleep 3; $o2 = [M]::FindWindow([NullString]::Value, 'esytype-e2e-target')
    $c = $speech[0]; $s = Dictate $o2 $c
    Report 'Missing chosen microphone: falls back to default' $c (([IO.File]::ReadAllText($tf2)).Trim()) $s
  } finally { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue; Stop-Process -Id $tgt2.Id -Force -ErrorAction SilentlyContinue }
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'realmic-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
