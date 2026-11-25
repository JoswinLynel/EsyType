# Insights (Mac design, milestone C) in the test build's own window and own profile, read through WebView2's
# debugging port (this test process only). Nothing is typed anywhere. Seeded usage totals (data-seed.py insights)
# give known values: the four tiles, words per day for 7/30/90 days with the average, the 18-week activity grid,
# this week with the split by kind of app, "How?" for Time saved, and the typing speed saved from the stepper.
param([string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe", [string]$Work = "D:\AI Projects\Tools\e2e")
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uia.ps1')
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-64} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }
$seed = Join-Path $PSScriptRoot 'data-seed.py'
$lad = Join-Path $Work 'localappdata-insights'; $data = Join-Path $lad 'EsyAI\EsyType'; $file = Join-Path $data 'settings.json'; $db = Join-Path $data 'esytype.db'
if (Test-Path $lad) { Remove-Item $lad -Recurse -Force }; New-Item -ItemType Directory -Force $data | Out-Null
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false; setup_done = $true } | ConvertTo-Json | Set-Content $file -Encoding ascii
$env:LOCALAPPDATA = $lad
$Port = 9337; $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--remote-debugging-port=$Port"

function Launch {
  $script:app = Start-Process $Exe -PassThru -RedirectStandardError (Join-Path $Work 'insights-trace.txt'); Start-Sleep 9
  $script:root = Get-AppWindow $app.Id 'EsyType'
  $t = @((Invoke-RestMethod "http://127.0.0.1:$Port/json") | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'pill|prompt' })[0]
  $script:ws = New-Object System.Net.WebSockets.ClientWebSocket; $ws.ConnectAsync([Uri]$t.webSocketDebuggerUrl, [Threading.CancellationToken]::None).Wait()
}
function Quit { if ($app) { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue; Start-Sleep 2 } }
function Js([string]$expr) {
  $json = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $expr; returnByValue = $true; awaitPromise = $true } } | ConvertTo-Json -Depth 4 -Compress
  $ws.SendAsync([ArraySegment[byte]][Text.Encoding]::UTF8.GetBytes($json), 'Text', $true, [Threading.CancellationToken]::None).Wait()
  $buf = New-Object byte[] 1048576
  while ($true) {
    $sb = New-Object Text.StringBuilder
    do { $r = $ws.ReceiveAsync([ArraySegment[byte]]$buf, [Threading.CancellationToken]::None).Result; [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)) } while (-not $r.EndOfMessage)
    $m = $sb.ToString() | ConvertFrom-Json; if ($m.id -eq 1) { return $m.result.result.value }
  }
}
function Go([string]$page) { Js "(()=>{const b=[...document.querySelectorAll('.side nav button')].find(b=>b.querySelector('.side-label')?.textContent.trim()==='$page');b.click();return !!b})()" | Out-Null; Start-Sleep 1.6 }
function Click([string]$sel, [string]$text) { Js "(()=>{const b=[...document.querySelectorAll('$sel')].find(b=>b.textContent.trim()==='$text');if(b)b.click();return !!b})()" | Out-Null; Start-Sleep 0.8 }
function Tile([int]$i) { Js "(()=>{const t=document.querySelectorAll('.tile')[$i];return t?[...t.children].map(c=>c.textContent.trim()).join(' | '):''})()" }
function Text([string]$sel) { Js "(()=>{const e=document.querySelector('$sel');return e?e.textContent.trim():''})()" }

try {
  Launch; Quit
  $want = python -I $seed insights $db | ConvertFrom-Json
  Launch
  Go 'Insights'
  Check 'Words dictated: the total, since the first day' ((Tile 0) -match "^$([regex]::Escape($want.words)) \| Words dictated \| since ") (Tile 0)
  Check 'Words per minute: speaking speed' ((Tile 1) -match "^$($want.wpm) \| Words per minute \| speaking, not typing") (Tile 1)
  Check 'Time saved at 40 wpm typing' ((Tile 2) -match "^$([regex]::Escape($want.saved40)) \| Time saved \| at 40 wpm typing") "$(Tile 2) / want $($want.saved40)"
  Check 'Meetings transcribed: "—", comes with EsyMeet' ((Tile 3) -eq '— | Meetings transcribed | comes with EsyMeet') (Tile 3)
  Click '.tile button' 'How?'
  $how = Text '.how'
  Check 'How? shows the sum' ($how -match '^Typing .+ words at 40 wpm: .+ − speaking .+ − processing .+ = .+ saved\.$' -and $how -match [regex]::Escape($want.saved40)) $how

  foreach ($n in 30, 7, 90) {
    Click '.chart-head .seg button' "$n days"
    $bars = Js "document.querySelectorAll('.bars-plot .bar').length"
    $head = Text '.chart-head .small'; $avg = Text '.avg-label'
    Check "Words per day, $n days: $n bars, total and average" ($bars -eq $n -and $head -eq "$($want.span."$n"[0]) words in $n days" -and $avg -eq "avg $($want.span."$n"[1])") "$bars bars; '$head'; '$avg'"
  }
  $cells = Js "(()=>{const c=[...document.querySelectorAll('.heat-grid .cell')];return c.length+'/'+c.filter(x=>Number(x.dataset.level)>0).length+'/'+c.filter(x=>x.dataset.level==='4').length})()"
  Check 'Activity: 18 weeks x 7 days; active days coloured; one busiest day' ($cells -eq "126/$($want.active)/1") "$cells (want 126/$($want.active)/1)"
  $tip = Js "document.querySelector('.heat-grid .cell[data-level=""4""]').title"
  Check 'Activity: a day shows its words on hover' ($tip -eq $want.busiest_tip) "'$tip' / want '$($want.busiest_tip)'"
  Check 'Activity: one summary for screen readers' ((Js "document.querySelector('.heat').getAttribute('aria-label')") -match "^$($want.active) days with dictation in the last 18 weeks; busiest day $([regex]::Escape($want.busiest)) words") ''
  $mini = Js "[...document.querySelectorAll('.mini-stats div')].map(d=>d.textContent.trim()).join(' | ')"
  Check 'Activity: streak, busiest day, words a day when active' ($mini -match "^3day streak \| .+busiest day \| $([regex]::Escape($want.per_active))words a day when active$") $mini
  Check 'This week: total words' ((Text '.week h2 + .small') -eq "$($want.week) words") (Text '.week h2 + .small')
  $kinds = Js "[...document.querySelectorAll('.kinds li')].map(l=>l.querySelector('.kind-name').textContent+'='+l.querySelector('.kind-pct').textContent).join(',')"
  $wantKinds = ($want.kinds.PSObject.Properties | Sort-Object { -$_.Value } | ForEach-Object { "$($_.Name)=$($_.Value)%" })
  Check 'This week: split by kind of app, largest first' ((@($kinds -split ',') | Sort-Object) -join ',' -eq ((@($wantKinds) | Sort-Object) -join ',')) "$kinds / want $($wantKinds -join ',')"

  Click '.stepper button' '+'
  Start-Sleep 0.8
  $saved = (Get-Content $file -Raw | ConvertFrom-Json).typing_wpm
  Check 'Typing speed: + saves 45 wpm; Time saved follows' ($saved -eq 45 -and (Tile 2) -match "^$([regex]::Escape($want.saved45)) \| Time saved \| at 45 wpm typing") "saved $saved; $(Tile 2)"
} catch {
  "STOPPED: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
} finally {
  Quit
  Remove-Item Env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS -ErrorAction SilentlyContinue
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'insights-results.json') -Encoding utf8
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
