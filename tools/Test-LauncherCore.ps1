# Tests for tools/LauncherCore.ps1: settings schema and recovery, argument quoting, build
# progress mapping, pre-flight rules and failure reports. No window, network or game image.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'LauncherCore.ps1')

$script:failures = 0
$script:passed = 0
function Assert-Equal($expected, $actual, [string]$name) {
  $same = if ($expected -is [array] -or $actual -is [array]) { (@($expected) -join "`n") -ceq (@($actual) -join "`n") -and @($expected).Count -eq @($actual).Count } else { $expected -ceq $actual -and ($null -eq $expected) -eq ($null -eq $actual) }
  if ($same) { $script:passed++ } else { $script:failures++; Write-Output ("FAIL {0}: expected [{1}] got [{2}]" -f $name,(@($expected) -join ', '),(@($actual) -join ', ')) }
}
function Assert-True([bool]$condition, [string]$name) { Assert-Equal $true $condition $name }

# --- Settings defaults and normalisation ---
$defaults = Get-LauncherSettingDefaults
Assert-Equal 19 $defaults.Count 'schema covers every profile key'
Assert-Equal '0' $defaults.anisotropy 'HD enhancements default off'
Assert-Equal $false $defaults.softParticles 'soft particles default off'
Assert-Equal 2.0 $defaults.scale 'default scale'
Assert-Equal 'original' $defaults.aspect 'default aspect'
Assert-Equal 100 $defaults.volume 'default volume'
Assert-Equal '' $defaults.deadzone 'default deadzone keeps runtime thresholds'

$fromNull = Read-LauncherSettings $null
Assert-Equal ($defaults | ConvertTo-Json -Compress) ($fromNull | ConvertTo-Json -Compress) 'no profile gives defaults'

$saved = '{"disc":"C:\\Games\\SFA.iso","scale":"1.5","aspect":"Widescreen","aa":"msaa","filter":null,"volume":"250","vsync":"true","fullscreen":1,"muteMusic":"maybe","deadzone":"7","unknown":"x"}' | ConvertFrom-Json
$read = Read-LauncherSettings $saved
Assert-Equal 'C:\Games\SFA.iso' $read.disc 'string kept'
Assert-Equal 1.5 $read.scale 'numeric string scale accepted'
Assert-Equal 'widescreen' $read.aspect 'allowed value matched without case, stored canonical'
Assert-Equal 'off' $read.aa 'unknown aa falls back'
Assert-Equal 'sharp' $read.filter 'null filter falls back'
Assert-Equal 100 $read.volume 'volume clamped to 100'
Assert-Equal $true $read.vsync 'string true read as bool'
Assert-Equal $true $read.fullscreen 'number 1 read as bool'
Assert-Equal $false $read.muteMusic 'unparseable bool falls back'
Assert-Equal '' $read.deadzone 'disallowed deadzone falls back'
Assert-True (-not $read.Contains('unknown')) 'unknown keys dropped'

Assert-Equal 0 (ConvertTo-LauncherSettingValue 'volume' -5) 'volume clamped to 0'
Assert-Equal 100 (ConvertTo-LauncherSettingValue 'volume' 'loud') 'non-numeric volume falls back'
Assert-Equal 2.0 (ConvertTo-LauncherSettingValue 'scale' 5) 'scale outside the list falls back'
Assert-Equal 0.0 (ConvertTo-LauncherSettingValue 'scale' 0) 'auto scale accepted'
Assert-Equal '15' (ConvertTo-LauncherSettingValue 'deadzone' 15) 'numeric deadzone accepted'

# A saved profile round-trips through JSON unchanged.
$roundTrip = Read-LauncherSettings ($read | ConvertTo-Json | ConvertFrom-Json)
Assert-Equal ($read | ConvertTo-Json -Compress) ($roundTrip | ConvertTo-Json -Compress) 'settings round-trip through JSON'

# The Settings page shows one label per allowed value; these counts must match its lists.
Assert-Equal 7 (Get-LauncherSettingAllowed 'scale').Count 'scale choices match the Settings page'
Assert-Equal 3 (Get-LauncherSettingAllowed 'aspect').Count 'aspect choices match the Settings page'
Assert-Equal 2 (Get-LauncherSettingAllowed 'aa').Count 'aa choices match the Settings page'
Assert-Equal 2 (Get-LauncherSettingAllowed 'filter').Count 'filter choices match the Settings page'
Assert-Equal 7 (Get-LauncherSettingAllowed 'deadzone').Count 'deadzone choices match the Settings page'

Assert-Equal @('--scale=1.5','--aspect=stretch','--aa=fxaa','--filter=smooth') (Get-NativeGraphicsArgumentList 1.5 'stretch' 'fxaa' 'smooth') 'graphics arguments'
Assert-Equal @('--scale=2','--aspect=original','--aa=off','--filter=sharp') (Get-NativeGraphicsArgumentList 9 'bad' $null '') 'graphics arguments fall back to defaults'

# --- HD enhancements ---
Assert-Equal 5 (Get-LauncherSettingAllowed 'anisotropy').Count 'anisotropy choices match the Settings page'
Assert-Equal '0' (ConvertTo-LauncherSettingValue 'anisotropy' '3') 'anisotropy outside the list falls back'
Assert-Equal '16' (ConvertTo-LauncherSettingValue 'anisotropy' 16) 'numeric anisotropy accepted'
$preset = Get-HdPresetSettings
Assert-Equal 4.0 $preset.scale 'HD preset uses 4x'
Assert-Equal '16' $preset.anisotropy 'HD preset uses 16x anisotropy'
foreach ($key in $preset.Keys) { Assert-Equal $preset[$key] (ConvertTo-LauncherSettingValue $key $preset[$key]) "HD preset $key is a valid setting" }
foreach ($name in 'original','hd','widescreen') {
  $p = Get-DisplayPreset $name
  foreach ($key in $p.Keys) { Assert-Equal $p[$key] (ConvertTo-LauncherSettingValue $key $p[$key]) "$name preset $key is a valid setting" }
}
Assert-Equal 'original' (Get-DisplayPreset 'original').aspect 'original preset is 4:3'
Assert-Equal '0' (Get-DisplayPreset 'original').anisotropy 'original preset turns enhancements off'
Assert-Equal 'widescreen' (Get-DisplayPreset 'widescreen').aspect 'widescreen preset is 16:9'
Assert-Equal '16' (Get-DisplayPreset 'widescreen').anisotropy 'widescreen preset keeps the HD settings'
Assert-True (-not (Get-DisplayPreset 'hd').Contains('aspect')) 'HD preset leaves aspect alone'
$none = Get-NativeEnhancementArgumentList (Get-LauncherSettingDefaults) '' ''
Assert-Equal 0 $none.Count 'defaults add no runtime flags'
$packDir = Join-Path ([IO.Path]::GetTempPath()) ('hd pack test ' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($packDir)
try {
  $on = Get-LauncherSettingDefaults; $on.anisotropy = '8'; $on.trilinear = $true; $on.softParticles = $true; $on.hdTextures = $true; $on.dumpTextures = $true
  $flags = Get-NativeEnhancementArgumentList $on $packDir 'D:\dump dir'
  Assert-Equal @('--anisotropy=8','--trilinear=1','--soft-particles=1',('--texture-pack="' + $packDir + '"'),'--texture-dump="D:\dump dir"') $flags 'every enhancement flag, paths quoted'
  $flags = Get-NativeEnhancementArgumentList $on (Join-Path $packDir 'missing') ''
  Assert-True (-not ($flags -match 'texture-pack')) 'a missing pack folder is not passed'
} finally { Remove-Item -LiteralPath $packDir -Recurse -Force }
Assert-True (Test-HdTextureName '0123456789abcdef.png') 'hash name accepted'
Assert-True (Test-HdTextureName '0123456789ABCDEF.PNG') 'hash name accepted without case'
Assert-True (-not (Test-HdTextureName 'tex_12.png')) 'dump-by-id name refused'
Assert-True (-not (Test-HdTextureName '0123456789abcdef.png.exe')) 'other extension refused'
Assert-True (-not (Test-HdTextureName '..\0123456789abcdef.png')) 'path refused'
Assert-True (Test-HdTextureName 'tex1_608x448_3350bc351be222ba_0a5410ad0d30eae2_9.png') 'Dolphin name with palette accepted'
Assert-True (Test-HdTextureName 'tex1_64x64_m_0123456789abcdef_14.png') 'Dolphin mipmapped name accepted'
Assert-True (Test-HdTextureName 'tex1_32x32_0123456789abcdef_$_8_arb.png') 'Dolphin wildcard and arb accepted'
Assert-True (Test-HdTextureName 'TEX1_32x32_$_0123456789abcdef_9_mip1.PNG') 'Dolphin texture wildcard and mip accepted'
Assert-True (Test-HdTextureName 'tex1_32x32_0123456789abcdef_8.dds') 'Dolphin DDS accepted'
Assert-True (-not (Test-HdTextureName '0123456789abcdef.dds')) 'DDS only under Dolphin names'
Assert-True (-not (Test-HdTextureName 'tex1_32x32_nothex_8.png')) 'bad Dolphin hash refused'

# --- Argument quoting (CommandLineToArgvW rules) ---
Assert-Equal '"C:\Games\SFA.iso"' (ConvertTo-NativeArgument 'C:\Games\SFA.iso') 'plain path quoted'
Assert-Equal '"C:\My Games\controls.txt"' (ConvertTo-NativeArgument 'C:\My Games\controls.txt') 'path with spaces quoted'
Assert-Equal '"C:\dir\\"' (ConvertTo-NativeArgument 'C:\dir\') 'trailing backslash doubled'
Assert-Equal '"say \"hi\""' (ConvertTo-NativeArgument 'say "hi"') 'embedded quotes escaped'

# --- Build progress ---
Assert-Equal 1 (Get-BuildPhaseStep 'Checking image') 'step 1'
Assert-Equal 2 (Get-BuildPhaseStep 'Preparing tools') 'step 2 from the build worker'
Assert-Equal 2 (Get-BuildPhaseStep 'Preparing build tools') 'step 2 from the toolchain script'
Assert-Equal 3 (Get-BuildPhaseStep 'Using build cache') 'step 3 cached'
Assert-Equal 4 (Get-BuildPhaseStep 'Compiling native executable') 'step 4'
Assert-Equal 5 (Get-BuildPhaseStep 'Ready to play') 'step 5'
Assert-Equal 0 (Get-BuildPhaseStep 'Build failed') 'failure has no step'
Assert-Equal 35 (Get-BuildOverallPercent 'Recompiling game' 0) 'recompile starts at 35%'
Assert-Equal 65 (Get-BuildOverallPercent 'Recompiling game' 100) 'recompile ends at 65%'
Assert-Equal 93 (Get-BuildOverallPercent 'Compiling native executable' 100) 'compile ends at 93%'
Assert-Equal 68 (Get-BuildOverallPercent 'Compiling native executable' -10) 'percent clamped low'
Assert-Equal 100 (Get-BuildOverallPercent 'Ready to play' 250) 'percent clamped high'
Assert-Equal '0:05' (Format-Elapsed ([TimeSpan]::FromSeconds(5))) 'elapsed seconds'
Assert-Equal '12:34' (Format-Elapsed ([TimeSpan]::FromSeconds(754))) 'elapsed minutes'
Assert-Equal '1:02:03' (Format-Elapsed ([TimeSpan]::FromSeconds(3723))) 'elapsed hours'
Assert-Equal '0:00' (Format-Elapsed ([TimeSpan]::FromSeconds(-3))) 'negative elapsed shown as zero'

# --- Pre-flight rules ---
$healthy = @{ ProjectPath = 'C:\Games\SFA'; Drive = 'C:'; FreeBytes = [long]50GB; Writable = $true; ToolsMissing = @(); LongPathsEnabled = $false }
Assert-Equal 0 (Get-BuildPreflightIssues $healthy).Count 'healthy machine has no issues'
$lowDisk = $healthy.Clone(); $lowDisk.FreeBytes = [long]1GB
$issues = Get-BuildPreflightIssues $lowDisk
Assert-Equal 'block' $issues[0].Severity 'under 3 GB blocks'
Assert-True ($issues[0].Message -match '1024\.0 MB') 'low-disk message names the free space'
$readOnly = $healthy.Clone(); $readOnly.Writable = $false; $readOnly.WriteError = 'Access denied'
Assert-Equal 'block' (Get-BuildPreflightIssues $readOnly)[0].Severity 'read-only folder blocks'
$offline = $healthy.Clone(); $offline.ToolsMissing = @('cmake','ninja'); $offline.Reachable = $false
$issues = Get-BuildPreflightIssues $offline
Assert-Equal 'block' $issues[0].Severity 'missing tools and no network blocks'
Assert-True ($issues[0].Message -match 'cmake, ninja') 'offline message names the tools'
$cachedOffline = $healthy.Clone(); $cachedOffline.Reachable = $false
Assert-Equal 0 (Get-BuildPreflightIssues $cachedOffline).Count 'no network is fine once tools are cached'
$longPath = $healthy.Clone(); $longPath.ProjectPath = 'C:\' + ('x' * 120)
Assert-Equal 'warn' (Get-BuildPreflightIssues $longPath)[0].Severity 'long path warns'
$longPath.LongPathsEnabled = $true
Assert-Equal 0 (Get-BuildPreflightIssues $longPath).Count 'long path is fine with long paths enabled'

# Missing-tool detection reads the real manifest against an empty tool folder.
$tempProject = Join-Path ([IO.Path]::GetTempPath()) ('launcher-core-test-' + [Guid]::NewGuid().ToString('N'))
try {
  [void][IO.Directory]::CreateDirectory((Join-Path $tempProject 'tools'))
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'portable-toolchain.json') -Destination (Join-Path $tempProject 'tools')
  $manifestIds = @((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'portable-toolchain.json') -Raw | ConvertFrom-Json).tools | ForEach-Object { [string]$_.id })
  Assert-Equal $manifestIds (Get-MissingPortableTools $tempProject) 'every tool missing in an empty folder'
  $first = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'portable-toolchain.json') -Raw | ConvertFrom-Json).tools[0]
  $stampDir = Join-Path $tempProject ('user-data\build-tools\{0}-{1}' -f $first.id,$first.version)
  [void][IO.Directory]::CreateDirectory($stampDir); [IO.File]::WriteAllText((Join-Path $stampDir '.ready.json'),'{}')
  Assert-Equal @($manifestIds | Select-Object -Skip 1) (Get-MissingPortableTools $tempProject) 'a stamped tool counts as present'
  $facts = Get-BuildPreflightFacts $tempProject
  Assert-Equal $true $facts.Writable 'temp project is writable'
  Assert-True ($facts.FreeBytes -gt 0) 'free space measured'
} finally { if (Test-Path -LiteralPath $tempProject) { Remove-Item -LiteralPath $tempProject -Recurse -Force } }

# --- Failure summaries and reports ---
$stdout = @(
  '[Recompiling game] Extracting and recompiling',
  '[12/400] Building C object foo.c.obj',
  'D:\Home\Pat\sfa\recomp\out\f_8001.c(12,3): error: use of undeclared identifier ''r33''',
  'warning: unused variable',
  'D:\Home\Pat\sfa\recomp\out\f_8001.c(12,3): error: use of undeclared identifier ''r33''',
  'ninja: build stopped: subcommand failed.',
  'FAILED: CMakeFiles/assault.dir/f_8001.c.obj',
  'Build succeeded with 0 errors'
)
$stderr = @('Compiling native executable failed (exit 1). See the build log for details.')
$errors = Get-BuildErrorLines $stdout $stderr
Assert-Equal 3 $errors.Count 'duplicates, warnings and "0 errors" skipped'
Assert-True ($errors[0] -match 'undeclared identifier') 'compiler error first'
Assert-True ($errors[1] -match '^FAILED:') 'ninja failure kept'
Assert-True ($errors[2] -match 'failed \(exit 1\)') 'worker error from stderr kept'
Assert-Equal 0 (Get-BuildErrorLines @() $null).Count 'empty logs give no errors'
# The worker writes its failure message to stdout with a phase tag and to stderr without one;
# the dialog already shows it above the list.
$failMsg = 'Compiling native executable failed (exit 1). See the build log for details.'
$picked = Get-BuildErrorLines @('x.c(1,1): error: bad', "[Build failed] $failMsg") @($failMsg) 5 @($failMsg)
Assert-Equal @('x.c(1,1): error: bad') $picked 'failure message shown once, not repeated in the list'
$picked = Get-BuildErrorLines @("[Build failed] $failMsg") @($failMsg)
Assert-Equal 1 $picked.Count 'tagged and untagged copies of a line count once'
Assert-Equal 2 (Get-BuildErrorLines @('error: a','error: b','error: c') @() 2).Count 'error count capped'

$protected = Protect-ReportText 'D:\Home\Pat\Games\SFA.iso and d:\home\pat\sfa\log' @{ 'D:\Home\Pat\Games\SFA.iso' = '<game image>'; 'D:\Home\Pat' = '%USERPROFILE%' }
Assert-Equal '<game image> and %USERPROFILE%\sfa\log' $protected 'longest path replaced first, without case'
Assert-Equal 'cost $5' (Protect-ReportText 'cost X' @{ 'X' = '$5' }) 'dollar signs in replacements stay literal'

$report = New-BuildFailureReport @{ Version = '0.2.0-test'; OsVersion = 'Windows'; Phase = 'Compiling native executable'; Message = 'failed'; ExitCode = 1; Elapsed = '3:00'; Errors = $errors; Tail = $stdout } @{ 'D:\Home\Pat' = '%USERPROFILE%' }
Assert-True ($report -match 'Failed phase: Compiling native executable') 'report names the phase'
Assert-True ($report -notmatch 'D:\\Home\\Pat') 'report has no profile path'
Assert-True ($report -match '%USERPROFILE%') 'report keeps redacted path'

# --- Crash reports ---
Assert-Equal '' (Get-CrashLogFlag @('graphics: OpenGL','[OS] OSLink: m4.rel')) 'an ordinary log is not flagged'
Assert-Equal '[guard] 800000E4 changed at frame 1234' (Get-CrashLogFlag @('ok','  [guard] 800000E4 changed at frame 1234  ','fatal: later')) 'first flagged line, trimmed'
Assert-Equal 'fatal: invalid instruction' (Get-CrashLogFlag @('fatal: invalid instruction')) 'fatal lines are flagged'
Assert-Equal '' (Get-CrashLogFlag @('nonfatal warning')) 'fatal only as a whole word'
Assert-Equal '' (Get-CrashLogFlag $null) 'no lines, no flag'
$summary = New-CrashReportSummary @{ Version = '0.2.0-test'; OsVersion = 'Windows'; Session = 'native-1'; When = 'today'; Flag = '[vertcheck] D:\Home\Pat\x'; Graphics = @('--scale=2'); Files = @('native-1.log') } @{ 'D:\Home\Pat' = '%USERPROFILE%' }
Assert-True ($summary -match 'Flagged line: \[vertcheck\] %USERPROFILE%\\x') 'bundle summary names the flag, redacted'
Assert-True ($summary -notmatch 'D:\\Home\\Pat') 'bundle summary has no profile path'

# --- Launcher modules stay readable by Windows PowerShell 5.1 ---
# A script without a BOM is read in the ANSI code page there, so any non-ASCII byte in one
# shows up garbled in the window. Use a BOM or build the character from its code point.
foreach ($module in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'Launcher*.ps1' -File) + @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'LauncherPages') -Filter '*.ps1' -File)) {
  $bytes = [IO.File]::ReadAllBytes($module.FullName)
  $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
  Assert-True ($hasBom -or -not @($bytes | Where-Object { $_ -gt 0x7F }).Count) "$($module.Name) is ASCII or has a BOM"
}

# --- Native build status (LauncherNative.ps1), with temporary files only ---
. (Join-Path $PSScriptRoot 'LauncherNative.ps1')
. (Join-Path $PSScriptRoot 'LauncherSaves.ps1')
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('launcher-core-test-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch) | Out-Null
try {
  $exe = Join-Path $scratch 'assault.exe'
  # Exact UTF-16 text, independent of how this file is decoded: READY, U+00B7, NATIVE PROTOTYPE.
  $readyText = 'READY ' + [char]0x00B7 + ' NATIVE PROTOTYPE'
  Assert-Equal 24 $readyText.Length 'ready text is 24 characters'
  Assert-Equal $readyText $script:NativeReadyStatus 'ready status has a real middle dot'
  $image = Join-Path $scratch 'game.iso'
  $old = { [DateTime]::MinValue }
  Assert-Equal 'NOT BUILT' (Get-NativeBuildStatus $exe $null $image $old).Status 'no executable: not built'
  [IO.File]::WriteAllBytes($exe,[byte[]](1,2,3))
  [IO.File]::WriteAllBytes($image,[byte[]](0..63))
  $imageItem = Get-Item -LiteralPath $image
  $exeHash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
  function New-Record([hashtable]$change = @{}) {
    $record = [ordered]@{ schema_version = 2; game_id = 'GF7E01'; image = $image; image_size = $imageItem.Length
      image_modified_utc_ticks = $imageItem.LastWriteTimeUtc.Ticks; image_sha256 = 'abc'; executable_sha256 = $exeHash }
    foreach ($key in $change.Keys) { $record[$key] = $change[$key] }
    return [pscustomobject]$record
  }
  function Status($record, [string]$img = $image, $source = $old) { Get-NativeBuildStatus $exe $record $img $source }
  $r = Status $null
  Assert-Equal 'REBUILD REQUIRED' $r.Status 'no record: rebuild'
  Assert-Equal 'build record is missing or from an older launcher' $r.Reason 'no record: reason'
  Assert-Equal 'build record is missing or from an older launcher' (Status (New-Record @{ schema_version = 1 })).Reason 'schema 1 record: rebuild'
  Assert-Equal 'build record is missing or from an older launcher' (Status (New-Record @{ image_sha256 = '' })).Reason 'record without image hash: rebuild'
  Assert-Equal 'selected game image was not found' (Status (New-Record) (Join-Path $scratch 'missing.iso')).Reason 'missing image: rebuild'
  Assert-Equal 'selected game image was not found' (Status (New-Record) '').Reason 'no image selected: rebuild'
  Assert-Equal 'selected game image differs from the one built' (Status (New-Record @{ image_size = 1 })).Reason 'size differs: rebuild'
  Assert-Equal 'selected game image differs from the one built' (Status (New-Record @{ image_modified_utc_ticks = 5 })).Reason 'time differs: rebuild'
  Assert-Equal 'selected game image differs from the one built' (Status (New-Record @{ image = (Join-Path $scratch 'other.iso') })).Reason 'path differs: rebuild'
  Assert-Equal 'selected game image differs from the one built' (Status (New-Record @{ game_id = 'GF7P01' })).Reason 'other region: rebuild'
  Assert-Equal 'selected game image could not be checked' (Status (New-Record @{ image = "bad`0path" })).Reason 'unreadable record path: rebuild'
  Assert-Equal 'project source changed since the last build' (Status (New-Record) $image { [DateTime]::MaxValue }).Reason 'newer source: rebuild'
  $ready = Status (New-Record)
  Assert-Equal $readyText $ready.Status 'matching build: ready'
  Assert-Equal '' $ready.Reason 'ready has no reason'
  $scanned = $false
  $null = Status (New-Record @{ image_size = 1 }) $image { $script:scanned = $true; [DateTime]::MinValue }
  Assert-Equal $false $scanned 'source scan skipped when a cheaper check fails'
  $upper = Join-Path $scratch 'GAME.ISO'
  Assert-Equal $readyText (Status (New-Record @{ image = $upper })).Status 'image path compared without case'

  Assert-Equal $true (Test-NativeBuildForImage $exe (New-Record) $image) 'launch allowed for matching build'
  Assert-Equal $false (Test-NativeBuildForImage $exe (New-Record @{ executable_sha256 = ('0' * 64) }) $image) 'launch refused for a changed executable'
  Assert-Equal $false (Test-NativeBuildForImage $exe (New-Record @{ executable_sha256 = '' }) $image) 'launch refused without an executable hash'
  Assert-Equal $false (Test-NativeBuildForImage $exe (New-Record @{ image_size = 1 }) $image) 'launch refused for another image'
  Assert-Equal $false (Test-NativeBuildForImage $exe $null $image) 'launch refused without a record'

  $recordDir = Join-Path $scratch 'user-data'
  [IO.Directory]::CreateDirectory($recordDir) | Out-Null
  Assert-Equal $null (Read-NativeBuildRecord $scratch) 'missing build record reads as null'
  [IO.File]::WriteAllText((Join-Path $recordDir 'native-build-info.json'),'{ not json')
  Assert-Equal $null (Read-NativeBuildRecord $scratch) 'unreadable build record reads as null'
  [IO.File]::WriteAllText((Join-Path $recordDir 'native-build-info.json'),'{"schema_version":2,"game_id":"GF7E01"}')
  Assert-Equal 'GF7E01' (Read-NativeBuildRecord $scratch).game_id 'build record read'

  # Session command line and environment (Start-NativeGame).
  $session = Get-LauncherSettingDefaults
  $session.disc = 'C:\Games\Star Fox\SFA.iso'
  $plain = @(Get-NativeSessionArgumentList $session 'C:\hd' 'C:\dump')
  Assert-Equal ('--vsync={0}' -f [int][bool]$session.vsync) ($plain | Where-Object { $_ -like '--vsync=*' }) 'vsync follows the profile'
  Assert-Equal '--volume=100' ($plain | Where-Object { $_ -like '--volume=*' }) 'volume passed'
  Assert-True ($plain -contains '--no-input-log') 'input log off by default'
  Assert-True (-not ($plain | Where-Object { $_ -like '--deadzone=*' -or $_ -eq '--fullscreen' -or $_ -eq '--no-music' -or $_ -like '--controls=*' })) 'optional arguments absent by default'
  Assert-Equal '"C:\Games\Star Fox\SFA.iso"' $plain[-1] 'game image last and quoted'
  Assert-Equal (@(Get-NativeGraphicsArgumentList $session.scale $session.aspect $session.aa $session.filter) -join ' ') (($plain[0..3]) -join ' ') 'graphics arguments first'
  $session.vsync = -not [bool]$session.vsync; $session.volume = 35; $session.deadzone = '7'; $session.fullscreen = $true
  $session.inputLog = $true; $session.muteMusic = $true; $session.controls = 'D:\My Pads\controls.txt'; $session.anisotropy = '16'
  $full = @(Get-NativeSessionArgumentList $session 'C:\hd' 'C:\dump')
  foreach ($expected in @(('--vsync={0}' -f [int][bool]$session.vsync),'--volume=35','--deadzone=7','--fullscreen','--no-music','--controls="D:\My Pads\controls.txt"','--anisotropy=16')) {
    Assert-True ($full -contains $expected) "session argument $expected"
  }
  Assert-True (-not ($full -contains '--no-input-log')) 'input log on when chosen'
  Assert-Equal '"C:\Games\Star Fox\SFA.iso"' $full[-1] 'game image still last'
  $envNoMods = Get-NativeSessionEnvironment 'C:\Proj' 'C:\Proj\run\s.ram.bin'
  Assert-Equal $null $envNoMods.GCN_MODS_DIR 'no mods folder clears GCN_MODS_DIR'
  Assert-True ($envNoMods.Contains('GCN_INPUT') -and $null -eq $envNoMods.GCN_INPUT) 'scripted input always cleared'
  Assert-Equal '800000E4' $envNoMods.GCN_GUARD 'thread-pointer guard on'
  Assert-Equal 'C:\Proj\assets\fonts' $envNoMods.GCN_FONT_DIR 'font folder'
  Assert-Equal 'C:\Proj\run\s.ram.bin' $envNoMods.GCN_RAM_DUMP 'RAM dump path'
  Assert-Equal 'C:\mods' (Get-NativeSessionEnvironment 'C:\Proj' 'x' 'C:\mods').GCN_MODS_DIR 'mods folder passed'

  $mine = [pscustomobject]@{ Path = $exe.ToUpperInvariant() }
  $other = [pscustomobject]@{ Path = (Join-Path $scratch 'elsewhere\assault.exe') }
  $hidden = [pscustomobject]@{ Path = $null }
  Assert-Equal 1 @(Get-NativeGameProcess $exe @($mine,$other)).Count 'only this project''s game counts'
  Assert-Equal 1 @(Get-NativeGameProcess $exe @($other,$hidden)).Count 'a game whose path cannot be read still counts'
  Assert-Equal 0 @(Get-NativeGameProcess $exe @($other)).Count 'another assault.exe does not count'

  # --- Save backups (LauncherSaves.ps1) ---
  $backups = Join-Path $scratch 'backups'
  [IO.Directory]::CreateDirectory($backups) | Out-Null
  Assert-Equal (Join-Path $backups 'a.raw') (Resolve-SaveBackupPath $backups ([pscustomobject]@{ FileName = 'a.raw' })) 'backup path inside the folder'
  foreach ($bad in @('..\a.raw','sub\a.raw','')) {
    $threw = $false; try { $null = Resolve-SaveBackupPath $backups ([pscustomobject]@{ FileName = $bad }) } catch { $threw = $true }
    Assert-True $threw "backup name '$bad' refused"
  }
  $threw = $false; try { $null = Resolve-SaveBackupPath $backups $null } catch { $threw = $true }
  Assert-True $threw 'no selection refused'

  $card = Join-Path $scratch 'card.raw'
  [IO.File]::WriteAllBytes($card,(New-Object byte[] 100))
  $threw = $false; try { $null = New-SaveBackupFile $card $backups 'x' @() 'manual backup' $true } catch { $threw = ($_.Exception.Message -match '100 bytes') }
  Assert-True $threw 'wrong-size card refused when the runtime size is required'
  Assert-Equal 0 @(Get-ChildItem -LiteralPath $backups).Count 'refused backup wrote nothing'
  $copy = New-SaveBackupFile $card $backups 'Before boss' @('manual') 'manual backup' $false
  Assert-True ((Split-Path -Leaf $copy) -match '^memcard-\d{8}-\d{6}-\d{3}-[0-9a-f]{32}\.raw$') 'backup file name'
  $meta = Read-SaveBackupMetadata $copy
  Assert-Equal 'Before boss' $meta.label 'backup label kept'
  Assert-Equal 'manual' (@($meta.tags) -join ',') 'backup tags kept'
  Assert-Equal (Get-FileHash -LiteralPath $card -Algorithm SHA256).Hash $meta.sha256 'backup metadata records the hash'
  Assert-Equal 100 $meta.sizeBytes 'backup metadata records the size'
  $tags = @(1..20 | ForEach-Object { "tag$_" }) + @(('x' * 40))
  [IO.File]::WriteAllText(($copy + '.meta.json'),(@{ schemaVersion = 1; fileName = (Split-Path -Leaf $copy); label = "a`tb`nc" + ('y' * 200); tags = $tags } | ConvertTo-Json))
  $meta = Read-SaveBackupMetadata $copy
  Assert-Equal 100 $meta.label.Length 'label capped at 100'
  Assert-True ($meta.label -notmatch '[\t\n]') 'label has no control characters'
  Assert-Equal 12 @($meta.tags).Count 'at most 12 tags'
  [IO.File]::WriteAllText(($copy + '.meta.json'),(@{ schemaVersion = 1; fileName = 'other.raw'; label = 'Wrong file' } | ConvertTo-Json))
  Assert-True ((Read-SaveBackupMetadata $copy).label -ne 'Wrong file') 'a sidecar for another file is ignored'
} finally {
  Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ("launcher core tests: {0} passed, {1} failed" -f $script:passed,$script:failures)
if ($script:failures) { exit 1 }
Write-Output 'PASS launcher core'
