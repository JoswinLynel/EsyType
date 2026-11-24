# Milestone 4 (page polish) in the test build's own window, own profile:
#  - empty profile: each list page's empty state and its first-action button (where the cursor lands)
#  - every button at least 32 px high on every page
#  - seeded profile: headings with counts, toolbar order, no-match and Clear search, Esc in the search box,
#    Up/Down between rows, Esc cancels an edit, Enter / Ctrl+Enter saves, focus after a delete and after a dialog,
#    the toasts
#  - a test-audio dictation: the main window's live region and the tray's recording icon (the region's politeness is
#    read from the browser's accessibility tree by forced-colors.ps1)
# Keys go only to the test build's own window, after checking it is in front.
param([string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe", [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio")
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Po {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
  public static void Tap(byte v) { Down(v); Up(v); }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-64} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }
$seed = Join-Path $PSScriptRoot 'data-seed.py'
$lad = Join-Path $Work 'localappdata-polish'; $data = Join-Path $lad 'EsyAI\EsyType'; $db = Join-Path $data 'esytype.db'
if (Test-Path $lad) { Remove-Item $lad -Recurse -Force }
New-Item -ItemType Directory -Force $data | Out-Null
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; undo_shortcut = 'Ctrl+F9'; paste_last_shortcut = 'Ctrl+F10'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false; setup_done = $true; style_rules = @() } |
  ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
Copy-Item (Join-Path $Audio '6930_5s.f32') (Join-Path $Work 'current.f32') -Force
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = Join-Path $Work 'current.f32'; $env:ESYTYPE_EXPORT_DIR = Join-Path $Work 'polish-exports'
# The page's focus is set and read through WebView2's debugging port (this test process only): UI Automation's focus
# reporting for WebView2 content is not reliable enough to check keyboard behaviour. Keys are real key presses.
$Port = 9335; $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--remote-debugging-port=$Port"
$userClip = Get-Clipboard -Raw
$trace = Join-Path $Work 'polish-trace.txt'

function Launch {
  $script:app = Start-Process $Exe -PassThru -RedirectStandardError $trace; Start-Sleep 9
  $script:root = Get-AppWindow $app.Id 'EsyType'; $script:h = [IntPtr]$root.Current.NativeWindowHandle; $script:scale = [Po]::GetDpiForWindow($h) / 96
  $t = (Invoke-RestMethod "http://127.0.0.1:$Port/json") | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'pill' } | Select-Object -First 1
  $script:ws = New-Object System.Net.WebSockets.ClientWebSocket; $ws.ConnectAsync([Uri]$t.webSocketDebuggerUrl, [Threading.CancellationToken]::None).Wait()
}
function Js([string]$expr) {
  $json = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $expr; returnByValue = $true } } | ConvertTo-Json -Depth 4 -Compress
  $ws.SendAsync([ArraySegment[byte]][Text.Encoding]::UTF8.GetBytes($json), 'Text', $true, [Threading.CancellationToken]::None).Wait()
  $buf = New-Object byte[] 262144
  while ($true) {
    $sb = New-Object Text.StringBuilder
    do { $r = $ws.ReceiveAsync([ArraySegment[byte]]$buf, [Threading.CancellationToken]::None).Result; [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)) } while (-not $r.EndOfMessage)
    $m = $sb.ToString() | ConvertFrom-Json; if ($m.id -eq 1) { return $m.result.result.value }
  }
}
function Front {
  for ($k = 0; $k -lt 6 -and [Po]::GetForegroundWindow() -ne $h; $k++) { [Po]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400 }
  if ([Po]::GetForegroundWindow() -ne $h) { throw 'The test build window is not in front; no keys sent.' }
}
function Go($page) { Close-Settings $root; Invoke-El (Find-El $root $page $CT::Button); Start-Sleep 0.9 }
function Texts { Find-All $root $CT::Text | ForEach-Object { $_.Current.Name } }
function Has([string]$like) { [bool]((Texts) | Where-Object { $_ -like $like }) }
# The page's focused element: its accessible name (or text), then @ and its row in a list (-1 outside one).
function Active { Js "(()=>{const a=document.activeElement;const li=a.closest('ul.entries > li');return (a.getAttribute('aria-label')||a.textContent.trim().slice(0,40))+'@'+(li?[...li.parentElement.children].indexOf(li):-1)})()" }
# JavaScript for elements: a row's button by its text; an element by its accessible name; the empty state's button.
function RowBtn([int]$i, [string]$name) { "[...[...document.querySelectorAll('ul.entries > li')][$i].querySelectorAll('button')].find(b=>b.textContent==='$name')" }
function Named([string]$label) { "[...document.querySelectorAll('[aria-label]')].find(e=>e.getAttribute('aria-label')==='$label')" }
$emptyBtn = "document.querySelector('.empty button')"
# Keyboard onto an element (window in front first), then keys.
function FocusOn([string]$el) {
  for ($k = 0; $k -lt 5; $k++) {
    Front
    # The browser control inside the window must hold Windows' keyboard focus too, or keys stop at the window.
    if (-not (Js 'document.hasFocus()')) { $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition($UA::ControlTypeProperty, $CT::Document))).SetFocus(); Start-Sleep 0.3 }
    [void](Js "($el).focus()"); Start-Sleep 0.3
    $on = { (Js "document.hasFocus() && document.activeElement === ($el)") -and [Po]::GetForegroundWindow() -eq $h }
    if ((& $on) -and (Start-Sleep 0.3) -eq $null -and (& $on)) { return }   # twice: a late focus change would move it
  }
  throw "could not put the keyboard on $el"
}
function Press([string]$el) { FocusOn $el; [Po]::Tap(0x0D); Start-Sleep 0.8 }
function Q([string]$sql) { $r = python -I $seed query $db $sql; $v = $r | ConvertFrom-Json; , $v }
function Col([string]$sql) { @((python -I $seed query $db $sql | ConvertFrom-Json) | ForEach-Object { $_[0] }) }
function Rows { @(Find-All $root $CT::ListItem | Where-Object { $_.Current.BoundingRectangle.Height -gt 30 }) }
function Small($page) {
  @(Find-All $root $CT::Button | Where-Object { -not $_.Current.IsOffscreen -and $_.Current.BoundingRectangle.Height -gt 0 -and $_.Current.BoundingRectangle.Height -lt 31.5 * $scale } |
    ForEach-Object { "$page/$($_.Current.Name) $([math]::Round($_.Current.BoundingRectangle.Height / $scale))px" })
}

try {
  # ---------- 1. Empty profile ----------
  Launch
  $small = @()
  foreach ($p in 'Dictation', 'Insights', 'History', 'Dictionary', 'Snippets', 'Style', 'Scratchpad') { Go $p; $small += Small $p }
  foreach ($sec in 'General', 'Shortcuts', 'Recording', 'Speech', 'Models', 'History & Privacy', 'Permissions', 'About') { Open-Settings $root $sec; $small += Small "Settings, $sec" }
  Close-Settings $root
  Check 'Every visible button at least 32 px high, on every page' ($small.Count -eq 0) ($small -join '; ')

  Go 'History'
  $ok = (Has 'Nothing here yet') -and (Has 'Your dictations appear here as you speak.*')
  Press $emptyBtn
  Check 'History empty: Open Scratchpad puts the cursor in the note' ($ok -and (Active) -eq 'Note@-1') "focus: $(Active)"
  Go 'Dictionary'
  $ok = Has 'Your dictionary is empty'
  Press $emptyBtn
  Check 'Dictionary empty: Add a word puts the cursor in the word box' ($ok -and (Active) -eq 'Word or name, spelled as you want it@-1') "focus: $(Active)"
  Go 'Snippets'
  $ok = Has 'No snippets yet'
  Press $emptyBtn
  Check 'Snippets empty: Add a snippet puts the cursor in the trigger box' ($ok -and (Active) -eq 'Trigger@-1') "focus: $(Active)"
  Go 'Style'
  $ok = (Has 'No app rules yet') -and (Has 'Every app uses Standard.')
  Press $emptyBtn
  Check 'Style empty: names the default; Add a rule puts the cursor in Program' ($ok -and (Active) -eq 'Program@-1') "focus: $(Active)"
  Go 'Scratchpad'
  $ok = (Has 'No notes yet') -and (Js "document.querySelector('.empty button').textContent") -eq 'New note'
  Press $emptyBtn
  Check 'Scratchpad empty: New note puts the cursor in the note' ($ok -and (Active) -eq 'Note@-1') "focus: $(Active)"
  Stop-Process -Id $app.Id -Force; Start-Sleep 2

  # ---------- 2. Seeded profile ----------
  python -I $seed many $db
  $s = Get-Content (Join-Path $data 'settings.json') -Raw | ConvertFrom-Json
  $s | Add-Member style_rules @(@{ app = 'slack.exe'; style = 'casual' }, @{ app = 'WINWORD.EXE'; style = 'professional' }) -Force
  $s | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
  Launch

  # No empty state while a seeded list loads
  Invoke-El (Find-El $root 'Dictionary' $CT::Button)
  $flash = $false; $t0 = Get-Date
  while (((Get-Date) - $t0).TotalMilliseconds -lt 1000) { if (Has 'Your dictionary is empty') { $flash = $true; break }; Start-Sleep -Milliseconds 30 }
  $n = (Rows).Count
  Check 'Seeded list: the empty state never shows while loading' (-not $flash -and $n -eq 3) "flash $flash, rows $n"

  # Headings with counts
  $heads = @{ History = 'History (3)'; Dictionary = 'Dictionary (3)'; Snippets = 'Snippets (3)'; Style = 'Apps (2)'; Scratchpad = 'Notes (2)' }
  $missing = foreach ($p in $heads.Keys) { Go $p; if (-not (Has $heads[$p])) { $heads[$p] } }
  Check 'Every list heading shows its count' (@($missing).Count -eq 0) "missing: $($missing -join ', ')"

  # Toolbar order, by position
  function Xs($names) { $names | ForEach-Object { (Find-El $root $_ $CT::Button).Current.BoundingRectangle.X } }
  Go 'Dictionary'; $d = Xs 'Import', 'Export CSV', 'Export JSON', 'Delete all'
  Go 'Snippets'; $sn = Xs 'Import', 'Export CSV', 'Export JSON', 'Delete all'
  Go 'History'; $hi = Xs 'Export CSV', 'Export JSON', 'Delete all history'
  $ordered = { param($x) for ($i = 1; $i -lt $x.Count; $i++) { if ($x[$i] -le $x[$i - 1]) { return $false } }; $true }
  Check 'Toolbars: Import, Export CSV, Export JSON, then Delete all' ((& $ordered $d) -and (& $ordered $sn) -and (& $ordered $hi)) "dict $($d -join ','); snip $($sn -join ','); hist $($hi -join ',')"
  Go 'Scratchpad'
  Check 'Scratchpad: Delete all notes in the list heading, above the notes' ((Find-El $root 'Delete all notes' $CT::Button).Current.BoundingRectangle.Y -lt (Rows)[0].Current.BoundingRectangle.Y) ''

  # Search: Esc clears; no match, Clear search
  Go 'Dictionary'
  $box = Find-El $root 'Search dictionary' $CT::Edit
  # Typed with real keys, as a person would (a value set through UI Automation is not ordinary typing)
  [void](Js "window.__keys=[];document.addEventListener('keydown',e=>__keys.push(e.key+' on '+(e.target.getAttribute('aria-label')||e.target.tagName)),true)")
  FocusOn (Named 'Search dictionary'); foreach ($k in 1..3) { [Po]::Tap(0x5A) }; Start-Sleep 0.6
  $typed = Js "($(Named 'Search dictionary')).value"
  [Po]::Tap(0x1B); Start-Sleep 0.5
  $v = Js "($(Named 'Search dictionary')).value"
  for ($k = 0; $k -lt 10 -and (Rows).Count -ne 3; $k++) { Start-Sleep -Milliseconds 200 }   # the full list is drawn again
  Check 'Esc in the search box clears it' ($typed -eq 'zzz' -and $v -eq '' -and (Rows).Count -eq 3) "typed '$typed', after Esc '$v', rows $((Rows).Count); keys seen: $(Js 'JSON.stringify(window.__keys)')"
  Set-Val $box 'zzz'; Start-Sleep 0.6
  $ok = (Has 'Nothing matches "zzz".') -and (Rows).Count -eq 0
  Invoke-El (@(Find-All $root $CT::Button | Where-Object { $_.Current.Name -eq 'Clear search' })[-1]); Start-Sleep 0.6
  Check 'No match names the search; Clear search brings the list back' ($ok -and (Rows).Count -eq 3) ''

  # Up and Down between rows (the same button on the next row; nothing past the ends)
  FocusOn (RowBtn 0 'Delete')
  [Po]::Tap(0x28); Start-Sleep 0.3; $a1 = Active
  [Po]::Tap(0x28); Start-Sleep 0.3; $a2 = Active
  [Po]::Tap(0x28); Start-Sleep 0.3; $a3 = Active
  [Po]::Tap(0x26); Start-Sleep 0.3; $a4 = Active
  Check 'Down and Up move to the same button on the next and previous row' ($a1 -eq 'Delete@1' -and $a2 -eq 'Delete@2' -and $a3 -eq 'Delete@2' -and $a4 -eq 'Delete@1') "$a1 $a2 $a3 $a4"

  # Esc cancels an edit; Enter saves one
  Press (RowBtn 0 'Edit')
  Set-Val (Find-El $root 'Word' $CT::Edit) 'Changed'; Start-Sleep 0.2
  FocusOn (Named 'Word'); [Po]::Tap(0x1B); Start-Sleep 0.6
  $terms = (Col "SELECT term FROM dictionary ORDER BY term") -join ','
  Check 'Dictionary: Esc cancels the edit; nothing saved; focus back on the row' ($terms -eq 'Alpha,Bravo,Charlie' -and (Active) -eq 'Edit@0') "$terms; focus $(Active)"
  Press (RowBtn 0 'Edit')
  Set-Val (Find-El $root 'Word' $CT::Edit) 'Alphabet'; Start-Sleep 0.2
  FocusOn (Named 'Word'); [Po]::Tap(0x0D); Start-Sleep 0.8
  $terms = (Col "SELECT term FROM dictionary ORDER BY term") -join ','
  Check 'Dictionary: Enter saves the edit, with a toast; focus back on the row' ($terms -eq 'Alphabet,Bravo,Charlie' -and (Has 'Saved.') -and (Active) -eq 'Edit@0') "$terms; focus $(Active)"

  # Delete with the keyboard: the dialog opens on Cancel, Tab to Delete, Enter; focus goes to the row now in its place
  $third = Js "[...document.querySelectorAll('ul.entries > li')][2].textContent"
  Press (RowBtn 1 'Delete')
  $dlg = Active
  [Po]::Tap(0x09); Start-Sleep 0.2; [Po]::Tap(0x0D); Start-Sleep 1.2
  $now = Js "[...document.querySelectorAll('ul.entries > li')][1].textContent"
  Check 'Delete: dialog opens on Cancel; toast; focus on the row now in its place' ((Q "SELECT COUNT(*) FROM dictionary")[0][0] -eq 2 -and $dlg -eq 'Cancel@-1' -and (Has 'Deleted "Bravo".') -and (Active) -eq 'Edit@1' -and $now -eq $third) "dialog focus $dlg; focus $(Active)"
  # Cancelling a dialog gives focus back to the button that opened it
  Press (RowBtn 0 'Delete'); [Po]::Tap(0x1B); Start-Sleep 0.5
  Check 'Dialog: Esc cancels and focus returns to the Delete button' ((Q "SELECT COUNT(*) FROM dictionary")[0][0] -eq 2 -and (Active) -eq 'Delete@0') "focus $(Active)"

  # Snippets: Ctrl+Enter saves, Esc cancels (the edited row's trigger box is the second one; the first is Add)
  Go 'Snippets'
  $editTrigger = "document.querySelectorAll('ul.entries [aria-label=Trigger]')[0]"
  Press (RowBtn 0 'Edit')
  Set-Val @(Find-All $root $CT::Edit | Where-Object { $_.Current.Name -eq 'Trigger' })[-1] 'sign off zero'; Start-Sleep 0.2
  FocusOn $editTrigger
  try { [Po]::Down(0x11); [Po]::Tap(0x0D) } finally { [Po]::Up(0x11) }; Start-Sleep 0.8
  $trig = (Col "SELECT trigger FROM snippets ORDER BY trigger") -join ','
  Check 'Snippets: Ctrl+Enter saves the edit' ($trig -match 'sign off zero' -and (Has 'Saved.')) $trig
  Press (RowBtn 0 'Edit')
  Set-Val @(Find-All $root $CT::Edit | Where-Object { $_.Current.Name -eq 'Trigger' })[-1] 'never saved'; Start-Sleep 0.2
  FocusOn $editTrigger; [Po]::Tap(0x1B); Start-Sleep 0.6
  Check 'Snippets: Esc cancels the edit; focus back on the row' (-not ((Col "SELECT trigger FROM snippets") -join ',' -match 'never saved') -and (Active) -eq 'Edit@0') "focus $(Active)"

  # History: Esc cancels, Ctrl+Enter saves
  Go 'History'
  Press (RowBtn 0 'Edit')
  Set-Val (Find-El $root 'Edit dictation' $CT::Edit) 'never saved'; Start-Sleep 0.2
  FocusOn (Named 'Edit dictation'); [Po]::Tap(0x1B); Start-Sleep 0.6
  Check 'History: Esc cancels the edit; nothing saved; focus back on the row' ((Q "SELECT COUNT(*) FROM transcripts WHERE edited_text IS NOT NULL")[0][0] -eq 0 -and (Active) -eq 'Copy@0') "focus $(Active)"
  Press (RowBtn 0 'Edit')
  Set-Val (Find-El $root 'Edit dictation' $CT::Edit) 'Edited with the keyboard.'; Start-Sleep 0.2
  FocusOn (Named 'Edit dictation')
  try { [Po]::Down(0x11); [Po]::Tap(0x0D) } finally { [Po]::Up(0x11) }; Start-Sleep 0.8
  Check 'History: Ctrl+Enter saves the edit' ((Q "SELECT COUNT(*) FROM transcripts WHERE edited_text = 'Edited with the keyboard.'")[0][0] -eq 1) ''

  # Style: deleting a rule says so
  Go 'Style'
  Invoke-El (@(Find-All $root $CT::Button | Where-Object { $_.Current.Name -eq 'Delete' })[0]); Start-Sleep 0.8
  Check 'Style: deleting a rule shows a toast; count follows' ((Has 'Deleted the rule for *') -and (Has 'Apps (1)')) ''

  # ---------- 3. Dictation: live region and tray ----------
  Go 'Scratchpad'; Invoke-El (Find-El $root 'New note' $CT::Button); Start-Sleep 0.8
  $live = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition($UA::AutomationIdProperty, 'dictation-status')))
  FocusOn (Named 'Note')
  $seen = [System.Collections.Generic.List[string]]::new()
  function Read-Live { $n = Js "document.getElementById('dictation-status').textContent"; if ($n -and ($seen.Count -eq 0 -or $seen[-1] -ne $n)) { $seen.Add($n) } }
  try { [Po]::Down(0x11); [Po]::Down(0x77); for ($i = 0; $i -lt 9; $i++) { Read-Live; Start-Sleep -Milliseconds 100 } } finally { [Po]::Up(0x77); [Po]::Up(0x11) }
  for ($i = 0; $i -lt 80; $i++) { Read-Live; Start-Sleep -Milliseconds 100 }
  Check 'Live region exposed to UI Automation in the main window' ([bool]$live) ''
  Check 'Live region announces the dictation (Listening/Transcribing, then Typed)' (($seen -contains 'Listening' -or $seen -contains 'Transcribing') -and $seen[-1] -eq 'Typed') ($seen -join ' > ')
  $tray = @(Get-Content $trace | Where-Object { $_ -match 'tray: ' } | ForEach-Object { ($_ -split 'tray: ')[1] })
  Check 'Tray icon: recording during the dictation, back to rest after' ($tray.Count -ge 2 -and $tray[-2] -eq 'recording' -and $tray[-1] -eq 'rest') ($tray -join ' > ')
} catch {
  "STOPPED: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
} finally {
  if ($app) { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue }
  [Po]::Up(0x77); [Po]::Up(0x11)
  Remove-Item Env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS -ErrorAction SilentlyContinue
  if ($userClip) { Set-Clipboard -Value $userClip }
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'polish-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
