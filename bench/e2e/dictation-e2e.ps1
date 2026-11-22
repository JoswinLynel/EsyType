# End-to-end test of the dictation milestone on a real Windows desktop.
# Requires an EsyType build with the `e2e` feature (replays ESYTYPE_TEST_AUDIO instead of the microphone).
# Drives real keyboard input, so do not type or click while it runs (about 2 minutes).
# Types only into a window this script creates; it never touches the user's own applications.
param(
  [string]$Exe = "$PSScriptRoot\..\..\src-tauri\target\release\esytype.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$ModelSource = "D:\AI Projects\Tools\bench\models\ggml-base.en-q5_1.bin",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio\1320_10s.f32",
  [string]$TargetKind = "TextBox",
  [string]$Reference = "the task will not be difficult returned david hesitating though i greatly fear your presence would rather increase than mitigate his unhappy fortunes"
)
$ErrorActionPreference = 'Stop'
# These older scripts use Ctrl+Space and look windows up by title: they need the installed EsyType closed.
if (Get-Process esytype -ErrorAction SilentlyContinue) { throw 'Quit your EsyType from its tray icon first: this test uses Ctrl+Space and the EsyType window title.' }
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class K {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  public static void Down(byte vk) { keybd_event(vk, 0, 0, UIntPtr.Zero); }
  public static void Up(byte vk) { keybd_event(vk, 0, 2, UIntPtr.Zero); }
}
"@
$CTRL = 0x11; $SHIFT = 0x10; $SPACE = 0x20; $ESC = 0x1B; $ALT = 0x12

$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = $detail }); "{0,-46} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

function Words($s) { (($s.ToLower() -replace "[^a-z' ]", ' ') -split '\s+') | Where-Object { $_ } }
function Wer($ref, $hyp) {
  $r = @(Words $ref); $h = @(Words $hyp)
  $d = 0..$h.Count
  for ($i = 1; $i -le $r.Count; $i++) {
    $prev = $d[0]; $d[0] = $i
    for ($j = 1; $j -le $h.Count; $j++) {
      $cur = $d[$j]; $d[$j] = [Math]::Min([Math]::Min($d[$j] + 1, $d[$j - 1] + 1), $prev + [int]($r[$i - 1] -ne $h[$j - 1])); $prev = $cur
    }
  }
  [Math]::Round(100 * $d[$h.Count] / $r.Count, 1)
}

# --- Isolated data folder with Base copied in (no download) ---
$lad = Join-Path $Work 'localappdata'; $models = Join-Path $lad 'EsyAI\EsyType\models'
New-Item -ItemType Directory -Force $models | Out-Null
Copy-Item $ModelSource $models -Force
Set-Content (Join-Path $lad 'EsyAI\EsyType\settings.json') '{"model":"base","mic":null,"threads":0,"ptt":"Ctrl+Space","toggle":"Ctrl+Shift+Space"}' -Encoding ascii

# --- Target: a text window this test owns (never the user's own apps) ---
$textFile = Join-Path $Work 'target-text.txt'; Set-Content $textFile '' -Encoding ascii
$targetScript = Join-Path $PSScriptRoot 'target-window.ps1'
$tgt = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$targetScript`"", '-Out', "`"$textFile`"", '-Kind', $TargetKind -PassThru
$tgtHwnd = [IntPtr]::Zero
for ($i = 0; $i -lt 40 -and $tgtHwnd -eq [IntPtr]::Zero; $i++) {
  Start-Sleep -Milliseconds 250
  $e = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst('Children', (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, 'esytype-e2e-target')))
  if ($e) { $tgtHwnd = [IntPtr]$e.Current.NativeWindowHandle }
}
if ($tgtHwnd -eq [IntPtr]::Zero) { throw "Test target window did not appear" }
function DocText {
  Start-Sleep -Milliseconds 150
  for ($i = 0; $i -lt 20; $i++) { try { return ([IO.File]::ReadAllText($textFile)).Trim() } catch [IO.IOException] { Start-Sleep -Milliseconds 30 } } # window may be mid-write
  throw "Could not read $textFile"
}
function FocusTarget { $wsh = New-Object -ComObject WScript.Shell; [void]$wsh.AppActivate('esytype-e2e-target'); Start-Sleep -Milliseconds 300; [K]::SetForegroundWindow($tgtHwnd) | Out-Null; Start-Sleep -Milliseconds 300; [K]::GetForegroundWindow() -eq $tgtHwnd }
function ClearDoc { FocusTarget | Out-Null; [K]::Down($CTRL); [K]::Down(0x41); [K]::Up(0x41); [K]::Up($CTRL); [K]::Down(0x2E); [K]::Up(0x2E); Start-Sleep -Milliseconds 400 }
function WaitText($timeoutS) { $t = [Diagnostics.Stopwatch]::StartNew(); while ($t.Elapsed.TotalSeconds -lt $timeoutS) { $x = DocText; if ($x.Length -gt 20) { Start-Sleep -Milliseconds 300; return @((DocText), $t.Elapsed.TotalSeconds) }; Start-Sleep -Milliseconds 100 }; return @((DocText), $timeoutS) }

# --- Start EsyType ---
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $Audio
$app = Start-Process $Exe -PassThru
Start-Sleep 8   # model load + warm-up
Check 'App starts and stays running' (-not $app.HasExited) "pid $($app.Id)"

# 1. Hold-to-talk into the target, clipboard preserved
ClearDoc
Set-Clipboard -Value 'ORIGINAL CLIPBOARD'
$fg = FocusTarget
Check "Target ($TargetKind) is the foreground window" $fg ''
[K]::Down($CTRL); [K]::Down($SPACE); Start-Sleep -Milliseconds 1500; [K]::Up($SPACE); [K]::Up($CTRL)
$text, $secs = WaitText 20
Check 'Hold Ctrl+Space: text inserted into the target' ($text.Length -gt 20) ("{0:N1} s after release: '{1}'" -f $secs, $text)
Check 'Transcript matches reference (WER <= 10%)' ((Wer $Reference $text) -le 10) ("WER {0}%" -f (Wer $Reference $text))
Start-Sleep 1
$clip = Get-Clipboard -Raw
Check 'Clipboard restored after paste' ($clip -eq 'ORIGINAL CLIPBOARD') "clipboard now: '$clip'"

# 2. Toggle mode
ClearDoc; FocusTarget | Out-Null
[K]::Down($CTRL); [K]::Down($SHIFT); [K]::Down($SPACE); [K]::Up($SPACE); [K]::Up($SHIFT); [K]::Up($CTRL)
Start-Sleep -Milliseconds 1500
[K]::Down($CTRL); [K]::Down($SHIFT); [K]::Down($SPACE); [K]::Up($SPACE); [K]::Up($SHIFT); [K]::Up($CTRL)
$text, $secs = WaitText 20
Check 'Toggle Ctrl+Shift+Space: text inserted' ($text.Length -gt 20) ("{0:N1} s after second press" -f $secs)

# 3. Accidental tap is ignored
ClearDoc; FocusTarget | Out-Null
[K]::Down($CTRL); [K]::Down($SPACE); Start-Sleep -Milliseconds 120; [K]::Up($SPACE); [K]::Up($CTRL)
Start-Sleep 6
Check 'Tap shorter than 0.4 s inserts nothing' (-not (DocText)) ''

# 4. Esc cancels
ClearDoc; FocusTarget | Out-Null
[K]::Down($CTRL); [K]::Down($SHIFT); [K]::Down($SPACE); [K]::Up($SPACE); [K]::Up($SHIFT); [K]::Up($CTRL)
Start-Sleep -Milliseconds 1000
[K]::Down($ESC); [K]::Up($ESC)
Start-Sleep 6
Check 'Esc cancels a recording' (-not (DocText)) ''

# 5. Focus moves to another app during recording: nothing typed there, text copied instead
ClearDoc; Set-Clipboard -Value 'BEFORE'; FocusTarget | Out-Null
[K]::Down($CTRL); [K]::Down($SHIFT); [K]::Down($SPACE); [K]::Up($SPACE); [K]::Up($SHIFT); [K]::Up($CTRL)
Start-Sleep -Milliseconds 800
$other = Start-Process powershell.exe -ArgumentList '-NoExit', '-Command', '$Host.UI.RawUI.WindowTitle=''e2e-other''' -PassThru
Start-Sleep 2; $wsh = New-Object -ComObject WScript.Shell; [void]$wsh.AppActivate('e2e-other'); Start-Sleep -Milliseconds 500
[K]::Down($CTRL); [K]::Down($SHIFT); [K]::Down($SPACE); [K]::Up($SPACE); [K]::Up($SHIFT); [K]::Up($CTRL)
Start-Sleep 10
$clip = Get-Clipboard -Raw
Check 'Window changed: nothing typed into the target' (-not (DocText)) ''
Check 'Window changed: transcript left on clipboard' ($clip -and $clip -ne 'BEFORE' -and $clip.Length -gt 20) "clipboard: '$clip'"
Stop-Process -Id $other.Id -Force -ErrorAction SilentlyContinue

# 6. Clipboard holds an image: EsyType types instead of pasting, image survives
ClearDoc
$bmp = New-Object System.Drawing.Bitmap 8, 8; [System.Windows.Forms.Clipboard]::SetImage($bmp)
FocusTarget | Out-Null
[K]::Down($CTRL); [K]::Down($SPACE); Start-Sleep -Milliseconds 1500; [K]::Up($SPACE); [K]::Up($CTRL)
$text, $secs = WaitText 25
Check 'Image on clipboard: text typed into the target' ($text.Length -gt 20) ("{0:N1} s" -f $secs)
Start-Sleep 1
Check 'Image on clipboard: image still there' ([System.Windows.Forms.Clipboard]::ContainsImage()) ''

# --- Memory and tidy-up ---
$p = Get-Process -Id $app.Id -ErrorAction SilentlyContinue
$mem = if ($p) { "{0:N0} MB working set (esytype.exe only; WebView2 runs in separate processes)" -f ($p.WorkingSet64 / 1MB) } else { 'exited' }
Check 'App still running after all tests' ([bool]$p) $mem
Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $tgt.Id -Force -ErrorAction SilentlyContinue  # the test's own window only
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'e2e-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
