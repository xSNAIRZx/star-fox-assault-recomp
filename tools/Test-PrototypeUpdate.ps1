param([string]$PackagePath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$projectDir = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$installer = Join-Path $PSScriptRoot 'Install-PrototypeUpdate.ps1'
if (-not $PackagePath) {
  $latest = Get-ChildItem -LiteralPath (Join-Path $projectDir 'user-data\releases') -Filter '*.zip' -File |
    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if (-not $latest) { throw 'No local prototype package ZIP was found.' }
  $PackagePath = $latest.FullName
}
$PackagePath = [IO.Path]::GetFullPath($PackagePath)
if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) { throw "Package not found: $PackagePath" }
$testRoot = Join-Path $projectDir ('user-data\verification\prototype-update-tests\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,6))
$verificationRoot = [IO.Path]::GetFullPath((Join-Path $projectDir 'user-data\verification')).TrimEnd('\') + '\'
$testFull = [IO.Path]::GetFullPath($testRoot)
if (-not $testFull.StartsWith($verificationRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Test scratch path escaped ignored verification data.' }
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$results = [ordered]@{ package=$PackagePath; tests=[ordered]@{}; completedUtc=$null }

function Set-TestFile([string]$root,[string]$relative,[byte[]]$bytes) {
  $path = Join-Path $root ($relative.Replace('/','\'))
  [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
  [IO.File]::WriteAllBytes($path,$bytes)
  return $path
}
function Assert-True([bool]$condition,[string]$message) { if (-not $condition) { throw $message } }
function Get-Hash([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }

$successRoot = Join-Path $testRoot 'success-install'
$failureRoot = Join-Path $testRoot 'rollback-install'
$schemaRoot = Join-Path $testRoot 'schema-rejection'
$hashRoot = Join-Path $testRoot 'hash-rejection'
foreach ($root in @($successRoot,$failureRoot,$schemaRoot,$hashRoot)) { [IO.Directory]::CreateDirectory($root) | Out-Null }

# A successful update replaces source/application files and leaves settings, card bytes, and image placeholders intact.
$null = Set-TestFile $successRoot 'CMakeLists.txt' ([Text.Encoding]::UTF8.GetBytes('old project build file'))
$null = Set-TestFile $successRoot 'Launch-StarFoxAssault.ps1' ([Text.Encoding]::UTF8.GetBytes('old launcher source'))
$oldLicensePath = Set-TestFile $successRoot 'LICENSE' ([Text.Encoding]::UTF8.GetBytes('old source license sentinel'))
$oldLicenseHash = Get-Hash $oldLicensePath
$settingsBytes = [Text.Encoding]::UTF8.GetBytes('{"disc":"kept-local-setting"}')
$profileBytes = [Text.Encoding]::UTF8.GetBytes('{"portableProfile":"kept-local-setting"}')
$cardBytes = New-Object byte[] 524288; for ($i=0; $i -lt $cardBytes.Length; $i++) { $cardBytes[$i] = 0xA5 }
$imageBytes = [Text.Encoding]::UTF8.GetBytes('synthetic user image sentinel')
$localNativeBytes = [Text.Encoding]::UTF8.GetBytes('recipient-local native game executable sentinel')
$settingsPath = Set-TestFile $successRoot 'user-data/app/settings.json' $settingsBytes
$profilePath = Set-TestFile $successRoot 'user-data/launcher-profile/settings.json' $profileBytes
$cardPath = Set-TestFile $successRoot 'user-data/native-run/saves/memcard_a.raw' $cardBytes
$imagePath = Set-TestFile $successRoot 'user-data/disc-image-sentinel.dat' $imageBytes
$localNativePath = Set-TestFile $successRoot 'build-desktop/Release/assault.exe' $localNativeBytes
$settingsHash = Get-Hash $settingsPath; $profileHash = Get-Hash $profilePath; $cardHash = Get-Hash $cardPath; $imageHash = Get-Hash $imagePath
$localNativeHash = Get-Hash $localNativePath
$successResultPath = Join-Path $testRoot 'success-result.json'
$success = & $installer -ArchivePath $PackagePath -TargetRoot $successRoot -ResultPath $successResultPath
Assert-True ($success.Status -eq 'installed') 'Installer did not report success.'
$successResult = Get-Content -LiteralPath $successResultPath -Raw | ConvertFrom-Json
Assert-True ($successResult.Status -eq 'installed' -and [int]$successResult.FilesChanged -eq [int]$success.FilesChanged) 'Installer result file did not match the reported success.'
Assert-True ((Get-Hash (Join-Path $successRoot 'CMakeLists.txt')) -ne (Get-Hash (Join-Path $success.BackupPath 'CMakeLists.txt'))) 'CMake source was not updated and backed up.'
Assert-True ((Get-Content -LiteralPath (Join-Path $success.BackupPath 'CMakeLists.txt') -Raw) -match 'old project build file') 'Pre-update source backup did not preserve prior contents.'
Assert-True ((Get-Hash $oldLicensePath) -ne $oldLicenseHash) 'Project LICENSE was not updated from the package.'
Assert-True ((Get-Content -LiteralPath (Join-Path $success.BackupPath 'LICENSE') -Raw) -match 'old source license sentinel') 'Pre-update backup did not preserve the prior LICENSE.'
Assert-True ((Get-Content -LiteralPath $oldLicensePath -Raw) -match 'MIT License') 'Updated LICENSE does not contain the project source license.'
Assert-True ((Get-Hash $settingsPath) -ceq $settingsHash) 'Settings sentinel changed.'
Assert-True ((Get-Hash $profilePath) -ceq $profileHash) 'Portable launcher profile sentinel changed.'
Assert-True ((Get-Hash $cardPath) -ceq $cardHash) 'Synthetic memory card sentinel changed.'
Assert-True ((Get-Hash $imagePath) -ceq $imageHash) 'Image sentinel changed.'
Assert-True ((Get-Hash $localNativePath) -ceq $localNativeHash) 'Recipient-local native game executable changed.'
$results.tests.successfulInstall = @{ passed=$true; filesChanged=$success.FilesChanged; backupPath=$success.BackupPath; logPath=$success.LogPath; licenseUpdatedAndBackedUp=$true; settingsCardImageAndLocalNativePreserved=$true }

# Hold the final sorted target exclusively. Earlier files apply, then the write fails; the installer must restore them.
$null = Set-TestFile $failureRoot 'assets/assault-launcher-background.png' ([Text.Encoding]::UTF8.GetBytes('old background'))
$null = Set-TestFile $failureRoot 'tools/Verify-Project.ps1' ([Text.Encoding]::UTF8.GetBytes('locked verifier sentinel'))
$failureBackground = Join-Path $failureRoot 'assets\assault-launcher-background.png'
$failureCmake = Set-TestFile $failureRoot 'CMakeLists.txt' ([Text.Encoding]::UTF8.GetBytes('rollback cmake sentinel'))
$lockedPath = Join-Path $failureRoot 'tools\Verify-Project.ps1'
$lock = [IO.File]::Open($lockedPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
$failureCaught = $false
try { $null = & $installer -ArchivePath $PackagePath -TargetRoot $failureRoot } catch { $failureCaught = $true }
finally { $lock.Dispose() }
Assert-True $failureCaught 'Locked destination did not fail the package update.'
Assert-True (([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($failureBackground))) -ceq 'old background') 'Rollback did not restore the earlier background file.'
Assert-True (([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($failureCmake))) -ceq 'rollback cmake sentinel') 'Rollback did not restore the earlier CMake file.'
$failedLog = Get-ChildItem -LiteralPath (Join-Path $failureRoot 'user-data\update-logs') -Filter 'install-*.json' -File | Select-Object -First 1
if ($failedLog) { $failedState = Get-Content -LiteralPath $failedLog.FullName -Raw | ConvertFrom-Json } else { throw 'Failed update log was not written.' }
Assert-True ($failedState.status -eq 'failed' -and $failedState.rolledBack) 'Failure log does not show a completed rollback.'
$results.tests.failureRollback = @{ passed=$true; rolledBack=[bool]$failedState.rolledBack; logPath=$failedLog.FullName }

# Add an unsafe traversal member to a package copy; preflight must reject before changing scratch files.
$badPathZip = Join-Path $testRoot 'unsafe-path.zip'
Copy-Item -LiteralPath $PackagePath -Destination $badPathZip
$badArchive = [IO.Compression.ZipFile]::Open($badPathZip,[IO.Compression.ZipArchiveMode]::Update)
try { $entry=$badArchive.CreateEntry('../escape.txt'); $writer=New-Object IO.StreamWriter($entry.Open()); try {$writer.Write('unsafe')} finally {$writer.Dispose()} } finally {$badArchive.Dispose()}
$schemaCmake = Set-TestFile $schemaRoot 'CMakeLists.txt' ([Text.Encoding]::UTF8.GetBytes('schema rejection sentinel'))
$schemaCaught = $false
$schemaResultPath = Join-Path $testRoot 'schema-result.json'
try { $null = & $installer -ArchivePath $badPathZip -TargetRoot $schemaRoot -ResultPath $schemaResultPath } catch { $schemaCaught = $true }
Assert-True $schemaCaught 'Traversal package was accepted.'
$schemaResult = Get-Content -LiteralPath $schemaResultPath -Raw | ConvertFrom-Json
Assert-True ($schemaResult.Status -eq 'failed' -and -not [string]::IsNullOrWhiteSpace([string]$schemaResult.Message)) 'Installer result file did not record the rejection.'
Assert-True (([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($schemaCmake))) -ceq 'schema rejection sentinel') 'Traversal rejection changed the scratch install.'
$results.tests.traversalRejection = @{ passed=$true; noTargetFilesChanged=$true }

# Corrupt a payload entry without updating its manifest; hash preflight must reject it.
$badHashZip = Join-Path $testRoot 'bad-hash.zip'
Copy-Item -LiteralPath $PackagePath -Destination $badHashZip
$badHashArchive = [IO.Compression.ZipFile]::Open($badHashZip,[IO.Compression.ZipArchiveMode]::Update)
try {
  $entry = $badHashArchive.GetEntry('README-PROTOTYPE.txt')
  if ($entry) { $entry.Delete() }
  $entry = $badHashArchive.CreateEntry('README-PROTOTYPE.txt')
  $writer = New-Object IO.StreamWriter($entry.Open())
  try { $writer.Write('corrupt content without a matching manifest hash') } finally { $writer.Dispose() }
} finally { $badHashArchive.Dispose() }
$hashCmake = Set-TestFile $hashRoot 'CMakeLists.txt' ([Text.Encoding]::UTF8.GetBytes('hash rejection sentinel'))
$hashCaught = $false
try { $null = & $installer -ArchivePath $badHashZip -TargetRoot $hashRoot } catch { $hashCaught = $true }
Assert-True $hashCaught 'Manifest hash mismatch was accepted.'
Assert-True (([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($hashCmake))) -ceq 'hash rejection sentinel') 'Hash rejection changed the scratch install.'
$results.tests.hashRejection = @{ passed=$true; noTargetFilesChanged=$true }

# A newer package's documentation in a place this installer has no rule for is checked against
# the manifest but left out, instead of stopping the whole update.
$docZip = Join-Path $testRoot 'unknown-doc.zip'
Copy-Item -LiteralPath $PackagePath -Destination $docZip
$docBytes = [Text.Encoding]::UTF8.GetBytes('# A guide a later release adds')
$docHasher = [Security.Cryptography.SHA256]::Create()
try { $docHash = [BitConverter]::ToString($docHasher.ComputeHash($docBytes)).Replace('-','').ToLowerInvariant() } finally { $docHasher.Dispose() }
$docArchive = [IO.Compression.ZipFile]::Open($docZip,[IO.Compression.ZipArchiveMode]::Update)
try {
  $entry = $docArchive.CreateEntry('guides/new-guide.md')
  $stream = $entry.Open(); try { $stream.Write($docBytes,0,$docBytes.Length) } finally { $stream.Dispose() }
  $manifest = $docArchive.GetEntry('SHA256SUMS.txt')
  $reader = New-Object IO.StreamReader($manifest.Open()); try { $manifestText = $reader.ReadToEnd() } finally { $reader.Dispose() }
  $manifest.Delete()
  $manifest = $docArchive.CreateEntry('SHA256SUMS.txt')
  $writer = New-Object IO.StreamWriter($manifest.Open(),(New-Object Text.UTF8Encoding($false)))
  try { $writer.Write($manifestText.TrimEnd("`r","`n") + "`n$docHash  guides/new-guide.md`n") } finally { $writer.Dispose() }
} finally { $docArchive.Dispose() }
$docRoot = Join-Path $testRoot 'unknown-doc-install'
[IO.Directory]::CreateDirectory($docRoot) | Out-Null
$null = Set-TestFile $docRoot 'CMakeLists.txt' ([Text.Encoding]::UTF8.GetBytes('unknown doc sentinel'))
$docResult = & $installer -ArchivePath $docZip -TargetRoot $docRoot
Assert-True ($docResult.Status -eq 'installed') 'An unknown documentation file stopped the update.'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $docRoot 'guides/new-guide.md'))) 'An unknown documentation file was installed.'
Assert-True ([string]$docResult.Message -match '1 documentation file') 'The result does not say a documentation file was left out.'
$results.tests.unknownDocSkipped = @{ passed=$true }

# VALIDATION.md may move under docs/ in a later package: that copy satisfies the requirement and
# is installed there, and a package with neither copy is still refused.
function New-ValidationVariant([string]$name, [string]$newPath) {
  $variantZip = Join-Path $testRoot $name
  Copy-Item -LiteralPath $PackagePath -Destination $variantZip
  $variant = [IO.Compression.ZipFile]::Open($variantZip,[IO.Compression.ZipArchiveMode]::Update)
  try {
    $old = $variant.GetEntry('VALIDATION.md')
    # Entry.Length is not reliable in Update mode; copy the whole stream instead.
    $buffer = New-Object IO.MemoryStream
    $source = $old.Open(); try { $source.CopyTo($buffer) } finally { $source.Dispose() }
    $bytes = $buffer.ToArray()
    if (-not $bytes.Length) { throw 'VALIDATION.md read back empty from the package copy.' }
    $old.Delete()
    if ($newPath) {
      $entry = $variant.CreateEntry($newPath)
      $stream = $entry.Open(); try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
    }
    $manifest = $variant.GetEntry('SHA256SUMS.txt')
    $reader = New-Object IO.StreamReader($manifest.Open()); try { $manifestText = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $manifest.Delete()
    $replacement = if ($newPath) { '  ' + $newPath } else { '' }
    $lines = @($manifestText -split "`r?`n" | Where-Object { $_ } | ForEach-Object {
      if ($_ -cmatch '^([0-9a-f]{64})  VALIDATION\.md$') { if ($newPath) { $Matches[1] + $replacement } } else { $_ }
    })
    $manifest = $variant.CreateEntry('SHA256SUMS.txt')
    $writer = New-Object IO.StreamWriter($manifest.Open(),(New-Object Text.UTF8Encoding($false)))
    try { $writer.Write(($lines -join "`n") + "`n") } finally { $writer.Dispose() }
  } finally { $variant.Dispose() }
  return $variantZip
}
$movedZip = New-ValidationVariant 'moved-validation.zip' 'docs/VALIDATION.md'
$movedRoot = Join-Path $testRoot 'moved-validation-install'
[IO.Directory]::CreateDirectory($movedRoot) | Out-Null
$null = Set-TestFile $movedRoot 'CMakeLists.txt' ([Text.Encoding]::UTF8.GetBytes('moved validation sentinel'))
$movedResult = & $installer -ArchivePath $movedZip -TargetRoot $movedRoot
Assert-True ($movedResult.Status -eq 'installed') 'A package with docs/VALIDATION.md was refused.'
Assert-True (Test-Path -LiteralPath (Join-Path $movedRoot 'docs/VALIDATION.md') -PathType Leaf) 'docs/VALIDATION.md was not installed.'
$missingZip = New-ValidationVariant 'missing-validation.zip' ''
$missingRoot = Join-Path $testRoot 'missing-validation-install'
[IO.Directory]::CreateDirectory($missingRoot) | Out-Null
$missingCmake = Set-TestFile $missingRoot 'CMakeLists.txt' ([Text.Encoding]::UTF8.GetBytes('missing validation sentinel'))
$missingRefused = $false
try {
  $missingResult = & $installer -ArchivePath $missingZip -TargetRoot $missingRoot
  if ($missingResult.Status -ne 'installed') { $missingRefused = $true }
} catch { $missingRefused = $true }
Assert-True $missingRefused 'A package without VALIDATION.md was accepted.'
Assert-True (([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($missingCmake))) -ceq 'missing validation sentinel') 'A refused package changed the scratch install.'
$results.tests.validationDocLocation = @{ passed=$true }

$results.completedUtc = [DateTime]::UtcNow.ToString('o')
$resultPath = Join-Path $testRoot 'results.json'
$results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding utf8
"Prototype update tests: PASS"
"Scratch evidence: $testRoot"
"Results: $resultPath"
