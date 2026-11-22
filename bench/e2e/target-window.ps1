# A throwaway text window owned by the test, used instead of the user's own apps.
# Writes its current text to $Out every 100 ms so the test can read it.
param([string]$Out, [string]$Kind = 'TextBox', [string]$Title = 'esytype-e2e-target', [int]$Delay = 600)
Add-Type -AssemblyName System.Windows.Forms
$f = New-Object System.Windows.Forms.Form
$f.Text = $Title; $f.Width = 700; $f.Height = 300; $f.StartPosition = 'CenterScreen'; $f.TopMost = $false
# 'None': no text field at all, so Ctrl+V does nothing (tests EsyType's 'not inserted' detection).
$t = if ($Kind -eq 'RichTextBox') { New-Object System.Windows.Forms.RichTextBox } elseif ($Kind -eq 'None') { New-Object System.Windows.Forms.Label } else { New-Object System.Windows.Forms.TextBox }
if ($Kind -ne 'None') { $t.Multiline = $true }; $t.Dock = 'Fill'; $t.Font = New-Object System.Drawing.Font('Segoe UI', 11)
$f.Controls.Add($t)
# A multi-line WinForms TextBox ignores Ctrl+A; the test uses it to clear the box between checks.
$t.Add_KeyDown({ if ($_.Control -and $_.KeyCode -eq 'A') { $t.SelectAll(); $_.SuppressKeyPress = $true } })
# 'SlowPaste': a program that pastes slowly, the hard case for EsyType: on Shift+Insert it reads the clipboard, is busy
# for $Delay ms, then reads it again and inserts what that second read got.
# 'DeferredPaste': the same, but the second read is done later from a timer, after the key has been handled.
# 'LatePaste': reads the clipboard once, $Delay ms after the key (a slow, starved program), and inserts that.
if ($Kind -in 'SlowPaste', 'DeferredPaste', 'LatePaste') {
  $t.Add_KeyDown({
    if ($_.Shift -and $_.KeyCode -eq 'Insert') {
      $_.SuppressKeyPress = $true
      if ($Kind -ne 'LatePaste') { [void][System.Windows.Forms.Clipboard]::GetText() }
      if ($Kind -eq 'SlowPaste') { Start-Sleep -Milliseconds $Delay; $t.SelectedText = [System.Windows.Forms.Clipboard]::GetText() }
      else { $script:later = New-Object System.Windows.Forms.Timer; $script:later.Interval = $Delay; $script:later.Add_Tick({ $script:later.Stop(); $t.SelectedText = [System.Windows.Forms.Clipboard]::GetText() }); $script:later.Start() }
    }
  })
}
# 'Opaque': takes typing and Shift+Insert but shows its text only as a painted label, so accessibility tools cannot
# read it (like apps EsyType cannot inspect).
if ($Kind -eq 'Opaque') {
  $f.Controls.Remove($t); $script:buf = ''
  $f.KeyPreview = $true
  $f.Add_KeyPress({ if ([int]$_.KeyChar -eq 13) { $script:buf += "`r`n" } elseif ([int]$_.KeyChar -ge 32) { $script:buf += $_.KeyChar }; $f.Invalidate() })
  $f.Add_KeyDown({ if ($_.Shift -and $_.KeyCode -eq 'Insert') { $script:buf += [System.Windows.Forms.Clipboard]::GetText(); $_.SuppressKeyPress = $true; $f.Invalidate() } })
  $f.Add_Paint({ $_.Graphics.DrawString($script:buf, $f.Font, [System.Drawing.Brushes]::Black, 10, 10) })
  $t = [pscustomobject]@{ Text = '' } | Add-Member -PassThru ScriptMethod Clear { $script:buf = '' } | Add-Member -PassThru ScriptMethod Focus { }
  $t | Add-Member -Force ScriptProperty Text { $script:buf }
}
$timer = New-Object System.Windows.Forms.Timer; $timer.Interval = 100
$timer.Add_Tick({
  if (Test-Path "$Out.clear") { $t.Clear(); Remove-Item "$Out.clear" -ErrorAction SilentlyContinue } # lets the test clear the box without sending keys
  try { [IO.File]::WriteAllText($Out, $t.Text) } catch {}
})
$timer.Start()
$f.Add_Shown({ $t.Focus() })
[System.Windows.Forms.Application]::Run($f)
