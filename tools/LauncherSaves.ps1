# Save-card backups for the launcher's Save Archive: backup file names, their metadata
# sidecars and new backups. No WinForms and no launcher globals, so tools/Test-LauncherCore.ps1
# can test it with temporary files.

# The native runtime's memory card: 4 Mbit.
$script:NativeCardBytes = 4 * 1024 * 1024 / 8

# The full path of a backup chosen in the list, refusing names that are not plain file names
# inside the backup folder.
function Resolve-SaveBackupPath([string]$BackupDir, $Item) {
  if ($null -eq $Item -or [string]::IsNullOrWhiteSpace([string]$Item.FileName)) { throw 'Select a save backup first.' }
  $fileName = [string]$Item.FileName
  if ([IO.Path]::GetFileName($fileName) -cne $fileName) { throw 'The selected backup name is invalid.' }
  $root = [IO.Path]::GetFullPath($BackupDir).TrimEnd('\') + '\'
  $path = [IO.Path]::GetFullPath((Join-Path $root $fileName))
  if (-not $path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'The selected backup is outside the backup folder.' }
  return $path
}

# A backup's metadata: its .meta.json sidecar when that is valid for this file, otherwise
# defaults from the file itself. Labels and tags are cleaned of control characters and capped.
function Read-SaveBackupMetadata([string]$RawPath) {
  $file = Get-Item -LiteralPath $RawPath -ErrorAction Stop
  $result = [ordered]@{
    schemaVersion = 1
    fileName = $file.Name
    label = [IO.Path]::GetFileNameWithoutExtension($file.Name) -replace '^memcard-',''
    tags = @()
    createdUtc = $file.LastWriteTimeUtc.ToString('o')
    sizeBytes = [long]$file.Length
    sha256 = ''
    source = 'existing backup'
  }
  $metaPath = $RawPath + '.meta.json'
  if (Test-Path -LiteralPath $metaPath -PathType Leaf) {
    try {
      $saved = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
      if ([int]$saved.schemaVersion -eq 1 -and [string]$saved.fileName -ceq $file.Name) {
        if (-not [string]::IsNullOrWhiteSpace([string]$saved.label)) {
          $safeLabel = [regex]::Replace([string]$saved.label,'[\r\n\t]',' ')
          if ($safeLabel.Length -gt 100) { $safeLabel = $safeLabel.Substring(0,100) }
          $result.label = $safeLabel
        }
        $result.tags = @($saved.tags | ForEach-Object {
          $tag = [regex]::Replace([string]$_,'[\r\n\t]',' ').Trim()
          if ($tag.Length -gt 32) { $tag = $tag.Substring(0,32) }
          if ($tag) { $tag }
        } | Select-Object -First 12)
        if ($saved.createdUtc) { $result.createdUtc = [string]$saved.createdUtc }
        if ($saved.sha256) { $result.sha256 = [string]$saved.sha256 }
        if ($saved.source) { $result.source = [string]$saved.source }
      }
    } catch { }
  }
  return [pscustomobject]$result
}

function Write-SaveBackupMetadata([string]$RawPath, [string]$Label, [string[]]$Tags, [string]$Source, [string]$CreatedUtc) {
  $file = Get-Item -LiteralPath $RawPath -ErrorAction Stop
  $meta = [ordered]@{
    schemaVersion = 1
    fileName = $file.Name
    label = $Label
    tags = @($Tags)
    createdUtc = $CreatedUtc
    sizeBytes = [long]$file.Length
    sha256 = (Get-FileHash -LiteralPath $RawPath -Algorithm SHA256).Hash
    source = $Source
  }
  [IO.File]::WriteAllText(($RawPath + '.meta.json'),($meta | ConvertTo-Json -Depth 4),(New-Object System.Text.UTF8Encoding($false)))
}

# Copy the card into the backup folder under a new unique name and write its metadata.
# Returns the backup's path.
function New-SaveBackupFile([string]$SourcePath, [string]$BackupDir, [string]$Label, [string[]]$Tags, [string]$Source, [bool]$RequireRuntimeSize = $false) {
  if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw 'The active memory card was not found.' }
  $file = Get-Item -LiteralPath $SourcePath -ErrorAction Stop
  if ($RequireRuntimeSize -and $file.Length -ne $script:NativeCardBytes) {
    throw "This memory card is $($file.Length) bytes. The native runtime uses a $($script:NativeCardBytes)-byte (4 Mbit) card, so it was not backed up."
  }
  [IO.Directory]::CreateDirectory($BackupDir) | Out-Null
  $name = 'memcard-{0}-{1}.raw' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'),[Guid]::NewGuid().ToString('N')
  $dest = Join-Path $BackupDir $name
  [IO.File]::Copy($SourcePath,$dest,$false)
  try { Write-SaveBackupMetadata -RawPath $dest -Label $Label -Tags $Tags -Source $Source -CreatedUtc ([DateTime]::UtcNow.ToString('o')) }
  catch { throw "Backup data was copied to $name, but its metadata could not be written: $($_.Exception.Message)" }
  return $dest
}
