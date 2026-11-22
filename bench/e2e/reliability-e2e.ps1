# Automated reliability test (recorded audio injected via the `e2e` build feature; no microphone).
# Types only into a window this script creates. Drives the real keyboard and mouse: do not touch them (about 6 minutes).
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$ModelSource = "D:\EsyAI\EsyType\models\ggml-base.en-q5_1.bin",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio\1320_10s.f32",
  [int]$Repeats = 20
)
$ErrorActionPreference = 'Stop'
# These older scripts use Ctrl+Space and look windows up by title: they need the installed EsyType closed.
if (Get-Process esytype -ErrorAction SilentlyContinue) { throw 'Quit your EsyType from its tray icon first: this test uses Ctrl+Space and the EsyType window title.' }
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class R {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
  public static string FgTitle() { var b = new System.Text.StringBuilder(256); GetWindowText(GetForegroundWindow(), b, 256); return b.ToString(); }
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, Rr, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
  public static void Down(byte vk) { keybd_event(vk, 0, 0, UIntPtr.Zero); } public static void Up(byte vk) { keybd_event(vk, 0, 2, UIntPtr.Zero); }
  public static void Click(int x, int y) { SetCursorPos(x, y); mouse_event(2, 0, 0, 0, UIntPtr.Zero); mouse_event(4, 0, 0, 0, UIntPtr.Zero); }
  /// Milliseconds for a window's message loop to answer WM_NULL (a hung window takes the full timeout).
  public static long Ping(IntPtr h) { var sw = System.Diagnostics.Stopwatch.StartNew(); IntPtr r; SendMessageTimeout(h, 0, IntPtr.Zero, IntPtr.Zero, 2, 5000, out r); return sw.ElapsedMilliseconds; }
}
"@
$CTRL = 0x11; $SHIFT = 0x10; $SPACE = 0x20
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-52} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }
function Hold($ms) { if (-not (Safe)) { throw 'Test window lost focus; stopping before sending keys' }; [R]::Down($CTRL); [R]::Down($SPACE); Start-Sleep -Milliseconds $ms; [R]::Up($SPACE); [R]::Up($CTRL) }
function Toggle { if (-not (Safe)) { throw 'Test window lost focus; stopping before sending keys' }; [R]::Down($CTRL); [R]::Down($SHIFT); [R]::Down($SPACE); [R]::Up($SPACE); [R]::Up($SHIFT); [R]::Up($CTRL) }

# Scratch data: Base copied in, start-with-Windows OFF so the test build never registers itself.
$lad = Join-Path $Work 'localappdata-rel'; $models = Join-Path $lad 'EsyAI\EsyType\models'
New-Item -ItemType Directory -Force $models | Out-Null
Copy-Item $ModelSource $models -Force
Set-Content (Join-Path $lad 'EsyAI\EsyType\settings.json') '{"model":"base","threads":0,"ptt":"Ctrl+Space","toggle":"Ctrl+Shift+Space","start_with_windows":false}' -Encoding ascii

# Target window owned by this test
$textFile = Join-Path $Work 'target-text.txt'; Set-Content $textFile '' -Encoding ascii
$tgt = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$textFile`"", '-Kind', 'RichTextBox' -PassThru
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 40 -and $h -eq [IntPtr]::Zero; $i++) { Start-Sleep -Milliseconds 250; $h = [R]::FindWindow([NullString]::Value, 'esytype-e2e-target') }
if ($h -eq [IntPtr]::Zero) { throw 'target window missing' }
function Text { for ($i = 0; $i -lt 40; $i++) { try { return ([IO.File]::ReadAllText($textFile)).Trim() } catch [IO.IOException] { Start-Sleep -Milliseconds 25 } }; throw 'could not read the test window text' }
function Focus { [void](New-Object -ComObject WScript.Shell).AppActivate('esytype-e2e-target'); Start-Sleep -Milliseconds 250; [R]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 250; [R]::GetForegroundWindow() -eq $h }
# Reads the box until two reads agree, so a half-written file is never mistaken for the real contents.
function Stable { $prev = $null; for ($i = 0; $i -lt 50; $i++) { $x = Text; if ($x -eq $prev) { return $x }; $prev = $x; Start-Sleep -Milliseconds 60 }; $prev }
function Clear { WaitIdle; $script:before = Stable }   # no clearing: each check measures what the dictation added
# Keys are only ever sent while the test's own window is in front.
function Safe { if ([R]::GetForegroundWindow() -eq $h) { return $true }; return (Focus) }
# EsyType is idle once its pill has been hidden for 300 ms; a new dictation must not start before that.
function WaitIdle { $quiet = 0; $t = [Diagnostics.Stopwatch]::StartNew(); while ($quiet -lt 3 -and $t.Elapsed.TotalSeconds -lt 30) { if ([R]::IsWindowVisible($pill)) { $quiet = 0 } else { $quiet++ }; Start-Sleep -Milliseconds 100 } }
# Seconds from now until the box changes, then exactly what the dictation added once EsyType is idle again.
function WaitText($s) {
  $t = [Diagnostics.Stopwatch]::StartNew(); $first = $s
  while ($t.Elapsed.TotalSeconds -lt $s) { if ((Text).Length -ne $script:before.Length) { $first = $t.Elapsed.TotalSeconds; break }; Start-Sleep -Milliseconds 50 }
  WaitIdle; $now = Stable
  $added = if ($now.StartsWith($script:before)) { $now.Substring($script:before.Length) } else { "<box changed unexpectedly>" }
  @($added.Trim(), $first)
}

$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $Audio
$app = Start-Process $Exe -PassThru -RedirectStandardError (Join-Path $Work 'reliability-trace.txt')
Start-Sleep 9
$main = [R]::FindWindow([NullString]::Value, 'EsyType')
$pill = [R]::FindWindow([NullString]::Value, 'EsyType recording')
Check 'App, main window and pill window exist' (-not $app.HasExited -and $main -ne [IntPtr]::Zero -and $pill -ne [IntPtr]::Zero) "main=$main pill=$pill"

# Second launch must not start a second instance
$second = Start-Process $Exe -PassThru; Start-Sleep 4
Check 'Single instance: second launch exits' ($second.HasExited) "second exited: $($second.HasExited)"
if (-not $second.HasExited) { Stop-Process -Id $second.Id -Force }

function Tree { $ids = @($app.Id) + @(Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $app.Id } | ForEach-Object ProcessId); $ids | ForEach-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue } }
function Sample { $p = Tree; [pscustomobject]@{ Ws = ($p | Measure-Object WorkingSet64 -Sum).Sum / 1MB; Cpu = ($p | ForEach-Object { $_.TotalProcessorTime.TotalSeconds } | Measure-Object -Sum).Sum } }

# 1. Focus never leaves the target during recording; clicking the pill's Stop button with the mouse
Clear; Focus | Out-Null
$idle = Sample
Toggle; Start-Sleep -Milliseconds 700
$fgDuring = 0; $titles = @{}; foreach ($i in 1..8) { if ([R]::GetForegroundWindow() -eq $h) { $fgDuring++ } else { $titles[[R]::FgTitle()] = 1 }; Start-Sleep -Milliseconds 100 }
Check 'Focus stays on target while the pill is shown' ($fgDuring -eq 8) "$fgDuring of 8 samples; other foreground: $($titles.Keys -join ' | ')"
$r = New-Object R+RECT; [R]::GetWindowRect($pill, [ref]$r) | Out-Null
Check 'Pill is visible during recording' ([R]::IsWindowVisible($pill)) "rect $($r.L),$($r.T)-$($r.Rr),$($r.B)"
$cpu0 = Sample; $sw = [Diagnostics.Stopwatch]::StartNew()
[R]::Click($r.Rr - 32, [int](($r.T + $r.B) / 2))   # Stop button sits at the pill's right end
Start-Sleep -Milliseconds 100
Check 'Clicking the pill does not take focus' ([R]::GetForegroundWindow() -eq $h) ''
$pingT = 0; $pingM = 0; while ($sw.Elapsed.TotalSeconds -lt 2.5) { $pingT = [Math]::Max($pingT, [R]::Ping($h)); $pingM = [Math]::Max($pingM, [R]::Ping($main)); Start-Sleep -Milliseconds 50 }
$text, $secs = WaitText 20; $cpu1 = Sample
Check 'Mouse Stop on pill: text inserted' ($text.Length -gt 100) ("{0:N1} s" -f $secs)
Check 'Target window responsive during transcription' ($pingT -lt 250) "slowest reply $pingT ms"
Check 'EsyType window responsive during transcription' ($pingM -lt 250) "slowest reply $pingM ms"
$cores = ($cpu1.Cpu - $cpu0.Cpu) / ($sw.Elapsed.TotalSeconds)
"   resources: idle {0:N0} MB; after dictation {1:N0} MB; {2:N1} CPU cores busy on average from stop to text" -f $idle.Ws, $cpu1.Ws, $cores

# 2. Cancel, then restart immediately
Clear; Focus | Out-Null
Toggle; Start-Sleep -Milliseconds 600; if (-not (Safe)) { throw 'focus lost' }; [R]::Down(0x1B); [R]::Up(0x1B); Start-Sleep -Milliseconds 150
Hold 1200
$text, $secs = WaitText 20
Check 'Cancel then immediate restart works' ($text.Length -gt 100 -and $text.Length -lt 300) "$($text.Length) chars (one transcript expected)"

# 3. Repeated dictations
$ok = 0; $times = @(); $mem = @()
foreach ($n in 1..$Repeats) {
  Clear; if (-not (Focus)) { continue }
  Hold 1000
  $text, $secs = WaitText 20
  if ($text -like '*unhappy fortunes*' -and $text.Length -lt 300) { $ok++ } else { "   repeat ${n}: {0} chars after {1:N1} s; foreground '{2}'" -f $text.Length, $secs, [R]::FgTitle() }
  $times += $secs; $mem += (Sample).Ws
}
$avg = ($times | Measure-Object -Average).Average; $max = ($times | Measure-Object -Maximum).Maximum
Check "Repeated dictations ($Repeats in a row) all inserted" ($ok -eq $Repeats) ("{0}/{1}; release-to-text avg {2:N1} s, max {3:N1} s" -f $ok, $Repeats, $avg, $max)
$growth = $mem[-1] - $mem[0]
Check 'No memory growth across repeats (< 50 MB)' ($growth -lt 50) ("first {0:N0} MB, last {1:N0} MB, change {2:N0} MB" -f $mem[0], $mem[-1], $growth)

# 4. Close button hides to tray; app keeps running and still dictates
[R]::PostMessage($main, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null; Start-Sleep 1   # WM_CLOSE to EsyType's window only
Check 'Closing the window keeps EsyType running (tray)' (-not $app.HasExited -and -not [R]::IsWindowVisible($main)) ''
Clear; Focus | Out-Null; Hold 1000; $text, $secs = WaitText 20
Check 'Dictation still works with the window closed' ($text.Length -gt 100) ''

$final = Sample
"   memory at end: {0:N0} MB (esytype.exe plus its WebView2 processes)" -f $final.Ws
Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $tgt.Id -Force -ErrorAction SilentlyContinue
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'reliability-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
