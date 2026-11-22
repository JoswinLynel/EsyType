# RETIRED for the owner's PC on 22 Nov 2026: EsyType is now installed and upgraded with its Windows installer
# (npx tauri build -> src-tauri\target\release\bundle\nsis). Kept for reference.
# Installs the production build on this PC, separately from every build folder, so no later build (release or
# test) can overwrite the EsyType that is running or that Windows starts at login.
#   1. npx tauri build          (production build: src-tauri\target\release\esytype.exe)
#   2. quit EsyType from its tray icon
#   3. powershell -File scripts\install-local.ps1
# It copies the program and its voice-activity model to $Dest, points the Start menu shortcut there and starts it
# in the tray; EsyType then points its own start-with-Windows entry at the installed copy. Settings, history and
# models live elsewhere (%LOCALAPPDATA%\EsyAI\EsyType and the models folder) and are not touched.
param([string]$Dest = 'D:\EsyAI\EsyType\app')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root 'src-tauri\target\release\esytype.exe'
$vad = Join-Path $root 'src-tauri\resources\ggml-silero-v6.2.0.bin'
if (-not (Test-Path $exe)) { throw "No production build at $exe. Run 'npx tauri build' first." }
# A test build is never installed: only test builds carry the e2e trace strings.
if (Select-String -Path $exe -Pattern 'ESYTYPE_TEST_AUDIO' -SimpleMatch -Quiet) { throw "$exe is a test build (e2e feature); refusing to install it." }
$running = Get-Process esytype -ErrorAction SilentlyContinue
if ($running) { throw "EsyType is running ($($running.Path -join ', ')). Quit it from its tray icon, then run this again." }

New-Item -ItemType Directory -Force (Join-Path $Dest 'resources') | Out-Null
Copy-Item $exe (Join-Path $Dest 'esytype.exe') -Force
Copy-Item $vad (Join-Path $Dest 'resources') -Force
foreach ($p in @(@($exe, (Join-Path $Dest 'esytype.exe')), @($vad, (Join-Path $Dest 'resources\ggml-silero-v6.2.0.bin')))) {
  if ((Get-FileHash $p[0]).Hash -ne (Get-FileHash $p[1]).Hash) { throw "Copy of $($p[0]) does not match." }
}

$lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\EsyType.lnk'
$s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$s.TargetPath = Join-Path $Dest 'esytype.exe'; $s.WorkingDirectory = $Dest; $s.Description = 'EsyType: local voice dictation'
$s.Save()

Start-Process (Join-Path $Dest 'esytype.exe') -ArgumentList '--minimized'
"Installed to $Dest and started in the tray. Start menu shortcut: $lnk"
