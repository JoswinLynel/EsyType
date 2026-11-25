# Milestone 6.1 (themes and glass) in the test build's own window and own profile, read through WebView2's debugging
# port (this test process only). Nothing is typed into any window; pages and the Theme setting are driven in the page.
#  - default "system" follows Windows' app mode; Light, Dark and back to Follow Windows; saved, kept after a restart
#  - the title bar follows the theme (DWM immersive dark mode); the pill stays dark whatever the window's theme
#  - frosted glass follows Windows' Transparency effects switch
#  - every page and the confirmation dialog, in both themes: every visible text passes WCAG AA contrast against what is
#    actually drawn behind it, and in Light no dark-theme colour is left over
param([string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe", [string]$Work = "D:\AI Projects\Tools\e2e")
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Th {
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int v, int size);
  public static int DarkTitle(IntPtr h) { int v; return DwmGetWindowAttribute(h, 20, out v, 4) == 0 ? v : -1; }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-64} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }
$seed = Join-Path $PSScriptRoot 'data-seed.py'
$lad = Join-Path $Work 'localappdata-theme'; $data = Join-Path $lad 'EsyAI\EsyType'; $settingsFile = Join-Path $data 'settings.json'
if (Test-Path $lad) { Remove-Item $lad -Recurse -Force }
New-Item -ItemType Directory -Force $data | Out-Null
# no "theme" key: an older settings file
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; undo_shortcut = 'Ctrl+F9'; paste_last_shortcut = 'Ctrl+F10'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false; setup_done = $true } |
  ConvertTo-Json | Set-Content $settingsFile -Encoding ascii
$env:LOCALAPPDATA = $lad
$Port = 9336; $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--remote-debugging-port=$Port"
$trace = Join-Path $Work 'theme-trace.txt'
$personalize = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue
$windowsDark = $personalize.AppsUseLightTheme -eq 0
$windowsGlass = $personalize.EnableTransparency -ne 0

function Connect($t) {
  $s = New-Object System.Net.WebSockets.ClientWebSocket; $s.ConnectAsync([Uri]$t.webSocketDebuggerUrl, [Threading.CancellationToken]::None).Wait(); $s
}
function Launch {
  $script:app = Start-Process $Exe -PassThru -RedirectStandardError $trace; Start-Sleep 9
  $script:root = Get-AppWindow $app.Id 'EsyType'; $script:h = [IntPtr]$root.Current.NativeWindowHandle
  $all = @((Invoke-RestMethod "http://127.0.0.1:$Port/json") | Where-Object type -eq 'page')
  $script:ws = Connect ($all | Where-Object { $_.url -notmatch 'pill|prompt' } | Select-Object -First 1)
  $script:pillWs = Connect ($all | Where-Object { $_.url -match 'pill' } | Select-Object -First 1)
}
function Stop-App { if ($app) { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue; Start-Sleep 2 } }
function JsOn($sock, [string]$expr) {
  $json = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $expr; returnByValue = $true; awaitPromise = $true } } | ConvertTo-Json -Depth 4 -Compress
  $sock.SendAsync([ArraySegment[byte]][Text.Encoding]::UTF8.GetBytes($json), 'Text', $true, [Threading.CancellationToken]::None).Wait()
  $buf = New-Object byte[] 1048576
  while ($true) {
    $sb = New-Object Text.StringBuilder
    do { $r = $sock.ReceiveAsync([ArraySegment[byte]]$buf, [Threading.CancellationToken]::None).Result; [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)) } while (-not $r.EndOfMessage)
    $m = $sb.ToString() | ConvertFrom-Json; if ($m.id -eq 1) { return $m.result.result.value }
  }
}
function Js([string]$expr) { JsOn $ws $expr }
function Dark { Js "matchMedia('(prefers-color-scheme: dark)').matches" }
function Bg { Js "getComputedStyle(document.body).backgroundColor" }
# Settings is a panel over the window (since the Mac design): Esc closes it before going to another page.
function CloseSettings { Js "(()=>{if(!document.querySelector('.settings-panel'))return false;window.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));return true})()" | Out-Null; Start-Sleep 0.4 }
function Go([string]$page) {
  CloseSettings
  Js "(()=>{const b=[...document.querySelectorAll('.side nav button')].find(b=>b.querySelector('.side-label')?.textContent.trim()==='$page');b.click();return !!b})()" | Out-Null; Start-Sleep 0.9
}
function Section([string]$name) { Js "(()=>{const b=[...document.querySelectorAll('.settings-side button')].find(b=>b.textContent.trim()==='$name');b.click();return !!b})()" | Out-Null; Start-Sleep 0.6 }
$themeNames = @{ system = 'Follow Windows'; dark = 'Dark'; light = 'Light' }
function SetTheme([string]$v) {
  Go 'Settings'; Section 'General'
  Js "(()=>{const b=[...document.querySelectorAll('.seg button')].find(b=>b.textContent.trim()==='$($themeNames[$v])');b.click();return !!b})()" | Out-Null
  Start-Sleep 1.5
  CloseSettings
}
function Saved { (Get-Content $settingsFile -Raw | ConvertFrom-Json).theme }

# Contrast of every visible text against what is drawn behind it (translucent layers composited over the page).
$audit = @'
(() => {
  const num = (c) => { let m = c.match(/^rgba?\(([^)]+)\)/); if (m) { const p = m[1].split(/[ ,\/]+/).filter(Boolean).map(Number); return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1]; }
    m = c.match(/^color\(srgb ([^)]+)\)/); if (m) { const p = m[1].split(/[ \/]+/).filter(Boolean).map(Number); return [p[0] * 255, p[1] * 255, p[2] * 255, p.length > 3 ? p[3] : 1]; }
    return null; };
  const over = (top, under) => { const a = top[3]; return [0, 1, 2].map((i) => top[i] * a + under[i] * (1 - a)).concat(1); };
  const lum = (c) => { const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]); };
  const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
  const page = num(getComputedStyle(document.body).backgroundColor);
  const behind = (el) => { const layers = []; for (let e = el; e && e !== document.documentElement; e = e.parentElement) { const c = num(getComputedStyle(e).backgroundColor); if (c && c[3] > 0) { layers.push(c); if (c[3] >= 1) break; } }
    let bg = page; for (let i = layers.length - 1; i >= 0; i--) bg = over(layers[i], bg); return bg; };
  const out = []; let checked = 0, darkLeft = [];
  const lightTheme = !matchMedia('(prefers-color-scheme: dark)').matches;
  const root = document.querySelector('.dialog') || document.querySelector('.settings-panel') || document.body;
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const seen = new Set();
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    const el = n.parentElement; if (!el || seen.has(el) || !n.textContent.trim()) continue; seen.add(el);
    if (el.closest('.sr-only, .side-label, option, script, style, [hidden]') || el.closest('button:disabled')) continue;
    const r = el.getBoundingClientRect(); if (!r.width || !r.height) continue;
    const st = getComputedStyle(el); if (st.visibility === 'hidden' || st.display === 'none') continue;
    let op = 1; for (let e = el; e; e = e.parentElement) op *= Number(getComputedStyle(e).opacity); if (op < 0.99) continue; // fading or disabled-looking
    const bg = behind(el); const fg0 = num(st.color); if (!fg0) continue; const fg = over(fg0, bg);
    const size = parseFloat(st.fontSize), bold = Number(st.fontWeight) >= 700; const large = size >= 24 || (bold && size >= 18.66);
    const rq = large ? 3 : 4.5, k = ratio(fg, bg); checked++;
    if (k < rq) out.push({ text: n.textContent.trim().slice(0, 40), ratio: Math.round(k * 100) / 100, need: rq });
  }
  if (lightTheme) for (const el of document.querySelectorAll('body *')) {
    if (el.closest('.btn.primary, .btn.dark, .badge, .steps, .progress, .meter, .btn.danger-fill, .sr-only, .hero, .hero-pill')) continue;
    const r = el.getBoundingClientRect(); if (!r.width || !r.height) continue;
    const c = num(getComputedStyle(el).backgroundColor); if (c && c[3] > 0.5 && lum(c) < 0.05) darkLeft.push(el.className || el.tagName);
  }
  out.sort((a, b) => a.ratio - b.ratio);
  return JSON.stringify({ checked, fails: out.slice(0, 8), failCount: out.length, darkLeft: [...new Set(darkLeft)].slice(0, 8) });
})()
'@
$pages = 'Dictation', 'EsyMeet', 'Insights', 'History', 'Dictionary', 'Snippets', 'Style', 'Scratchpad'
$sections = 'General', 'Shortcuts', 'Recording', 'Speech', 'Models', 'Meetings', 'History & Privacy', 'Permissions', 'About'
function AuditAll([string]$label) {
  $views = @($pages | ForEach-Object { @{ name = "$_ page"; go = [scriptblock]::Create("Go '$_'") } }) + @($sections | ForEach-Object { @{ name = "Settings, $_"; go = [scriptblock]::Create("if (-not (Js `"!!document.querySelector('.settings-panel')`")) { Go 'Settings' }; Section '$_'") } })
  foreach ($v in $views) {
    & $v.go; $p = $v.name
    $a = Js $audit | ConvertFrom-Json
    Check "$label, ${p}: all text passes AA contrast" ($a.failCount -eq 0 -and $a.checked -gt $(if ($p -match "EsyMeet|Insights") { 2 } else { 5 })) ("{0} texts checked{1}" -f $a.checked, $(if ($a.failCount) { "; $($a.failCount) below: " + (($a.fails | ForEach-Object { "'$($_.text)' $($_.ratio)/$($_.need)" }) -join '; ') } else { '' }))
    if ($label -eq 'Light') { Check "Light, ${p}: no dark colour left over" (@($a.darkLeft).Count -eq 0) (($a.darkLeft) -join ', ') }
  }
  # the confirmation dialog (Delete all history, cancelled), over a frosted backdrop
  Go 'History'
  Js "(()=>{const b=[...document.querySelectorAll('button')].find(b=>/^Delete all/.test(b.textContent.trim()));if(b)b.click();return !!b})()" | Out-Null; Start-Sleep 0.8
  $a = Js $audit | ConvertFrom-Json
  $open = Js "!!document.querySelector('.dialog')"
  Check "$label, confirmation dialog: all text passes AA contrast" ($open -and $a.failCount -eq 0) ("dialog open: $open; {0} texts{1}" -f $a.checked, $(if ($a.failCount) { "; below: " + (($a.fails | ForEach-Object { "'$($_.text)' $($_.ratio)/$($_.need)" }) -join '; ') } else { '' }))
  Js "(()=>{const b=[...document.querySelectorAll('.dialog button')].find(b=>b.textContent.trim()==='Cancel');if(b)b.click();return !!b})()" | Out-Null; Start-Sleep 0.5
}

try {
  Launch; Stop-App   # first start creates the database; then fill it so lists, chips and entries are drawn
  python -I $seed many (Join-Path $data 'esytype.db')
  Launch
  Check 'No theme saved yet: follows Windows (light or dark)' ((Dark) -eq $windowsDark) ("Windows dark: $windowsDark; page dark: $(Dark); background $(Bg)")
  Check 'Frosted glass follows Windows'' Transparency effects' ((Js 'document.documentElement.dataset.glass') -eq $(if ($windowsGlass) { 'on' } else { 'off' })) ("Windows: $windowsGlass; page: $(Js 'document.documentElement.dataset.glass')")
  $before = Get-Content $settingsFile -Raw
  Check 'Starting does not rewrite the settings file' ((Get-Content $settingsFile -Raw) -eq $before -and -not (Saved)) ''

  SetTheme 'light'
  Check 'Light: page light, title bar light, saved' (-not (Dark) -and (Bg) -eq 'rgb(255, 255, 255)' -and [Th]::DarkTitle($h) -eq 0 -and (Saved) -eq 'light') ("background $(Bg); dark title bar $([Th]::DarkTitle($h)); saved '$(Saved)'")
  $pillText = JsOn $pillWs "(()=>{const d=document.createElement('span');d.style.color='var(--et-text-2)';document.body.appendChild(d);const c=getComputedStyle(d).color;d.remove();return c+' / '+getComputedStyle(document.body).colorScheme})()"
  Check 'Light: the pill stays dark (light text, dark scheme)' ($pillText -eq 'rgba(255, 255, 255, 0.8) / dark') $pillText
  AuditAll 'Light'

  # The hero's voice wave: drawn on its canvas; still while the window is not in front (the test window is in the background)
  Go 'Dictation'
  $paint = "(()=>{const c=document.querySelector('.hero canvas');if(!c)return 'none';const d=c.getContext('2d').getImageData(0,0,c.width,c.height).data;let n=0,h=0;for(let i=0;i<d.length;i+=4){if(d[i+3]){n++;h=(h*31+d[i]+d[i+1]*7+d[i+2]*13)%1000003}}return c.width+'x'+c.height+' '+n+' '+h})()"
  $w1 = Js $paint; Start-Sleep 0.5; $w2 = Js $paint
  Check 'Hero wave drawn on its canvas, in the logo colours' ($w1 -match '^\d+x\d+ (\d+)' -and [int]$Matches[1] -gt 500 -and (Js "(()=>{const d=document.createElement('i');d.style.color='var(--et-mark-mid)';document.body.appendChild(d);const c=getComputedStyle(d).color;d.remove();return c})()") -eq 'rgb(255, 255, 255)') $w1
  Check 'Hero wave still while the window is not in front' ((Js 'document.hasFocus()') -or $w1 -eq $w2) "focus $(Js 'document.hasFocus()'); $w1 / $w2"
  # Fold the Dictionary hero into the pill beside the title; remembered after a restart
  Go 'Dictionary'
  Js "document.querySelector('.hero .switch').click()" | Out-Null; Start-Sleep 0.5
  $folded = Js "!document.querySelector('.hero') && !!document.querySelector('.title-row .hero-pill canvas')"

  Stop-App; Launch
  Go 'Dictionary'
  Check 'Hero folds into a pill beside the title, remembered after a restart' ($folded -and (Js "!document.querySelector('.hero') && !!document.querySelector('.hero-pill')")) "folded $folded"
  Js "document.querySelector('.hero-pill .switch').click()" | Out-Null; Start-Sleep 0.5
  Check 'Hero unfolds again' (Js "!!document.querySelector('.hero') && !document.querySelector('.hero-pill')") ''
  Check 'Light kept after a restart (page and title bar)' (-not (Dark) -and [Th]::DarkTitle($h) -eq 0) ("background $(Bg)")

  SetTheme 'dark'
  Check 'Dark: page dark, title bar dark, saved' ((Dark) -and (Bg) -eq 'rgb(11, 11, 12)' -and [Th]::DarkTitle($h) -eq 1 -and (Saved) -eq 'dark') ("background $(Bg); dark title bar $([Th]::DarkTitle($h)); saved '$(Saved)'")
  AuditAll 'Dark'

  SetTheme 'system'
  Check 'Follow Windows again: matches Windows, saved' ((Dark) -eq $windowsDark -and (Saved) -eq 'system') ("page dark: $(Dark); saved '$(Saved)'")

  # Transparency effects off (simulated in the test build only; the Windows setting is not touched): everything solid
  Go 'History'
  Js "(()=>{const b=[...document.querySelectorAll('button')].find(b=>/^Delete all/.test(b.textContent.trim()));if(b)b.click();return !!b})()" | Out-Null; Start-Sleep 0.8
  $onBlur = Js "getComputedStyle(document.querySelector('.dialog')).backdropFilter"
  Stop-App
  $env:ESYTYPE_TEST_TRANSPARENCY = '0'
  Launch
  Go 'History'
  Js "(()=>{const b=[...document.querySelectorAll('button')].find(b=>/^Delete all/.test(b.textContent.trim()));if(b)b.click();return !!b})()" | Out-Null; Start-Sleep 0.8
  $off = Js "(()=>{const d=document.querySelector('.dialog'),s=document.querySelector('.scrim');return document.documentElement.dataset.glass+' | dialog '+getComputedStyle(d).backdropFilter+' '+getComputedStyle(d).backgroundColor+' | scrim '+getComputedStyle(s).backdropFilter})()"
  Check 'Transparency effects on: the dialog is frosted' ($onBlur -match 'blur') "dialog backdrop: $onBlur"
  Check 'Transparency effects off: solid dialog and backdrop, no glass' ($off -match '^off \| dialog none rgb\(' -and $off -match 'scrim none$') $off
  Remove-Item Env:ESYTYPE_TEST_TRANSPARENCY
} catch {
  "STOPPED: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
} finally {
  Stop-App
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'theme-results.json') -Encoding utf8
"{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
