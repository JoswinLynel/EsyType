# Does a Dictionary hint (Whisper initial prompt) help? Sentences with uncommon names and terms, spoken by Windows'
# built-in voices (no download), plus the 10 benchmark clips and silence/noise, are transcribed by Base with and
# without the glossary using bench/stt-bench (ESYTYPE_BENCH_APP=1: the app's settings). Results: summary.py.
param(
  [string]$Bench = "D:\AI Projects\Tools\bench\target\release\stt-bench.exe",
  [string]$Model = "D:\EsyAI\EsyType\models\ggml-base.en-q5_1.bin",
  [string]$Audio = "D:\AI Projects\Tools\bench\audio",
  [string]$Out = "D:\AI Projects\Tools\bench\results\dictionary-hint",
  [int]$Threads = 7
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$dir = Join-Path $Audio 'dictionary'; New-Item -ItemType Directory -Force $dir, $Out | Out-Null

$sentences = [ordered]@{
  'EsyType' = 'I tested EsyType on my laptop this morning.'
  'Siobhan' = 'Siobhan will send the contract on Friday.'
  'Kubernetes' = 'We moved the service to Kubernetes last year.'
  'Okonkwo' = 'Please book a meeting with Doctor Okonkwo.'
  'Nguyen' = 'Mrs Nguyen asked about the invoice.'
  'Tauri' = 'The app is built with Tauri and Rust.'
  'PostgreSQL' = 'Our database runs on PostgreSQL.'
  'Llandudno' = 'The conference is in Llandudno this spring.'
  'Saoirse' = 'Saoirse joined the team in March.'
  'Wispr' = 'Wispr Flow is a dictation app.'
  'Ljubljana' = 'We flew to Ljubljana for the workshop.'
  'GitHub' = 'Push the branch to GitHub before lunch.'
  'Aoife' = 'Aoife fixed the login bug.'
  'Xero' = 'Export the invoices from Xero.'
  'Supabase' = 'We store the files in Supabase.'
}
$glossary = 'Glossary: ' + (($sentences.Keys) -join ', ') + '.'

function Write-F32($samples, $path) { $o = New-Object byte[] ($samples.Length * 4); [Buffer]::BlockCopy($samples, 0, $o, 0, $o.Length); [IO.File]::WriteAllBytes($path, $o) }
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$clips = @(); $meta = @()
foreach ($v in 'Microsoft Hazel Desktop', 'Microsoft David Desktop', 'Microsoft Zira Desktop') {
  $synth.SelectVoice($v); $short = ($v -split ' ')[1].ToLower()
  foreach ($term in $sentences.Keys) {
    $f = Join-Path $dir "$short-$term.f32"
    if (-not (Test-Path $f)) {
      $wav = "$f.wav"; $synth.SetOutputToWaveFile($wav, $fmt); $synth.Speak($sentences[$term]); $synth.SetOutputToNull()
      $b = [IO.File]::ReadAllBytes($wav); $at = 12; while ([Text.Encoding]::ASCII.GetString($b, $at, 4) -ne 'data') { $at += 8 + [BitConverter]::ToInt32($b, $at + 4) }
      $n = [BitConverter]::ToInt32($b, $at + 4) / 2; $s = New-Object float[] ($n + 8000)
      for ($k = 0; $k -lt $n; $k++) { $s[$k] = [BitConverter]::ToInt16($b, $at + 8 + 2 * $k) / 32768.0 }
      Write-F32 $s $f; Remove-Item $wav
    }
    $clips += $f; $meta += [pscustomobject]@{ clip = $f; term = $term; voice = $short; sentence = $sentences[$term] }
  }
}
# Silence and quiet noise, 5 s each: the hint must not make the engine invent words.
$sil = Join-Path $dir 'silence.f32'; Write-F32 (New-Object float[] 80000) $sil
$noi = Join-Path $dir 'noise.f32'; $r = New-Object Random 7; $x = New-Object float[] 80000; for ($k = 0; $k -lt 80000; $k++) { $x[$k] = ($r.NextDouble() - 0.5) * 0.02 }; Write-F32 $x $noi
$libri = Get-ChildItem $Audio -Filter '*.f32' | ForEach-Object FullName
$all = $clips + $libri + $sil + $noi
$meta | ConvertTo-Json | Set-Content (Join-Path $Out 'clips.json') -Encoding utf8

$env:ESYTYPE_BENCH_APP = '1'
$ErrorActionPreference = 'Continue'   # whisper.cpp prints its loading messages on stderr; Windows PowerShell would stop on them
foreach ($cond in 'none', 'glossary') {
  if ($cond -eq 'glossary') { $env:ESYTYPE_BENCH_PROMPT = $glossary } else { Remove-Item Env:ESYTYPE_BENCH_PROMPT -ErrorAction SilentlyContinue }
  & $Bench $Model $Threads 1 0 @all 2>$null | Set-Content (Join-Path $Out "$cond.jsonl") -Encoding utf8
  "$cond done"
}
Set-Content (Join-Path $Out 'glossary.txt') $glossary -Encoding utf8
