# Reproduces the Windows 11 Notepad paste problem without touching the user's own Notepad tabs:
# opens a dedicated file, sends keys only while that file's tab is in front, then clears, saves and closes only that tab.
param([string]$File = "D:\AI Projects\Tools\e2e\esytype-notepad-probe.txt")
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public static class P {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] static extern bool OpenClipboard(IntPtr h);
  [DllImport("user32.dll")] static extern bool CloseClipboard();
  [DllImport("user32.dll")] static extern bool EmptyClipboard();
  [DllImport("user32.dll")] static extern IntPtr SetClipboardData(uint f, IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern uint RegisterClipboardFormat(string n);
  [DllImport("kernel32.dll")] static extern IntPtr GlobalAlloc(uint f, UIntPtr n);
  [DllImport("kernel32.dll")] static extern IntPtr GlobalLock(IntPtr h);
  [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr h);
  static void Put(uint fmt, byte[] data) { IntPtr g = GlobalAlloc(2, (UIntPtr)data.Length); Marshal.Copy(data, 0, GlobalLock(g), data.Length); GlobalUnlock(g); SetClipboardData(fmt, g); }
  public static void SetText(string t, bool exclude) {
    for (int i = 0; i < 20 && !OpenClipboard(IntPtr.Zero); i++) System.Threading.Thread.Sleep(20);
    EmptyClipboard();
    Put(13, Encoding.Unicode.GetBytes(t + "\0"));
    if (exclude) { byte[] z = new byte[4]; foreach (var n in new[]{"ExcludeClipboardContentFromMonitorProcessing","CanUploadToCloudClipboard","CanIncludeInClipboardHistory"}) Put(RegisterClipboardFormat(n), z); }
    CloseClipboard();
  }
  public static string Title() { var s = new StringBuilder(512); GetWindowText(GetForegroundWindow(), s, 512); return s.ToString(); }
  public static void Key(byte vk, bool up) { keybd_event(vk, 0, up ? 2u : 0u, UIntPtr.Zero); }
}
"@
$name = Split-Path $File -Leaf
Set-Content $File '' -Encoding ascii
Start-Process notepad.exe -ArgumentList "`"$File`"" | Out-Null
Start-Sleep 3
$win = $null
for ($i = 0; $i -lt 20 -and -not $win; $i++) {
  $win = [System.Windows.Automation.AutomationElement]::RootElement.FindAll('Children', [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { $_.Current.Name -like "*$name*" } | Select-Object -First 1
  if (-not $win) { Start-Sleep -Milliseconds 300 }
}
if (-not $win) { throw "Notepad tab for $name not found" }
$h = [IntPtr]$win.Current.NativeWindowHandle
function Ours { [P]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 300; ([P]::Title()) -like "*$name*" }
function Keys([byte[]]$down) { if (-not (Ours)) { throw "Our Notepad tab is not in front; stopping without sending keys." }; foreach ($k in $down) { [P]::Key($k, $false) }; [array]::Reverse($down); foreach ($k in $down) { [P]::Key($k, $true) } }
function Doc { $d = $win.FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Document))); ([string]$d.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(-1)).Trim() }
function Clear { Keys 0x11, 0x41; Keys 0x08; Start-Sleep -Milliseconds 300 }   # Backspace: Delete needs the extended-key flag

$text = '"The task will not be difficult," returned David, hesitating. "Though I greatly fear your presence would rather increase than mitigate his unhappy fortunes."'
# Mirrors the app: clipboard set with history markers, Ctrl+V as one burst, original clipboard restored afterwards.
foreach ($v in @(@{gap=0; restore=500}, @{gap=0; restore=-1}, @{gap=250; restore=500}, @{gap=250; restore=1500})) {
  Clear
  Set-Clipboard -Value 'ORIGINAL'
  $before = Doc
  if (-not (Ours)) { throw "Our Notepad tab is not in front" }
  [P]::SetText($text, $true)
  Start-Sleep -Milliseconds $v.gap
  [P]::Key(0x11, $false); [P]::Key(0x56, $false); [P]::Key(0x56, $true); [P]::Key(0x11, $true)
  if ($v.restore -ge 0) { Start-Sleep -Milliseconds $v.restore; Set-Clipboard -Value 'ORIGINAL' }
  Start-Sleep 2
  $got = Doc; $added = $got.Substring([Math]::Min($before.Length, $got.Length))
  "gap {0,4} ms, restore {1,5} -> added {2,3} chars: {3}" -f $v.gap, $(if ($v.restore -lt 0) { 'never' } else { "$($v.restore) ms" }), $added.Length, $added.Substring(0, [Math]::Min(50, $added.Length))
}
# Tidy up only our own tab: empty it, save our file, close the tab.
Clear; Keys 0x11, 0x53; Start-Sleep 1; Keys 0x11, 0x57; Start-Sleep 1
"closed our tab: $(-not (([P]::Title()) -like "*$name*"))"
