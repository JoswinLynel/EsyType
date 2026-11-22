# Measures dictation by Whisper thread count, in the test build's own test window (keys go only there):
#   seconds from key release to text, the longest a normal window (the test window) and EsyType's own window took to
#   answer a message while transcribing (responsiveness), model warm-up time, and the text with its word error rate.
# -Load n keeps n processes busy at below normal priority for the whole run (stopped at the end) to imitate other
# programs. Rows are appended to -Csv; the summary line per thread count is printed.
param([string[]]$Threads = @('7', '4', '2'), [int]$Reps = 3, [int]$Load = 0, [string]$Label = 'idle',
      [string]$Clip = '6930_10s', [string]$Csv = "D:\AI Projects\Tools\e2e\threads-results.csv",
      [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
      [string]$Work = "D:\AI Projects\Tools\e2e", [string]$Audio = "D:\AI Projects\Tools\bench\audio")
$ErrorActionPreference = 'Stop'
$counts = [int[]]@($Threads | ForEach-Object { "$_" -split "," })   # own variable: $Threads is [string[]] and would turn these back into text
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Diagnostics;
public static class Tp {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
  // Milliseconds a window takes to answer a no-op message (2000 = no answer within 2 s).
  public static double Lag(IntPtr h) { var sw = Stopwatch.StartNew(); IntPtr r; return SendMessageTimeout(h, 0, IntPtr.Zero, IntPtr.Zero, 2, 2000, out r) == IntPtr.Zero ? 2000 : sw.Elapsed.TotalMilliseconds; }
  public static int Edits(string[] r, string[] h) {   // word-level edit distance
    var d = new int[r.Length + 1, h.Length + 1];
    for (int i = 0; i <= r.Length; i++) d[i, 0] = i; for (int j = 0; j <= h.Length; j++) d[0, j] = j;
    for (int i = 1; i <= r.Length; i++) for (int j = 1; j <= h.Length; j++)
      d[i, j] = Math.Min(Math.Min(d[i - 1, j] + 1, d[i, j - 1] + 1), d[i - 1, j - 1] + (r[i - 1] == h[j - 1] ? 0 : 1));
    return d[r.Length, h.Length];
  }
  public static IntPtr WindowOf(int pid) { IntPtr found = IntPtr.Zero; EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid) { found = h; return false; } return true; }, IntPtr.Zero); return found; }
}
"@
function Words($s) { [string[]]@(($s.ToUpper() -replace "[^A-Z0-9' ]", ' ' -replace "'", '') -split '\s+' | Where-Object { $_ }) }
function Wer($ref, $hyp) { [Math]::Round([Tp]::Edits((Words $ref), (Words $hyp)) / [double](Words $ref).Count, 3) }   # word error rate
if ((Wer 'a b c d' 'a x c') -ne 0.5) { throw 'Wer self-check failed' }
$reference = ((Get-Content (Join-Path $Audio 'clips.json') -Raw | ConvertFrom-Json) | Where-Object file -eq "$Clip.wav").reference
$lad = Join-Path $Work 'localappdata-threads'; $data = Join-Path $lad 'EsyAI\EsyType'; New-Item -ItemType Directory -Force $data | Out-Null
$current = Join-Path $Work 'current.f32'; Copy-Item (Join-Path $Audio "$Clip.f32") $current -Force
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current
$userClip = Get-Clipboard -Raw
$f = Join-Path $Work 'threads-target.txt'; Set-Content $f '' -Encoding ascii
function Typed { try { ([IO.File]::ReadAllText($f)).Trim() } catch [IO.IOException] { '' } }   # the window may be writing it
$trace = Join-Path $Work 'threads-trace.txt'
if (-not (Test-Path $Csv)) { 'label,threads,rep,seconds,window_lag_ms,esytype_lag_ms,ready_s,wer,text' | Set-Content $Csv -Encoding utf8 }
$loader = $null; $app = $null; $win = $null
try {
  if ($Load) {
    $si = New-Object Diagnostics.ProcessStartInfo 'pythonw.exe', "-I `"$(Join-Path $PSScriptRoot 'cpu-load.py')`" $Load 7200"
    $si.UseShellExecute = $false; $si.CreateNoWindow = $true
    $loader = [Diagnostics.Process]::Start($si); $loader.PriorityClass = 'BelowNormal'; Start-Sleep 3   # workers inherit it
  }
  $win = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$f`"", '-Title', 'esytype-threads' -PassThru
  Start-Sleep 3; $h = [Tp]::FindWindow([NullString]::Value, 'esytype-threads')
  if ($h -eq [IntPtr]::Zero) { throw 'Test window not found.' }
  foreach ($t in $counts) {
    [ordered]@{ model = 'base'; threads = $t; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; undo_shortcut = 'Ctrl+F9'; paste_last_shortcut = 'Ctrl+F10'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false; history_enabled = $false } |
      ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
    $trace = Join-Path $Work "threads-trace-$Label-$t-$(Get-Date -Format HHmmss).txt"   # one log per run, kept for checking failures
    $app = Start-Process $Exe -ArgumentList '--minimized' -PassThru -RedirectStandardError $trace
    $sw = [Diagnostics.Stopwatch]::StartNew()   # model load + warm-up, until the test build traces "model ready"
    while ($sw.Elapsed.TotalSeconds -lt 600 -and -not ((Get-Content $trace -Raw -ErrorAction SilentlyContinue) -match 'model ready')) { Start-Sleep -Milliseconds 250 }
    $ready = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
    if ($ready -ge 600) { throw "threads ${t}: the model was not ready after 600 s" }
    Start-Sleep 1; $esy = [Tp]::WindowOf($app.Id)
    $rows = @()
    for ($i = 1; $i -le $Reps; $i++) {
      Set-Content "$f.clear" ''; Start-Sleep 0.6
      for ($k = 0; $k -lt 6 -and [Tp]::GetForegroundWindow() -ne $h; $k++) { [Tp]::Down(0x12); [Tp]::Up(0x12); [Tp]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400 }
      if ([Tp]::GetForegroundWindow() -ne $h) { throw 'The test window is not in front; no keys sent.' }
      try { [Tp]::Down(0x11); [Tp]::Down(0x77); Start-Sleep -Milliseconds 900 } finally { [Tp]::Up(0x77); [Tp]::Up(0x11) }
      $sw = [Diagnostics.Stopwatch]::StartNew(); $lagWin = 0; $lagEsy = 0; $text = ''
      while ($sw.Elapsed.TotalSeconds -lt 120 -and -not ($text = Typed)) {   # read once: a second read can collide with the window writing
        $lagWin = [Math]::Max($lagWin, [Tp]::Lag($h)); if ($esy -ne [IntPtr]::Zero) { $lagEsy = [Math]::Max($lagEsy, [Tp]::Lag($esy)) }
        Start-Sleep -Milliseconds 100
      }
      $secs = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
      $wer = if ($text) { Wer $reference $text } else { 1 }
      $rows += [pscustomobject]@{ s = $secs; text = $text }
      '{0},{1},{2},{3},{4:0},{5:0},{6},{7},"{8}"' -f $Label, $t, $i, $secs, $lagWin, $lagEsy, $ready, $wer, ($text -replace '"', "'") | Add-Content $Csv -Encoding utf8
      Start-Sleep 2
    }
    Stop-Process -Id $app.Id -Force; $app = $null; Start-Sleep 2
    $s = @($rows.s | Sort-Object)
    "{0} threads {1}: ready {2} s; dictation median {3} s, range {4}-{5} s ({6} runs, {7} without text)" -f $Label, $t, $ready, $s[[int][Math]::Floor($s.Count / 2)], $s[0], $s[-1], $s.Count, @($rows | Where-Object { -not $_.text }).Count
  }
} finally {
  if ($win) { Stop-Process -Id $win.Id -Force -ErrorAction SilentlyContinue }
  if ($app) { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue }
  if ($loader) { Get-CimInstance Win32_Process -Filter "ParentProcessId=$($loader.Id)" | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Stop-Process -Id $loader.Id -Force -ErrorAction SilentlyContinue }
  [Tp]::Up(0x77); [Tp]::Up(0x11)
  if ($userClip) { Set-Clipboard -Value $userClip }
}
