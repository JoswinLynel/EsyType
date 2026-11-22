# Speaks bench/accuracy/sentences.json with Windows' own voices (no download): three desktop voices (British, two
# American) and the two Indian English OneCore voices. WAV files go to $Out; convert.py turns them into the 16 kHz
# f32 clips the benchmark reads. Synthetic speech is a stand-in, not a substitute for real recordings.
param([string]$Out = "D:\AI Projects\Tools\bench\audio\accuracy")
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Out | Out-Null
$items = Get-Content (Join-Path $PSScriptRoot 'sentences.json') -Raw | ConvertFrom-Json
function Say($s) { if ($s.say) { $s.say } else { $s.ref } }

# Desktop (SAPI) voices
Add-Type -AssemblyName System.Speech
$sapi = New-Object System.Speech.Synthesis.SpeechSynthesizer
foreach ($v in 'Hazel', 'David', 'Zira') {
  $sapi.SelectVoice("Microsoft $v Desktop")
  foreach ($s in $items) {
    $f = Join-Path $Out "$($v.ToLower())-$($s.id).wav"
    if (-not (Test-Path $f)) { $sapi.SetOutputToWaveFile($f); $sapi.Speak((Say $s)); $sapi.SetOutputToNull() }
  }
}

# OneCore voices (Windows Runtime), for Indian English
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[void][Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType = WindowsRuntime]
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
function Await($op, [type]$t) { $task = $asTask.MakeGenericMethod($t).Invoke($null, @($op)); [void]$task.Wait(-1); $task.Result }
$one = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
foreach ($v in 'Heera', 'Ravi') {
  $one.Voice = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | Where-Object { $_.DisplayName -eq "Microsoft $v" } | Select-Object -First 1
  foreach ($s in $items) {
    $f = Join-Path $Out "$($v.ToLower())-$($s.id).wav"
    if (Test-Path $f) { continue }
    $stream = Await ($one.SynthesizeTextToStreamAsync((Say $s))) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
    $in = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
    $fs = [IO.File]::Create($f); $in.CopyTo($fs); $fs.Close(); $in.Close()
  }
}
"$(@(Get-ChildItem $Out -Filter *.wav).Count) WAV files in $Out"
