# EsyMeet plan 8.1: capture test. Runs meet-capture for -Seconds while a spoken sentence (Windows' own voice) plays
# through the speakers every -Every seconds, then analyze.py checks the system sound against what was played: found,
# on time, and readable by Whisper. -Dictation: also runs the dictation timing probe (keys only into its own window)
# while capturing. Output: <Out>\result.json. The microphone file is deleted after measuring.
param([int]$Seconds = 30, [int]$Every = 10, [string]$Out = "D:\AI Projects\Tools\bench\results\meet-capture\run",
      [string]$Exe = "D:\AI Projects\Tools\bench\meet-target\release\meet-capture.exe",
      [string]$Sentence = 'The quarterly figures are ready, and the launch meeting moves to Thursday afternoon.', [switch]$Echo)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
New-Item -ItemType Directory -Force $Out | Out-Null
$wav = Join-Path $Out 'sentence.wav'
$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer; $voice.SelectVoice('Microsoft Hazel Desktop')
$voice.SetOutputToWaveFile($wav); $voice.Speak($Sentence); $voice.SetOutputToNull(); $voice.Dispose()
$player = New-Object System.Media.SoundPlayer $wav; $player.Load()
$len = (New-Object IO.FileInfo $wav).Length
$secs = [Math]::Round(($len - 44) / (22050 * 2), 2)   # the synthesiser's default WAV: 22.05 kHz, 16-bit mono

$log = Join-Path $Out 'capture.jsonl'
$p = Start-Process $Exe -ArgumentList $Seconds, "`"$Out`"" -PassThru -NoNewWindow -RedirectStandardOutput $log
for ($i = 0; $i -lt 50 -and -not (Select-String -Path $log -Pattern 'started' -Quiet -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 100 }
$t0 = Get-Date
$plays = @()
for ($k = 1; ($k * $Every + $secs + 2) -lt $Seconds; $k++) {
  while (((Get-Date) - $t0).TotalSeconds -lt $k * $Every) { Start-Sleep -Milliseconds 20 }
  $ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $player.PlaySync()
  $plays += [pscustomobject]@{ start_unix_ms = $ms; seconds = $secs }
}
$p.WaitForExit()
ConvertTo-Json -InputObject @($plays) | Set-Content (Join-Path $Out 'plays.json') -Encoding utf8
Get-Content $log | Where-Object { $_ -match '"summary"' } | Set-Content (Join-Path $Out 'summary.json') -Encoding utf8
# -Echo: also transcribe the microphone track around each play (does the microphone repeat what the speakers said?)
$extra = @(); if ($Echo) { $extra = @('--echo') }
python -I (Join-Path $PSScriptRoot 'analyze.py') $Out (Join-Path $Out 'summary.json') (Join-Path $Out 'plays.json') $Sentence @extra | Tee-Object (Join-Path $Out 'result.json')
