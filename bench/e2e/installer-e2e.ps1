# Milestone 5 installer tests (docs/plans/installer-plan.md, section 6), with the separate "EsyType Test" product only:
# its own program file (esytype-test.exe), identifier, data folder (%LOCALAPPDATA%\EsyAI\EsyType Test), Apps-list
# entry, Start menu shortcut and startup value. Installers run silently (/S). After every step the owner's EsyType is
# checked: same process, settings hash, History count and schema, startup entry, Start menu shortcut, no Apps entry.
# No keys are sent anywhere.
param([string]$Installers = "D:\AI Projects\Tools\e2e\installers", [string]$Work = "D:\AI Projects\Tools\e2e")
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uia.ps1')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class In {
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
"@
$results = [System.Collections.Generic.List[object]]::new()
function Check($name, $ok, $detail) { $results.Add([pscustomobject]@{ Test = $name; Pass = [bool]$ok; Detail = "$detail" }); "{0,-66} {1}  {2}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail }

$product = 'EsyType Test'; $bin = 'esytype-test.exe'
$setup = @{ '0.2.0' = (Join-Path $Installers 'EsyType Test_0.2.0_x64-setup.exe'); '0.2.1' = (Join-Path $Installers 'EsyType Test_0.2.1_x64-setup.exe') }
$root = Join-Path $Work 'install-test'; $appDir = Join-Path $root 'app'; $scripted = Join-Path $root 'scripted'
$data = Join-Path $env:LOCALAPPDATA "EsyAI\$product"            # the test product's own data folder
$web = Join-Path $env:LOCALAPPDATA 'uk.co.esyai.esytype.test'    # its browser-engine folder
$uninstKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$product"
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$lnk = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$product.lnk"
$desk = Join-Path ([Environment]::GetFolderPath('Desktop')) "$product.lnk"   # silent installs make one too
$seed = Join-Path $PSScriptRoot 'data-seed.py'

# ---------- the owner's EsyType, which must not change ----------
$ownExe = 'D:\EsyAI\EsyType\app\esytype.exe'; $ownData = Join-Path $env:LOCALAPPDATA 'EsyAI\EsyType'
function Db($path) { if (Test-Path $path) { python -I -c "import sqlite3,sys; c=sqlite3.connect('file:'+sys.argv[1]+'?mode=ro', uri=True); print(c.execute('select count(*) from transcripts').fetchone()[0], c.execute('pragma user_version').fetchone()[0])" $path } else { 'none' } }
function RunValue($name) { (Get-ItemProperty $runKey -ErrorAction SilentlyContinue).$name }
function Owner {
  [ordered]@{
    process = (@(Get-Process esytype -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $ownExe }).Id -join ',')
    settings = (Get-FileHash (Join-Path $ownData 'settings.json')).Hash
    history = (Db (Join-Path $ownData 'esytype.db'))
    startup = (RunValue 'EsyType')
    shortcut = (Test-Path (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\EsyType.lnk'))
    appsList = (Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\EsyType')
  } | ConvertTo-Json -Compress
}
$owner0 = Owner
function Yours($step) { $o = Owner; Check "Your EsyType untouched: $step" ($o -eq $owner0) $(if ($o -ne $owner0) { $o }) }

# ---------- the test product ----------
function TestProcs { @(Get-Process esytype-test -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root\*" }) }
function StopTest { TestProcs | Stop-Process -Force; Start-Sleep 1.5 }
function StartTest($dir, [switch]$Minimized) {
  $a = @{ FilePath = (Join-Path $dir $bin); PassThru = $true }; if ($Minimized) { $a.ArgumentList = '--minimized' }
  $p = Start-Process @a; Start-Sleep 9; $p
}
function Shown($p) { [bool]([AppWin]::All() | Where-Object { $_[1] -eq $p.Id -and $_[2] -eq 'EsyType' }) }
function Install($version, [string]$dir) {
  $a = '/S' + $(if ($dir) { " /D=$dir" })   # /D= must come last and unquoted
  (Start-Process $setup[$version] -ArgumentList $a -Wait -PassThru).ExitCode
}
# Runs the uninstaller as Windows does (it copies itself to %TEMP% and exits), then waits for it to finish.
# Silent (/S) keeps the data. -DeleteData uses its window as a person would (this Tauri version has no command-line
# option for it): tick the delete-data box, press Uninstall, then Finish. Only that window, which this test started,
# is operated, through UI Automation; no keys are sent.
$script:boxLabel = ''
function Uninstall([switch]$DeleteData) {
  $u = ((Get-ItemProperty $uninstKey).UninstallString).Trim('"'); $dir = Split-Path $u
  if (-not $DeleteData) {
    Start-Process $u -ArgumentList '/S' | Out-Null
  } else {
    $before = @(Get-Process | ForEach-Object Id)
    Start-Process $u | Out-Null
    $w = $null
    for ($i = 0; $i -lt 40 -and -not $w; $i++) { Start-Sleep -Milliseconds 500; $w = Get-TopWindows "$product Uninstall*" | Where-Object { $_.Current.ProcessId -notin $before } | Select-Object -First 1 }
    if (-not $w) { throw 'The uninstaller window did not appear.' }
    # The installer's classic controls show in UI Automation as plain panes with names only, so they are clicked
    # with the standard button message (BM_CLICK) sent to their own window handles.
    $box = Find-El $w 'Also delete*' $null -Like; if (-not $box) { throw 'No delete-data box in the uninstaller.' }
    $script:boxLabel = $box.Current.Name; $hb = [IntPtr]$box.Current.NativeWindowHandle
    [void][In]::SendMessage($hb, 0xF5, [IntPtr]::Zero, [IntPtr]::Zero); Start-Sleep 0.3
    if ([In]::SendMessage($hb, 0xF0, [IntPtr]::Zero, [IntPtr]::Zero) -ne 1) { throw 'The delete-data box could not be ticked.' }   # BM_GETCHECK
    [void][In]::PostMessage([IntPtr](Find-El $w 'Uninstall' $null).Current.NativeWindowHandle, 0xF5, [IntPtr]::Zero, [IntPtr]::Zero)
    for ($i = 0; $i -lt 60; $i++) {
      Start-Sleep -Milliseconds 500
      $b = foreach ($n in 'Finish', 'Close') { Find-El $w $n $null -Tries 1 }
      if ($b -and @($b)[0].Current.IsEnabled) { [void][In]::PostMessage([IntPtr]@($b)[0].Current.NativeWindowHandle, 0xF5, [IntPtr]::Zero, [IntPtr]::Zero); break }
    }
  }
  for ($i = 0; $i -lt 120 -and ((Test-Path $uninstKey) -or (Test-Path (Join-Path $dir $bin))); $i++) { Start-Sleep -Milliseconds 500 }
  Start-Sleep 2
}
function Key($name) { (Get-ItemProperty $uninstKey -ErrorAction SilentlyContinue).$name }
function LnkTarget { if (Test-Path $lnk) { (New-Object -ComObject WScript.Shell).CreateShortcut($lnk).TargetPath } }
function DataHashes { Get-ChildItem $data -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '-(wal|shm)$' } | Sort-Object FullName | ForEach-Object { "$($_.Name) $((Get-FileHash $_.FullName).Hash)" } }
function Cleanup {
  StopTest
  if (Test-Path $uninstKey) { Uninstall -DeleteData }
  Remove-ItemProperty $runKey -Name $product -ErrorAction SilentlyContinue
  Remove-Item $lnk, $desk -ErrorAction SilentlyContinue
  $j = Join-Path $data 'linked'; if (Test-Path $j) { cmd /c rmdir "$j" | Out-Null }   # the link only, never its target
  foreach ($p in $data, $web, $root) { if (Test-Path $p) { Remove-Item $p -Recurse -Force } }
}

"free on C: $([math]::Round((Get-PSDrive C).Free/1MB)) MB at the start"
Cleanup   # leftovers of an earlier run, test product only
try {
  # 1. Clean install
  $code = Install '0.2.0' $appDir
  Check '1. Clean install: succeeds silently' ($code -eq 0) "exit $code"
  Check '1. Program, voice model and uninstaller in the chosen folder' ((Test-Path (Join-Path $appDir $bin)) -and (Test-Path (Join-Path $appDir 'resources\ggml-silero-v6.2.0.bin')) -and (Test-Path (Join-Path $appDir 'uninstall.exe'))) ''
  Check '1. Apps list: name, version, publisher, folder' ((Key 'DisplayName') -eq $product -and (Key 'DisplayVersion') -eq '0.2.0' -and (Key 'Publisher') -eq 'EsyAI' -and (Key 'InstallLocation').Trim('"') -eq $appDir) "$(Key 'DisplayName') $(Key 'DisplayVersion') $(Key 'Publisher') $(Key 'InstallLocation')"
  Check '1. Start menu shortcut points at the program' ((LnkTarget) -eq (Join-Path $appDir $bin)) (LnkTarget)
  Check '1. Desktop shortcut made (the installer default)' (Test-Path $desk) $desk
  Check '1. Start with Windows set by the installer (new user: on)' ((RunValue $product) -eq "`"$(Join-Path $appDir $bin)`" --minimized") (RunValue $product)
  Check '1. No data written by the installer' (-not (Test-Path $data)) ''
  $p = StartTest $appDir
  $wizard = (Shown $p) -and [bool](Find-El (Get-AppWindow $p.Id 'EsyType') 'Get started' $CT::Button)
  StopTest
  Check '1. First start: the setup wizard opens' $wizard ''
  Yours 'clean install'

  # Existing user: settings, start with Windows on, History
  Remove-Item $data -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $data | Out-Null
  [ordered]@{ model = 'base'; ptt = 'Ctrl+F8'; toggle = 'Ctrl+F7'; undo_shortcut = 'Ctrl+F9'; paste_last_shortcut = 'Ctrl+F10'; models_dir = (Join-Path $Work 'restart-models'); start_with_windows = $true; setup_done = $true } |
    ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
  $p = StartTest $appDir -Minimized; StopTest
  python -I $seed many (Join-Path $data 'esytype.db')
  $hist = Db (Join-Path $data 'esytype.db'); $files = DataHashes
  Check '1. Existing user: starts in the tray, History seeded' (-not (Shown $p) -and $hist -eq "3 6") "history $hist"

  # 2. Upgrade 0.2.0 -> 0.2.1 while running
  $running = StartTest $appDir -Minimized
  $code = Install '0.2.1'
  Check '2. Upgrade: succeeds silently, same folder' ($code -eq 0 -and (Key 'DisplayVersion') -eq '0.2.1' -and (Key 'InstallLocation').Trim('"') -eq $appDir) "exit $code, $(Key 'DisplayVersion') in $(Key 'InstallLocation')"
  Check '2. Upgrade: the program is the new version' ((Get-Item (Join-Path $appDir $bin)).VersionInfo.ProductVersion -eq '0.2.1') (Get-Item (Join-Path $appDir $bin)).VersionInfo.ProductVersion
  Check '2. Upgrade: the running test copy was closed' (-not (Get-Process -Id $running.Id -ErrorAction SilentlyContinue)) ''
  Check '2. Upgrade: data files byte-for-byte unchanged' ((Compare-Object $files (DataHashes)) -eq $null -and (Db (Join-Path $data 'esytype.db')) -eq $hist) ''
  Check '2. Upgrade: start with Windows still points at it' ((RunValue $product) -like "*$appDir\$bin*") (RunValue $product)
  Yours 'upgrade'

  # 3. Older over newer: refused
  $exe = (Get-FileHash (Join-Path $appDir $bin)).Hash
  $code = Install '0.2.0'
  Check '3. Older installer over newer: refused, nothing changed' ($code -ne 0 -and (Key 'DisplayVersion') -eq '0.2.1' -and (Get-FileHash (Join-Path $appDir $bin)).Hash -eq $exe) "exit $code"
  Yours 'refused downgrade'

  # 4. Uninstall, keep data (the default), with the test copy running
  $running = StartTest $appDir -Minimized
  Copy-Item $appDir $scripted -Recurse   # kept for the take-over test (5)
  Uninstall
  Check '4. Uninstall: program folder, Apps entry, shortcuts and startup entry gone' (-not (Test-Path $appDir) -and -not (Test-Path $desk) -and -not (Test-Path $uninstKey) -and -not (Test-Path $lnk) -and -not (RunValue $product)) ''
  Check '4. Uninstall: the running test copy was closed' (-not (Get-Process -Id $running.Id -ErrorAction SilentlyContinue)) ''
  Check '4. Uninstall (keep data): every data file still there, unchanged' ((Compare-Object $files (DataHashes)) -eq $null) ''
  Yours 'uninstall, keep data'

  # 5. Take-over from a scripted copy: its folder, its shortcut and startup entry
  Remove-Item (Join-Path $scripted 'uninstall.exe') -ErrorAction SilentlyContinue
  $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk); $s.TargetPath = Join-Path $scripted $bin; $s.Save()
  Set-ItemProperty $runKey -Name $product -Value "$(Join-Path $scripted $bin) --minimized"
  $code = Install '0.2.1' $scripted
  Check '5. Take-over: installs over the scripted copy' ($code -eq 0 -and (Key 'InstallLocation').Trim('"') -eq $scripted -and (Test-Path (Join-Path $scripted 'uninstall.exe'))) "exit $code"
  Check '5. Take-over: one Start menu shortcut, pointing at it' ((LnkTarget) -eq (Join-Path $scripted $bin) -and @(Get-ChildItem (Split-Path $lnk) -Filter "$product*.lnk").Count -eq 1) (LnkTarget)
  Check '5. Take-over: start with Windows points at it' ((RunValue $product) -like "*$scripted\$bin*") (RunValue $product)
  $p = StartTest $scripted -Minimized
  $shown = Shown $p; $now = Db (Join-Path $data 'esytype.db')
  StopTest   # the database is open while it runs
  $settingsSame = (Get-FileHash (Join-Path $data 'settings.json')).Hash -eq (($files | Where-Object { $_ -like 'settings.json *' }) -split ' ')[1]
  Check '5. Reinstall finds the kept data: no wizard, History and settings back' (-not $shown -and $now -eq $hist -and $settingsSame) "history $now; window shown $shown; settings unchanged $settingsSame"
  Yours 'take-over'

  # 6. Start with Windows turned off: an install leaves it off
  $j = Get-Content (Join-Path $data 'settings.json') -Raw | ConvertFrom-Json; $j.start_with_windows = $false
  $j | ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding ascii
  Remove-ItemProperty $runKey -Name $product -ErrorAction SilentlyContinue
  $code = Install '0.2.1'
  Check '6. Reinstall with start with Windows off: no startup entry' ($code -eq 0 -and -not (RunValue $product)) "exit $code; $(RunValue $product)"

  # 7. Uninstall, delete data: only EsyType's own files go
  [void](StartTest $scripted -Minimized); StopTest   # the browser-engine folder exists after a start
  $outside = Join-Path $root 'outside'; New-Item -ItemType Directory -Force $outside | Out-Null; Set-Content (Join-Path $outside 'keep.txt') 'keep'
  cmd /c mklink /J "$(Join-Path $data 'linked')" "$outside" | Out-Null
  Set-Content (Join-Path $data 'my-notes.txt') 'mine'
  New-Item -ItemType Directory -Force (Join-Path $data 'before-restore') | Out-Null; Set-Content (Join-Path $data 'before-restore\before-restore-2026-11-22-1200.esytype-backup') 'x'
  $webBefore = Test-Path $web
  Uninstall -DeleteData
  $left = @(Get-ChildItem $data -Force -ErrorAction SilentlyContinue | ForEach-Object Name)
  Check '7. The tick box says what it deletes' ($script:boxLabel -eq 'Also delete my settings, History, notes and downloaded speech models') "'$($script:boxLabel)'"
  Check '7. Delete data: settings, database and safety copies gone' (-not (Test-Path (Join-Path $data 'settings.json')) -and -not (Test-Path (Join-Path $data 'esytype.db')) -and -not (Test-Path (Join-Path $data 'before-restore'))) "left: $($left -join ', ')"
  Check '7. Delete data: a file of yours in the folder is kept' (Test-Path (Join-Path $data 'my-notes.txt')) ''
  Check '7. Delete data: a folder link is not followed (its files stay)' (Test-Path (Join-Path $outside 'keep.txt')) ''
  Check '7. Delete data: the browser-engine folder is gone' ($webBefore -and -not (Test-Path $web)) "existed before: $webBefore"
  Check '7. Delete data: program folder, Apps entry, shortcuts, startup entry gone' (-not (Test-Path $scripted) -and -not (Test-Path $desk) -and -not (Test-Path $uninstKey) -and -not (Test-Path $lnk) -and -not (RunValue $product)) ''
  Yours 'uninstall, delete data'
} catch {
  "STOPPED: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
} finally {
  Cleanup
  Yours 'clean-up'
  "free on C: $([math]::Round((Get-PSDrive C).Free/1MB)) MB at the end"
}
$results | ConvertTo-Json | Set-Content (Join-Path $Work 'installer-results.json')
"`n{0} of {1} checks passed" -f @($results | Where-Object Pass).Count, $results.Count
