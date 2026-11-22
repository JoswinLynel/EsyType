# Word error rate (%) after lower-casing, removing punctuation and spelling out numbers 0-99.
$script:Ones = 'zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen' -split ' '
$script:Tens = '_ _ twenty thirty forty fifty sixty seventy eighty ninety' -split ' '
function NumWord([int]$n) { if ($n -lt 20) { $Ones[$n] } elseif ($n -lt 100) { $Tens[[math]::Floor($n / 10)] + $(if ($n % 10) { ' ' + $Ones[$n % 10] }) } else { "$n" } }
function Words($s) {
  $s = $s.ToLower() -replace '-', ' ' -replace '[‘’]', "'"
  $s = [regex]::Replace($s, '\d+', { param($m) ' ' + (NumWord ([int]$m.Value)) + ' ' })
  (($s -replace "[^a-z' ]", ' ') -split '\s+') | ForEach-Object { $_.Trim("'") } | Where-Object { $_ }
}
function Wer($ref, $hyp) {
  $r = @(Words $ref); $h = @(Words $hyp)
  if ($r.Count -eq 0) { return 0 }
  $d = 0..$h.Count
  for ($i = 1; $i -le $r.Count; $i++) {
    $prev = $d[0]; $d[0] = $i
    for ($j = 1; $j -le $h.Count; $j++) { $cur = $d[$j]; $d[$j] = [Math]::Min([Math]::Min($d[$j] + 1, $d[$j - 1] + 1), $prev + [int]($r[$i - 1] -ne $h[$j - 1])); $prev = $cur }
  }
  [Math]::Round(100 * $d[$h.Count] / $r.Count, 1)
}
