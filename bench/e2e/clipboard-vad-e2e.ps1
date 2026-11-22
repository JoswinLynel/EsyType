# Clipboard preservation across clipboard types, and voice activity detection on silence and noise.
# Recorded audio is injected (e2e build); the audio file is swapped between dictations.
# Types only into a window this script creates; keys are sent only while that window is in front.
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$ModelSource = "D:\EsyAI\EsyType\models\ggml-base.en-q5_1.bin",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio"
)
$ErrorActionPreference = 'Stop'
# These older scripts use Ctrl+Space and look windows up by title: they need the installed EsyType closed.
if (Get-Process esytype -ErrorAction SilentlyContinue) { throw 'Quit your EsyType from its tray icon first: this test uses Ctrl+Space and the EsyType window title.' }
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class C {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool OpenClipboard(IntPtr h);
  [DllImport("user32.dll")] static extern bool CloseClipboard();
  [DllImport("user32.dll")] static extern uint EnumClipboardFormats(uint f);
  [DllImport("user32.dll")] static extern IntPtr GetClipboardData(uint f);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClipboardFormatName(uint f, StringBuilder s, int n);
  [DllImport("kernel32.dll")] static extern UIntPtr GlobalSize(IntPtr h);
  [DllImport("kernel32.dll")] static extern IntPtr GlobalLock(IntPtr h);
  [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr h);
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
  static string Name(uint f) { var b = new StringBuilder(128); return GetClipboardFormatName(f, b, 128) > 0 ? b.ToString() : "CF" + f; }
  // Fingerprint of the clipboard's real content: format name + SHA-256 of its bytes. Formats Windows synthesises
  // (ANSI/OEM text, locale, bitmap) and OLE/history bookkeeping are left out, as EsyType does not copy them.
  public static string Fingerprint() {
    for (int i = 0; i < 25 && !OpenClipboard(IntPtr.Zero); i++) System.Threading.Thread.Sleep(20);
    var parts = new List<string>(); uint f = 0;
    var skip = new HashSet<string> { "CF1", "CF7", "CF16", "CF2", "DataObject", "Ole Private Data", "ExcludeClipboardContentFromMonitorProcessing", "CanIncludeInClipboardHistory", "CanUploadToCloudClipboard" };
    try {
      while ((f = EnumClipboardFormats(f)) != 0) {
        string n = Name(f); if (skip.Contains(n)) continue;
        IntPtr h = GetClipboardData(f); if (h == IntPtr.Zero) { parts.Add(n + "=null"); continue; }
        int size = (int)GlobalSize(h); IntPtr p = GlobalLock(h); if (p == IntPtr.Zero) { parts.Add(n + "=handle"); continue; }
        var bytes = new byte[size]; Marshal.Copy(p, bytes, 0, size); GlobalUnlock(h);
        using (var sha = System.Security.Cryptography.SHA256.Create()) parts.Add(n + "=" + BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "").Substring(0, 12));
      }
    } finally { CloseClipboard(); }
    parts.Sort(); return string.Join(" ", parts);
  }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-50} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

# EsyType with isolated settings; ESYTYPE_TEST_AUDIO points at a file this script swaps.
$lad = Join-Path $Work 'localappdata-clip'; $m = Join-Path $lad 'EsyAI\EsyType\models'
New-Item -ItemType Directory -Force $m | Out-Null; Copy-Item $ModelSource $m -Force
Set-Content (Join-Path $lad 'EsyAI\EsyType\settings.json') '{"model":"base","threads":0,"ptt":"Ctrl+Space","toggle":"Ctrl+Shift+Space","start_with_windows":false}' -Encoding ascii
$current = Join-Path $Work 'current.f32'; Copy-Item (Join-Path $Audio '1320_10s.f32') $current -Force
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current
$trace = Join-Path $Work 'clip-trace.txt'
$app = Start-Process $Exe -PassThru -RedirectStandardError $trace
$tf = Join-Path $Work 'clip-target.txt'; Set-Content $tf '' -Encoding ascii
$tgt = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$tf`"", '-Kind', 'RichTextBox' -PassThru
Start-Sleep 9
$h = [C]::FindWindow([NullString]::Value, 'esytype-e2e-target'); $pill = [C]::FindWindow([NullString]::Value, 'EsyType recording')
function Text { for ($i = 0; $i -lt 40; $i++) { try { return ([IO.File]::ReadAllText($tf)).Trim() } catch { Start-Sleep -Milliseconds 25 } }; throw 'read failed' }
function Stable { $prev = $null; for ($i = 0; $i -lt 50; $i++) { $x = Text; if ($x -eq $prev) { return $x }; $prev = $x; Start-Sleep -Milliseconds 60 }; $prev }
# Seconds until the pill has been hidden for 300 ms (EsyType idle again).
function WaitIdle { $t = [Diagnostics.Stopwatch]::StartNew(); $q = 0; while ($q -lt 3 -and $t.Elapsed.TotalSeconds -lt 30) { if ([C]::IsWindowVisible($pill)) { $q = 0 } else { $q++ }; Start-Sleep -Milliseconds 100 }; $t.Elapsed.TotalSeconds - 0.3 }
function Outcomes { @(Get-Content $trace -ErrorAction SilentlyContinue | Select-String 'inserted (\w+)' | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
function Dictate($clip) {
  Copy-Item (Join-Path $Audio $clip) $current -Force
  if ([C]::GetForegroundWindow() -ne $h) { [void](New-Object -ComObject WScript.Shell).AppActivate('esytype-e2e-target'); Start-Sleep -Milliseconds 300; [C]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 300 }
  if ([C]::GetForegroundWindow() -ne $h) { throw 'Test window is not in front; stopping before sending keys.' }
  $n0 = (Outcomes).Count; $before = Stable
  [C]::Down(0x11); [C]::Down(0x20); Start-Sleep -Milliseconds 900; [C]::Up(0x20); [C]::Up(0x11)
  $idle = WaitIdle; $after = Stable
  $o = @(Outcomes); $outcome = if ($o.Count -gt $n0) { $o[-1] } else { 'nothing inserted' }
  @(($after.Substring([Math]::Min($before.Length, $after.Length))).Trim(), $outcome, $idle)
}

try {
  # --- Clipboard preservation ---
  $file = Join-Path $Work 'clip-file.txt'; Set-Content $file 'x'
  $cases = [ordered]@{
    'Text copied by a .NET app (OLE formats)' = { Set-Clipboard -Value 'Plain text from a .NET app' }
    'Unicode text'                            = { Set-Clipboard -Value 'Ünïcödé ✓ 日本語 — “quotes”' }
    'HTML and text (as from a browser)'       = { $d = New-Object System.Windows.Forms.DataObject; $d.SetData([System.Windows.Forms.DataFormats]::Html, "Version:0.9`r`nStartHTML:-1`r`nEndHTML:-1`r`nStartFragment:0`r`nEndFragment:0`r`n<b>bold</b> text"); $d.SetText('bold text'); [System.Windows.Forms.Clipboard]::SetDataObject($d, $true) }
    'Image'                                   = { $b = New-Object System.Drawing.Bitmap 40, 30; [System.Drawing.Graphics]::FromImage($b).Clear([System.Drawing.Color]::Coral); [System.Windows.Forms.Clipboard]::SetImage($b) }
    'File list (copied in Explorer)'          = { $c = New-Object System.Collections.Specialized.StringCollection; [void]$c.Add($file); [System.Windows.Forms.Clipboard]::SetFileDropList($c) }
    'Empty clipboard'                         = { [System.Windows.Forms.Clipboard]::Clear() }
  }
  foreach ($k in $cases.Keys) {
    & $cases[$k]; Start-Sleep -Milliseconds 300
    $fp0 = [C]::Fingerprint()
    $added, $outcome, $idle = Dictate '1320_10s.f32'
    $fp1 = [C]::Fingerprint()
    Check "$k : text inserted" ($added -like '*unhappy fortunes*') ("outcome {0}; pill hidden {1:N1} s after release; added {2} chars: '{3}'" -f $outcome, $idle, $added.Length, $added.Substring(0, [Math]::Min(40, $added.Length)))
    Check "$k : clipboard identical afterwards" ($fp0 -eq $fp1) $(if ($fp0 -eq $fp1) { "formats: $(($fp0 -split ' ' | ForEach-Object { ($_ -split '=')[0] }) -join ', ')" } else { "before [$fp0] after [$fp1]" })
  }
  # --- Voice activity detection ---
  foreach ($clip in 'silence_5s.f32', 'noise_5s.f32') {
    $added, $outcome, $idle = Dictate $clip
    Check "VAD: $clip inserts nothing" (-not $added) "outcome: $outcome; added '$added'"
  }
  $added, $outcome, $idle = Dictate '6930_15s.f32'
  Check 'VAD: real speech after silence still transcribed' ($added.Length -gt 100) "$($added.Length) chars, $outcome"
} finally {
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
  Stop-Process -Id $tgt.Id -Force -ErrorAction SilentlyContinue
  [C]::Up(0x20); [C]::Up(0x11)
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'clipboard-vad-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
