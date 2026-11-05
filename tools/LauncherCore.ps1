# Launcher logic with no WinForms dependency. Launch-StarFoxAssault.ps1 dot-sources this file
# and tools/Test-LauncherCore.ps1 exercises it, so behaviour here can be checked on any host
# without opening the launcher window.

# --- Settings -------------------------------------------------------------------------------
# One definition of every profile value: its type, default and allowed values. The loader,
# the Settings page and the native argument builder all read from here.
$script:LauncherSettingSchema = [ordered]@{
  disc       = @{ Type = 'string'; Default = '' }
  dolphin    = @{ Type = 'string'; Default = '' }
  scale      = @{ Type = 'double'; Default = 2.0; Allowed = @(0.0,1.0,1.5,2.0,3.0,4.0,6.0) }
  muteMusic  = @{ Type = 'bool';   Default = $false }
  inputLog   = @{ Type = 'bool';   Default = $false }
  controls   = @{ Type = 'string'; Default = '' }
  nativeMods = @{ Type = 'bool';   Default = $false }
  fullscreen = @{ Type = 'bool';   Default = $false }
  vsync      = @{ Type = 'bool';   Default = $false }
  volume     = @{ Type = 'int';    Default = 100; Min = 0; Max = 100 }
  aspect     = @{ Type = 'string'; Default = 'original'; Allowed = @('original','widescreen','stretch') }
  aa         = @{ Type = 'string'; Default = 'off'; Allowed = @('off','fxaa') }
  filter     = @{ Type = 'string'; Default = 'sharp'; Allowed = @('sharp','smooth') }
  # Empty leaves the runtime's own per-axis thresholds alone, which is what a profile saved
  # before this setting existed should keep using.
  deadzone   = @{ Type = 'string'; Default = ''; Allowed = @('','0','5','10','15','20','30') }
  # HD enhancements (runtime render_set_texture_filtering, render_set_soft_particles and
  # gx/texture_pack.h). All off by default: the game as the console drew it.
  anisotropy    = @{ Type = 'string'; Default = '0'; Allowed = @('0','2','4','8','16') }
  trilinear     = @{ Type = 'bool';   Default = $false }
  softParticles = @{ Type = 'bool';   Default = $false }
  hdTextures    = @{ Type = 'bool';   Default = $false }
  dumpTextures  = @{ Type = 'bool';   Default = $false }
}

# The HD preset: 4x internal resolution, 16x anisotropic filtering, trilinear mips, sharp
# output without FXAA. Aspect, audio, input and soft particles are left as they are: soft
# particles also dim glow cards a game lays onto its models on purpose (an engine's glare
# across a hull, say), so they stay a choice of their own.
function Get-HdPresetSettings {
  return [ordered]@{ scale = 4.0; aa = 'off'; filter = 'sharp'; anisotropy = '16'; trilinear = $true }
}

# The runtime flags for the HD enhancements. Texture paths are quoted for the command line;
# a pack is passed only when it is switched on and its folder exists.
function Get-NativeEnhancementArgumentList($settings, [string]$hdTextureDir, [string]$textureDumpDir) {
  $list = New-Object System.Collections.Generic.List[string]
  $aniso = ConvertTo-LauncherSettingValue 'anisotropy' $settings.anisotropy
  if ($aniso -ne '0') { $list.Add("--anisotropy=$aniso") }
  if (ConvertTo-LauncherSettingValue 'trilinear' $settings.trilinear) { $list.Add('--trilinear=1') }
  if (ConvertTo-LauncherSettingValue 'softParticles' $settings.softParticles) { $list.Add('--soft-particles=1') }
  if ((ConvertTo-LauncherSettingValue 'hdTextures' $settings.hdTextures) -and $hdTextureDir -and (Test-Path -LiteralPath $hdTextureDir -PathType Container)) {
    $list.Add('--texture-pack=' + (ConvertTo-NativeArgument $hdTextureDir))
  }
  if ((ConvertTo-LauncherSettingValue 'dumpTextures' $settings.dumpTextures) -and $textureDumpDir) {
    $list.Add('--texture-dump=' + (ConvertTo-NativeArgument $textureDumpDir))
  }
  return ,$list.ToArray()
}

# A file an HD texture pack may hold: a texture's 16-hex-digit content hash and .png, as the
# runtime's texture dump names them. Anything else in a pack ZIP is ignored.
function Test-HdTextureName([string]$name) {
  return [bool]($name -match '^[0-9A-Fa-f]{16}\.[Pp][Nn][Gg]$')
}

function Get-LauncherSettingDefaults {
  $defaults = [ordered]@{}
  foreach ($key in $script:LauncherSettingSchema.Keys) { $defaults[$key] = $script:LauncherSettingSchema[$key].Default }
  return $defaults
}

function Get-LauncherSettingAllowed([string]$key) {
  if (-not $script:LauncherSettingSchema.Contains($key)) { throw "Unknown launcher setting: $key" }
  return @($script:LauncherSettingSchema[$key].Allowed)
}

# Returns the value converted to the setting's type, or the default when it cannot be. A
# hand-edited or half-written profile must never stop the launcher from opening.
function ConvertTo-LauncherSettingValue([string]$key, $value) {
  if (-not $script:LauncherSettingSchema.Contains($key)) { throw "Unknown launcher setting: $key" }
  $spec = $script:LauncherSettingSchema[$key]
  if ($null -eq $value) { return $spec.Default }
  $invariant = [Globalization.CultureInfo]::InvariantCulture
  switch ($spec.Type) {
    'bool' {
      if ($value -is [bool]) { return $value }
      $text = ([string]$value).Trim()
      if ($text -eq 'true' -or $text -eq '1') { return $true }
      if ($text -eq 'false' -or $text -eq '0') { return $false }
      return $spec.Default
    }
    'int' {
      $number = 0.0
      if (-not [double]::TryParse([string]::Format($invariant,'{0}',$value),[Globalization.NumberStyles]::Float,$invariant,[ref]$number)) { return $spec.Default }
      if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) { return $spec.Default }
      return [int][Math]::Max($spec.Min,[Math]::Min($spec.Max,[Math]::Round($number)))
    }
    'double' {
      $number = 0.0
      if (-not [double]::TryParse([string]::Format($invariant,'{0}',$value),[Globalization.NumberStyles]::Float,$invariant,[ref]$number)) { return $spec.Default }
      if ($spec.Allowed -and ($spec.Allowed -notcontains $number)) { return $spec.Default }
      return $number
    }
    default {
      $text = [string]$value
      if (-not $spec.Allowed) { return $text }
      # Matched without regard to case, then returned in the canonical spelling.
      foreach ($allowed in $spec.Allowed) { if ([string]::Equals($allowed,$text.Trim(),[StringComparison]::OrdinalIgnoreCase)) { return $allowed } }
      return $spec.Default
    }
  }
}

# $saved is the object ConvertFrom-Json produced, or $null. Unknown keys are dropped.
function Read-LauncherSettings($saved) {
  $settings = Get-LauncherSettingDefaults
  if ($null -eq $saved) { return $settings }
  foreach ($key in $script:LauncherSettingSchema.Keys) {
    $property = $saved.PSObject.Properties[$key]
    if ($property) { $settings[$key] = ConvertTo-LauncherSettingValue $key $property.Value }
  }
  return $settings
}

function Get-NativeGraphicsArgumentList($scale, $aspect, $aa, $filter) {
  $scaleText = ([double](ConvertTo-LauncherSettingValue 'scale' $scale)).ToString('0.##',[Globalization.CultureInfo]::InvariantCulture)
  return @(
    "--scale=$scaleText",
    ('--aspect={0}' -f (ConvertTo-LauncherSettingValue 'aspect' $aspect)),
    ('--aa={0}' -f (ConvertTo-LauncherSettingValue 'aa' $aa)),
    ('--filter={0}' -f (ConvertTo-LauncherSettingValue 'filter' $filter))
  )
}

# Quotes one argument for a Windows command line (CommandLineToArgvW rules).
function ConvertTo-NativeArgument([string]$value) {
  $escaped = $value -replace '(\\*)"','$1$1\"'
  $escaped = $escaped -replace '(\\+)$','$1$1'
  return '"' + $escaped + '"'
}

# --- Build progress -------------------------------------------------------------------------
# Phase names come from tools/Build-NativeGame.ps1 and tools/Ensure-PortableToolchain.ps1.
function Get-BuildPhaseStep([string]$phase) {
  switch -Regex ($phase) {
    '^Checking image$' { return 1 }
    '^Preparing (build )?tools$' { return 2 }
    '^Recompiling game$|^Using build cache$' { return 3 }
    '^Compiling native executable$' { return 4 }
    '^Installing native build$|^Ready to play$' { return 5 }
  }
  return 0
}

# Maps a phase's own 0-100 progress onto the whole build so the bar only moves forward.
function Get-BuildOverallPercent([string]$phase, $rawPercent) {
  $raw = [Math]::Max(0.0,[Math]::Min(100.0,[double]$rawPercent))
  switch ($phase) {
    'Recompiling game' { return 35 + [int]($raw * 0.30) }
    'Compiling native executable' { return 68 + [int]($raw * 0.25) }
  }
  return [int]$raw
}

function Format-Elapsed([TimeSpan]$span) {
  if ($span -lt [TimeSpan]::Zero) { $span = [TimeSpan]::Zero }
  if ($span.TotalHours -ge 1) { return '{0}:{1:00}:{2:00}' -f [int][Math]::Floor($span.TotalHours),$span.Minutes,$span.Seconds }
  return '{0}:{1:00}' -f $span.Minutes,$span.Seconds
}

function Format-Megabytes([long]$bytes) {
  return ([double]$bytes / 1MB).ToString('0.0',[Globalization.CultureInfo]::InvariantCulture) + ' MB'
}

# --- Pre-flight -----------------------------------------------------------------------------
$script:BuildMinimumFreeBytes = 3GB
$script:BuildPathWarningLength = 100

# Pure rules over facts gathered by Get-BuildPreflightFacts, so each rule can be tested.
# Returns objects with Severity 'block' (the build would fail) or 'warn' (it may fail).
function Get-BuildPreflightIssues([hashtable]$facts) {
  $issues = New-Object System.Collections.Generic.List[object]
  if ($null -ne $facts.FreeBytes -and [long]$facts.FreeBytes -lt $script:BuildMinimumFreeBytes) {
    $issues.Add([pscustomobject]@{ Severity = 'block'; Message = ('Only {0} free on drive {1}. The build needs at least 3 GB for tools and generated files.' -f (Format-Megabytes $facts.FreeBytes),$facts.Drive) })
  }
  if ($facts.ContainsKey('Writable') -and -not $facts.Writable) {
    $issues.Add([pscustomobject]@{ Severity = 'block'; Message = ('The launcher folder is not writable ({0}). Move it out of Program Files or a read-only location.' -f $facts.WriteError) })
  }
  if (@($facts.ToolsMissing).Count -gt 0 -and $facts.ContainsKey('Reachable') -and $facts.Reachable -eq $false) {
    $issues.Add([pscustomobject]@{ Severity = 'block'; Message = ('The first build downloads its build tools ({0}, about 280 MB) from github.com and python.org, which could not be reached. Check the internet connection and try again.' -f (@($facts.ToolsMissing) -join ', ')) })
  }
  if ($facts.ProjectPath -and $facts.ProjectPath.Length -gt $script:BuildPathWarningLength -and -not $facts.LongPathsEnabled) {
    $issues.Add([pscustomobject]@{ Severity = 'warn'; Message = ('The launcher folder path is {0} characters long and Windows long paths are off. Generated files may exceed the 260-character limit; if the build fails, move the launcher to a short folder such as C:\Games\SFA.' -f $facts.ProjectPath.Length) })
  }
  return ,$issues.ToArray()
}

# Tool ids from the pinned manifest whose verified install stamp is absent.
function Get-MissingPortableTools([string]$projectDir) {
  $manifestPath = Join-Path $projectDir 'tools\portable-toolchain.json'
  $toolRoot = Join-Path $projectDir 'user-data\build-tools'
  $missing = @()
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  foreach ($tool in $manifest.tools) {
    $stamp = Join-Path (Join-Path $toolRoot ('{0}-{1}' -f $tool.id,$tool.version)) '.ready.json'
    if (-not (Test-Path -LiteralPath $stamp -PathType Leaf)) { $missing += [string]$tool.id }
  }
  return ,$missing
}

function Test-BuildHostReachable([string]$url = 'https://github.com', [int]$timeoutMs = 5000) {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $request = [Net.HttpWebRequest]::Create($url)
    $request.Method = 'HEAD'; $request.Timeout = $timeoutMs; $request.ReadWriteTimeout = $timeoutMs
    $request.AllowAutoRedirect = $true; $request.UserAgent = 'PeregrineForge-Preflight'
    $response = $request.GetResponse(); $response.Dispose()
    return $true
  } catch [Net.WebException] {
    # Any HTTP answer, even an error status, proves the host is reachable.
    return ($null -ne $_.Exception.Response)
  } catch { return $false }
}

function Get-BuildPreflightFacts([string]$projectDir) {
  $facts = @{ ProjectPath = $projectDir }
  try {
    $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($projectDir))
    $facts.Drive = $drive.Name.TrimEnd('\'); $facts.FreeBytes = [long]$drive.AvailableFreeSpace
  } catch { $facts.FreeBytes = $null }
  try {
    $probeDir = Join-Path $projectDir 'user-data'
    [void][IO.Directory]::CreateDirectory($probeDir)
    $probe = Join-Path $probeDir ('.write-probe-' + [Guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($probe,'ok'); [IO.File]::Delete($probe)
    $facts.Writable = $true
  } catch { $facts.Writable = $false; $facts.WriteError = $_.Exception.Message }
  try { $facts.ToolsMissing = Get-MissingPortableTools $projectDir } catch { $facts.ToolsMissing = @() }
  # Only the first build downloads anything, so only then is the network worth checking.
  if (@($facts.ToolsMissing).Count -gt 0) { $facts.Reachable = Test-BuildHostReachable }
  try {
    $facts.LongPathsEnabled = ((Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -ErrorAction Stop).LongPathsEnabled -eq 1)
  } catch { $facts.LongPathsEnabled = $false }
  return $facts
}

# --- Build failures -------------------------------------------------------------------------
$script:BuildErrorPattern = '(?i)(\berror\b\s*[:(\[]|^FAILED:|CMake Error|^Traceback|\bfatal\b|Exception:|failed \(exit)'

# Picks the lines worth showing from the worker's logs: the first few that look like errors,
# in log order, without duplicates. The compiler's own output is echoed into stdout.log.
function Get-BuildErrorLines([string[]]$stdoutLines, [string[]]$stderrLines, [int]$max = 5) {
  $seen = New-Object 'System.Collections.Generic.HashSet[string]'
  $picked = New-Object System.Collections.Generic.List[string]
  foreach ($line in @($stdoutLines) + @($stderrLines)) {
    if ($picked.Count -ge $max) { break }
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $text = $line.Trim()
    if ($text -match '(?i)\b0 errors?\b|warning:') { continue }
    if ($text -match $script:BuildErrorPattern -and $seen.Add($text)) {
      if ($text.Length -gt 300) { $text = $text.Substring(0,297) + '...' }
      $picked.Add($text)
    }
  }
  return ,$picked.ToArray()
}

# Replaces private paths so a report can be pasted into a public issue.
function Protect-ReportText([string]$text, [hashtable]$replacements) {
  if (-not $text) { return $text }
  # Longest first, so a game image under the profile folder is replaced as a whole.
  foreach ($key in @($replacements.Keys | Sort-Object Length -Descending)) {
    if ([string]::IsNullOrEmpty($key)) { continue }
    $text = [regex]::Replace($text,[regex]::Escape($key),$replacements[$key].Replace('$','$$'),'IgnoreCase')
  }
  return $text
}

function New-BuildFailureReport([hashtable]$failure, [hashtable]$replacements) {
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('Peregrine Forge build failure report')
  $lines.Add(('Launcher version: {0}' -f $failure.Version))
  $lines.Add(('Windows: {0}' -f $failure.OsVersion))
  $lines.Add(('Failed phase: {0}' -f $failure.Phase))
  $lines.Add(('Message: {0}' -f $failure.Message))
  $lines.Add(('Worker exit code: {0}' -f $failure.ExitCode))
  $lines.Add(('Elapsed: {0}' -f $failure.Elapsed))
  $lines.Add('')
  $lines.Add('Top errors:')
  if (@($failure.Errors).Count) { foreach ($e in $failure.Errors) { $lines.Add('  ' + $e) } } else { $lines.Add('  (none recognised in the logs)') }
  $lines.Add('')
  $lines.Add('Last log lines:')
  foreach ($l in @($failure.Tail)) { $lines.Add('  ' + $l) }
  return Protect-ReportText ($lines -join "`r`n") $replacements
}
