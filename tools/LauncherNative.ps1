# Native build status for the launcher: the build record, whether the installed native build
# still matches the selected game image and project source, and which game processes are
# this project's. No WinForms and no launcher globals, so tools/Test-LauncherCore.ps1 can
# test every branch with temporary files.

$script:NativeGameId = 'GF7E01'
# This file is plain ASCII: Windows PowerShell 5.1 reads a script without a BOM in the ANSI
# code page, so a literal middle dot would display as two wrong characters. Build it from its
# code point instead.
$script:NativeReadyStatus = 'READY ' + [char]0x00B7 + ' NATIVE PROTOTYPE'

# The newest write time of the files a native build is made from. Scanning these trees is
# slow on large checkouts; the launcher caches the result for its session.
function Get-NativeSourceWriteUtc([string]$ProjectDir) {
  $sources = @('CMakeLists.txt','runtime','recomp','decomp\config\GF7E01') | ForEach-Object { Join-Path $ProjectDir $_ }
  $latest = Get-ChildItem -LiteralPath $sources -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
      $_.FullName -notmatch '\\(build[^\\]*|docs|\.git|__pycache__)\\' -and
      ($_.Name -eq 'CMakeLists.txt' -or $_.Extension -in @('.c','.cpp','.h','.hpp','.py','.cmake','.txt','.yml','.yaml','.manifest','.rc'))
    } |
    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if ($latest) { return $latest.LastWriteTimeUtc }
  return [DateTime]::MinValue
}

# user-data/native-build-info.json as written by the build worker, or $null when it is missing
# or unreadable.
function Read-NativeBuildRecord([string]$ProjectDir) {
  $path = Join-Path $ProjectDir 'user-data\native-build-info.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
  try { return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Test-NativeImageMatchesRecord($Record, [string]$ImagePath) {
  # Path, size and modification time must match what the build recorded; matching them avoids
  # re-hashing a multi-gigabyte image on every launch.
  $image = Get-Item -LiteralPath $ImagePath -ErrorAction Stop
  $fullImagePath = [IO.Path]::GetFullPath($ImagePath)
  $builtImagePath = [IO.Path]::GetFullPath([string]$Record.image)
  return [string]::Equals($fullImagePath,$builtImagePath,[StringComparison]::OrdinalIgnoreCase) -and
    [long]$image.Length -eq [long]$Record.image_size -and
    [long]$image.LastWriteTimeUtc.Ticks -eq [long]$Record.image_modified_utc_ticks -and
    [string]$Record.game_id -ceq $script:NativeGameId
}

# Status is 'NOT BUILT', 'REBUILD REQUIRED' (with a Reason) or $script:NativeReadyStatus.
# $SourceWriteUtc is a scriptblock so the slow source scan only runs when every cheaper check
# has passed.
function Get-NativeBuildStatus([string]$NativePath, $Record, [string]$ImagePath, [scriptblock]$SourceWriteUtc) {
  function Result([string]$status, [string]$reason = '') { [pscustomobject]@{ Status = $status; Reason = $reason } }
  if ([string]::IsNullOrWhiteSpace($NativePath) -or -not (Test-Path -LiteralPath $NativePath -PathType Leaf)) { return (Result 'NOT BUILT') }
  if (-not $Record -or [int]$Record.schema_version -lt 2 -or [string]::IsNullOrWhiteSpace([string]$Record.image_sha256)) {
    return (Result 'REBUILD REQUIRED' 'build record is missing or from an older launcher')
  }
  if ([string]::IsNullOrWhiteSpace($ImagePath) -or -not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
    return (Result 'REBUILD REQUIRED' 'selected game image was not found')
  }
  try {
    if (-not (Test-NativeImageMatchesRecord $Record $ImagePath)) { return (Result 'REBUILD REQUIRED' 'selected game image differs from the one built') }
  } catch { return (Result 'REBUILD REQUIRED' 'selected game image could not be checked') }
  $exeTime = (Get-Item -LiteralPath $NativePath).LastWriteTimeUtc
  if ($SourceWriteUtc -and ((& $SourceWriteUtc) -gt $exeTime)) { return (Result 'REBUILD REQUIRED' 'project source changed since the last build') }
  return (Result $script:NativeReadyStatus)
}

# Whether the native build may be launched with this image: the record must be complete and
# match the image, and the executable must be the one the build recorded.
function Test-NativeBuildForImage([string]$NativePath, $Record, [string]$ImagePath) {
  if (-not $Record) { return $false }
  try {
    if ([int]$Record.schema_version -lt 2 -or
        [string]::IsNullOrWhiteSpace([string]$Record.image_sha256) -or
        [string]::IsNullOrWhiteSpace([string]$Record.executable_sha256)) { return $false }
    if (-not (Test-NativeImageMatchesRecord $Record $ImagePath)) { return $false }
    # The build hash stays part of the record; the build pipeline verifies it when the image
    # is read.
    $exeHash = (Get-FileHash -LiteralPath $NativePath -Algorithm SHA256).Hash
    return [string]::Equals($exeHash,[string]$Record.executable_sha256,[StringComparison]::OrdinalIgnoreCase)
  } catch { return $false }
}

# Only this project's assault.exe counts; an unrelated program with the same name must not
# block launches. A process whose path cannot be read (for example one running elevated) is
# still treated as running, so saves and asset packs are never changed under a live game.
function Get-NativeGameProcess([string]$NativePath, $Processes = $null) {
  $target = [IO.Path]::GetFullPath($NativePath)
  if ($null -eq $Processes) { $Processes = @(Get-Process -Name assault -ErrorAction SilentlyContinue) }
  return @($Processes | Where-Object {
    $path = $null
    try { $path = [string]$_.Path } catch {}
    [string]::IsNullOrEmpty($path) -or [string]::Equals([IO.Path]::GetFullPath($path),$target,[StringComparison]::OrdinalIgnoreCase)
  })
}
