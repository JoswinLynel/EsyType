# Accuracy through the whole app (VAD, decoding settings, insertion) on the 10 benchmark clips, injected as audio.
# Compare with docs/testing/2026-11-17-stt-dev-pc.md (Base Q5_1, plain whisper.cpp: 3.4% WER).
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$ModelSource = "D:\EsyAI\EsyType\models\ggml-base.en-q5_1.bin",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio"
)
$ErrorActionPreference = 'Stop'
# These older scripts use Ctrl+Space and look windows up by title: they need the installed EsyType closed.
if (Get-Process esytype -ErrorAction SilentlyContinue) { throw 'Quit your EsyType from its tray icon first: this test uses Ctrl+Space and the EsyType window title.' }
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class A {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
}
"@
. (Join-Path $PSScriptRoot 'wer.ps1')
$lad = Join-Path $Work 'localappdata-acc'; $m = Join-Path $lad 'EsyAI\EsyType\models'
New-Item -ItemType Directory -Force $m | Out-Null; Copy-Item $ModelSource $m -Force
Set-Content (Join-Path $lad 'EsyAI\EsyType\settings.json') '{"model":"base","threads":0,"ptt":"Ctrl+Space","toggle":"Ctrl+Shift+Space","start_with_windows":false}' -Encoding ascii
$current = Join-Path $Work 'current.f32'
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current
$app = Start-Process $Exe -PassThru -RedirectStandardError (Join-Path $Work 'acc-trace.txt')
$tf = Join-Path $Work 'acc-target.txt'; Set-Content $tf '' -Encoding ascii
$tgt = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$tf`"", '-Kind', 'RichTextBox' -PassThru
Start-Sleep 9
$h = [A]::FindWindow([NullString]::Value, 'esytype-e2e-target'); $pill = [A]::FindWindow([NullString]::Value, 'EsyType recording')
function Text { for ($i = 0; $i -lt 40; $i++) { try { return ([IO.File]::ReadAllText($tf)).Trim() } catch { Start-Sleep -Milliseconds 25 } }; throw 'read failed' }
function Stable { $prev = $null; for ($i = 0; $i -lt 50; $i++) { $x = Text; if ($x -eq $prev) { return $x }; $prev = $x; Start-Sleep -Milliseconds 60 }; $prev }
function WaitIdle { $t = [Diagnostics.Stopwatch]::StartNew(); $q = 0; while ($q -lt 3 -and $t.Elapsed.TotalSeconds -lt 60) { if ([A]::IsWindowVisible($pill)) { $q = 0 } else { $q++ }; Start-Sleep -Milliseconds 100 }; $t.Elapsed.TotalSeconds - 0.3 - 0.7 }
$errs = 0; $words = 0
try {
  foreach ($c in (Get-Content (Join-Path $Audio 'clips.json') -Raw | ConvertFrom-Json)) {
    Copy-Item (Join-Path $Audio ($c.file -replace '\.wav$', '.f32')) $current -Force
    if ([A]::GetForegroundWindow() -ne $h) { [void](New-Object -ComObject WScript.Shell).AppActivate('esytype-e2e-target'); Start-Sleep -Milliseconds 300; [A]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 300 }
    if ([A]::GetForegroundWindow() -ne $h) { throw 'Test window is not in front; stopping before sending keys.' }
    $before = Stable
    [A]::Down(0x11); [A]::Down(0x20); Start-Sleep -Milliseconds 900; [A]::Up(0x20); [A]::Up(0x11)
    $secs = WaitIdle; $after = Stable
    $got = $after.Substring([Math]::Min($before.Length, $after.Length)).Trim()
    $w = Wer $c.reference $got; $n = @(Words $c.reference).Count
    $errs += [Math]::Round($w * $n / 100); $words += $n
    "{0,-14} {1,5:N1} s audio  {2,5:N1} s release-to-text  WER {3,5}%  ({4} words)" -f $c.file, $c.duration_s, $secs, $w, $n
  }
} finally { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue; Stop-Process -Id $tgt.Id -Force -ErrorAction SilentlyContinue; [A]::Up(0x20); [A]::Up(0x11) }
"`nOverall WER through the app: {0:N1}% ({1} errors in {2} words). Benchmark (whisper.cpp alone): 3.4%." -f (100 * $errs / $words), $errs, $words
