# Writing styles end to end: the Style page through UI Automation (rules, default, Custom switches, try-it box);
# spoken sentences from Windows' built-in voice through the real engine into the test window, whose program
# (powershell.exe) gets a rule switched between Formal, Casual and Concise; the default, Custom and Verbatim; the pill
# label and History's style column. Test build with its own settings, Ctrl+F8, its own window.
param(
  [string]$Exe = "D:\AI Projects\Tools\e2e\bin\esytype-e2e.exe",
  [string]$Work = "D:\AI Projects\Tools\e2e"
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech, UIAutomationClient, UIAutomationTypes
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class D {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static void Down(byte v) { keybd_event(v, 0, 0, UIntPtr.Zero); } public static void Up(byte v) { keybd_event(v, 0, 2, UIntPtr.Zero); }
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-58} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

$lad = Join-Path $Work 'localappdata-style'; $data = Join-Path $lad 'EsyAI\EsyType'; $exports = Join-Path $Work 'style-exports'
New-Item -ItemType Directory -Force $data, $exports | Out-Null
Get-ChildItem $data -Filter 'esytype.db*' | Remove-Item -Force; Get-ChildItem $exports | Remove-Item -Force
[ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $false } | ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
$db = Join-Path $data 'esytype.db'; $py = Join-Path $PSScriptRoot 'history-db.py'; $current = Join-Path $Work 'current.f32'
$env:LOCALAPPDATA = $lad; $env:ESYTYPE_TEST_AUDIO = $current; $env:ESYTYPE_EXPORT_DIR = $exports
$userClip = Get-Clipboard -Raw

$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer; $voice.SelectVoice('Microsoft Hazel Desktop')
function Say($text) {
  $wav = Join-Path $Work 'style-say.wav'
  $fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
  $voice.SetOutputToWaveFile($wav, $fmt); $voice.Speak($text); $voice.SetOutputToNull()
  $b = [IO.File]::ReadAllBytes($wav); $at = 12; while ([Text.Encoding]::ASCII.GetString($b, $at, 4) -ne 'data') { $at += 8 + [BitConverter]::ToInt32($b, $at + 4) }
  $n = [BitConverter]::ToInt32($b, $at + 4) / 2; $f = New-Object float[] ($n + 8000)
  for ($k = 0; $k -lt $n; $k++) { $f[$k] = [BitConverter]::ToInt16($b, $at + 8 + 2 * $k) / 32768.0 }
  $o = New-Object byte[] ($f.Length * 4); [Buffer]::BlockCopy($f, 0, $o, 0, $o.Length); [IO.File]::WriteAllBytes($current, $o)
}
$tf = Join-Path $Work 'style-target.txt'; Set-Content $tf '' -Encoding ascii
$tgt = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'target-window.ps1')`"", '-Out', "`"$tf`"", '-Kind', 'RichTextBox', '-Title', 'esytype-style-target' -PassThru
Start-Sleep 3; $h = [D]::FindWindow([NullString]::Value, 'esytype-style-target')
function Rows { $r = & python -I $py rows $db | ConvertFrom-Json; @($r | Where-Object { $_ }) }
function Dictate($phrase) {
  Say $phrase; Set-Content "$tf.clear" ''; Start-Sleep -Milliseconds 400
  for ($k = 0; $k -lt 8 -and [D]::GetForegroundWindow() -ne $h; $k++) {
    $fg = 0; [void][D]::GetWindowThreadProcessId([D]::GetForegroundWindow(), [ref]$fg)
    if ($k -gt 0 -and $fg -in @($tgt.Id, $app.Id)) { [D]::Down(0x12); [D]::Up(0x12) }
    [void](New-Object -ComObject WScript.Shell).AppActivate('esytype-style-target'); [D]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 400
  }
  if ([D]::GetForegroundWindow() -ne $h) { throw 'Test window is not in front; no keys sent.' }
  $n = (Rows).Count
  try { [D]::Down(0x11); [D]::Down(0x77); Start-Sleep -Milliseconds 900 } finally { [D]::Up(0x77); [D]::Up(0x11) }
  for ($i = 0; $i -lt 60 -and (Rows).Count -eq $n; $i++) { Start-Sleep -Milliseconds 250 }
  Start-Sleep -Milliseconds 400
  [pscustomobject]@{ Inserted = ([IO.File]::ReadAllText($tf)).Trim(); Row = (Rows | Select-Object -Last 1) }
}
function Btn($name, $within) { Find-El $(if ($within) { $within } else { $root }) $name $CT::Button }
function Field($name) { $f = Find-El $root $name $CT::Edit; if (-not $f) { $f = Find-El $root $name $CT::ComboBox -Tries 3 }; if (-not $f) { throw "No field '$name'; fields: " + ((Find-All $root $CT::Edit | ForEach-Object { $_.Current.Name }) -join ' | ') + '; buttons: ' + ((Find-All $root $CT::Button | ForEach-Object { $_.Current.Name }) -join ' | ') }; $f }
function Settings { Get-Content (Join-Path $data 'settings.json') -Raw | ConvertFrom-Json }
function Rows2 { $r = & python -I -c "import sqlite3,json,sys; c=sqlite3.connect(sys.argv[1]); print(json.dumps([dict(zip(('final_text','raw_text','mode','style'),r)) for r in c.execute('select final_text,raw_text,mode,style from transcripts order by id')]))" $db | ConvertFrom-Json; @($r | Where-Object { $_ }) }
function Choose($comboName, $option) {
  $opt = $null
  $cb = Find-El $root $comboName $CT::ComboBox
  if (-not $cb) { throw "No list '$comboName'" }
  # The list's items appear in the accessibility tree only once it has been opened, and slowly on a busy PC.
  for ($k = 0; $k -lt 4 -and -not $opt; $k++) {
    $cb.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand(); Start-Sleep -Milliseconds (400 + 400 * $k)
    $opt = Find-El $cb $option $CT::ListItem; if (-not $opt) { $opt = Find-El $root $option $CT::ListItem }
  }
  if (-not $opt) { throw "No option '$option' in '$comboName'; items: " + ((Find-All $root $CT::ListItem | ForEach-Object { $_.Current.Name }) -join ' | ') }
  $opt.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 300
  try { $cb.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse() } catch {}
  Start-Sleep 0.8
}
function PillText { $p = Get-TopWindows 'EsyType recording' @($app.Id) | Select-Object -First 1; if ($p) { (Find-All $p $CT::Text | ForEach-Object { $_.Current.Name }) -join ' ' } }
$sentence = 'Yeah, I don''t know if we can finish it in order to ship tomorrow.'

$app = Start-Process $Exe -PassThru -RedirectStandardError (Join-Path $Work 'style-trace.txt'); Start-Sleep 9
$root = Get-AppWindow $app.Id 'EsyType'   # the test build's window, not an installed EsyType's
try {
  Invoke-El (Btn 'Style'); Start-Sleep 1
  Check 'Starter rules and Standard default' (((Settings).style_default -eq $null -or (Settings).style_default -eq 'standard') -and (Find-El $root 'OUTLOOK.EXE' $CT::Text) -and (Find-El $root 'slack.exe' $CT::Text)) ''

  # Formal through a rule for the test window's program
  Set-Val (Field 'Program') 'powershell.exe'; Choose 'Style for new program' 'Formal'
  Invoke-El (Btn 'Add rule'); Start-Sleep 1
  Check 'Rule added' (@((Settings).style_rules | Where-Object { $_.app -eq 'powershell.exe' -and $_.style -eq 'formal' }).Count -eq 1) ''
  $r = Dictate $sentence; $pill = PillText
  Check 'Formal: written forms and contractions' ($r.Inserted -match '^Yes' -and $r.Inserted -match 'do not know' -and $r.Inserted -notmatch "don't") "'$($r.Inserted)' (heard '$($r.Row.raw_text)')"
  Check 'Pill names the style' ($pill -match 'Formal') "'$pill'"
  Check 'History records the style' ((Rows2)[-1].style -eq 'formal') "style=$((Rows2)[-1].style)"

  Choose 'Style for powershell.exe' 'Casual'
  $r = Dictate 'Sounds good.'
  Check 'Casual: no full stop on a one-sentence message' ($r.Inserted -eq 'Sounds good') "'$($r.Inserted)'"
  Choose 'Style for powershell.exe' 'Concise'
  $r = Dictate 'We left early in order to catch the train.'
  Check 'Concise: stock phrase shortened' ($r.Inserted -match 'early to catch' -and $r.Inserted -notmatch 'in order') "'$($r.Inserted)'"

  # Rule deleted: the default applies
  Invoke-El (Btn 'Delete' (@(Find-All $root $CT::ListItem | Where-Object { $_.Current.Name -match 'powershell' })[0])); Start-Sleep 1
  Check 'Rule deleted' (@((Settings).style_rules | Where-Object { $_.app -eq 'powershell.exe' }).Count -eq 0) ''
  $r = Dictate $sentence
  Check 'Standard default: nothing beyond Clean' ($r.Inserted -match "don't" -and $r.Inserted -match 'in order to') "'$($r.Inserted)'"

  # Custom as the default
  Invoke-El (Find-El $root 'Expand contractions*' $CT::CheckBox -Like); Start-Sleep 0.8
  Choose 'Style for other apps' 'Custom'
  $r = Dictate $sentence
  Check 'Custom: chosen switch applied' ($r.Inserted -match 'do not' -and $r.Inserted -match '^Yeah' -and (Settings).style_custom.expand_contractions) "'$($r.Inserted)'"

  # Try-it box
  Set-Val (Field 'Try a sentence') 'yeah I''m gonna go'; Start-Sleep 1.5
  Check 'Try it shows each style' ((Find-El $root "Yes, I'm going to go." $CT::Text) -and (Find-El $root 'Yes, I am going to go.' $CT::Text)) ''

  # Verbatim: no style
  Invoke-El (Btn 'Style'); Start-Sleep 1   # Clean or Verbatim is on the Style page since the Mac design
  (Find-El $root 'Verbatim*' $CT::RadioButton -Like).GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep 1
  $r = Dictate $sentence
  Check 'Verbatim: style not applied' ($r.Inserted -eq $r.Row.raw_text -and $null -eq (Rows2)[-1].style) "'$($r.Inserted)'"
} catch {
  "STOPPED: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
} finally {
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue; Stop-Process -Id $tgt.Id -Force -ErrorAction SilentlyContinue
  [D]::Up(0x77); [D]::Up(0x11); [D]::Up(0x12)
  if ($userClip) { Set-Clipboard -Value $userClip }
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'style-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
