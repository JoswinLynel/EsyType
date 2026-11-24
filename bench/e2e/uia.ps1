# UI Automation helpers for driving EsyType's own window in tests (dot-source this file).
# They act only on the window handle passed in, never on other applications.
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$script:UA = [System.Windows.Automation.AutomationElement]
$script:CT = [System.Windows.Automation.ControlType]

# Retries for up to about 2 s: WebView2 builds its accessibility tree only when first asked.
function Find-El($root, [string]$name, $type, [switch]$Like, [int]$Tries = 10) {
  for ($t = 0; $t -lt $Tries; $t++) {
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($e in $all) {
      $n = $e.Current.Name
      if (($Like -and $n -like $name) -or (-not $Like -and $n -eq $name)) { if (-not $type -or $e.Current.ControlType -eq $type) { return $e } }
    }
    Start-Sleep -Milliseconds 200
  }
}
function Find-All($root, $type) { @($root.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition($UA::ControlTypeProperty, $type)))) }
function Invoke-El($e) {
  if (-not $e) { throw 'element not found' }
  $p = $null
  if ($e.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$p)) { $p.Invoke() }
  elseif ($e.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$p)) { $p.Toggle() }
  else { throw "cannot click $($e.Current.Name)" }
}
function Set-Val($e, [string]$v) { $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($v) }
function Toggled($e) { $e.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -eq 'On' }
# Answers a JavaScript confirm() raised by the window: 'OK' or 'Cancel'. Returns the dialog text.
function Answer-Dialog($root, [string]$button, [switch]$Like) {
  for ($i = 0; $i -lt 40; $i++) {
    $b = Find-El $root $button $CT::Button -Like:$Like
    if ($b) { $text = (Find-All $root $CT::Text | ForEach-Object { $_.Current.Name }) -join ' | '; Invoke-El $b; return $text }
    Start-Sleep -Milliseconds 100
  }
  throw "no dialog with a '$button' button"
}

# The top-level window called $name that belongs to process $id (never another program's window with the same title).
# Uses EnumWindows rather than UI Automation's desktop list, which waits on any window that is not responding.
Add-Type @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class AppWin {
  delegate bool Cb(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(Cb cb, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  public static List<object[]> All() {
    var list = new List<object[]>();
    EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); var b = new StringBuilder(256); GetWindowText(h, b, 256);
      if (b.Length > 0 && IsWindowVisible(h)) list.Add(new object[] { h, (int)p, b.ToString() }); return true; }, IntPtr.Zero);
    return list;
  }
  public static IntPtr Find(uint pid, string title) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p != pid) return true;
      var b = new StringBuilder(256); GetWindowText(h, b, 256); if (b.ToString() == title) { found = h; return false; } return true; }, IntPtr.Zero);
    return found;
  }
}
"@
function Get-AppWindow([int]$id, [string]$name) {
  for ($i = 0; $i -lt 20; $i++) {
    $h = [AppWin]::Find([uint32]$id, $name)
    if ($h -ne [IntPtr]::Zero) { return $UA::FromHandle($h) }
    Start-Sleep -Milliseconds 500
  }
  throw "No '$name' window in process $id"
}

# Visible top-level windows whose title is -like $pattern (optionally only in processes $ids), as UI Automation elements
# (the test build also has hidden windows with the same titles).
# Safe while another program is not responding, unlike listing the desktop through UI Automation.
function Get-TopWindows([string]$pattern, [int[]]$ids) {
  [AppWin]::All() | Where-Object { $_[2] -like $pattern -and (-not $ids -or $_[1] -in $ids) } | ForEach-Object { $UA::FromHandle([IntPtr]$_[0]) }
}

# Settings is a panel over the window (since the Mac design, 24 Nov), one section at a time.
function Open-Settings($root, [string]$section = 'General') {
  if (-not (Find-El $root 'General' $CT::Button -Tries 1)) { Invoke-El (Find-El $root 'Settings' $CT::Button); Start-Sleep 0.8 }
  Invoke-El (Find-El $root $section $CT::Button); Start-Sleep 0.8
}
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class SetWin { [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid); [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra); }
"@
# Esc closes the panel. The key goes only to this window: it is brought to the front and checked first. Windows lets a
# background script bring a window forward after an Alt tap; that tap is sent only while the window in front belongs to
# the test build or to a test window of the suite (-Allow process ids), never to anyone else's.
function Close-Settings($root, [int[]]$Allow = @()) {
  if (-not (Find-El $root 'General' $CT::Button -Tries 1)) { return }
  $h = [IntPtr]$root.Current.NativeWindowHandle; $own = @([int]$root.Current.ProcessId) + $Allow
  for ($k = 0; $k -lt 8 -and [SetWin]::GetForegroundWindow() -ne $h; $k++) {
    $fgPid = [uint32]0; [void][SetWin]::GetWindowThreadProcessId([SetWin]::GetForegroundWindow(), [ref]$fgPid)
    if ($k -gt 0 -and $own -contains [int]$fgPid) { [SetWin]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [SetWin]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero) }
    [SetWin]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 300
  }
  if ([SetWin]::GetForegroundWindow() -ne $h) { throw 'EsyType is not in front; Esc not sent.' }
  Add-Type -AssemblyName System.Windows.Forms
  [System.Windows.Forms.SendKeys]::SendWait('{ESC}'); Start-Sleep 0.6
}

# EsyType keeps a pasted dictation on the clipboard for 1-3 s after the program takes it (Word reads it several
# times), then puts the user's clipboard back: waits for that.
function Wait-Clipboard($value, [double]$seconds = 5) {
  $t = [Diagnostics.Stopwatch]::StartNew()
  while ($t.Elapsed.TotalSeconds -lt $seconds) { if ((Get-Clipboard -Raw) -eq $value) { return $true }; Start-Sleep -Milliseconds 100 }
  $false
}
