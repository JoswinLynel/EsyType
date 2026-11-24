# Navigation in the test build's own window: every sidebar item opens its page (by mouse, and by keyboard with the
# arrow keys and Enter), the footer shows the engine status, Settings has every section, Esc closes a dialog without
# acting, and a toast confirms an action. Keys go only to the test build's own window.
param([string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe", [string]$Work = "D:\AI Projects\Tools\e2e")
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Nv {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public static void Tap(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); keybd_event(v, 0, 2, UIntPtr.Zero); }
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); }
  public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-62} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

$lad = Join-Path $Work 'localappdata-nav'; $data = Join-Path $lad 'EsyAI\EsyType'; New-Item -ItemType Directory -Force $data | Out-Null
Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; undo_shortcut = 'Ctrl+F9'; paste_last_shortcut = 'Ctrl+F10'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false } |
  ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
$env:LOCALAPPDATA = $lad
$userClip = Get-Clipboard -Raw
function Front {
  for ($k = 0; $k -lt 6 -and [Nv]::GetForegroundWindow() -ne $h; $k++) { [Nv]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400 }
  if ([Nv]::GetForegroundWindow() -ne $h) { throw 'The test build window is not in front; no keys sent.' }
}
# Each page's own mark: its heading (Dictation has the practice box instead).
$pages = [ordered]@{ Dictation = 'Practice area'; Insights = 'Insights'; History = 'History'; Dictionary = 'Dictionary'; Snippets = 'Snippets'; Style = 'Style'; Scratchpad = 'Scratchpad' }
function OnPage($p) { if ($p -eq 'Dictation') { [bool](Find-El $root 'Practice area' $CT::Edit) } else { [bool](Find-All $root $CT::Text | Where-Object { $_.Current.Name -eq $pages[$p] }) } }

$app = Start-Process $Exe -PassThru -RedirectStandardError (Join-Path $Work 'nav-trace.txt'); Start-Sleep 9
try {
  $root = Get-AppWindow $app.Id 'EsyType'; $h = [IntPtr]$root.Current.NativeWindowHandle
  # 1. By mouse
  foreach ($p in $pages.Keys) { Invoke-El (Find-El $root $p $CT::Button); Start-Sleep 0.8; Check "Sidebar opens $p" (OnPage $p) '' }
  Invoke-El (Find-El $root 'EsyMeet*' $CT::Button -Like); Start-Sleep 0.8
  Check 'Sidebar opens EsyMeet, marked Soon, saying it is not built yet' ([bool](Find-El $root 'EsyMeet is coming' $CT::Text) -and [bool](Find-El $root '*Soon*' -Like)) ''
  # 2. By keyboard: from Dictation, Down moves to the next item, Enter opens it
  Invoke-El (Find-El $root 'Dictation' $CT::Button); Start-Sleep 0.8
  Front; (Find-El $root 'Dictation' $CT::Button).SetFocus(); Start-Sleep 0.3
  [Nv]::Tap(0x28); [Nv]::Tap(0x28); [Nv]::Tap(0x28); [Nv]::Tap(0x28); [Nv]::Tap(0x0D); Start-Sleep 0.8
  Check 'Keyboard: Down four times, Enter opens Dictionary' (OnPage 'Dictionary') ''
  [Nv]::Tap(0x26); [Nv]::Tap(0x0D); Start-Sleep 0.8
  Check 'Keyboard: Up, Enter opens History' (OnPage 'History') ''
  # 3. Footer status
  Check 'Footer shows the local engine and threads' ([bool](Find-El $root 'Local*Base*threads' $CT::Button -Like -Tries 20)) ''
  # 4. Settings is a panel with every section; Esc closes it; Ctrl+, opens it again
  $missing = @('General', 'Shortcuts', 'Recording', 'Speech', 'Models', 'History & Privacy', 'Permissions', 'About') |
    Where-Object { Open-Settings $root $_; @(Find-All $root $CT::Text | Where-Object { $_.Current.Name -eq $_ }).Count -eq 0 -and -not (Find-El $root $_ $CT::Text -Tries 3) }
  Check 'Settings panel shows every section with its title' ($missing.Count -eq 0) "missing: $($missing -join ', ')"
  Open-Settings $root 'Shortcuts'
  $keys = [bool](Find-El $root 'Change Hold to talk shortcut' $CT::Button) -and [bool](Find-El $root 'Change Paste last again shortcut' $CT::Button)
  Open-Settings $root 'Speech'
  Check 'Settings shows the shortcuts with Change buttons, and the threads in Speech' ($keys -and [bool](Find-El $root 'Processor threads*' $CT::ComboBox -Like)) ''
  Close-Settings $root
  Check 'Esc closes the Settings panel' (-not (Find-El $root 'General' $CT::Button -Tries 2) -and [bool](Find-El $root 'Scratchpad' $CT::Button)) ''
  Front; [Nv]::Down(0x11); [Nv]::Tap(0xBC); [Nv]::Up(0x11); Start-Sleep 0.8
  Check 'Ctrl+, opens Settings at the last section (Speech)' ([bool](Find-El $root 'Processor threads*' $CT::ComboBox -Like)) ''
  Close-Settings $root
  # 5. Esc closes a dialog without acting; a toast confirms Copy all
  Invoke-El (Find-El $root 'Scratchpad' $CT::Button); Start-Sleep 0.8
  Set-Val (Find-El $root 'Note' $CT::Edit) 'Shopping list'; Start-Sleep 1.5
  Invoke-El (Find-El $root 'Delete' $CT::Button); Start-Sleep 0.6
  $open = [bool](Find-El $root 'Delete this note?' $CT::Text)
  Front; [Nv]::Tap(0x1B); Start-Sleep 0.6
  Check 'Dialog opens; Esc closes it and keeps the note' ($open -and -not (Find-El $root 'Delete this note?' $CT::Text) -and [bool](Find-El $root 'Shopping list*' $CT::Button -Like)) ''
  Invoke-El (Find-El $root 'Copy all' $CT::Button); Start-Sleep 0.6
  Check 'Toast confirms Copy all' ([bool](Find-El $root 'Copied.' $CT::Text)) ''
} catch {
  "STOPPED: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
} finally {
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
  if ($userClip) { Set-Clipboard -Value $userClip }
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'nav-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
