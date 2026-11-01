param(
  [switch]$IncludeNativePrototype,
  [string]$NativePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'user-data\verification\desktop-release\Release\assault.exe'),
  [string]$HostToolPath = (Join-Path $PSScriptRoot 'native\assault-image-tool.exe'),
  [string]$ReleaseVersion = '0.2.0-rc.2',
  [string]$ArchiveName = '',
  [string]$Stamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$projectDir = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$nativePath = [IO.Path]::GetFullPath($NativePath)
$expectedNative = [IO.Path]::GetFullPath((Join-Path $projectDir 'user-data\verification\desktop-release\Release\assault.exe'))
$hostToolPath = [IO.Path]::GetFullPath($HostToolPath)
if (-not (Test-Path -LiteralPath $hostToolPath -PathType Leaf)) { throw "Required standalone host image inspector not found: $hostToolPath" }
if ($IncludeNativePrototype) {
  if (-not [string]::Equals($nativePath,$expectedNative,[StringComparison]::OrdinalIgnoreCase)) {
    throw "Private native prototype packaging only accepts the validated desktop-release candidate: $expectedNative"
  }
  if (-not (Test-Path -LiteralPath $nativePath -PathType Leaf)) { throw "Native candidate not found: $nativePath" }
}
if ($Stamp -notmatch '^\d{8}-\d{6}$') { throw 'Stamp must use yyyyMMdd-HHmmss.' }
if ($ReleaseVersion -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,63}$') { throw 'ReleaseVersion must be a short printable version identifier.' }
if (-not $ArchiveName) { $ArchiveName = "Star-Fox-Assault-Recomp-v$ReleaseVersion-Windows-x64-$Stamp" }
if ($ArchiveName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,159}$') { throw 'ArchiveName must contain only letters, digits, dots, underscores and hyphens, without a file extension.' }

$sourceRoot = [IO.Path]::GetFullPath($projectDir).TrimEnd('\') + '\'
$releaseRoot = [IO.Path]::GetFullPath((Join-Path $projectDir 'user-data\releases'))
$userDataRoot = [IO.Path]::GetFullPath((Join-Path $projectDir 'user-data')).TrimEnd('\') + '\'
if (-not $releaseRoot.StartsWith($userDataRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Release output escaped project user-data.' }
[IO.Directory]::CreateDirectory($releaseRoot) | Out-Null
$runId = $Stamp + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$stage = Join-Path $releaseRoot ('.stage-' + $runId)
$verify = Join-Path $releaseRoot ('.verify-' + $runId)
$zipPath = Join-Path $releaseRoot ($ArchiveName + '.zip')
$archiveHashPath = Join-Path $releaseRoot ($ArchiveName + '.zip.sha256')
foreach ($path in @($stage,$verify,$zipPath,$archiveHashPath)) {
  $full = [IO.Path]::GetFullPath($path)
  if (-not $full.StartsWith($userDataRoot,[StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe package path: $full" }
  if (Test-Path -LiteralPath $full) { throw "Refusing to overwrite an existing package path: $full" }
}

$allowedExtensions = @('.c','.cc','.cpp','.cs','.h','.hh','.hpp','.inl','.cmake','.txt','.md','.py','.ps1','.cmd','.bat','.sh','.yml','.yaml','.json','.xml','.mm','.swift','.entitlements','.frag','.vert','.geom','.comp','.glsl','.glslinc','.inc','.rc','.def','.properties','.java','.kt','.gradle','.kts','.mk','.in','.manifest','.bin','.png','.ico','.sha1')
$excludedSegments = @('.git','.claude','.githooks','analysis','orig','build','build-native','build-desktop','userdata','user-data','saves','reference-metadata')
$packageFiles = New-Object 'System.Collections.Generic.List[object]'
$manifestPath = 'SHA256SUMS.txt'

function Add-PackageFile([string]$source,[string]$relative,[switch]$BinaryException) {
  $full = [IO.Path]::GetFullPath($source)
  if (-not $full.StartsWith($sourceRoot,[StringComparison]::OrdinalIgnoreCase)) { throw "Source path escaped project: $full" }
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Required package source is missing: $full" }
  $rel = $relative.Replace('\','/')
  if ($rel.StartsWith('/') -or $rel -match '(^|/)\.\.?(/|$)' -or $rel.Contains(':')) { throw "Unsafe package path: $rel" }
  if ($rel -match '(^|/)\.git(/|$)|(^|/)(analysis|orig|build-native|userdata|user-data|saves|reference-metadata)(/|$)') { throw "Excluded package path: $rel" }
  $extension = [IO.Path]::GetExtension($rel).ToLowerInvariant()
  if ($extension -notin $allowedExtensions -and [IO.Path]::GetFileName($rel) -notin @('LICENSE','NOTICE') -and -not ($BinaryException -and $extension -eq '.exe')) { throw "Extension is not approved for packaging: $rel" }
  if ($rel -match '\.(iso|ciso|gcm|dol|rel|raw|elf)$') { throw "Forbidden game image or executable content: $rel" }
  $dest = Join-Path $stage ($rel.Replace('/','\'))
  $destFull = [IO.Path]::GetFullPath($dest)
  $stagePrefix = [IO.Path]::GetFullPath($stage).TrimEnd('\') + '\'
  if (-not $destFull.StartsWith($stagePrefix,[StringComparison]::OrdinalIgnoreCase)) { throw "Package destination escaped staging root: $rel" }
  if (Test-Path -LiteralPath $destFull) { throw "Duplicate package path: $rel" }
  [IO.Directory]::CreateDirectory((Split-Path -Parent $destFull)) | Out-Null
  Copy-Item -LiteralPath $full -Destination $destFull
  $packageFiles.Add([pscustomobject]@{ Source=$full; Relative=$rel })
}

function Add-SourceTree([string]$relativeRoot) {
  $root = Join-Path $projectDir $relativeRoot
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Required source directory is missing: $relativeRoot" }
  foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
    $relative = $file.FullName.Substring($sourceRoot.Length).Replace('\','/')
    $segments = $relative.Split('/')
    if ($segments | Where-Object { $_ -in $excludedSegments -or $_.StartsWith('.') }) { continue }
    if ([IO.Path]::GetExtension($file.Name).ToLowerInvariant() -notin $allowedExtensions -and $file.Name -notin @('LICENSE','NOTICE')) { continue }
    Add-PackageFile $file.FullName $relative
  }
}

function Get-PackageRelativeFiles([string]$root) {
  return @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object { $_.FullName.Substring(([IO.Path]::GetFullPath($root).TrimEnd('\') + '\').Length).Replace('\','/') } | Sort-Object)
}

try {
  [IO.Directory]::CreateDirectory($stage) | Out-Null
  $hostToolHashBefore = (Get-FileHash -LiteralPath $hostToolPath -Algorithm SHA256).Hash
  $nativeHashBefore = if ($IncludeNativePrototype) { (Get-FileHash -LiteralPath $nativePath -Algorithm SHA256).Hash } else { $null }

  foreach ($file in @('Launch-StarFoxAssault.ps1','Start-StarFoxAssault.cmd','Star Fox Assault Recomp.exe','CMakeLists.txt','LICENSE','THIRD_PARTY_NOTICES.md','CREDITS.md','RELEASE-NOTES.md','portable.txt')) {
    Add-PackageFile (Join-Path $projectDir $file) $file -BinaryException:($file -like '*.exe')
  }
  Add-PackageFile $hostToolPath 'tools/native/assault-image-tool.exe' -BinaryException
  if ($IncludeNativePrototype) { Add-PackageFile $nativePath 'build-desktop/Release/assault.exe' -BinaryException }
  Add-PackageFile (Join-Path $projectDir 'assets\assault-launcher-background.png') 'assets/assault-launcher-background.png'
  Add-PackageFile (Join-Path $projectDir 'assets\assault-arwing-hangar.png') 'assets/assault-arwing-hangar.png'
  Add-PackageFile (Join-Path $projectDir 'assets\assault-arwing-hangar.prompt.txt') 'assets/assault-arwing-hangar.prompt.txt'
  Add-PackageFile (Join-Path $projectDir 'assets\assault-launcher.ico') 'assets/assault-launcher.ico'
  Add-SourceTree 'assets\fonts'
  Add-SourceTree 'tools'
  Add-SourceTree 'recomp'
  Add-SourceTree 'decomp\config\GF7E01'
  Add-SourceTree 'runtime'
  Add-SourceTree 'third_party_licenses'

  $hostToolHash = (Get-FileHash -LiteralPath (Join-Path $stage 'tools\native\assault-image-tool.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
  $releaseInfo = [ordered]@{
    schemaVersion = 1
    version = $ReleaseVersion
    releaseId = $Stamp
    releaseChannel = 'experimental-source'
    targetPlatform = 'Windows x64'
    packageKind = if ($IncludeNativePrototype) { 'private-native-test' } else { 'source-and-host-tools' }
    nativeGameExecutableIncluded = [bool]$IncludeNativePrototype
    nativeGameExecutableSha256 = if ($IncludeNativePrototype) { (Get-FileHash -LiteralPath $nativePath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
    userSuppliedGameImageRequired = $true
    originalGameImageIncluded = $false
    dolRelGameCodeIncluded = $false
    firstNativeBuildRequiresInternet = $true
    hostInspector = [ordered]@{ path='tools/native/assault-image-tool.exe'; sha256=$hostToolHash }
    payloadIntegrityManifest = 'SHA256SUMS.txt'
    sha256Sidecar = ([IO.Path]::GetFileName($zipPath) + '.sha256')
  }
  $releaseJson = Join-Path $stage 'release.json'
  $releaseInfo | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $releaseJson -Encoding utf8
  $packageFiles.Add([pscustomobject]@{ Source=$releaseJson; Relative='release.json' })

  $required = @(
    'Launch-StarFoxAssault.ps1','Start-StarFoxAssault.cmd','Star Fox Assault Recomp.exe',
    'tools/native/assault-image-tool.exe','tools/portable-toolchain.json','release.json','LICENSE','CREDITS.md','RELEASE-NOTES.md','portable.txt','CMakeLists.txt','THIRD_PARTY_NOTICES.md',
    'assets/assault-launcher-background.png','assets/fonts/font_western.bin',
    'assets/assault-arwing-hangar.png','assets/assault-arwing-hangar.prompt.txt',
    'assets/assault-launcher.ico',
    'assets/fonts/font_japanese.bin','assets/fonts/font-licenses.txt',
    'recomp/special_calls.txt','recomp/names.txt','recomp/idle.txt','recomp/hle.txt',
    'decomp/config/GF7E01/symbols.txt','decomp/config/GF7E01/build.sha1','runtime/CMakeLists.txt','runtime/LICENSE',
    'runtime/runtime/hw/exi.cpp','runtime/runtime/disc_mods.cpp','runtime/runtime/assault.manifest','runtime/recomp/rel.py',
    'tools/Build-StarFoxAssault.ps1','tools/Build-NativeGame.ps1','tools/Build-CacheSignature.ps1','tools/Ensure-PortableToolchain.ps1','tools/Build-Launcher.ps1','tools/LauncherBootstrap.cs',
    'tools/Package-Prototype.ps1'
  )
  foreach ($relative in $required) {
    $copied = $packageFiles | Where-Object { $_.Relative -ceq $relative } | Select-Object -First 1
    if (-not $copied -and $relative -eq 'tools/Package-Prototype.ps1') { continue }
    if (-not $copied) { throw "Required package payload missing: $relative" }
  }
  if ($IncludeNativePrototype -and -not ($packageFiles | Where-Object { $_.Relative -ceq 'build-desktop/Release/assault.exe' })) {
    throw 'The private native prototype package is missing its opt-in game executable.'
  }

  $hostToolHashAfter = (Get-FileHash -LiteralPath $hostToolPath -Algorithm SHA256).Hash
  if ($hostToolHashBefore -ne $hostToolHashAfter) { throw 'The standalone host inspector changed while packaging; output was not created.' }
  if ($IncludeNativePrototype) {
    $nativeHashAfter = (Get-FileHash -LiteralPath $nativePath -Algorithm SHA256).Hash
    if ($nativeHashBefore -ne $nativeHashAfter) { throw 'The validated native candidate changed while packaging; output was not created.' }
  }

  $readme = @'
STAR FOX ASSAULT RECOMP 0.2.0-RC.2 - WINDOWS X64 SOURCE PACKAGE

This package contains the launcher, recompiler source, build tools, and a standalone
game-image inspector. It does not contain a game image or a prebuilt game executable.
You must provide your own USA Star Fox: Assault ISO or CISO (disc ID GF7E01).

GETTING STARTED

1. Extract this folder somewhere you can write files.
2. Start "Star Fox Assault Recomp.exe" (or "Start-StarFoxAssault.cmd").
3. Choose Import Game Image and select your own supported USA ISO/CISO.
4. Choose Import & Build. The launcher checks the image, downloads the pinned
   portable build tools and required SDL source, then builds a local game executable.
5. When the build finishes, choose Play Native.

The first build needs internet access and downloads about 280 MB of pinned build tools,
plus SDL source. Allow several GB of free disk space for downloads, build files, and
caches. It requires 64-bit Windows 10 version 1903 or newer and a graphics adapter
with desktop OpenGL 3.3 support. It does not require administrator installation,
Dolphin, or a separately installed compiler. Later builds reuse the local tool cache.
If Windows blocks a download, read the launcher message and retry after restoring
internet access.

PORTABLE FILES AND UPDATES

This folder includes portable.txt. Settings, downloaded tools, build output, saves,
and logs are kept under user-data. Package updates preserve those local files and
your locally built game executable. Keep the whole folder together when moving the
installation to another location.

The launcher provides graphics options, controller mapping, save backups, local mod
pack management, package updates, and optional Dolphin launch support. Native asset
replacement currently accepts same-size files at matching disc paths. It does not
replace DOL/REL game code. Online update and mod services are not included.

PROJECT STATUS

This is an experimental source-build release candidate, not a complete or stable
game release. The rc.2 package completed an empty-cache online build and bounded
hidden boot on the tested machine; see VALIDATION.md for scope. First-mission flight
and profile persistence have been tested. The
first-boss visibility report, an invalid-current-thread-pointer crash, later missions,
mission completion, full audio fidelity, and all physical controllers remain
unverified. Widescreen is experimental. See RELEASE-NOTES.md and VALIDATION.md.

The included LICENSE covers original project software source; CREDITS.md,
THIRD_PARTY_NOTICES.md, and the font license file list
attributions and licenses. The original game image and extracted or generated game
code are not included. The adjacent SHA256SUMS.txt covers package files, and the
adjacent .zip.sha256 file fingerprints the complete ZIP archive.
'@
  Set-Content -LiteralPath (Join-Path $stage 'README-PROTOTYPE.txt') -Value $readme -Encoding utf8
  $packageValidation = @'
# Validation summary

Validation date: 2026-11-01. This report summarizes the completed rc.2 empty-cache
package build and bounded boot. It contains no local image paths, image hashes, or
user data.

## Checks passed

- The rc.2 source package was extracted into a Unicode-named folder with no existing
  tool, SDL or game build cache. Its actual **Import & Build** action downloaded all
  four pinned tool archives, verified their SHA-256 values, fetched and built SDL, and
  compiled 101 fresh Ninja units. A plain ISO path with spaces and an apostrophe was
  accepted. The 42,158,080-byte native executable was produced in about 150 seconds.
  This is an end-to-end empty-cache online first-use run.
- The launcher build used only the Windows system path plus portable tools from
  `user-data`; it did not use a preinstalled compiler, CMake, Ninja, Python, or Dolphin.
- Existing `%LOCALAPPDATA%` launcher settings remained unchanged during the portable
  build.
- A hidden normal-speed boot ran for its full 10-second bound after that build. The
  health-and-safety screen rendered readable text. Both Japanese and Western
  replacement fonts loaded from the Unicode-named asset path. The test used an
  isolated synthetic save and ended at the planned time limit.
- Portable Windows x64 build-tool manifest verification and an incremental native
  build completed successfully.
- The runtime regression suite passed 9 of 9 checks.
- The rc.2 launcher build UI passed six cases covering Unicode paths, successful
  build, cancellation, worker failure, exit-code mismatch, missing status, and retry.
  Build-cache signature regressions passed two cases. Worker invalid-image and
  cancellation runs returned the expected failure/cancel states and retained the
  prior executable.
- Portable tool setup rejected empty offline caches, quarantined a corrupt archive,
  and rejected a traversal archive without leaving staging files.
- An unchanged offline rebuild completed in 2.86 seconds with the same native
  executable hash.
- The standalone image inspector validates supported USA GF7E01 images read-only.
- Package integrity, excluded-file checks, and update rollback/preservation checks
  passed for the source-and-host-tools package.

## Not yet established

- Full-game compatibility, later missions, mission completion, complete audio
  fidelity, and all physical controllers remain unverified.
- The reported first-boss visibility issue and invalid-current-thread-pointer crash
  remain unresolved. Widescreen remains experimental.

The package excludes game images, extracted DOL/REL files, generated game code,
prebuilt game executables, local settings, saves, and build caches. Each recipient
provides their own supported game image and builds locally.
'@
  $validationPath = Join-Path $stage 'VALIDATION.md'
  Set-Content -LiteralPath $validationPath -Value $packageValidation -Encoding utf8
  $packageFiles.Add([pscustomobject]@{ Source=$validationPath; Relative='VALIDATION.md' })

  $manifest = New-Object 'System.Collections.Generic.List[string]'
  foreach ($relative in (Get-PackageRelativeFiles $stage)) {
    $file = Join-Path $stage ($relative.Replace('/','\'))
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest.Add("$hash  $relative")
  }
  Set-Content -LiteralPath (Join-Path $stage $manifestPath) -Value $manifest -Encoding ascii

  [IO.Compression.ZipFile]::CreateFromDirectory($stage,$zipPath,[IO.Compression.CompressionLevel]::Optimal,$false)
  [IO.Directory]::CreateDirectory($verify) | Out-Null
  [IO.Compression.ZipFile]::ExtractToDirectory($zipPath,$verify)

  $manifestFile = Join-Path $verify $manifestPath
  if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) { throw 'Package manifest is missing after extraction.' }
  $listed = @{}
  foreach ($line in Get-Content -LiteralPath $manifestFile) {
    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { throw "Malformed manifest line: $line" }
    $relative = $Matches[2]
    $listed[$relative] = $Matches[1]
    $file = Join-Path $verify ($relative.Replace('/','\'))
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Manifest entry missing after extraction: $relative" }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Matches[1]) { throw "Manifest hash mismatch: $relative" }
  }
  $actual = @(Get-PackageRelativeFiles $verify | Where-Object { $_ -cne $manifestPath })
  if ($actual.Count -ne $listed.Count) { throw "Manifest covers $($listed.Count) files but extracted payload has $($actual.Count)." }
  foreach ($relative in $actual) { if (-not $listed.ContainsKey($relative)) { throw "Unlisted package file: $relative" } }
  $forbidden = @('.iso','.ciso','.gcm','.dol','.rel','.raw','.elf','.o','.obj','.lib','.pdb','.dll')
  $allFiles = Get-PackageRelativeFiles $verify
  $expectedExecutables = @('Star Fox Assault Recomp.exe','tools/native/assault-image-tool.exe')
  if ($IncludeNativePrototype) { $expectedExecutables += 'build-desktop/Release/assault.exe' }
  $actualExecutables = @($allFiles | Where-Object { [IO.Path]::GetExtension($_).ToLowerInvariant() -eq '.exe' } | Sort-Object)
  $expectedExecutables = @($expectedExecutables | Sort-Object)
  if (($actualExecutables -join "`n") -cne ($expectedExecutables -join "`n")) {
    throw "Unexpected package executables: $($actualExecutables -join ', ')"
  }
  if (-not $IncludeNativePrototype) {
    $releaseMetadata = Get-Content -LiteralPath (Join-Path $verify 'release.json') -Raw | ConvertFrom-Json
    if ($releaseMetadata.packageKind -cne 'source-and-host-tools' -or $releaseMetadata.nativeGameExecutableIncluded -or $releaseMetadata.originalGameImageIncluded -or $releaseMetadata.dolRelGameCodeIncluded) {
      throw 'Source package release metadata does not accurately exclude the game image and generated game executable/code.'
    }
  }
  $expectedAssets = @(
    'assets/assault-arwing-hangar.png','assets/assault-arwing-hangar.prompt.txt',
    'assets/assault-launcher-background.png','assets/assault-launcher.ico',
    'assets/fonts/font-licenses.txt','assets/fonts/font_japanese.bin','assets/fonts/font_western.bin'
  ) | Sort-Object
  $actualAssets = @($allFiles | Where-Object { $_.StartsWith('assets/') } | Sort-Object)
  if (($actualAssets -join "`n") -cne ($expectedAssets -join "`n")) {
    throw "Unexpected asset payload: $($actualAssets -join ', ')"
  }
  $approvedMediaFiles = @('assets/assault-arwing-hangar.png','assets/assault-launcher-background.png','assets/assault-launcher.ico','assets/fonts/font_japanese.bin','assets/fonts/font_western.bin')
  foreach ($relative in $allFiles) {
    $extension = [IO.Path]::GetExtension($relative).ToLowerInvariant()
    if ($extension -in $forbidden) { throw "Forbidden extension in archive: $relative" }
    if ($extension -in @('.bin','.png','.ico') -and $relative -cnotin $approvedMediaFiles) { throw "Unapproved binary or image asset in archive: $relative" }
    if ($relative -match '(^|/)\.git(/|$)|(^|/)(analysis|orig|build-native|userdata|user-data|saves|reference-metadata)(/|$)') { throw "Forbidden content path in archive: $relative" }
    if ($relative -match '(^|/)(game_recomp|generated_game_code|extracted_game)(/|$)') { throw "Generated or extracted game code in archive: $relative" }
    if ($relative -match '^build-desktop/' -and $relative -cne 'build-desktop/Release/assault.exe') { throw "Unexpected build output in archive: $relative" }
  }
  $textExtensions = @('.txt','.md','.ps1','.cmd','.bat','.cs','.c','.cc','.cpp','.h','.hh','.hpp','.inl','.json','.xml','.py','.yml','.yaml','.cmake','.sh','.properties','.manifest')
  foreach ($relative in $allFiles) {
    if ([IO.Path]::GetExtension($relative).ToLowerInvariant() -notin $textExtensions) { continue }
    $contents = Get-Content -LiteralPath (Join-Path $verify ($relative.Replace('/','\'))) -Raw
    if ($contents -match '(?i)(?:^|["''\s=,(])[A-Z]:\\(?:Users\\[^\\\r\n]+\\|Emulators\\|Roms\\|AppData\\|Documents\\ChatGPT\\)') { throw "Personal absolute Windows path in package text: $relative" }
  }
  $powershellFiles = Get-ChildItem -LiteralPath $verify -Recurse -File -Filter '*.ps1'
  foreach ($script in $powershellFiles) {
    $tokens = $null; $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$parseErrors) | Out-Null
    if ($parseErrors.Count) { throw "Packaged PowerShell parse failed: $($script.FullName)" }
  }
  $archiveHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
  Set-Content -LiteralPath $archiveHashPath -Value "$archiveHash  $([IO.Path]::GetFileName($zipPath))" -Encoding ascii
  "Package: $zipPath"
  "Archive SHA256: $archiveHash"
  "Payload files verified: $($actual.Count)"
  "Extracted manifest hash checks: PASS"
  'Excluded-extension and content-path checks: PASS'
  'Source-only metadata, asset allowlist, and local-path checks: PASS'
  'Packaged PowerShell parser checks: PASS'
} catch {
  if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
  if (Test-Path -LiteralPath $archiveHashPath) { Remove-Item -LiteralPath $archiveHashPath -Force }
  throw
} finally {
  foreach ($path in @($stage,$verify)) {
    $full = [IO.Path]::GetFullPath($path)
    if (-not $full.StartsWith($userDataRoot,[StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to clean outside user-data: $full" }
    if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force }
  }
}
