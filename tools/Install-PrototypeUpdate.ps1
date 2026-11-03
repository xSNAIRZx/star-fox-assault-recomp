param(
  [Parameter(Mandatory=$true)][string]$ArchivePath,
  [string]$TargetRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$targetRoot = [IO.Path]::GetFullPath($TargetRoot).TrimEnd('\')
$archivePath = [IO.Path]::GetFullPath($ArchivePath)
$runId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'),([Guid]::NewGuid().ToString('N').Substring(0,8))
$userData = Join-Path $targetRoot 'user-data'
$stageRoot = Join-Path $userData ('update-staging\' + $runId)
$payloadRoot = Join-Path $stageRoot 'payload'
$backupRoot = Join-Path $userData ('update-backups\' + $runId)
$logRoot = Join-Path $userData 'update-logs'
$logPath = Join-Path $logRoot ('install-' + $runId + '.json')
$manifestName = 'SHA256SUMS.txt'
$maxEntries = 4096
$maxExpandedBytes = 512MB
$allowedSourceExtensions = @('.c','.cc','.cpp','.cs','.h','.hh','.hpp','.inl','.cmake','.txt','.md','.py','.ps1','.cmd','.bat','.sh','.yml','.yaml','.json','.xml','.mm','.swift','.entitlements','.frag','.vert','.geom','.comp','.glsl','.glslinc','.inc','.rc','.def','.properties','.java','.kt','.gradle','.kts','.mk','.in','.manifest','.bin','.png','.ico','.sha1')
$forbiddenExtensions = @('.iso','.ciso','.gcm','.dol','.rel','.raw','.elf','.dll','.lib','.obj','.o','.pdb')
$requiredFiles = @(
  'Launch-StarFoxAssault.ps1','Start-StarFoxAssault.cmd','Star Fox Assault Recomp.exe',
  'tools/native/assault-image-tool.exe','tools/portable-toolchain.json','release.json','LICENSE','CREDITS.md','RELEASE-NOTES.md','VALIDATION.md','portable.txt',
  'CMakeLists.txt','THIRD_PARTY_NOTICES.md',
  'README-PROTOTYPE.txt',$manifestName,'assets/assault-launcher-background.png',
  'assets/assault-arwing-hangar.png','assets/assault-arwing-hangar.prompt.txt','assets/assault-launcher.ico',
  'assets/fonts/font_western.bin','assets/fonts/font_japanese.bin','assets/fonts/font-licenses.txt',
  'recomp/special_calls.txt','recomp/names.txt','recomp/idle.txt','recomp/hle.txt',
  'decomp/config/GF7E01/symbols.txt','decomp/config/GF7E01/build.sha1',
  'runtime/CMakeLists.txt','runtime/LICENSE','runtime/runtime/assault.manifest','runtime/runtime/hw/exi.cpp',
  'runtime/runtime/disc_mods.cpp','runtime/recomp/rel.py',
  'tools/Build-StarFoxAssault.ps1','tools/Build-NativeGame.ps1','tools/Build-CacheSignature.ps1','tools/Ensure-PortableToolchain.ps1','tools/Build-Launcher.ps1','tools/LauncherBootstrap.cs'
)
$archive = $null
$manifestTable = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
$archiveFiles = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
$applied = New-Object 'System.Collections.Generic.List[object]'
$status = 'failed'
$rolledBack = $false
$failureText = $null
$changedCount = 0
$backupReady = $false

function Test-UpdatePath([string]$path) {
  if ([string]::IsNullOrWhiteSpace($path) -or $path.Contains([char]0)) { return $false }
  $normalized = $path.Replace('\','/')
  if ($normalized.StartsWith('/') -or $normalized -match '^[A-Za-z]:' -or $normalized.Contains(':')) { return $false }
  $parts = $normalized.Split('/')
  if (@($parts | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) { return $false }
  if ($normalized -match '(^|/)(\.git|\.claude|\.githooks|analysis|orig|build-native|userdata|user-data|saves|reference-metadata)(/|$)') { return $false }
  $extension = [IO.Path]::GetExtension($normalized).ToLowerInvariant()
  if ($extension -in $forbiddenExtensions) { return $false }
  switch -Regex ($normalized) {
    '^(Launch-StarFoxAssault\.ps1|Start-StarFoxAssault\.cmd|Star Fox Assault Recomp\.exe|CMakeLists\.txt|LICENSE|THIRD_PARTY_NOTICES\.md|README-PROTOTYPE\.txt|SHA256SUMS\.txt|release\.json|CREDITS\.md|RELEASE-NOTES\.md|VALIDATION\.md|portable\.txt)$' { return $true }
    '^build-desktop/Release/assault\.exe$' { return $true }
    '^tools/native/assault-image-tool\.exe$' { return $true }
    '^tools/portable-toolchain\.json$' { return $true }
    '^assets/assault-launcher-background\.png$' { return $true }
    '^assets/assault-arwing-hangar\.png$' { return $true }
    '^assets/assault-arwing-hangar\.prompt\.txt$' { return $true }
    '^assets/assault-launcher\.ico$' { return $true }
    '^assets/fonts/(font_western\.bin|font_japanese\.bin|font-licenses\.txt)$' { return $true }
    '^recomp/(special_calls|names|idle|hle)\.txt$' { return $true }
    '^decomp/config/GF7E01/([A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.(txt|yml|yaml|sha1)$' { return $true }
    '^runtime/([A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+$' {
      if ([IO.Path]::GetFileName($normalized) -in @('LICENSE','NOTICE')) { return $true }
      return $extension -in $allowedSourceExtensions
    }
    '^tools/([A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+$' { return $extension -in @('.ps1','.cs','.py','.txt','.sh','.cmd','.bat') }
    '^third_party_licenses/[A-Za-z0-9_.-]+\.txt$' { return $true }
    default { return $false }
  }
}

function Get-UpdateFullPath([string]$root,[string]$relative) {
  $rootPrefix = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
  $candidate = [IO.Path]::GetFullPath((Join-Path $root ($relative.Replace('/','\'))))
  if (-not $candidate.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw "Package path escaped the install root: $relative" }
  return $candidate
}

function Assert-NoReparseParents([string]$root,[string]$target,[bool]$includeLeaf) {
  $rootFull = [IO.Path]::GetFullPath($root).TrimEnd('\')
  if (([IO.File]::GetAttributes($rootFull) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'The install root is a reparse point; update stopped.' }
  $relative = [IO.Path]::GetFullPath($target).Substring($rootFull.Length).TrimStart('\')
  $parts = $relative.Split('\')
  $count = if ($includeLeaf) { $parts.Length } else { [Math]::Max(0,$parts.Length-1) }
  $current = $rootFull
  for ($i=0; $i -lt $count; $i++) {
    $current = Join-Path $current $parts[$i]
    if (Test-Path -LiteralPath $current) {
      if (([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse point in update path: $current" }
    }
  }
}

function Write-UpdateLog([string]$state,[string]$details) {
  try {
    [IO.Directory]::CreateDirectory($logRoot) | Out-Null
    $obj = [ordered]@{
      schemaVersion = 1
      status = $state
      package = [IO.Path]::GetFileName($archivePath)
      packageSha256 = if (Test-Path -LiteralPath $archivePath -PathType Leaf) { (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
      filesChanged = $changedCount
      backupPath = if ($backupReady) { $backupRoot } else { $null }
      rolledBack = $rolledBack
      message = $details
      completedUtc = [DateTime]::UtcNow.ToString('o')
    }
    $obj | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $logPath -Encoding utf8
  } catch { }
}

function Get-FileSha256([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Replace-UpdateFile([string]$source,[string]$destination,[string]$suffix) {
  $atomicBackup = $destination + '.' + $suffix + '-' + [Guid]::NewGuid().ToString('N')
  try { [IO.File]::Replace($source,$destination,$atomicBackup) }
  finally { if (Test-Path -LiteralPath $atomicBackup -PathType Leaf) { [IO.File]::Delete($atomicBackup) } }
}

try {
  if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) { throw "Install folder not found: $targetRoot" }
  if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf) -or [IO.Path]::GetExtension($archivePath) -ine '.zip') { throw 'Choose a prototype package ZIP file.' }
  if ([IO.File]::GetAttributes($targetRoot) -band [IO.FileAttributes]::ReparsePoint) { throw 'The install folder is a reparse point; update stopped.' }
  $liveInstall = [string]::Equals($targetRoot,$projectRoot,[StringComparison]::OrdinalIgnoreCase)
  if ($liveInstall -and (Get-Process -Name assault -ErrorAction SilentlyContinue)) { throw 'Close the native game before installing an update package.' }

  $sidecar = $archivePath + '.sha256'
  if (Test-Path -LiteralPath $sidecar -PathType Leaf) {
    $sidecarText = (Get-Content -LiteralPath $sidecar -Raw).Trim()
    if ($sidecarText -notmatch '^([A-Fa-f0-9]{64})\s{2}(.+)$' -or $Matches[2] -cne [IO.Path]::GetFileName($archivePath)) { throw 'The archive SHA-256 sidecar is malformed or names a different file.' }
    if ((Get-FileSha256 $archivePath) -cne $Matches[1].ToLowerInvariant()) { throw 'The archive does not match its SHA-256 sidecar.' }
  }

  $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
  if ($archive.Entries.Count -lt 25 -or $archive.Entries.Count -gt $maxEntries) { throw 'This ZIP does not have the expected prototype package structure.' }
  $totalExpanded = [long]0
  foreach ($entry in $archive.Entries) {
    $rawName = [string]$entry.FullName
    $name = $rawName.Replace('\','/')
    if ($name.EndsWith('/')) {
      $dirName = $name.TrimEnd('/')
      if (-not (Test-UpdatePath $dirName)) { throw "Unsafe package directory: $rawName" }
      continue
    }
    if (-not (Test-UpdatePath $name)) { throw "Package contains a path or file outside the update schema: $rawName" }
    if (((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000)) { throw "Package contains a symlink: $name" }
    if ($archiveFiles.ContainsKey($name)) { throw "Duplicate or case-colliding package path: $name" }
    $totalExpanded += [long]$entry.Length
    if ($totalExpanded -gt $maxExpandedBytes) { throw 'The expanded package exceeds the 512 MiB safety limit.' }
    $archiveFiles.Add($name,$entry)
  }
  if (-not $archiveFiles.ContainsKey($manifestName)) { throw 'SHA256SUMS.txt is missing from the prototype package.' }
  $manifestEntry = $archiveFiles[$manifestName]
  $manifestStream = $manifestEntry.Open()
  try { $reader = New-Object IO.StreamReader($manifestStream,[Text.Encoding]::UTF8,$true); try { $manifestText=$reader.ReadToEnd() } finally { $reader.Dispose() } } finally { if ($manifestStream) { $manifestStream.Dispose() } }
  foreach ($line in ($manifestText -split "`r?`n" | Where-Object { $_ -ne '' })) {
    if ($line -notmatch '^([A-Fa-f0-9]{64})  (.+)$') { throw 'SHA256SUMS.txt contains an invalid line.' }
    $relative = $Matches[2]
    if ($relative -ceq $manifestName -or -not (Test-UpdatePath $relative)) { throw "Manifest path is not allowed: $relative" }
    if ($manifestTable.ContainsKey($relative)) { throw "Duplicate manifest path: $relative" }
    $manifestTable.Add($relative,$Matches[1].ToLowerInvariant())
  }
  if ($manifestTable.Count -ne ($archiveFiles.Count - 1)) { throw 'The manifest does not cover every package file exactly once.' }
  foreach ($name in $archiveFiles.Keys) {
    if ($name -ceq $manifestName) { continue }
    if (-not $manifestTable.ContainsKey($name)) { throw "Package file is not listed in its manifest: $name" }
    $stream = $archiveFiles[$name].Open()
    try { $hasher = [Security.Cryptography.SHA256]::Create(); try { $actualHash = [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-','').ToLowerInvariant() } finally { $hasher.Dispose() } } finally { $stream.Dispose() }
    if ($actualHash -cne $manifestTable[$name]) { throw "Package hash mismatch: $name" }
  }
  foreach ($required in $requiredFiles) { if (-not $archiveFiles.ContainsKey($required)) { throw "Required prototype package file is missing: $required" } }

  [IO.Directory]::CreateDirectory($payloadRoot) | Out-Null
  foreach ($name in $archiveFiles.Keys) {
    $entry = $archiveFiles[$name]
    if ($name -ceq $manifestName) { $relative = $manifestName } else { $relative = $name }
    $destination = Get-UpdateFullPath $payloadRoot $relative
    Assert-NoReparseParents $payloadRoot $destination $false
    [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
    $entryStream = $entry.Open()
    $output = [IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $entryStream.CopyTo($output) } finally { $output.Dispose(); $entryStream.Dispose() }
    if ($name -cne $manifestName -and (Get-FileSha256 $destination) -cne $manifestTable[$name]) { throw "Staged package verification failed: $name" }
  }
  $archive.Dispose(); $archive = $null

  if ($liveInstall -and (Get-Process -Name assault -ErrorAction SilentlyContinue)) { throw 'The native game started while the update was being prepared; no files were replaced.' }
  [IO.Directory]::CreateDirectory($backupRoot) | Out-Null
  $backupReady = $true
  $orderedNames = @($archiveFiles.Keys | Sort-Object)
  try {
    foreach ($name in $orderedNames) {
      $destination = Get-UpdateFullPath $targetRoot $name
      $stagedFile = Get-UpdateFullPath $payloadRoot $name
      Assert-NoReparseParents $targetRoot $destination $true
      $parent = Split-Path -Parent $destination
      [IO.Directory]::CreateDirectory($parent) | Out-Null
      $wasPresent = Test-Path -LiteralPath $destination
      if ($wasPresent -and -not (Test-Path -LiteralPath $destination -PathType Leaf)) { throw "A package file path is occupied by a directory: $name" }
      $oldHash = if ($wasPresent) { Get-FileSha256 $destination } else { $null }
      $backupFile = Get-UpdateFullPath $backupRoot $name
      if ($wasPresent) {
        [IO.Directory]::CreateDirectory((Split-Path -Parent $backupFile)) | Out-Null
        [IO.File]::Copy($destination,$backupFile,$false)
        if ((Get-FileSha256 $backupFile) -cne $oldHash) { throw "Could not verify update backup for $name" }
      }
      $record = [pscustomobject]@{ Relative=$name; Destination=$destination; Backup=$backupFile; WasPresent=$wasPresent; OldHash=$oldHash; Applied=$false }
      $applied.Add($record)
      $temporary = $destination + '.update-' + [Guid]::NewGuid().ToString('N')
      [IO.File]::Copy($stagedFile,$temporary,$false)
      if ($wasPresent) { Replace-UpdateFile $temporary $destination 'update-old' } else { [IO.File]::Move($temporary,$destination) }
      $record.Applied = $true
      if ((Get-FileSha256 $destination) -cne $(if($name -ceq $manifestName){Get-FileSha256 $stagedFile}else{$manifestTable[$name]})) { throw "Installed file verification failed: $name" }
      $changedCount++
    }
  } catch {
    $failureText = $_.Exception.Message
    $rollbackOk = $true
    for ($i=$applied.Count-1; $i -ge 0; $i--) {
      $record = $applied[$i]
      try {
        if ($record.WasPresent) {
          if (Test-Path -LiteralPath $record.Backup -PathType Leaf) {
            $restoreTemp = $record.Destination + '.rollback-' + [Guid]::NewGuid().ToString('N')
            [IO.File]::Copy($record.Backup,$restoreTemp,$false)
            if (Test-Path -LiteralPath $record.Destination -PathType Leaf) { Replace-UpdateFile $restoreTemp $record.Destination 'rollback-old' } else { [IO.File]::Move($restoreTemp,$record.Destination) }
          } elseif ((Test-Path -LiteralPath $record.Destination -PathType Leaf) -and (Get-FileSha256 $record.Destination) -ceq $record.OldHash) {
            # A locked target can fail during its backup copy before it was touched.
          } else { throw "Prior contents unavailable for rollback: $($record.Relative)" }
        } elseif ($record.Applied -and (Test-Path -LiteralPath $record.Destination -PathType Leaf)) {
          [IO.File]::Delete($record.Destination)
        }
      } catch { $rollbackOk=$false; $failureText += "`nRollback failed for $($record.Relative): $($_.Exception.Message)" }
    }
    $rolledBack = $rollbackOk
    throw $failureText
  }

  $status = 'installed'
  $failureText = 'Update applied. Previous application files are retained in the backup folder; settings and user data were not included in the replacement set.'
  Write-UpdateLog $status $failureText
  [pscustomobject]@{ Status=$status; Package=[IO.Path]::GetFileName($archivePath); FilesChanged=$changedCount; BackupPath=$backupRoot; LogPath=$logPath; Message=$failureText }
} catch {
  if (-not $failureText) { $failureText = $_.Exception.Message }
  Write-UpdateLog 'failed' $failureText
  throw $failureText
} finally {
  if ($archive) { $archive.Dispose() }
  foreach ($path in @($stageRoot)) {
    $full = [IO.Path]::GetFullPath($path)
    $prefix = [IO.Path]::GetFullPath((Join-Path $targetRoot 'user-data')).TrimEnd('\') + '\'
    if (-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to remove update scratch outside user-data: $full" }
    if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue }
  }
}
