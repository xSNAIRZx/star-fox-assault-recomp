# Launcher page: Save Archive. Dot-sourced by Launch-StarFoxAssault.ps1 into its script scope,
# so it uses the launcher's $script: state and helpers. Defines functions only.

function Get-BackupFilePath($item) { return (Resolve-SaveBackupPath $script:backupDir $item) }
function Get-BackupMetadata([string]$rawPath) { return (Read-SaveBackupMetadata $rawPath) }
function Write-BackupMetadata([string]$rawPath,[string]$label,[string[]]$tags,[string]$source,[string]$createdUtc) {
  Write-SaveBackupMetadata -RawPath $rawPath -Label $label -Tags $tags -Source $source -CreatedUtc $createdUtc
}
function New-SaveBackup([string]$sourcePath,[string]$label,[string[]]$tags,[string]$source,[bool]$requireRuntimeSize = $false) {
  return (New-SaveBackupFile -SourcePath $sourcePath -BackupDir $script:backupDir -Label $label -Tags $tags -Source $source -RequireRuntimeSize $requireRuntimeSize)
}

function Update-BackupDetails {
  $item = $script:backupList.SelectedItem
  if ($null -eq $item) {
    $script:backupLabelBox.Text = ''
    $script:backupTagsBox.Text = ''
    $script:backupDetails.Text = 'Select a backup to see its details.'
    $script:saveBackupDetailsButton.Enabled = $false
    $script:restoreBackupButton.Enabled = $false
    return
  }
  try {
    $path = Get-BackupFilePath $item
    $meta = Get-BackupMetadata $path
    $file = Get-Item -LiteralPath $path
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $expectedSize = 4 * 1024 * 1024 / 8
    $script:backupLabelBox.Text = [string]$meta.label
    $script:backupTagsBox.Text = (@($meta.tags) -join ', ')
    try { $created = [DateTime]::Parse([string]$meta.createdUtc).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') }
    catch { $created = $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') }
    $validSize = $file.Length -eq $expectedSize
    $sizeLine = if ($validSize) { '{0:N0} bytes · valid native card size' -f $file.Length } else { '{0:N0} bytes · expected {1:N0}; restore disabled' -f $file.Length,$expectedSize }
    $script:backupDetails.Text = "File: $($file.Name)`r`nCreated: $created`r`n$sizeLine`r`nSHA-256: $hash"
    $script:backupDetails.ForeColor = if ($validSize) { $script:colors.muted } else { $script:colors.red }
    $script:saveBackupDetailsButton.Enabled = $true
    $script:restoreBackupButton.Enabled = $validSize
  } catch {
    $script:backupDetails.Text = $_.Exception.Message
    $script:backupDetails.ForeColor = $script:colors.red
    $script:saveBackupDetailsButton.Enabled = $false
    $script:restoreBackupButton.Enabled = $false
  }
}

function Refresh-Backups($list) {
  $keepName = if ($list.SelectedItem) { [string]$list.SelectedItem.FileName } else { '' }
  $list.BeginUpdate()
  $list.Items.Clear()
  if (Test-Path -LiteralPath $script:backupDir) {
    foreach ($file in (Get-ChildItem -LiteralPath $script:backupDir -Filter 'memcard-*.raw' -File | Sort-Object LastWriteTimeUtc -Descending)) {
      $meta = Get-BackupMetadata $file.FullName
      $tagText = if (@($meta.tags).Count) { '  ·  [' + (@($meta.tags) -join ', ') + ']' } else { '' }
      $entry = [pscustomobject]@{ FileName=$file.Name; DisplayName=([string]$meta.label + $tagText) }
      [void]$list.Items.Add($entry)
    }
  }
  $list.EndUpdate()
  if ($script:backupEmptyLabel) { $script:backupEmptyLabel.Visible = ($list.Items.Count -eq 0) }
  if ($keepName) {
    for ($i=0; $i -lt $list.Items.Count; $i++) { if ($list.Items[$i].FileName -ceq $keepName) { $list.SelectedIndex=$i; break } }
  }
  if ($list.SelectedIndex -lt 0 -and $list.Items.Count -gt 0) { $list.SelectedIndex=0 }
  Update-BackupDetails
}

function Build-SavesPage {
  Add-SectionHeader $script:content 'Save archive' 'Label and tag snapshots of the native runtime memory card. Backups are blocked while the game is running.'
  $pageWidth = Get-ContentPageWidth
  $card = New-Card 30 112 $pageWidth 485
  $pathLabel = New-Label 'ACTIVE MEMORY CARD' 9 $true $script:colors.cyan; $pathLabel.Location = New-Object Drawing.Point(24,18); $card.Controls.Add($pathLabel)
  # Shown relative to the launcher folder; the tooltip keeps the full path.
  $memcardShown = $script:memcardPath
  if ($memcardShown.StartsWith($script:projectDir.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) { $memcardShown = 'Launcher folder\' + $memcardShown.Substring($script:projectDir.TrimEnd('\').Length + 1) }
  $p = New-Label $memcardShown 8 $false $script:colors.muted; $p.AutoSize=$false; $p.AutoEllipsis=$true
  $p.Location = New-Object Drawing.Point(25,42); $p.Size=New-Object Drawing.Size(($card.Width - 50),20); $card.Controls.Add($p)
  $script:savePathToolTip = New-Object Windows.Forms.ToolTip; $script:savePathToolTip.SetToolTip($p,$script:memcardPath)

  $script:backupList = New-Object Windows.Forms.ListBox
  $script:backupList.DisplayMember = 'DisplayName'
  $script:backupList.Location=New-Object Drawing.Point(25,75); $script:backupList.Size=New-Object Drawing.Size(420,300)
  $script:backupList.BackColor=$script:colors.panel2; $script:backupList.ForeColor=$script:colors.text; $script:backupList.BorderStyle='FixedSingle'
  $script:backupList.HorizontalScrollbar=$true; $script:backupList.Anchor='Top,Left,Bottom'; $card.Controls.Add($script:backupList)
  $script:backupEmptyLabel=New-Label 'No backups yet' 10 $true $script:colors.muted
  $script:backupEmptyLabel.AutoSize=$false; $script:backupEmptyLabel.TextAlign='MiddleCenter'
  $script:backupEmptyLabel.BackColor=$script:colors.panel2
  $script:backupEmptyLabel.Location=New-Object Drawing.Point(26,198); $script:backupEmptyLabel.Size=New-Object Drawing.Size(418,38); $card.Controls.Add($script:backupEmptyLabel)
  $script:backupEmptyLabel.BringToFront()

  $detailPanel = New-Card 465 75 ([Math]::Max(300,$pageWidth-490)) 300; $card.Controls.Add($detailPanel)
  $detailTitle = New-Label 'SELECTED BACKUP' 8 $true $script:colors.cyan; $detailTitle.Location=New-Object Drawing.Point(18,16); $detailPanel.Controls.Add($detailTitle)
  $labelCaption = New-Label 'DISPLAY LABEL' 8 $true $script:colors.muted; $labelCaption.Location=New-Object Drawing.Point(18,47); $detailPanel.Controls.Add($labelCaption)
  $script:backupLabelBox=New-Object Windows.Forms.TextBox; $script:backupLabelBox.Location=New-Object Drawing.Point(18,68); $script:backupLabelBox.Size=New-Object Drawing.Size(($detailPanel.Width - 36),28)
  $script:backupLabelBox.BackColor=$script:colors.panel2; $script:backupLabelBox.ForeColor=$script:colors.text; $script:backupLabelBox.BorderStyle='FixedSingle'; $script:backupLabelBox.Anchor='Top,Left,Right'; $detailPanel.Controls.Add($script:backupLabelBox)
  $tagCaption = New-Label 'TAGS · COMMA SEPARATED' 8 $true $script:colors.muted; $tagCaption.Location=New-Object Drawing.Point(18,104); $detailPanel.Controls.Add($tagCaption)
  $script:backupTagsBox=New-Object Windows.Forms.TextBox; $script:backupTagsBox.Location=New-Object Drawing.Point(18,125); $script:backupTagsBox.Size=New-Object Drawing.Size(($detailPanel.Width - 36),28)
  $script:backupTagsBox.BackColor=$script:colors.panel2; $script:backupTagsBox.ForeColor=$script:colors.text; $script:backupTagsBox.BorderStyle='FixedSingle'; $script:backupTagsBox.Anchor='Top,Left,Right'; $detailPanel.Controls.Add($script:backupTagsBox)
  $script:backupDetails=New-Label 'Select a backup to see its details.' 8 $false $script:colors.muted
  $script:backupDetails.AutoSize=$false; $script:backupDetails.Size=New-Object Drawing.Size(($detailPanel.Width - 36),118); $script:backupDetails.Location=New-Object Drawing.Point(18,164)
  $script:backupDetails.Anchor='Top,Left,Right'; $detailPanel.Controls.Add($script:backupDetails)

  $backup = New-Button 'BACK UP NOW' 148 $true; $backup.Location=New-Object Drawing.Point(25,405)
  $backup.Add_Click({
    try {
      if (Get-RunningNativeGame) { throw 'Close the native game before making a backup so the snapshot is consistent.' }
      if (-not (Test-Path -LiteralPath $script:memcardPath -PathType Leaf)) { throw 'The native app has not created a memory card yet. Launch the native build once, then return here.' }
      $label = 'Manual backup · ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')
      $dest = New-SaveBackup $script:memcardPath $label @('manual') 'manual backup' $true
      Refresh-Backups $script:backupList
      for ($i=0; $i -lt $script:backupList.Items.Count; $i++) { if ($script:backupList.Items[$i].FileName -ceq [IO.Path]::GetFileName($dest)) { $script:backupList.SelectedIndex=$i; break } }
      Set-Status 'Memory card snapshot created. Add a custom label or tags in the details panel.' $true
    } catch { Set-Status $_.Exception.Message }
  }); $card.Controls.Add($backup)

  $script:saveBackupDetailsButton=New-Button 'SAVE DETAILS' 148; $script:saveBackupDetailsButton.Location=New-Object Drawing.Point(190,405)
  $script:saveBackupDetailsButton.Add_Click({
    try {
      if (-not $script:backupList.SelectedItem) { throw 'Select a backup first.' }
      $path = Get-BackupFilePath $script:backupList.SelectedItem
      $label = $script:backupLabelBox.Text.Trim()
      if ([string]::IsNullOrWhiteSpace($label)) { throw 'Enter a display label.' }
      if ($label.Length -gt 100) { throw 'Display labels must be 100 characters or fewer.' }
      $tags = @($script:backupTagsBox.Text.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
      if ($tags.Count -gt 12 -or @($tags | Where-Object { $_.Length -gt 32 }).Count) { throw 'Use up to 12 tags, each 32 characters or fewer.' }
      $old = Get-BackupMetadata $path
      Write-BackupMetadata -rawPath $path -label $label -tags $tags -source $old.source -createdUtc $old.createdUtc
      Refresh-Backups $script:backupList
      Set-Status 'Backup label and tags saved.' $true
    } catch { Set-Status $_.Exception.Message }
  }); $card.Controls.Add($script:saveBackupDetailsButton)

  $script:restoreBackupButton=New-Button 'RESTORE SELECTED' 170; $script:restoreBackupButton.Location=New-Object Drawing.Point(355,405)
  $script:restoreBackupButton.Add_Click({
    try {
      if (Get-RunningNativeGame) { throw 'Close the native game before restoring a save.' }
      if (-not $script:backupList.SelectedItem) { throw 'Select a backup first.' }
      $src=Get-BackupFilePath $script:backupList.SelectedItem
      $expectedSize = 4 * 1024 * 1024 / 8
      if ((Get-Item -LiteralPath $src).Length -ne $expectedSize) { throw "This backup is not a $expectedSize-byte (4 Mbit) card used by the native runtime. It cannot be restored." }
      $meta=Get-BackupMetadata $src
      $expectedHash=[string]$meta.sha256
      if ($expectedHash -and $expectedHash -notmatch '^[0-9a-fA-F]{64}$') { throw 'This backup has invalid checksum metadata and cannot be restored safely.' }
      $sourceHash=(Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
      if ($expectedHash -and -not [string]::Equals($sourceHash,$expectedHash,[StringComparison]::OrdinalIgnoreCase)) { throw 'This backup does not match its saved SHA-256 checksum. The active memory card was not changed.' }
      $integrityText=if($expectedHash){'Backup checksum verified.'}else{'No saved checksum is available for this older backup; its current contents cannot be compared with the original snapshot.'}
      $answer=[Windows.Forms.MessageBox]::Show("Restore '$($meta.label)'?`r`n$([IO.Path]::GetFileName($src))`r`n$integrityText`r`n`r`nThe active card will first be backed up automatically.",'Restore memory card','YesNo','Warning')
      if ($answer -ne 'Yes') { return }
      if (Get-RunningNativeGame) { throw 'The native game started while the restore confirmation was open. Close it and retry.' }
      if (Test-Path -LiteralPath $script:memcardPath -PathType Leaf) {
        $preLabel='Before restore · ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')
        [void](New-SaveBackup $script:memcardPath $preLabel @('auto','pre-restore') 'automatic backup before restore' $false)
      }
      [IO.Directory]::CreateDirectory((Split-Path -Parent $script:memcardPath)) | Out-Null
      $restoreTemp=$script:memcardPath+'.restore-'+[Guid]::NewGuid().ToString('N')+'.tmp'
      try {
        [IO.File]::Copy($src,$restoreTemp,$false)
        $tempFile=Get-Item -LiteralPath $restoreTemp -ErrorAction Stop
        if ($tempFile.Length -ne $expectedSize) { throw 'The temporary restored card has the wrong size. The active card was not changed.' }
        $tempHash=(Get-FileHash -LiteralPath $restoreTemp -Algorithm SHA256).Hash
        if ($expectedHash -and -not [string]::Equals($tempHash,$expectedHash,[StringComparison]::OrdinalIgnoreCase)) { throw 'The temporary restored card failed its checksum check. The active card was not changed.' }
        if (Test-Path -LiteralPath $script:memcardPath -PathType Leaf) { [IO.File]::Replace($restoreTemp,$script:memcardPath,[NullString]::Value) }
        else { [IO.File]::Move($restoreTemp,$script:memcardPath) }
      } finally { if (Test-Path -LiteralPath $restoreTemp -PathType Leaf) { Remove-Item -LiteralPath $restoreTemp -Force -ErrorAction SilentlyContinue } }
      Refresh-Backups $script:backupList
      Set-Status 'Save restored. The previous card was kept as an automatic backup.' $true
    } catch { Set-Status $_.Exception.Message }
  }); $card.Controls.Add($script:restoreBackupButton)
  $open = New-Button 'OPEN FOLDER' 136; $open.Location=New-Object Drawing.Point(540,405); $open.Add_Click({ Open-Folder $script:backupDir }); $card.Controls.Add($open)

  $script:backupList.Add_SelectedIndexChanged({ Update-BackupDetails })
  Refresh-Backups $script:backupList
  # Inside the card, so it is not printed straight onto the artwork.
  $note=New-Label 'Labels and tags are stored beside each snapshot. The native runtime uses a 4 Mbit (524,288-byte) card; backups of any other size cannot be restored.' 8 $false $script:colors.muted
  $note.Location=New-Object Drawing.Point(26,455); $note.MaximumSize=New-Object Drawing.Size(($pageWidth-52),0); $card.Controls.Add($note)
  $script:content.Controls.Add($card)
}
