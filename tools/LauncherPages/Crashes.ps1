# Launcher page: Crash Reports. Dot-sourced by Launch-StarFoxAssault.ps1 into its script scope,
# so it uses the launcher's $script: state and helpers. Defines functions only.

# Zips the selected session's .log and .err (the last 2 MB of each) with private paths
# replaced, and a summary, into user-data\crash-bundles. No RAM dump, save or game file.
function Save-CrashReportBundle {
  $i = $script:crashLogList.SelectedIndex
  if ($i -lt 0 -or $i -ge $script:crashLogPaths.Count) { throw 'Select a crash log first.' }
  $selected = Get-Item -LiteralPath $script:crashLogPaths[$i]
  $session = $selected.Name -replace '\.(log|err|txt)$',''
  $files = @(Get-ChildItem -LiteralPath $selected.DirectoryName -File | Where-Object { ($_.Name -replace '\.(log|err|txt)$','') -eq $session -and $_.Extension -in @('.log','.err','.txt') })
  $replacements = @{}
  if ($script:discValue) { $replacements[[string]$script:discValue] = '<game image>' }
  $replacements[[string]$script:projectDir] = '<launcher folder>'
  if ($env:USERPROFILE) { $replacements[[string]$env:USERPROFILE] = '%USERPROFILE%' }
  $outDir = Join-Path $script:projectDir 'user-data\crash-bundles'
  [IO.Directory]::CreateDirectory($outDir) | Out-Null
  $zipPath = Join-Path $outDir ('{0}-report.zip' -f $session)
  if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
  $flag = ''
  $zip = [IO.Compression.ZipFile]::Open($zipPath,'Create')
  try {
    foreach ($f in $files) {
      $stream = [IO.File]::Open($f.FullName,'Open','Read','ReadWrite')
      try {
        $keep = [Math]::Min($stream.Length,2MB); [void]$stream.Seek(-$keep,'End')
        $bytes = New-Object byte[] $keep; [void]$stream.Read($bytes,0,$keep)
      } finally { $stream.Dispose() }
      $text = [Text.Encoding]::UTF8.GetString($bytes)
      if (-not $flag) { $flag = Get-CrashLogFlag ($text -split "`r?`n") }
      $entry = $zip.CreateEntry($f.Name); $w = New-Object IO.StreamWriter($entry.Open())
      try { $w.Write((Protect-ReportText $text $replacements)) } finally { $w.Dispose() }
    }
    $summary = New-CrashReportSummary @{
      Version = (Get-LauncherVersionText); OsVersion = [Environment]::OSVersion.VersionString
      Session = $session; When = $selected.LastWriteTime.ToString('yyyy-MM-dd HH:mm'); Flag = $flag
      Graphics = [string[]](Get-NativeGraphicsArguments) + [string[]](Get-NativeEnhancementArgumentList $script:settings '' '')
      Files = @($files | ForEach-Object { $_.Name })
    } $replacements
    $entry = $zip.CreateEntry('summary.txt'); $w = New-Object IO.StreamWriter($entry.Open())
    try { $w.Write($summary) } finally { $w.Dispose() }
  } finally { $zip.Dispose() }
  return $zipPath
}
function Refresh-CrashLogs($list) {
  $list.Items.Clear()
  $script:crashLogPaths = @()
  if (-not (Test-Path -LiteralPath $script:nativeRunDir)) { return }
  $logs = Get-ChildItem -LiteralPath $script:nativeRunDir -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { ($_.Extension -in @('.log','.err') -or ($_.Extension -eq '.txt' -and $_.Name -match 'crash|error')) -and $_.Length -gt 0 } |
    Sort-Object LastWriteTimeUtc -Descending
  $script:crashLogFlags = @()
  foreach ($log in $logs) {
    # A session whose log has a guard, vertex-check, thread-watch or fatal line is marked, so
    # the evidence is easy to find among ordinary sessions.
    $hit = Select-String -LiteralPath $log.FullName -Pattern $script:CrashFlagPattern -List -ErrorAction SilentlyContinue | Select-Object -First 1
    $flag = if ($hit) { Get-CrashLogFlag @($hit.Line) } else { '' }
    # Date, time and kind fit the list's width; the file name heads the log view.
    $kind = switch ($log.Extension) { '.err' { 'errors' } '.log' { 'output' } default { $log.Name } }
    [void]$list.Items.Add(('{0}{1:yyyy-MM-dd HH:mm:ss}  ·  {2}' -f $(if ($flag) { '[!] ' } else { '' }),$log.LastWriteTime,$kind))
    $script:crashLogPaths += $log.FullName
    $script:crashLogFlags += $flag
  }
  if ($script:crashEmptyLabel) { $script:crashEmptyLabel.Visible = ($list.Items.Count -eq 0) }
  if ($list.Items.Count -gt 0) { $list.SelectedIndex = 0 }
}

function Build-CrashesPage {
  Add-SectionHeader $script:content 'Crash reports' 'Inspect native runtime logs saved in this project''s isolated run folder.'
  $pageWidth = Get-ContentPageWidth
  # Fill the window height (down to a usable minimum) instead of a fixed 650, so the page
  # fits the minimum window without scrolling. The list, log and buttons follow the card.
  $cardHeight = [Math]::Max(420,[Math]::Min(650,(Get-ContentLogicalHeight) - 136))
  $card = New-Card 30 112 $pageWidth $cardHeight
  $list = New-Object Windows.Forms.ListBox
  $list.Location = New-Object Drawing.Point(24,24); $list.Size = New-Object Drawing.Size(340,($cardHeight - 110))
  $list.BackColor = $script:colors.panel2; $list.ForeColor = $script:colors.text; $list.BorderStyle = 'FixedSingle'
  $list.Anchor = 'Top,Bottom,Left'; $card.Controls.Add($list)
  $script:crashEmptyLabel = New-Label 'No crash logs yet' 10 $true $script:colors.muted
  $script:crashEmptyLabel.AutoSize = $false; $script:crashEmptyLabel.TextAlign = 'MiddleCenter'
  $script:crashEmptyLabel.BackColor = $script:colors.panel2
  $script:crashEmptyLabel.Location = New-Object Drawing.Point(25,220); $script:crashEmptyLabel.Size = New-Object Drawing.Size(338,38); $card.Controls.Add($script:crashEmptyLabel)
  # Controls added later sit behind earlier ones; the message must sit above the list.
  $script:crashEmptyLabel.BringToFront()
  $detail = New-Object Windows.Forms.TextBox
  $detailWidth = [Math]::Max(300,$pageWidth - 430)
  $detail.Location = New-Object Drawing.Point(382,24); $detail.Size = New-Object Drawing.Size($detailWidth,($cardHeight - 110))
  $detail.Multiline = $true; $detail.ReadOnly = $true; $detail.WordWrap = $true; $detail.ScrollBars = 'None'; $detail.BorderStyle = 'None'
  $detail.BackColor = $script:colors.base; $detail.ForeColor = $script:colors.text
  $detail.Font = New-Object Drawing.Font('Consolas',9); $detail.Anchor = 'Top,Bottom,Left,Right'; $card.Controls.Add($detail)
  $script:crashLogList = $list; $script:crashLogDetail = $detail
  $list.Add_SelectedIndexChanged({
    if ($script:crashLogList.SelectedIndex -ge 0 -and $script:crashLogList.SelectedIndex -lt $script:crashLogPaths.Count) {
      try {
        $selectedLog = $script:crashLogPaths[$script:crashLogList.SelectedIndex]
        $script:crashLogDetail.ScrollBars = 'Vertical'
        $flagLine = $script:crashLogFlags[$script:crashLogList.SelectedIndex]
        $script:crashLogDetail.Text = ('{0}{1}' -f [IO.Path]::GetFileName($selectedLog),[Environment]::NewLine) + $(if ($flagLine) { "FLAGGED: $flagLine
" } else { '' }) + [Environment]::NewLine + (Get-Content -LiteralPath $selectedLog -Raw -ErrorAction Stop)
        $ramDump = [IO.Path]::ChangeExtension($selectedLog,'.ram.bin')
        if (Test-Path -LiteralPath $ramDump -PathType Leaf) {
          $script:crashLogDetail.AppendText(("`r`n`r`nRAM dump available:`r`n{0}" -f $ramDump))
        }
      }
      catch { $script:crashLogDetail.Text = $_.Exception.Message }
    }
  })
  Refresh-CrashLogs $list
  $refresh = New-Button 'REFRESH' 110; $refresh.Location = New-Object Drawing.Point(24,($cardHeight - 66))
  $refresh.Add_Click({ Refresh-CrashLogs $script:crashLogList }); $card.Controls.Add($refresh)
  $open = New-Button 'OPEN LOG FOLDER' 155; $open.Location = New-Object Drawing.Point(145,($cardHeight - 66))
  $open.Add_Click({ Open-Folder $script:nativeRunDir }); $card.Controls.Add($open)
  $bundle = New-Button 'SAVE REPORT BUNDLE' 190 $true; $bundle.Location = New-Object Drawing.Point(312,($cardHeight - 66))
  $bundleTip = New-Object Windows.Forms.ToolTip; $bundleTip.SetToolTip($bundle,'Zip the selected session''s logs with private paths replaced, to attach to a GitHub issue. No saves or RAM dumps.')
  $bundle.Add_Click({ try { $zip = Save-CrashReportBundle; Set-Status ('Report bundle saved: {0}' -f [IO.Path]::GetFileName($zip)) $true; Open-Folder (Split-Path -Parent $zip) } catch { Set-Status $_.Exception.Message } }); $card.Controls.Add($bundle)
  $script:content.Controls.Add($card)
}
