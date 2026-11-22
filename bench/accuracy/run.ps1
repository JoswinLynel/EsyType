# Transcribes the accuracy clips (bench/accuracy) and the 10 LibriSpeech benchmark clips with EsyType's engine
# settings (stt-bench, ESYTYPE_BENCH_APP=1), once per condition, into $Out\<condition>.jsonl. score.py compares them.
#   -Conditions baseline,prompt,beam   (see $defs)
param([string[]]$Conditions = @('baseline'), [string]$Model = "D:\AI Projects\Tools\bench\models\ggml-base.en-q5_1.bin", [int]$Threads = 4,
  [string]$Bench = "D:\AI Projects\Tools\bench\target\release\stt-bench.exe", [string]$Audio = "D:\AI Projects\Tools\bench\audio",
  [string]$Out = "D:\AI Projects\Tools\bench\results\accuracy")
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Out | Out-Null
$Conditions = @($Conditions | ForEach-Object { $_ -split ',' })
$defs = @{
  baseline = @{}
  # a short, natural-sentence prompt with common product names (the earlier "Glossary: ..." list was 150 tokens)
  prompt = @{ ESYTYPE_BENCH_PROMPT = 'We use ChatGPT, OpenAI, Claude, Gemini, Copilot, GitHub, Supabase, Vercel, Next.js and Power Automate.' }
  beam = @{ ESYTYPE_BENCH_BEAM = '5' }
}
$clips = @(Get-ChildItem (Join-Path $Audio 'accuracy') -Filter *.f32 | Sort-Object Name | ForEach-Object FullName) +
  @((Get-Content (Join-Path $Audio 'clips.json') -Raw | ConvertFrom-Json) | ForEach-Object { Join-Path $Audio ($_.file -replace '\.wav$', '.f32') })
$env:ESYTYPE_BENCH_APP = '1'
foreach ($c in $Conditions) {
  foreach ($k in 'ESYTYPE_BENCH_PROMPT', 'ESYTYPE_BENCH_BEAM') { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
  foreach ($kv in $defs[$c].GetEnumerator()) { Set-Item "Env:$($kv.Key)" $kv.Value }
  $b = Get-CimInstance Win32_Battery
  $t = Get-Date
  $ErrorActionPreference = 'Continue'   # whisper.cpp writes its loading messages to stderr
  & $Bench $Model $Threads 1 0 @clips 2>$null | Where-Object { $_ -like '{*' } | Set-Content (Join-Path $Out "$c.jsonl") -Encoding utf8
  $ErrorActionPreference = 'Stop'
  "{0}: {1} clips in {2:N0} s (power status {3}, {4}%)" -f $c, $clips.Count, ((Get-Date) - $t).TotalSeconds, $b.BatteryStatus, $b.EstimatedChargeRemaining
}
