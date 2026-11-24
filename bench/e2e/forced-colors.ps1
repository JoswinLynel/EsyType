# Screenshots of every page, a dialog and the recording pill with Windows high-contrast (forced colours) emulated
# inside the test build only: its WebView2 gets a debugging port through an environment variable set for that one
# process, and the emulation is switched on through it. Windows' own contrast setting is not touched.
param([string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe", [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio", [string]$Out = "D:\AI Projects\Tools\e2e\forced-colors", [int]$Port = 9333)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Fc {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
}
"@
New-Item -ItemType Directory -Force $Out | Out-Null
$lad = Join-Path $Work 'localappdata-polish'   # the profile polish-e2e.ps1 leaves behind (seeded)
if (-not (Test-Path (Join-Path $lad 'EsyAI\EsyType\esytype.db'))) { throw 'Run polish-e2e.ps1 first: it leaves a seeded profile.' }
Copy-Item (Join-Path $Audio '6930_5s.f32') (Join-Path $Work 'current.f32') -Force
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = Join-Path $Work 'current.f32'
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--remote-debugging-port=$Port"

# A minimal Chrome DevTools Protocol client over the built-in WebSocket class.
function Connect($url) {
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  $ws.ConnectAsync([Uri]$url, [Threading.CancellationToken]::None).Wait(); $ws
}
$script:msgId = 0
function Send($ws, $method, $params = @{}) {
  $id = ++$script:msgId
  $json = @{ id = $id; method = $method; params = $params } | ConvertTo-Json -Depth 6 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $ws.SendAsync([ArraySegment[byte]]$bytes, 'Text', $true, [Threading.CancellationToken]::None).Wait()
  $buf = New-Object byte[] 1048576
  while ($true) {
    $sb = New-Object System.Text.StringBuilder
    do { $r = $ws.ReceiveAsync([ArraySegment[byte]]$buf, [Threading.CancellationToken]::None).Result; [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)) } while (-not $r.EndOfMessage)
    $m = $sb.ToString() | ConvertFrom-Json
    if ($m.id -eq $id) { if ($m.error) { throw "$method failed: $($m.error.message)" }; return $m.result }
  }
}
function Shot($ws, $name) { $r = Send $ws 'Page.captureScreenshot' @{ format = 'png' }; [IO.File]::WriteAllBytes((Join-Path $Out "$name.png"), [Convert]::FromBase64String($r.data)); $name }
function ForcedOn($ws) { Send $ws 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'forced-colors'; value = 'active' }, @{ name = 'prefers-contrast'; value = 'more' }) } | Out-Null }

$app = Start-Process $Exe -PassThru -RedirectStandardError (Join-Path $Work 'forced-trace.txt'); Start-Sleep 9
try {
  $root = Get-AppWindow $app.Id 'EsyType'; $h = [IntPtr]$root.Current.NativeWindowHandle
  $targets = Invoke-RestMethod "http://127.0.0.1:$Port/json"
  $main = Connect ($targets | Where-Object { $_.url -match 'index\.html|localhost/?$|tauri\.localhost/?$' -and $_.type -eq 'page' } | Select-Object -First 1).webSocketDebuggerUrl
  $pillT = $targets | Where-Object { $_.url -match 'pill' } | Select-Object -First 1
  ForcedOn $main
  # The dictation live region as the browser exposes it to screen readers
  Send $main 'Accessibility.enable' | Out-Null
  $obj = (Send $main 'Runtime.evaluate' @{ expression = "document.getElementById('dictation-status')" }).result.objectId
  $node = (Send $main 'Accessibility.getPartialAXTree' @{ objectId = $obj; fetchRelatives = $false }).nodes[0]
  $live = ($node.properties | Where-Object { $_.name -eq 'live' }).value.value
  "live region: role $($node.role.value), live $live -> $(if ($live -eq 'polite') { 'PASS' } else { 'FAIL' })"
  $saved = foreach ($p in 'Dictation', 'History', 'Dictionary', 'Snippets', 'Style', 'Scratchpad') {
    Invoke-El (Find-El $root $p $CT::Button); Start-Sleep 1; Shot $main "fc-$($p.ToLower())"
  }
  Open-Settings $root 'General'; $saved += Shot $main 'fc-settings'; Close-Settings $root
  Invoke-El (Find-El $root 'Dictionary' $CT::Button); Start-Sleep 0.8
  Invoke-El (Find-El $root 'Delete all' $CT::Button); Start-Sleep 0.8
  $saved += Shot $main 'fc-dialog'
  Invoke-El (Find-El $root 'Cancel' $CT::Button); Start-Sleep 0.5
  if ($pillT) {
    $pill = Connect $pillT.webSocketDebuggerUrl; ForcedOn $pill
    for ($k = 0; $k -lt 6 -and [Fc]::GetForegroundWindow() -ne $h; $k++) { [Fc]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400 }
    if ([Fc]::GetForegroundWindow() -ne $h) { throw 'The test build window is not in front; no keys sent.' }
    (Find-El $root 'Dictionary' $CT::Button).SetFocus()   # a button, not a text box: the dictation is not typed anywhere useful
    try { [Fc]::Down(0x11); [Fc]::Down(0x77); Start-Sleep -Milliseconds 700; $saved += Shot $pill 'fc-pill-recording' } finally { [Fc]::Up(0x77); [Fc]::Up(0x11) }
    Start-Sleep 0.4; $saved += Shot $pill 'fc-pill-processing'
    Start-Sleep 6
  } else { 'no pill target found' }
  "saved: $($saved -join ', ') in $Out"
} finally {
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
  [Fc]::Up(0x77); [Fc]::Up(0x11)
  Remove-Item Env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS -ErrorAction SilentlyContinue
}
