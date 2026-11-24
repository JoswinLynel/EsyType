# The Dictation page (Mac design, milestone B) in the test build with its own profile: greeting and your name,
# the numbers card (total words, wpm, day streak) from the usage totals, Dictionary and snippet counts, recent
# dictations by day, and usage still counted with History off. Speech is injected; keys go only to the test build's
# own window, which is brought to the front and checked first.
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio"
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Hm {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-64} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }
$seed = Join-Path $PSScriptRoot 'data-seed.py'
$lad = Join-Path $Work 'localappdata-home'; $data = Join-Path $lad 'EsyAI\EsyType'; $db = Join-Path $data 'esytype.db'; $file = Join-Path $data 'settings.json'
if (Test-Path $lad) { Remove-Item $lad -Recurse -Force }; New-Item -ItemType Directory -Force $data | Out-Null
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; undo_shortcut = 'Ctrl+F9'; paste_last_shortcut = 'Ctrl+F10'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false; setup_done = $true } |
  ConvertTo-Json | Set-Content $file -Encoding ascii
Copy-Item (Join-Path $Audio '6930_5s.f32') (Join-Path $Work 'current.f32') -Force
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = Join-Path $Work 'current.f32'
$userClip = Get-Clipboard -Raw
function Launch { $script:app = Start-Process $Exe -PassThru -RedirectStandardError (Join-Path $Work 'home-trace.txt'); Start-Sleep 9; $script:root = Get-AppWindow $app.Id 'EsyType'; $script:h = [IntPtr]$root.Current.NativeWindowHandle }
function Quit { if ($app) { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue; Start-Sleep 2 } }
function Texts { (@(Find-All $root $CT::Text) + @(Find-All $root $CT::Button) | ForEach-Object { $_.Current.Name }) -join ' | ' }   # a button's text is its name
function Go($page) { Close-Settings $root; Invoke-El (Find-El $root $page $CT::Button); Start-Sleep 1.2 }
function Q([string]$sql) { python -I $seed query $db $sql | ConvertFrom-Json }

try {
  Launch; Quit   # the first start creates the database
  python -I $seed many $db; python -I $seed usage $db
  Launch
  for ($k = 0; $k -lt 20 -and -not ((Texts) -match '12\.4K'); $k++) { Start-Sleep -Milliseconds 250 }   # the numbers arrive after the page
  $t = Texts
  Check 'Greeting without a name: "Welcome back"' ([bool](Find-El $root 'Welcome back' $CT::Text)) ''
  Check 'Numbers: 12.4K total words, 124 wpm, 3 day streak' ($t -match '12\.4K' -and $t -match 'total words' -and $t -match '\b124\b' -and $t -match '\b3\b' -and $t -match 'day streak') ''
  Check 'Your words: 3 in your dictionary, 3 snippets' ($t -match '3 in your dictionary . 3 snippets') ''
  Check 'Recent dictations under Today, newest first' ($t -match 'Today' -and $t.IndexOf('First dictation here.') -ge 0 -and $t.IndexOf('First dictation here.') -lt $t.IndexOf('Third dictation here.')) ''
  Check 'No microphone card while Windows allows the microphone' (-not ($t -match 'EsyType needs your permission')) ''
  Invoke-El (Find-El $root '*total words*' $CT::Button -Like); Start-Sleep 1
  Check 'The numbers open Insights' ([bool](Find-El $root 'Insights' $CT::Text -Tries 5)) ''
  Invoke-El (Find-El $root 'Dictation' $CT::Button); Start-Sleep 1
  Invoke-El (Find-El $root 'Set your style' $CT::Button); Start-Sleep 1
  Check 'Set your style opens Style, with Clean or Verbatim at the top' ([bool](Find-El $root 'Clean or Verbatim' $CT::Text -Tries 5) -and [bool](Find-El $root 'Clean*' $CT::RadioButton -Like -Tries 3)) ''

  # your name
  Open-Settings $root 'General'
  $name = Find-El $root 'Your name' $CT::Edit
  Set-Val $name 'Priya Sharma'; (Find-El $root 'Follow Windows').SetFocus(); Start-Sleep 1
  $saved = (Get-Content $file -Raw | ConvertFrom-Json).user_name
  Go 'Dictation'
  Check 'Your name saved; greeting uses its first word' ($saved -eq 'Priya Sharma' -and [bool](Find-El $root 'Welcome back, Priya' $CT::Text -Tries 5)) "saved '$saved'"

  # History off: the dictation is counted in the totals, no text is kept
  Quit
  $st = Get-Content $file -Raw | ConvertFrom-Json; $st | Add-Member -Force history_enabled $false; [IO.File]::WriteAllText($file, ($st | ConvertTo-Json -Depth 5))   # no byte-order mark
  $before = (Q "SELECT sum(words), sum(dictations) FROM usage_days")[0]
  Launch
  for ($k = 0; $k -lt 20 -and -not ((Texts) -match 'History is off'); $k++) { Start-Sleep -Milliseconds 250 }
  Check 'History off: the page says so, and that totals still count' ((Texts) -match 'History is off') ''
  Invoke-El (Find-El $root 'Scratchpad' $CT::Button); Start-Sleep 1; Invoke-El (Find-El $root 'New note' $CT::Button); Start-Sleep 0.8
  $box = Find-El $root 'Note' $CT::Edit
  for ($k = 0; $k -lt 6 -and [Hm]::GetForegroundWindow() -ne $h; $k++) { [Hm]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400 }
  if ([Hm]::GetForegroundWindow() -ne $h) { throw 'The test build window is not in front; no keys sent.' }
  $box = Find-El $root 'Note' $CT::Edit; $box.SetFocus(); Start-Sleep 0.5
  if (-not $box.Current.HasKeyboardFocus) { throw 'The note does not have the focus; no keys sent.' }
  try { [Hm]::Down(0x11); [Hm]::Down(0x77); Start-Sleep -Milliseconds 900 } finally { [Hm]::Up(0x77); [Hm]::Up(0x11) }
  $typed = ''; for ($i = 0; $i -lt 240 -and -not $typed; $i++) { Start-Sleep -Milliseconds 250; $typed = [string]$box.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }
  Start-Sleep 1
  $after = (Q "SELECT sum(words), sum(dictations) FROM usage_days")[0]
  $words = @($typed.Trim() -split '\s+').Count
  Check 'History off: the dictation still adds to the totals' ($typed -match 'Congratulations' -and $after[0] -eq $before[0] + $words -and $after[1] -eq $before[1] + 1) "before $($before -join '/'), after $($after -join '/'), $words words"
  Check 'History off: no dictation text saved' ((Q "SELECT count(*) FROM transcripts")[0][0] -eq 3) ''
  Check 'Usage table holds numbers only' (((Q "SELECT group_concat(name) FROM pragma_table_info('usage_days')")[0][0]) -eq 'day,dictations,words,audio_ms,processing_ms') ''
} catch {
  "STOPPED: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
} finally {
  Quit
  Remove-Item Env:ESYTYPE_TEST_AUDIO -ErrorAction SilentlyContinue
  if ($userClip) { Set-Clipboard -Value $userClip }
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'home-results.json') -Encoding utf8
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
