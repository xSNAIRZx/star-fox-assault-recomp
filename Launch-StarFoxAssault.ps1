# Star Fox Assault Recomp launcher. The UI is original; game assets remain user supplied.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
[Windows.Forms.Application]::EnableVisualStyles()

$script:projectDir = $PSScriptRoot
$script:launcherBrand = 'Peregrine Forge'
$script:projectTitle = 'Star Fox Assault Recomp'
$script:windowTitle = '{0} | {1}' -f $script:launcherBrand,$script:projectTitle
$script:legacyAppDir = Join-Path $env:LOCALAPPDATA 'StarFoxAssaultRecomp'
$script:legacySettingsPath = Join-Path $script:legacyAppDir 'settings.json'
$script:portableProfileDir = Join-Path $script:projectDir 'user-data\launcher-profile'
$portableMarker = Join-Path $script:projectDir 'portable.txt'
$portableEnvironment = [Environment]::GetEnvironmentVariable('STARFOX_ASSAULT_PORTABLE','Process') -eq '1'
$script:portableMode = $portableEnvironment -or (Test-Path -LiteralPath $portableMarker -PathType Leaf) -or (-not (Test-Path -LiteralPath $script:legacySettingsPath -PathType Leaf))
$script:appDir = if ($script:portableMode) { $script:portableProfileDir } else { $script:legacyAppDir }
$script:settingsPath = Join-Path $script:appDir 'settings.json'
$script:nativePath = Join-Path $script:projectDir 'build-desktop\Release\assault.exe'
$script:nativeRunDir = Join-Path $script:projectDir 'user-data\native-run'
$script:memcardPath = Join-Path $script:nativeRunDir 'saves\memcard_a.raw'
$script:backupDir = Join-Path $script:projectDir 'user-data\save-backups'
$script:dolphinUserDir = Join-Path $script:appDir 'dolphin-user'
$script:modsDir = Join-Path $script:dolphinUserDir 'Load\Textures\GF7E01'
$script:modsWorkDir = Join-Path $script:projectDir 'user-data\texture-pack-staging'
$script:controllerLogDir = Join-Path $script:projectDir 'user-data\controller-setup'
$script:nativeModsDir = Join-Path $script:projectDir 'user-data\native-mods\active'
$script:buildState = @{ Process=$null; Dialog=$null; Timer=$null }
[IO.Directory]::CreateDirectory($script:appDir) | Out-Null
if ($script:portableMode -and -not (Test-Path -LiteralPath $script:settingsPath -PathType Leaf) -and (Test-Path -LiteralPath $script:legacySettingsPath -PathType Leaf)) {
  try { Copy-Item -LiteralPath $script:legacySettingsPath -Destination $script:settingsPath -ErrorAction Stop } catch {}
}

$script:settings = [ordered]@{
  disc = ''
  dolphin = ''
  scale = 2
  muteMusic = $false
  inputLog = $false
  controls = ''
  nativeMods = $false
  fullscreen = $false
  vsync = $false
  volume = 100
  aspect = 'original'
  aa = 'off'
  filter = 'sharp'
  deadzone = ''
}
if (Test-Path -LiteralPath $script:settingsPath) {
  try {
    $saved = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
    foreach ($key in @('disc','dolphin','scale','muteMusic','inputLog','controls','nativeMods','fullscreen','vsync','volume','aspect','aa','filter','deadzone')) {
      if ($null -ne $saved.$key) { $script:settings[$key] = $saved.$key }
    }
  } catch {}
}
$script:discValue = [string]$script:settings.disc
$script:dolphinValue = [string]$script:settings.dolphin
$script:controlsValue = [string]$script:settings.controls
$script:scaleValue = 2.0
try { $script:scaleValue = [Convert]::ToDouble($script:settings.scale,[Globalization.CultureInfo]::InvariantCulture) } catch {}
if ($script:scaleValue -notin @(0.0,1.0,1.5,2.0,3.0,4.0,6.0)) { $script:scaleValue = 2.0 }
$script:aspectValue = [string]$script:settings.aspect
if ($script:aspectValue -notin @('original','widescreen','stretch')) { $script:aspectValue = 'original' }
$script:aaValue = [string]$script:settings.aa
if ($script:aaValue -notin @('off','fxaa')) { $script:aaValue = 'off' }
$script:filterValue = [string]$script:settings.filter
if ($script:filterValue -notin @('sharp','smooth')) { $script:filterValue = 'sharp' }
# Empty leaves the runtime's own per-axis thresholds alone, which is what a profile saved
# before this setting existed should keep using.
$script:deadzoneValue = [string]$script:settings.deadzone
if ($script:deadzoneValue -notin @('','0','5','10','15','20','30')) { $script:deadzoneValue = '' }
$script:muteValue = [bool]$script:settings.muteMusic
$script:logValue = [bool]$script:settings.inputLog
$script:nativeModsValue = [bool]$script:settings.nativeMods
$script:fullscreenValue = [bool]$script:settings.fullscreen
$script:vsyncValue = [bool]$script:settings.vsync
# A hand-edited or half-written profile must not stop the launcher from opening, so a
# volume that is not a number falls back to the default like the other values above.
$script:volumeValue = 100
try { $script:volumeValue = [Math]::Max(0,[Math]::Min(100,[int]$script:settings.volume)) } catch { $script:volumeValue = 100 }

$script:colors = @{
  base = [Drawing.Color]::FromArgb(4,11,15)
  panel = [Drawing.Color]::FromArgb(8,24,31)
  panel2 = [Drawing.Color]::FromArgb(12,38,47)
  line = [Drawing.Color]::FromArgb(112,137,145)
  text = [Drawing.Color]::FromArgb(235,245,246)
  muted = [Drawing.Color]::FromArgb(143,170,177)
  blue = [Drawing.Color]::FromArgb(61,202,222)
  cyan = [Drawing.Color]::FromArgb(61,202,222)
  green = [Drawing.Color]::FromArgb(76,213,157)
  red = [Drawing.Color]::FromArgb(238,91,86)
  steelLight = [Drawing.Color]::FromArgb(193,207,210)
  steelShade = [Drawing.Color]::FromArgb(42,67,74)
  selection = [Drawing.Color]::FromArgb(15,47,55)
}
$script:flightDisplayFonts = [Drawing.Text.PrivateFontCollection]::new()
$script:flightDisplayFontFamily = $null
$script:flightDisplayFontPath = Join-Path $script:projectDir 'assets\fonts\Orbitron-Variable.ttf'
if (Test-Path -LiteralPath $script:flightDisplayFontPath -PathType Leaf) {
  try {
    $script:flightDisplayFonts.AddFontFile($script:flightDisplayFontPath)
    if ($script:flightDisplayFonts.Families.Count -gt 0) { $script:flightDisplayFontFamily = $script:flightDisplayFonts.Families[0] }
  } catch { $script:flightDisplayFontFamily = $null }
}

function Save-Settings {
  $script:settings.disc = $script:discValue
  $script:settings.dolphin = $script:dolphinValue
  $script:settings.scale = [double]$script:scaleValue
  $script:settings.aspect = [string]$script:aspectValue
  $script:settings.aa = [string]$script:aaValue
  $script:settings.filter = [string]$script:filterValue
  $script:settings.deadzone = [string]$script:deadzoneValue
  $script:settings.muteMusic = [bool]$script:muteValue
  $script:settings.inputLog = [bool]$script:logValue
  $script:settings.controls = $script:controlsValue
  $script:settings.nativeMods = [bool]$script:nativeModsValue
  $script:settings.fullscreen = [bool]$script:fullscreenValue
  $script:settings.vsync = [bool]$script:vsyncValue
  $script:settings.volume = [int]$script:volumeValue
  # Write beside the profile and swap it in, so an interrupted save leaves the previous
  # settings readable instead of truncating them mid-document.
  $tempPath = $script:settingsPath + '.tmp'
  try {
    [IO.File]::WriteAllText($tempPath,($script:settings | ConvertTo-Json),(New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $script:settingsPath -PathType Leaf) {
      try { [IO.File]::Replace($tempPath,$script:settingsPath,[NullString]::Value) }
      catch {
        # File.Replace needs a volume that supports it; removable FAT/exFAT folders do not.
        [IO.File]::Copy($tempPath,$script:settingsPath,$true)
        [IO.File]::Delete($tempPath)
      }
    } else { [IO.File]::Move($tempPath,$script:settingsPath) }
  } finally {
    if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
  }
}
function Set-Status([string]$text, [bool]$good = $false) {
  if ($script:statusLabel) {
    $script:statusLabel.Text = $text
    $script:statusLabel.ForeColor = if ($good) { $script:colors.green } else { $script:colors.muted }
    if ($script:statusTip) { $script:statusTip.SetToolTip($script:statusLabel,[string]$text) }
  }
}
function Test-FilePath([string]$path) {
  if ([string]::IsNullOrWhiteSpace($path)) { return $false }
  return (Test-Path -LiteralPath $path -PathType Leaf)
}
function New-Label([string]$text, [int]$size = 10, [bool]$bold = $false, $color = $null) {
  $l = New-Object Windows.Forms.Label
  $l.Text = $text
  $l.AutoSize = $true
  $fontSize = [Math]::Max(8,$size)
  $fontFamily = if ($bold -or $fontSize -ge 20) { 'Bahnschrift SemiBold' } else { 'Segoe UI' }
  $l.Font = New-Object Drawing.Font($fontFamily, $fontSize, [Drawing.FontStyle]::Regular)
  $l.ForeColor = if ($null -eq $color -or $color.IsEmpty) { $script:colors.text } else { $color }
  $l.BackColor = [Drawing.Color]::Transparent
  return $l
}
function New-Button([string]$text, [int]$width = 150, [bool]$primary = $false) {
  $b = New-Object Windows.Forms.Button
  $b.Text = $text
  $b.TextAlign = 'MiddleCenter'
  $b.Size = New-Object Drawing.Size($width, 40)
  $b.FlatStyle = 'Flat'
  $b.UseVisualStyleBackColor = $false
  $b.FlatAppearance.BorderSize = 1
  $b.FlatAppearance.BorderColor = if ($primary) { $script:colors.cyan } else { $script:colors.line }
  $b.BackColor = if ($primary) { [Drawing.Color]::FromArgb(10,104,119) } else { $script:colors.panel2 }
  $b.FlatAppearance.MouseOverBackColor = if ($primary) { [Drawing.Color]::FromArgb(12,126,142) } else { [Drawing.Color]::FromArgb(20,56,65) }
  $b.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(10,82,94)
  $b.ForeColor = $script:colors.text
  $b.Font = New-Object Drawing.Font('Bahnschrift SemiBold', 10)
  $b.Cursor = [Windows.Forms.Cursors]::Hand
  return $b
}
function New-Card([int]$x, [int]$y, [int]$w, [int]$h) {
  $p = New-Object Windows.Forms.Panel
  $p.Location = New-Object Drawing.Point($x,$y)
  $p.Size = New-Object Drawing.Size($w,$h)
  $p.BackColor = $script:colors.panel
  $p.BorderStyle = 'None'
  $cardBorder = $script:colors.line
  $cardHighlight = $script:colors.steelLight
  $cardShade = $script:colors.steelShade
  $p.Add_Paint({
    param($sender,$e)
    $w = $sender.ClientSize.Width; $h = $sender.ClientSize.Height
    if ($w -lt 20 -or $h -lt 20) { return }
    $points = [Drawing.Point[]]@(
      [Drawing.Point]::new(10,1),[Drawing.Point]::new($w - 11,1),[Drawing.Point]::new($w - 1,11),
      [Drawing.Point]::new($w - 1,$h - 12),[Drawing.Point]::new($w - 11,$h - 2),[Drawing.Point]::new(10,$h - 2),
      [Drawing.Point]::new(1,$h - 12),[Drawing.Point]::new(1,11),[Drawing.Point]::new(10,1)
    )
    $outer = [Drawing.Pen]::new($cardBorder,2)
    $bright = [Drawing.Pen]::new($cardHighlight,1)
    $shade = [Drawing.Pen]::new($cardShade,2)
    try {
      $e.Graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
      $e.Graphics.DrawPolygon($outer,$points)
      $e.Graphics.DrawLine($bright,12,3,[Math]::Max(13,$w - 13),3)
      $e.Graphics.DrawLine($bright,3,12,3,[Math]::Max(13,$h - 14))
      $e.Graphics.DrawLine($shade,[Math]::Max(3,$w - 4),14,[Math]::Max(3,$w - 4),[Math]::Max(14,$h - 14))
      $e.Graphics.DrawLine($shade,13,[Math]::Max(3,$h - 4),[Math]::Max(13,$w - 13),[Math]::Max(3,$h - 4))
    } finally { $outer.Dispose(); $bright.Dispose(); $shade.Dispose() }
  }.GetNewClosure())
  return $p
}
function Set-DarkComboBox($combo) {
  $combo.DrawMode = [Windows.Forms.DrawMode]::OwnerDrawFixed
  $combo.FlatStyle = [Windows.Forms.FlatStyle]::Flat
  $combo.ItemHeight = 22
  $combo.BackColor = $script:colors.panel2
  $combo.ForeColor = $script:colors.text
  $panelColor = $script:colors.panel2
  $selectedColor = $script:colors.selection
  $normalText = $script:colors.muted
  $selectedText = $script:colors.text
  $combo.Add_DrawItem({
    param($sender,$e)
    $selected = (($e.State -band [Windows.Forms.DrawItemState]::Selected) -ne 0)
    $back = if ($selected) { $selectedColor } else { $panelColor }
    $fore = if ($selected) { $selectedText } else { $normalText }
    $bgBrush = [Drawing.SolidBrush]::new($back)
    try { $e.Graphics.FillRectangle($bgBrush,$e.Bounds) } finally { $bgBrush.Dispose() }
    if ($e.Index -ge 0 -and $e.Index -lt $sender.Items.Count) {
      $textRect = [Drawing.Rectangle]::new(($e.Bounds.X + 8),$e.Bounds.Y,[Math]::Max(0,$e.Bounds.Width - 14),$e.Bounds.Height)
      $flags = [Windows.Forms.TextFormatFlags]::VerticalCenter -bor [Windows.Forms.TextFormatFlags]::Left -bor [Windows.Forms.TextFormatFlags]::NoPrefix
      [Windows.Forms.TextRenderer]::DrawText($e.Graphics,[string]$sender.Items[$e.Index],$sender.Font,$textRect,$fore,$flags)
    }
    if ($selected) { $e.DrawFocusRectangle() }
  }.GetNewClosure())
}
function Add-SectionHeader($parent, [string]$title, [string]$subtitle = '') {
  $a = New-Label $title.ToUpperInvariant() 24 $true
  $a.Location = New-Object Drawing.Point(34,24)
  $parent.Controls.Add($a)
  if ($subtitle) {
    $b = New-Label $subtitle 11 $false $script:colors.muted
    $b.Location = New-Object Drawing.Point(36,65)
    $parent.Controls.Add($b)
  }
}
function Get-NativeStatus {
  if (-not (Test-Path -LiteralPath $script:nativePath -PathType Leaf)) { return 'NOT BUILT' }
  $buildInfoPath = Join-Path $script:projectDir 'user-data\native-build-info.json'
  $buildInfo = $null
  try { if (Test-Path -LiteralPath $buildInfoPath -PathType Leaf) { $buildInfo = Get-Content -LiteralPath $buildInfoPath -Raw | ConvertFrom-Json } } catch { }
  if (-not $buildInfo -or [int]$buildInfo.schema_version -lt 2 -or [string]::IsNullOrWhiteSpace([string]$buildInfo.image_sha256)) { return 'UPDATE AVAILABLE' }
  if (-not (Test-FilePath ([string]$script:discValue))) { return 'UPDATE AVAILABLE' }
  try {
    $imagePath = [IO.Path]::GetFullPath([string]$script:discValue)
    $builtImagePath = [IO.Path]::GetFullPath([string]$buildInfo.image)
    $imageFile = Get-Item -LiteralPath $imagePath -ErrorAction Stop
    if (-not [string]::Equals($imagePath,$builtImagePath,[StringComparison]::OrdinalIgnoreCase) -or
        [long]$buildInfo.image_size -ne [long]$imageFile.Length -or
        [long]$buildInfo.image_modified_utc_ticks -ne [long]$imageFile.LastWriteTimeUtc.Ticks -or
        [string]$buildInfo.game_id -cne 'GF7E01') { return 'UPDATE AVAILABLE' }
  } catch { return 'UPDATE AVAILABLE' }
  $exeTime = (Get-Item -LiteralPath $script:nativePath).LastWriteTimeUtc
  $sources = @('CMakeLists.txt','runtime','recomp','decomp\config\GF7E01') | ForEach-Object { Join-Path $script:projectDir $_ }
  $latest = Get-ChildItem -LiteralPath $sources -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
      $_.FullName -notmatch '\\(build[^\\]*|docs|\.git|__pycache__)\\' -and
      ($_.Name -eq 'CMakeLists.txt' -or $_.Extension -in @('.c','.cpp','.h','.hpp','.py','.cmake','.txt','.yml','.yaml','.manifest','.rc'))
    } |
    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if ($latest -and $latest.LastWriteTimeUtc -gt $exeTime) { return 'UPDATE AVAILABLE' }
  return 'READY · NATIVE PROTOTYPE'
}
function Test-NativeBuildImage([string]$imagePath) {
  $buildInfoPath = Join-Path $script:projectDir 'user-data\native-build-info.json'
  if (-not (Test-Path -LiteralPath $buildInfoPath -PathType Leaf)) { return $false }
  try {
    $buildInfo = Get-Content -LiteralPath $buildInfoPath -Raw | ConvertFrom-Json
    if ([int]$buildInfo.schema_version -lt 2 -or [string]$buildInfo.game_id -cne 'GF7E01' -or
        [string]::IsNullOrWhiteSpace([string]$buildInfo.image_sha256) -or [string]::IsNullOrWhiteSpace([string]$buildInfo.executable_sha256)) { return $false }
    $image = Get-Item -LiteralPath $imagePath -ErrorAction Stop
    $fullImagePath = [IO.Path]::GetFullPath($imagePath)
    $builtImagePath = [IO.Path]::GetFullPath([string]$buildInfo.image)
    if (-not [string]::Equals($fullImagePath,$builtImagePath,[StringComparison]::OrdinalIgnoreCase) -or
        [long]$image.Length -ne [long]$buildInfo.image_size -or
        [long]$image.LastWriteTimeUtc.Ticks -ne [long]$buildInfo.image_modified_utc_ticks) { return $false }
    # A size/time/path mismatch forces a rebuild; matching these recorded attributes
    # avoids re-hashing a multi-gigabyte image on every launch. The build hash remains
    # part of the record and is verified by the build pipeline when the image is read.
    $exeHash = (Get-FileHash -LiteralPath $script:nativePath -Algorithm SHA256).Hash
    return [string]::Equals($exeHash,[string]$buildInfo.executable_sha256,[StringComparison]::OrdinalIgnoreCase)
  } catch { return $false }
}
function Test-GameImage {
  param([string]$path)
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Select an existing ISO or CISO image first.' }
  $tool = Join-Path $script:projectDir 'tools\native\assault-image-tool.exe'
  if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw 'The bundled game-image inspector is missing. Repair or reinstall the launcher package.' }
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $tool
  $psi.Arguments = '--inspect-image=' + (ConvertTo-NativeArgument $path)
  $psi.WorkingDirectory = $script:projectDir
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $proc = New-Object Diagnostics.Process; $proc.StartInfo = $psi
  try {
    if (-not $proc.Start()) { throw 'Could not start the game-image inspector.' }
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    $raw = $stdoutTask.Result; $stderr = $stderrTask.Result
    if ($proc.ExitCode -ne 0) { throw "The selected file is not a readable supported game image. $($stderr.Trim())" }
    $info = $raw | ConvertFrom-Json
  } finally { $proc.Dispose() }
  if (-not $info.valid -or $info.game_id -ne 'GF7E01') { throw "This is $($info.internal_name) ($($info.game_id)). The native build expects Star Fox Assault USA (GF7E01)." }
  return $info
}
function ConvertTo-NativeArgument([string]$value) {
  $escaped = $value -replace '(\\*)"','$1$1\"'
  $escaped = $escaped -replace '(\\+)$','$1$1'
  return '"' + $escaped + '"'
}
function Get-PlaytimeText {
  $seconds = 0.0
  $historyDir = Join-Path $script:projectDir 'user-data\play-history'
  foreach($file in (Get-ChildItem -LiteralPath $historyDir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
    try {
      $session=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
      if($session.version -eq 1 -and [double]$session.seconds -ge 0){$seconds += [double]$session.seconds}
    } catch {}
  }
  $minutes=[Math]::Floor($seconds / 60)
  if($minutes -lt 1){return 'LESS THAN 1 MIN PLAYED'}
  if($minutes -lt 60){return ('{0} MIN PLAYED' -f $minutes)}
  return ('{0}H {1:00}M PLAYED' -f [Math]::Floor($minutes/60),($minutes%60))
}
function Start-NativeGame {
  try {
    if (Get-Process -Name assault -ErrorAction SilentlyContinue) { throw 'The native game is already running. Close it before starting another session.' }
    if (-not (Test-Path -LiteralPath $script:nativePath -PathType Leaf)) { throw 'Build the native app first with Build / Update.' }
    $info = Test-GameImage $script:discValue
    if (-not (Test-NativeBuildImage $script:discValue)) { throw 'This native build does not match the selected game image, or its build record is missing. Rebuild from the selected image before playing.' }
    Save-Settings
    [IO.Directory]::CreateDirectory($script:nativeRunDir) | Out-Null
    $nativeArgs = Get-NativeGraphicsArguments
    $nativeArgs += "--vsync=$([int]$script:vsyncValue)"
    $nativeArgs += "--volume=$([int]$script:volumeValue)"
    if ($script:deadzoneValue) { $nativeArgs += ('--deadzone={0}' -f $script:deadzoneValue) }
    if($script:fullscreenValue){$nativeArgs += '--fullscreen'}
    if (-not $script:logValue) { $nativeArgs += '--no-input-log' }
    if ($script:muteValue) { $nativeArgs += '--no-music' }
    if ($script:controlsValue) { $nativeArgs += ('--controls="{0}"' -f $script:controlsValue) }
    $nativeArgs += ('"{0}"' -f $script:discValue)
    $logsDir = Join-Path $script:nativeRunDir 'logs'
    [IO.Directory]::CreateDirectory($logsDir) | Out-Null
    $sessionName = 'native-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'),([Guid]::NewGuid().ToString('N').Substring(0,6))
    $stderr = Join-Path $logsDir ($sessionName + '.err')
    $stdout = Join-Path $logsDir ($sessionName + '.log')
    $ramDump = Join-Path $logsDir ($sessionName + '.ram.bin')
    $previousModsDir = [Environment]::GetEnvironmentVariable('GCN_MODS_DIR','Process')
    $previousFontDir = [Environment]::GetEnvironmentVariable('GCN_FONT_DIR','Process')
    $previousTimeScale = [Environment]::GetEnvironmentVariable('GCN_TIMESCALE','Process')
    $previousClockLog = [Environment]::GetEnvironmentVariable('GCN_CLOCKLOG','Process')
    $previousScriptInput = [Environment]::GetEnvironmentVariable('GCN_INPUT','Process')
    $previousRamDump = [Environment]::GetEnvironmentVariable('GCN_RAM_DUMP','Process')
    $previousWatchAddr = [Environment]::GetEnvironmentVariable('GCN_WATCH_ADDR','Process')
    $previousGuard = [Environment]::GetEnvironmentVariable('GCN_GUARD','Process')
    try {
      [Environment]::SetEnvironmentVariable('GCN_TIMESCALE','1','Process')
      [Environment]::SetEnvironmentVariable('GCN_CLOCKLOG','1','Process')
      [Environment]::SetEnvironmentVariable('GCN_INPUT',$null,'Process')
      [Environment]::SetEnvironmentVariable('GCN_RAM_DUMP',$ramDump,'Process')
      # GCN_WATCH_ADDR only reports in a diagnostic build, which the packaged build is not.
      # The guard reports in any build, so a session that hits the current-thread crash
      # carries the frame and the value either side of the change in its own log.
      [Environment]::SetEnvironmentVariable('GCN_WATCH_ADDR','800000E4','Process')
      [Environment]::SetEnvironmentVariable('GCN_GUARD','800000E4','Process')
      [Environment]::SetEnvironmentVariable('GCN_FONT_DIR',(Join-Path $script:projectDir 'assets\fonts'),'Process')
      if($script:nativeModsValue) {
        if(-not(Test-Path -LiteralPath $script:nativeModsDir -PathType Container)){throw 'Install a native asset pack before enabling native mods.'}
        [Environment]::SetEnvironmentVariable('GCN_MODS_DIR',$script:nativeModsDir,'Process')
      } else { [Environment]::SetEnvironmentVariable('GCN_MODS_DIR',$null,'Process') }
      $gameProcess = Start-Process -FilePath $script:nativePath -ArgumentList $nativeArgs -WorkingDirectory $script:nativeRunDir -RedirectStandardError $stderr -RedirectStandardOutput $stdout -PassThru
    } finally {
      [Environment]::SetEnvironmentVariable('GCN_MODS_DIR',$previousModsDir,'Process')
      [Environment]::SetEnvironmentVariable('GCN_FONT_DIR',$previousFontDir,'Process')
      [Environment]::SetEnvironmentVariable('GCN_TIMESCALE',$previousTimeScale,'Process')
      [Environment]::SetEnvironmentVariable('GCN_CLOCKLOG',$previousClockLog,'Process')
      [Environment]::SetEnvironmentVariable('GCN_INPUT',$previousScriptInput,'Process')
      [Environment]::SetEnvironmentVariable('GCN_RAM_DUMP',$previousRamDump,'Process')
      [Environment]::SetEnvironmentVariable('GCN_WATCH_ADDR',$previousWatchAddr,'Process')
      [Environment]::SetEnvironmentVariable('GCN_GUARD',$previousGuard,'Process')
    }
    try {
      $tracker=Join-Path $script:projectDir 'tools\Track-Session.ps1'
      $sessionPath=Join-Path $script:projectDir ('user-data\play-history\'+$sessionName+'.json')
      $trackArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $tracker),'-GameProcessId',$gameProcess.Id,'-StartTimeUtcTicks',$gameProcess.StartTime.ToUniversalTime().Ticks,'-SessionPath',('"{0}"' -f $sessionPath))
      Start-Process -FilePath 'powershell.exe' -ArgumentList $trackArgs -WindowStyle Hidden | Out-Null
    } catch { Set-Status 'Game started, but playtime tracking could not start.'; return }
    Set-Status "Native run started · $($info.game_id) · saves are isolated" $true
  } catch { Set-Status $_.Exception.Message }
}
function Get-NativeGraphicsArguments {
  $scaleText = ([double]$script:scaleValue).ToString('0.##',[Globalization.CultureInfo]::InvariantCulture)
  $aspect = [string]$script:aspectValue
  if ($aspect -notin @('original','widescreen','stretch')) { $aspect = 'original' }
  $aa = [string]$script:aaValue
  if ($aa -notin @('off','fxaa')) { $aa = 'off' }
  $filter = [string]$script:filterValue
  if ($filter -notin @('sharp','smooth')) { $filter = 'sharp' }
  return @("--scale=$scaleText", "--aspect=$aspect", "--aa=$aa", "--filter=$filter")
}
function Start-DolphinGame {
  try {
    $info = Test-GameImage $script:discValue
    if (-not (Test-FilePath $script:dolphinValue)) { throw 'Dolphin.exe was not found. Update its path in Settings.' }
    Save-Settings
    [IO.Directory]::CreateDirectory($script:dolphinUserDir) | Out-Null
    Start-Process -FilePath $script:dolphinValue -ArgumentList @('-u',('"{0}"' -f $script:dolphinUserDir),'-e',('"{0}"' -f $script:discValue)) | Out-Null
    Set-Status "Opened the original CISO directly in Dolphin · $($info.game_id)" $true
  } catch { Set-Status $_.Exception.Message }
}
function Start-NativeBuild {
  try {
    $null = Test-GameImage $script:discValue
    Save-Settings
    if ($script:buildState.Process -and -not $script:buildState.Process.HasExited) { Set-Status 'A native build is already running.'; return }
    $buildScript = Join-Path $script:projectDir 'tools\Build-StarFoxAssault.ps1'
    if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) { throw 'The native build script is missing from this launcher package.' }
    $jobId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'),([Guid]::NewGuid().ToString('N'))
    $jobDir = Join-Path (Join-Path $script:projectDir 'user-data\build-jobs') $jobId
    [IO.Directory]::CreateDirectory($jobDir) | Out-Null
    $statusPath = Join-Path $jobDir 'status.json'; $cancelPath = Join-Path $jobDir 'cancel.request'
    $stdoutPath = Join-Path $jobDir 'stdout.log'; $stderrPath = Join-Path $jobDir 'stderr.log'
    $buildArgs = '-NoProfile -ExecutionPolicy Bypass -File ' + (ConvertTo-NativeArgument $buildScript) +
      ' -GameImage ' + (ConvertTo-NativeArgument $script:discValue) +
      ' -UsePortableToolchain -ProgressFile ' + (ConvertTo-NativeArgument $statusPath) +
      ' -CancelFile ' + (ConvertTo-NativeArgument $cancelPath)
    $oldPortableEnv=[Environment]::GetEnvironmentVariable('STARFOX_ASSAULT_PORTABLE','Process')
    try {
      [Environment]::SetEnvironmentVariable('STARFOX_ASSAULT_PORTABLE','1','Process')
      $script:buildState.Process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
        -ArgumentList $buildArgs -WorkingDirectory $script:projectDir -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
      if ($script:buildState.Process) { $null = $script:buildState.Process.Handle }
    } finally { [Environment]::SetEnvironmentVariable('STARFOX_ASSAULT_PORTABLE',$oldPortableEnv,'Process') }
    if (-not $script:buildState.Process) { throw 'Could not start the native build worker.' }

    $dialog = New-Object Windows.Forms.Form; $dialog.Text = 'Building Star Fox Assault'; $dialog.Size = New-Object Drawing.Size(700,270)
    $dialog.StartPosition = 'CenterParent'; $dialog.FormBorderStyle = 'FixedDialog'; $dialog.MaximizeBox = $false; $dialog.MinimizeBox = $false
    $dialog.BackColor = $script:colors.base; $dialog.ForeColor = $script:colors.text
    $message = New-Label 'Preparing the portable native toolchain…' 13 $true $script:colors.text
    $message.Location = New-Object Drawing.Point(26,22); $message.Size = New-Object Drawing.Size(620,28); $dialog.Controls.Add($message)
    $detail = New-Label 'Your selected game image stays in its original location.' 9 $false $script:colors.muted
    $detail.Location = New-Object Drawing.Point(27,56); $detail.Size = New-Object Drawing.Size(615,22); $dialog.Controls.Add($detail)
    $bar = New-Object Windows.Forms.ProgressBar; $bar.Location = New-Object Drawing.Point(27,94); $bar.Size = New-Object Drawing.Size(640,26)
    $bar.Style = 'Marquee'; $bar.MarqueeAnimationSpeed = 24; $bar.ForeColor = $script:colors.cyan; $dialog.Controls.Add($bar)
    $progressText = New-Label 'STEP 1 OF 5  ·  CHECKING GAME IMAGE' 9 $true $script:colors.cyan
    $progressText.Location = New-Object Drawing.Point(27,130); $progressText.Size = New-Object Drawing.Size(500,22); $dialog.Controls.Add($progressText)
    $safetyText = New-Label 'The original game image and existing saves are kept unchanged.' 9 $false $script:colors.muted
    $safetyText.Location = New-Object Drawing.Point(27,164); $safetyText.Size = New-Object Drawing.Size(490,22); $dialog.Controls.Add($safetyText)
    $cancel = New-Button 'CANCEL BUILD' 135; $cancel.Location = New-Object Drawing.Point(532,163); $dialog.Controls.Add($cancel)
    $cancel.Add_Click({ if($cancel.Tag -eq 'finished'){$dialog.Close();return}; try { [IO.File]::WriteAllText($cancelPath,'cancel',[Text.Encoding]::ASCII); $cancel.Enabled = $false; $message.Text = 'Cancellation requested; cleaning up the build…' } catch { $detail.Text = $_.Exception.Message } }.GetNewClosure())
    $buildState = $script:buildState
    $statusLabel = $script:statusLabel
    $nativePath = $script:nativePath
    $colors = $script:colors
    $navButtons = $script:navButtons
    $dialog.Add_FormClosing({
      if ($buildState.Process -and -not $buildState.Process.HasExited -and $cancel.Tag -ne 'finished') {
        $_.Cancel = $true
        try { [IO.File]::WriteAllText($cancelPath,'cancel',[Text.Encoding]::ASCII); $cancel.Enabled=$false; $message.Text='Cancellation requested; cleaning up the build…' } catch {}
      }
    }.GetNewClosure())
    $timer = New-Object Windows.Forms.Timer; $timer.Interval = 300
    $buildState.Timer = $timer; $buildState.Dialog = $dialog
    $timer.Add_Tick({
      try {
        $state = $null
        if (Test-Path -LiteralPath $statusPath -PathType Leaf) {
          try { $state = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
        }
        if ($state) {
          $message.Text = [string]$state.message
          $detail.Text = [string]$state.phase
          $phaseName = [string]$state.phase
          $step = switch -Regex ($phaseName) {
            '^Checking image$' { 1; break }
            '^Preparing tools$' { 2; break }
            '^Recompiling game$|^Using build cache$' { 3; break }
            '^Compiling native executable$' { 4; break }
            '^Installing native build$|^Ready to play$' { 5; break }
            '^Cancelled$|^Build failed$' { 0; break }
            default { 0 }
          }
          $stepText = if($step -gt 0){'STEP {0} OF 5  ·  {1}' -f $step,$phaseName.ToUpperInvariant()}else{$phaseName.ToUpperInvariant()}
          if ($null -ne $state.percent) {
            $rawPercent = [Math]::Max(0,[Math]::Min(100,[double]$state.percent))
            if ($phaseName -eq 'Recompiling game') { $overallPercent = 35 + [int]($rawPercent * 0.30) }
            elseif ($phaseName -eq 'Compiling native executable') { $overallPercent = 68 + [int]($rawPercent * 0.25) }
            else { $overallPercent = [int]$rawPercent }
            $bar.Style='Continuous'; $bar.Value=[Math]::Max($bar.Value,[Math]::Min(99,$overallPercent))
            $progressText.Text = '{0}  ·  {1}%' -f $stepText,$overallPercent
          } else {
            $bar.Style='Marquee'; $bar.MarqueeAnimationSpeed=24
            $progressText.Text = if($step -gt 0){$stepText + '  ·  WORKING'}else{$stepText}
          }
        }
        if ($buildState.Process.HasExited) {
          $timer.Stop(); $timer.Dispose()
          $buildState.Process.WaitForExit()
          $buildState.Process.Refresh()
          $exitCode = $buildState.Process.ExitCode
          $buildState.Process.Dispose(); $buildState.Process = $null
          $nativeOutputExists = Test-Path -LiteralPath $nativePath -PathType Leaf
          $success = ($exitCode -eq 0 -and $state -and $state.state -eq 'succeeded' -and $nativeOutputExists)
          if ($success) { $message.Text='Native build completed'; $detail.Text='The game image and existing saves were left unchanged.'; $bar.Style='Continuous'; $bar.MarqueeAnimationSpeed=0; $bar.Value=100; $progressText.Text='BUILD COMPLETE  ·  100%'; $progressText.ForeColor=$colors.green; $statusLabel.Text='Native build ready.'; $statusLabel.ForeColor=$colors.green; if($navButtons.ContainsKey('Home')){Build-PageRefresh} }
          else {
            $phase = if($state -and $state.state -in @('failed','cancelled')){[string]$state.state}else{'worker stopped'}
            $message.Text = if($phase -eq 'cancelled'){'Build cancelled'}else{'Build did not complete'}
            $detail.Text = "Details are saved in $jobDir"
            $bar.Style='Continuous'; $bar.MarqueeAnimationSpeed=0; $progressText.Text=if($phase -eq 'cancelled'){'BUILD CANCELLED'}else{'BUILD FAILED'}; $progressText.ForeColor=$colors.red
            $statusLabel.Text=('{0} · state {1}, exit {2}, output {3}' -f $message.Text,$phase,$exitCode,$nativeOutputExists); $statusLabel.ForeColor=$colors.muted
          }
          $cancel.Text='CLOSE'; $cancel.Enabled=$true; $cancel.Tag='finished'
        }
      } catch {
        try { [IO.File]::AppendAllText($stderrPath,('Launcher progress monitor error: '+$_.Exception.Message+[Environment]::NewLine)) } catch {}
        $timer.Stop(); $message.Text='Could not read build progress'; $detail.Text="Build worker and logs remain in $jobDir"; $statusLabel.Text='Build progress monitor error · check build job logs'; $statusLabel.ForeColor=$colors.muted
      }
    }.GetNewClosure())
    $dialog.Add_FormClosed({ if($timer){$timer.Stop();$timer.Dispose()}; if($buildState.Timer -eq $timer){$buildState.Timer=$null}; if($buildState.Dialog -eq $dialog){$buildState.Dialog=$null} }.GetNewClosure())
    $timer.Start(); $dialog.Show($script:form) | Out-Null
    Set-Status 'Building native game…' $true
  } catch { Set-Status $_.Exception.Message }
}
function Build-PageRefresh {
  $page = 'Home'
  foreach($key in $script:navButtons.Keys){if($script:navButtons[$key].BackColor -eq $script:colors.selection){$page=$key;break}}
  Show-Page $page
}
function Build-Native { Start-NativeBuild }
function Select-GameImage([bool]$buildIfNeeded = $true) {
  $dialog = New-Object Windows.Forms.OpenFileDialog
  $dialog.Title = 'Choose your Star Fox Assault game image'
  $dialog.Filter = 'GameCube images (*.iso;*.ciso)|*.iso;*.ciso|ISO images (*.iso)|*.iso|Compressed ISO (*.ciso)|*.ciso'
  $dialog.CheckFileExists = $true; $dialog.RestoreDirectory = $true
  try {
    if ($dialog.ShowDialog($script:form) -ne [Windows.Forms.DialogResult]::OK) { return $false }
    $info = Test-GameImage $dialog.FileName
    $script:discValue = [IO.Path]::GetFullPath($dialog.FileName); $script:settings.disc = $script:discValue
    Save-Settings
    Set-Status ("Image ready · {0} · {1}" -f $info.game_id,$info.format) $true
    if ($buildIfNeeded -and -not (Test-Path -LiteralPath $script:nativePath -PathType Leaf)) { Start-NativeBuild }
    return $true
  } catch { Set-Status $_.Exception.Message; [Windows.Forms.MessageBox]::Show($script:form,$_.Exception.Message,'Game image not accepted','OK','Warning') | Out-Null; return $false }
  finally { $dialog.Dispose() }
}
function Open-PrototypeUpdateDialog {
  $installer = Join-Path $script:projectDir 'tools\Install-PrototypeUpdate.ps1'
  if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { Set-Status 'The local package installer is missing.'; return }
  $dialog = New-Object Windows.Forms.OpenFileDialog
  $dialog.Title = 'Choose a local Star Fox Assault prototype package'
  $dialog.Filter = 'Prototype update package (*.zip)|*.zip'
  $dialog.CheckFileExists = $true
  if ($dialog.ShowDialog($script:form) -ne [Windows.Forms.DialogResult]::OK) { return }
  $oldCursor = $script:form.UseWaitCursor
  try {
    $script:form.UseWaitCursor = $true
    $result = & $installer -ArchivePath $dialog.FileName
    if ($null -eq $result -or $result.Status -ne 'installed') { throw 'The package installer did not report a completed update.' }
    Set-Status ('Installed local package · {0} files · restart launcher to use update' -f $result.FilesChanged) $true
    $message = "Updated $($result.FilesChanged) application files.`r`n`r`nPrevious files are backed up at:`r`n$($result.BackupPath)`r`n`r`nReview log:`r`n$($result.LogPath)`r`n`r`nRestart the launcher to load the update. Your current Settings and user data were left in place. SHA-256 checks detect package changes but do not authenticate its publisher."
    [Windows.Forms.MessageBox]::Show($script:form,$message,'Local package update','OK','Information') | Out-Null
  } catch {
    Set-Status ('Update not applied · {0}' -f $_.Exception.Message)
    [Windows.Forms.MessageBox]::Show($script:form,$_.Exception.Message,'Local package update failed','OK','Warning') | Out-Null
  } finally {
    $script:form.UseWaitCursor = $oldCursor
    $dialog.Dispose()
  }
}
function Start-ControllerDetector {
  try {
    if (-not (Test-Path -LiteralPath $script:nativePath -PathType Leaf)) { throw 'Build the native app first with Build / Update.' }
    [IO.Directory]::CreateDirectory($script:controllerLogDir) | Out-Null
    [IO.Directory]::CreateDirectory($script:nativeRunDir) | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:controllerLogPath = Join-Path $script:controllerLogDir "controls-$stamp.txt"
    $errorLog = Join-Path $script:controllerLogDir "controls-$stamp-errors.txt"
    Start-Process -FilePath $script:nativePath -ArgumentList @('--list-controls') `
      -WorkingDirectory $script:nativeRunDir -RedirectStandardOutput $script:controllerLogPath `
      -RedirectStandardError $errorLog -PassThru | Out-Null
    Set-Status 'Controller detector opened. Press inputs, close its window, then view the results.' $true
  } catch { Set-Status $_.Exception.Message }
}
function Open-ControllerLog {
  if (-not $script:controllerLogPath -and (Test-Path -LiteralPath $script:controllerLogDir)) {
    $latest = Get-ChildItem -LiteralPath $script:controllerLogDir -Filter 'controls-*.txt' -File |
      Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($latest) { $script:controllerLogPath = $latest.FullName }
  }
  if (-not $script:controllerLogPath -or -not (Test-Path -LiteralPath $script:controllerLogPath)) {
    Set-Status 'Run the controller detector first.'
    return
  }
  Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:controllerLogPath) | Out-Null
}
function Get-DetectedControllerSources {
  if (-not $script:controllerLogPath -or -not (Test-Path -LiteralPath $script:controllerLogPath)) {
    $latest = Get-ChildItem -LiteralPath $script:controllerLogDir -Filter 'controls-*.txt' -File -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($latest) { $script:controllerLogPath = $latest.FullName }
  }
  if (-not $script:controllerLogPath -or -not (Test-Path -LiteralPath $script:controllerLogPath)) { return @() }

  $found = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($line in [IO.File]::ReadAllLines($script:controllerLogPath)) {
    $s = $line.Trim()
    $m = [regex]::Match($s,'^(?<source>key\s+(?:"[^"]+"|\S+))\s*$')
    if ($m.Success) { [void]$found.Add($m.Groups['source'].Value); continue }
    $m = [regex]::Match($s,'^(?<device>"[^"]+")\s+(?<binding>button\s+\d+|hat\s+\d+\s+(?:up|down|left|right)|axis\s+\d+(?:[+-])?(?:\s+invert)?)\s*(?:\(.*)?$')
    if ($m.Success) { [void]$found.Add(($m.Groups['device'].Value + ' ' + $m.Groups['binding'].Value)) }
  }
  return @($found | Sort-Object)
}

function Open-ControlsFile {
  $mapPath = [string]$script:settings.controls
  if (-not $mapPath) { $mapPath = Join-Path $script:appDir 'controls.txt' }
  $targets = @('A','B','X','Y','Z','start','dpad_up','dpad_down','dpad_left','dpad_right','L','R',
    'stick_x','stick_y','cstick_x','cstick_y','stick_left','stick_right','stick_up','stick_down',
    'cstick_left','cstick_right','cstick_up','cstick_down')
  $validTargets = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($name in $targets) { [void]$validTargets.Add($name) }
  $extras = New-Object 'System.Collections.Generic.List[string]'

  $dialog = New-Object Windows.Forms.Form
  $dialog.Text = 'Controller mapping'
  $dialog.StartPosition = 'CenterParent'
  $dialog.ClientSize = New-Object Drawing.Size(960,610)
  $dialog.MinimumSize = New-Object Drawing.Size(960,610)
  $dialog.BackColor = $script:colors.base
  $dialog.ForeColor = $script:colors.text
  $dialog.Font = New-Object Drawing.Font('Segoe UI',10)
  $dialog.AutoScaleMode = 'Dpi'

  $title = New-Label 'MAP YOUR CONTROLLER' 18 $true
  $title.Location = New-Object Drawing.Point(24,20); $dialog.Controls.Add($title)
  $sub = New-Label 'Choose an action and a detected input. Map all controls needed on a custom device; keyboard defaults remain available.' 9 $false $script:colors.muted
  $sub.Location = New-Object Drawing.Point(26,54); $dialog.Controls.Add($sub)
  $targetLabel = New-Label 'GAMECUBE ACTION' 8 $true $script:colors.cyan
  $targetLabel.Location = New-Object Drawing.Point(26,100); $dialog.Controls.Add($targetLabel)
  $targetBox = New-Object Windows.Forms.ComboBox
  $targetBox.DropDownStyle = 'DropDownList'; $targetBox.Items.AddRange([object[]]$targets)
  $targetBox.SelectedIndex = 0; $targetBox.Location = New-Object Drawing.Point(25,124); $targetBox.Size = New-Object Drawing.Size(330,30)
  Set-DarkComboBox $targetBox; $dialog.Controls.Add($targetBox)
  $sourceLabel = New-Label 'DETECTED INPUT' 8 $true $script:colors.cyan
  $sourceLabel.Location = New-Object Drawing.Point(26,178); $dialog.Controls.Add($sourceLabel)
  $sourceBox = New-Object Windows.Forms.ComboBox
  $sourceBox.DropDownStyle = 'DropDownList'; $sourceBox.Location = New-Object Drawing.Point(25,202); $sourceBox.Size = New-Object Drawing.Size(330,30)
  Set-DarkComboBox $sourceBox; $dialog.Controls.Add($sourceBox)
  $sourceHelp = New-Label 'Run detection, press each button or move each stick, then reload this list.' 8 $false $script:colors.muted
  $sourceHelp.Location = New-Object Drawing.Point(26,239); $dialog.Controls.Add($sourceHelp)
  $detect = New-Button 'DETECT INPUTS' 152 $true; $detect.Location = New-Object Drawing.Point(25,274)
  $dialog.Controls.Add($detect)
  $reload = New-Button 'RELOAD LIST' 134; $reload.Location = New-Object Drawing.Point(188,274); $dialog.Controls.Add($reload)
  $add = New-Button 'ADD MAPPING' 152 $true; $add.Location = New-Object Drawing.Point(25,330); $dialog.Controls.Add($add)
  $hint = New-Label 'ACTIONS' 8 $true $script:colors.muted
  $hint.Location = New-Object Drawing.Point(26,401); $dialog.Controls.Add($hint)
  $hintText = New-Label "Buttons: A, B, X, Y, Z, L, R, start, D-pad`r`nMovement: stick and C-stick directions or axes" 9 $false $script:colors.text
  $hintText.Location = New-Object Drawing.Point(26,425); $dialog.Controls.Add($hintText)

  $bindingLabel = New-Label 'ACTIVE MAPPINGS' 8 $true $script:colors.cyan
  $bindingLabel.Location = New-Object Drawing.Point(390,100); $dialog.Controls.Add($bindingLabel)
  $bindingList = New-Object Windows.Forms.ListBox
  $bindingList.Location = New-Object Drawing.Point(389,124); $bindingList.Size = New-Object Drawing.Size(545,360)
  $bindingList.BackColor = $script:colors.panel; $bindingList.ForeColor = $script:colors.text; $bindingList.BorderStyle = 'FixedSingle'
  $bindingList.Font = New-Object Drawing.Font('Consolas',9); $dialog.Controls.Add($bindingList)
  $remove = New-Button 'REMOVE SELECTED' 168; $remove.Location = New-Object Drawing.Point(389,496); $dialog.Controls.Add($remove)
  $pathText = New-Label ("Mapping file: {0}" -f $mapPath) 8 $false $script:colors.muted
  $pathText.Location = New-Object Drawing.Point(26,530); $dialog.Controls.Add($pathText)
  $save = New-Button 'SAVE & USE' 150 $true; $save.Location = New-Object Drawing.Point(765,535); $dialog.Controls.Add($save)
  $cancel = New-Button 'CANCEL' 110; $cancel.Location = New-Object Drawing.Point(812,26); $cancel.Anchor = 'Top,Right'
  $cancel.Add_Click({ $dialog.Close() }); $dialog.Controls.Add($cancel)

  $refreshSourceList = {
    $sourceBox.Items.Clear()
    try {
      foreach ($item in (Get-DetectedControllerSources)) { [void]$sourceBox.Items.Add([string]$item) }
      if ($sourceBox.Items.Count -gt 0) { $sourceBox.SelectedIndex = 0; $sourceHelp.Text = 'Choose a detected input. Press additional controls, then reload to add them.' }
      else { $sourceHelp.Text = 'No inputs detected yet. Choose DETECT INPUTS, close that window, then RELOAD LIST.' }
    } catch { $sourceHelp.Text = 'Could not read the last detector log. Close the detector and reload.' }
  }.GetNewClosure()
  $reload.Add_Click($refreshSourceList)
  $detect.Add_Click({ Start-ControllerDetector }.GetNewClosure())

  if (Test-Path -LiteralPath $mapPath -PathType Leaf) {
    foreach ($line in [IO.File]::ReadAllLines($mapPath)) {
      $m = [regex]::Match($line,'^\s*(?<target>[A-Za-z0-9_]+)\s*=')
      if ($m.Success -and $validTargets.Contains($m.Groups['target'].Value)) { [void]$bindingList.Items.Add($line.Trim()) }
      else { [void]$extras.Add($line) }
    }
  }
  & $refreshSourceList

  $add.Add_Click({
    if ($null -eq $targetBox.SelectedItem -or $null -eq $sourceBox.SelectedItem) {
      [Windows.Forms.MessageBox]::Show('Run controller detection and reload the input list first.','No detected input','OK','Information') | Out-Null
      return
    }
    $mapping = '{0} = {1}' -f [string]$targetBox.SelectedItem,[string]$sourceBox.SelectedItem
    if (-not $bindingList.Items.Contains($mapping)) { [void]$bindingList.Items.Add($mapping) }
  }.GetNewClosure())
  $remove.Add_Click({ if ($bindingList.SelectedIndex -ge 0) { $bindingList.Items.RemoveAt($bindingList.SelectedIndex) } }.GetNewClosure())
  $save.Add_Click({
    try {
      $output = New-Object 'System.Collections.Generic.List[string]'
      foreach ($line in $extras) { [void]$output.Add($line) }
      if ($output.Count -eq 0) {
        [void]$output.Add('# Star Fox Assault controller mappings')
        [void]$output.Add('# Each line maps one GameCube control to a detected keyboard, button, hat or axis input.')
      }
      foreach ($line in $bindingList.Items) { [void]$output.Add([string]$line) }
      [IO.Directory]::CreateDirectory((Split-Path -Parent $mapPath)) | Out-Null
      [IO.File]::WriteAllLines($mapPath,$output.ToArray(),(New-Object System.Text.UTF8Encoding($false)))
      $script:settings.controls = $mapPath
      $script:controlsValue = $mapPath
      if ($script:settings_controls) { $script:settings_controls.Text = $mapPath }
      Save-Settings
      Set-Status 'Controller mappings saved and selected for the next native launch.' $true
      $dialog.DialogResult = [Windows.Forms.DialogResult]::OK
      $dialog.Close()
    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Could not save mappings','OK','Error') | Out-Null }
  }.GetNewClosure())

  [void]$dialog.ShowDialog($script:form)
}
function Open-Folder([string]$path) {
  [IO.Directory]::CreateDirectory($path) | Out-Null
  Start-Process explorer.exe -ArgumentList ('"{0}"' -f $path) | Out-Null
}

$script:form = New-Object Windows.Forms.Form
$script:form.Text = $script:windowTitle
$script:form.StartPosition = 'Manual'
$workArea = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$initialWidth = [Math]::Min(1480,[Math]::Max(1100,$workArea.Width - 36))
$initialHeight = [Math]::Min(900,[Math]::Max(680,$workArea.Height - 60))
$script:form.ClientSize = New-Object Drawing.Size($initialWidth,$initialHeight)
$script:form.MinimumSize = New-Object Drawing.Size([Math]::Min(1180,$initialWidth),[Math]::Min(720,$initialHeight))
$script:form.BackColor = $script:colors.base
$script:formIcon = $null
$script:iconPath = Join-Path $script:projectDir 'assets\assault-launcher.ico'
if (Test-Path -LiteralPath $script:iconPath -PathType Leaf) {
  try {
    $iconBytes = [IO.File]::ReadAllBytes($script:iconPath)
    $iconStream = [IO.MemoryStream]::new($iconBytes)
    try {
      $sourceIcon = [Drawing.Icon]::new($iconStream)
      try { $script:formIcon = [Drawing.Icon]$sourceIcon.Clone() }
      finally { $sourceIcon.Dispose() }
    } finally { $iconStream.Dispose() }
    if ($script:formIcon) { $script:form.Icon = $script:formIcon }
  } catch {
    if ($script:formIcon) { $script:formIcon.Dispose(); $script:formIcon = $null }
  }
}
$script:backgroundImage = $null
$script:backgroundRendered = $null
$script:backgroundResizeTimer = $null
$script:backgroundPath = Join-Path $script:projectDir 'assets\peregrine-assault-flightdeck.png'
if (-not (Test-Path -LiteralPath $script:backgroundPath -PathType Leaf)) {
  $script:backgroundPath = Join-Path $script:projectDir 'assets\assault-arwing-hangar.png'
}
if (-not (Test-Path -LiteralPath $script:backgroundPath -PathType Leaf)) {
  $script:backgroundPath = Join-Path $script:projectDir 'assets\assault-launcher-background.png'
}
if (Test-Path -LiteralPath $script:backgroundPath -PathType Leaf) {
  $sourceImage = [Drawing.Image]::FromFile($script:backgroundPath)
  try { $script:backgroundImage = [Drawing.Bitmap]::new($sourceImage) }
  finally { $sourceImage.Dispose() }
}
function Update-LauncherBackground {
  if (-not $script:backgroundImage -or $script:form.IsDisposed) { return }
  $width = $script:form.ClientSize.Width; $height = $script:form.ClientSize.Height
  if ($width -le 0 -or $height -le 0) { return }
  if ($script:backgroundRendered -and $script:backgroundRendered.Width -eq $width -and $script:backgroundRendered.Height -eq $height) { return }
  $scale = [Math]::Max(($width / [double]$script:backgroundImage.Width),($height / [double]$script:backgroundImage.Height))
  $drawWidth = [int][Math]::Ceiling($script:backgroundImage.Width * $scale)
  $drawHeight = [int][Math]::Ceiling($script:backgroundImage.Height * $scale)
  # The art keeps its characters and craft near the right edge, with deliberate empty
  # hangar space on the left. Anchor the cover crop there so narrower windows preserve
  # the full squad instead of trimming the outer Arwing.
  $drawX = $width - $drawWidth
  $drawY = [int][Math]::Floor(($height - $drawHeight) / 2.0)
  $rendered = [Drawing.Bitmap]::new($width,$height,[Drawing.Imaging.PixelFormat]::Format32bppPArgb)
  $graphics = [Drawing.Graphics]::FromImage($rendered)
  try {
    $graphics.Clear($script:colors.base)
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.DrawImage($script:backgroundImage,[Drawing.Rectangle]::new($drawX,$drawY,$drawWidth,$drawHeight))
  } catch {
    $graphics.Dispose(); $rendered.Dispose(); throw
  }
  $graphics.Dispose()
  $previous = $script:backgroundRendered
  $script:backgroundRendered = $rendered
  $script:form.BackgroundImage = $rendered
  $script:form.BackgroundImageLayout = 'Stretch'
  if ($previous) { $previous.Dispose() }
}
if ($script:backgroundImage) { Update-LauncherBackground }
$script:form.ForeColor = $script:colors.text
$script:form.Font = New-Object Drawing.Font('Segoe UI',10)
$script:form.AutoScaleMode = 'Dpi'
$script:form.Location = New-Object Drawing.Point(($workArea.Left + [Math]::Max(0,($workArea.Width - $initialWidth) / 2)),($workArea.Top + [Math]::Max(0,($workArea.Height - $initialHeight) / 2)))

$script:sidebarWidth = 258
$sidebar = New-Object Windows.Forms.Panel
$script:sidebar = $sidebar
$sidebar.Dock = 'None'; $sidebar.Location = New-Object Drawing.Point(0,0); $sidebar.Size = New-Object Drawing.Size($script:sidebarWidth,$script:form.ClientSize.Height)
$sidebar.Anchor = 'Top,Bottom,Left'; $sidebar.BackColor = [Drawing.Color]::FromArgb(246,4,11,15)
$sidebar.Add_Paint({
  param($sender,$e)
  $w=$sender.ClientSize.Width; $h=$sender.ClientSize.Height
  $edge=[Drawing.Pen]::new([Drawing.Color]::FromArgb(80,61,202,222),1)
  $glow=[Drawing.Pen]::new([Drawing.Color]::FromArgb(150,61,202,222),2)
  try { $e.Graphics.DrawLine($edge,$w-1,0,$w-1,$h); $e.Graphics.DrawLine($glow,$w-3,20,$w-3,[Math]::Min(90,$h-20)) }
  finally { $edge.Dispose();$glow.Dispose() }
})
$script:form.Controls.Add($sidebar)
  $brand = New-Label 'PEREGRINE' 13 $true $script:colors.text
  $brand.Location = New-Object Drawing.Point(86,20); $sidebar.Controls.Add($brand); $script:brandLabel = $brand
  $brandSub = New-Label 'FORGE  /  GF7E01' 8 $true $script:colors.cyan
  $brandSub.Location = New-Object Drawing.Point(87,48); $sidebar.Controls.Add($brandSub); $script:brandSubLabel = $brandSub
  $brandMark = New-Object Windows.Forms.Panel
  $brandMark.Location = New-Object Drawing.Point(19,14); $brandMark.Size = New-Object Drawing.Size(60,54)
  $brandMark.BackColor = [Drawing.Color]::Transparent
  $script:brandFont = New-Object Drawing.Font('Bahnschrift SemiBold',23,[Drawing.FontStyle]::Bold)
  $script:brandBrush = New-Object Drawing.SolidBrush($script:colors.text)
  $script:brandAccent = New-Object Drawing.Pen($script:colors.blue,2)
  $brandMark.Add_Paint({
    param($sender,$e)
    $e.Graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $e.Graphics.DrawString('PF',$script:brandFont,$script:brandBrush,5,5)
    $e.Graphics.DrawLine($script:brandAccent,6,44,52,44)
    $e.Graphics.DrawLine($script:brandAccent,16,49,43,49)
  }.GetNewClosure())
  $sidebar.Controls.Add($brandMark); $script:brandMark = $brandMark

$script:content = New-Object Windows.Forms.Panel
$script:content.Dock = 'None'; $script:content.Location = New-Object Drawing.Point($script:sidebarWidth,0)
$script:content.Size = New-Object Drawing.Size([Math]::Max(320,$script:form.ClientSize.Width-$script:sidebarWidth),$script:form.ClientSize.Height); $script:content.Anchor = 'Top,Bottom,Left,Right'
$script:content.BackColor = [Drawing.Color]::Transparent; $script:content.AutoScroll = $true
$script:form.Controls.Add($script:content)
$script:form.Add_Resize({
  if ($script:form.WindowState -ne [Windows.Forms.FormWindowState]::Minimized) {
    $script:sidebar.Height = $script:form.ClientSize.Height
    $script:content.Location = New-Object Drawing.Point($script:sidebarWidth,0)
    $script:content.Size = New-Object Drawing.Size([Math]::Max(320,$script:form.ClientSize.Width - $script:sidebarWidth),[Math]::Max(100,$script:form.ClientSize.Height))
    Update-StatusLabelBounds
    if ($script:backgroundResizeTimer) { $script:backgroundResizeTimer.Stop(); $script:backgroundResizeTimer.Start() }
  }
})
$script:form.Add_Shown({
  # Rebuild after the first DPI pass so the overview uses the real client dimensions.
  $script:form.PerformLayout()
  $script:sidebar.Height = $script:form.ClientSize.Height
  $script:content.Location = New-Object Drawing.Point($script:sidebarWidth,0)
  $script:content.Size = New-Object Drawing.Size([Math]::Max(320,$script:form.ClientSize.Width - $script:sidebarWidth),[Math]::Max(100,$script:form.ClientSize.Height))
  Update-LauncherBackground
  Update-StatusLabelBounds
  $script:sidebar.BringToFront()
  Show-Page 'Home'
  if (-not (Test-FilePath $script:discValue)) {
    $script:form.BeginInvoke([Action]{ [void](Select-GameImage $true) }) | Out-Null
  }
})
$script:backgroundResizeTimer = New-Object Windows.Forms.Timer
$script:backgroundResizeTimer.Interval = 80
$script:backgroundResizeTimer.Add_Tick({
  $script:backgroundResizeTimer.Stop()
  Update-LauncherBackground
})
$script:form.Add_FormClosed({
  if ($script:backgroundResizeTimer) { $script:backgroundResizeTimer.Stop(); $script:backgroundResizeTimer.Dispose(); $script:backgroundResizeTimer = $null }
  $script:form.BackgroundImage = $null
  if ($script:backgroundRendered) { $script:backgroundRendered.Dispose(); $script:backgroundRendered = $null }
  if ($script:backgroundImage) { $script:backgroundImage.Dispose(); $script:backgroundImage = $null }
  if ($script:formIcon) { $script:formIcon.Dispose(); $script:formIcon = $null }
  if ($script:flightDisplayFonts) { $script:flightDisplayFonts.Dispose(); $script:flightDisplayFonts = $null; $script:flightDisplayFontFamily = $null }
  foreach ($resource in @($script:brandFont,$script:brandBrush,$script:brandAccent)) { if ($resource) { $resource.Dispose() } }
  $script:brandFont = $null; $script:brandBrush = $null; $script:brandAccent = $null
})
$railLabel=New-Label 'SYSTEM STATUS' 8 $true $script:colors.muted
$railLabel.Location=New-Object Drawing.Point(20,548); $sidebar.Controls.Add($railLabel)
$script:statusLabel = New-Label 'LOCAL PROJECT' 9 $true $script:colors.cyan
$script:statusLabel.AutoSize = $false; $script:statusLabel.TextAlign = 'MiddleLeft'; $script:statusLabel.AutoEllipsis = $true
$script:statusLabel.BackColor=$script:colors.panel; $script:statusLabel.Padding=New-Object Windows.Forms.Padding(10,0,6,0)
$script:statusLabel.BorderStyle='FixedSingle'; $script:statusLabel.Size = New-Object Drawing.Size(220,38)
$sidebar.Controls.Add($script:statusLabel)
$script:statusTip = New-Object Windows.Forms.ToolTip
$script:statusTip.AutoPopDelay = 20000; $script:statusTip.InitialDelay = 400; $script:statusTip.ReshowDelay = 100
# Status messages carry error details; the rail tooltip retains their full text when it clips.
function Update-StatusLabelBounds {
  if (-not $script:statusLabel) { return }
  $script:statusLabel.Location = [Drawing.Point]::new(18,[Math]::Max(570,$script:sidebar.Height - 62))
  $script:statusLabel.Size = [Drawing.Size]::new(($script:sidebarWidth - 36),38)
}
Update-StatusLabelBounds

$navItems = @(
  @{key='Home';label='FLIGHT DECK'},
  @{key='Library';label='GAME LIBRARY'},
  @{key='Saves';label='SAVE ARCHIVE'},
  @{key='Mods';label='MOD LIBRARY'},
  @{key='Crashes';label='CRASH REPORTS'},
  @{key='Settings';label='SYSTEMS & CONTROLS'},
  @{key='About';label='ABOUT PEREGRINE FORGE'}
)
$script:navButtons = @{}
$navSection=New-Label 'NAVIGATION' 8 $true $script:colors.muted
$navSection.Location=New-Object Drawing.Point(21,112); $sidebar.Controls.Add($navSection)
$navY = 140
foreach ($item in $navItems) {
  $b = New-Object Windows.Forms.Button
  $b.Text = $item.label; $b.Tag = $item.key; $b.Location = New-Object Drawing.Point(14,$navY)
  $b.Size = [Drawing.Size]::new(($script:sidebarWidth - 28),46); $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
  $b.TextAlign = 'MiddleLeft'; $b.Padding=New-Object Windows.Forms.Padding(14,0,4,0)
  $b.BackColor = [Drawing.Color]::Transparent; $b.ForeColor = $script:colors.muted
  $b.FlatAppearance.MouseOverBackColor=[Drawing.Color]::FromArgb(14,38,45)
  $b.Font = New-Object Drawing.Font('Bahnschrift SemiBold',10); $b.Cursor = [Windows.Forms.Cursors]::Hand
  $b.Add_Click({ Show-Page ([string]$this.Tag) })
  $sidebar.Controls.Add($b); $script:navButtons[$item.key] = $b; $navY += 52
}
Update-StatusLabelBounds

function Show-Page([string]$page) {
  $script:content.SuspendLayout()
  foreach ($c in @($script:content.Controls)) { $script:content.Controls.Remove($c); $c.Dispose() }
  foreach ($key in $script:navButtons.Keys) {
    $selected = ($key -eq $page)
    $script:navButtons[$key].BackColor = if ($selected) { $script:colors.selection } else { [Drawing.Color]::Transparent }
    $script:navButtons[$key].FlatAppearance.BorderSize = if ($selected) { 1 } else { 0 }
    $script:navButtons[$key].FlatAppearance.BorderColor = if ($selected) { $script:colors.blue } else { $script:colors.line }
    $script:navButtons[$key].ForeColor = if ($selected) { $script:colors.cyan } else { $script:colors.muted }
  }
  if ($script:brandLabel) { $script:brandLabel.Visible = $true }
  if ($script:brandSubLabel) { $script:brandSubLabel.Visible = $true }
  if ($script:brandMark) { $script:brandMark.Visible = $true }
  switch ($page) {
    'Home' { Build-HomePage }
    'Library' { Build-LibraryPage }
    'Saves' { Build-SavesPage }
    'Mods' { Build-ModsPage }
    'Crashes' { Build-CrashesPage }
    'Settings' { Build-SettingsPage }
    'About' { Build-AboutPage }
  }
  $script:content.ResumeLayout()
}

function Build-HomePage {
  $pageWidth = [Math]::Max(880,$script:content.ClientSize.Width)
  $pageHeight = [Math]::Max(640,$script:content.ClientSize.Height)
  $scene = New-Object Windows.Forms.Panel
  $scene.Location = New-Object Drawing.Point(0,0); $scene.Size = New-Object Drawing.Size($pageWidth,$pageHeight)
  $scene.Anchor = 'Top,Bottom,Left,Right'; $scene.BackColor = [Drawing.Color]::Transparent
  $scene.Add_Paint({
    param($sender,$e)
    $w = $sender.ClientSize.Width; $h = $sender.ClientSize.Height
    $left = [Drawing.Rectangle]::new(0,0,[Math]::Min(650,$w),$h)
    $leftBrush = New-Object Drawing.Drawing2D.LinearGradientBrush($left,[Drawing.Color]::FromArgb(218,4,11,15),[Drawing.Color]::FromArgb(0,4,11,15),[Drawing.Drawing2D.LinearGradientMode]::Horizontal)
    $e.Graphics.FillRectangle($leftBrush,$left); $leftBrush.Dispose()
    $titleY = [Math]::Max(176,[int]($h * 0.32))
    $titleField = [Drawing.Rectangle]::new(16,[Math]::Max(0,$titleY - 42),[Math]::Min(570,$w - 16),204)
    $titleBrush = [Drawing.Drawing2D.LinearGradientBrush]::new($titleField,[Drawing.Color]::FromArgb(196,4,11,15),[Drawing.Color]::FromArgb(18,4,11,15),[Drawing.Drawing2D.LinearGradientMode]::Horizontal)
    $e.Graphics.FillRectangle($titleBrush,$titleField); $titleBrush.Dispose()
    $bottom = [Drawing.Rectangle]::new(0,[Math]::Max(0,$h-260),$w,[Math]::Min(260,$h))
    $bottomBrush = New-Object Drawing.Drawing2D.LinearGradientBrush($bottom,[Drawing.Color]::FromArgb(0,4,11,15),[Drawing.Color]::FromArgb(235,4,11,15),[Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $e.Graphics.FillRectangle($bottomBrush,$bottom); $bottomBrush.Dispose()
    $rule = New-Object Drawing.Pen([Drawing.Color]::FromArgb(95,61,202,222),1)
    $e.Graphics.DrawLine($rule,36,88,[Math]::Min($w-36,450),88)
    $e.Graphics.DrawLine($rule,36,[Math]::Max(0,$h-224),[Math]::Min($w-36,660),[Math]::Max(0,$h-224))
    $rule.Dispose()
  })
  $script:content.Controls.Add($scene)

  $eyebrow = New-Label 'PEREGRINE FORGE  /  FLIGHT SYSTEMS' 9 $true $script:colors.cyan
  $eyebrow.Location = New-Object Drawing.Point(38,35); $scene.Controls.Add($eyebrow)
  $titleY = [Math]::Max(176,[int]($pageHeight * 0.32))
  $eyebrowTitle=New-Label 'GAMECUBE RECOMPILATION' 9 $true $script:colors.muted
  $eyebrowTitle.BackColor = $script:colors.base
  $eyebrowTitle.Location=New-Object Drawing.Point(40,($titleY-35)); $scene.Controls.Add($eyebrowTitle)
  $name = New-Label 'STAR FOX' 28 $true
  $name.BackColor = $script:colors.base
  if ($script:flightDisplayFontFamily) { $name.Font = [Drawing.Font]::new($script:flightDisplayFontFamily,28,[Drawing.FontStyle]::Bold) }
  $name.Location = New-Object Drawing.Point(35,$titleY); $scene.Controls.Add($name)
  $name2 = New-Label 'ASSAULT' 30 $true $script:colors.cyan
  $name2.BackColor = $script:colors.base
  if ($script:flightDisplayFontFamily) { $name2.Font = [Drawing.Font]::new($script:flightDisplayFontFamily,30,[Drawing.FontStyle]::Bold) }
  $name2.Location = New-Object Drawing.Point(35,($titleY+47)); $scene.Controls.Add($name2)
  $validation=New-Label 'EXPERIMENTAL NATIVE BUILD  ·  GAMEPLAY VALIDATION IN PROGRESS' 9 $false $script:colors.muted
  $validation.BackColor = $script:colors.base
  $validation.Location=New-Object Drawing.Point(40,($titleY+122)); $scene.Controls.Add($validation)

  $cardY=[Math]::Max(470,$pageHeight-206)
  $cardWidth=[Math]::Min(480,$pageWidth-300)
  $statusCard=New-Card 36 $cardY $cardWidth 132; $scene.Controls.Add($statusCard)
  $nativeStatus = Get-NativeStatus
  $buildTitle = New-Label 'NATIVE BUILD' 8 $true $script:colors.muted
  $buildTitle.Location = New-Object Drawing.Point(19,18); $statusCard.Controls.Add($buildTitle)
  $buildValueText = if ($nativeStatus -eq 'UPDATE AVAILABLE') { 'REBUILD REQUIRED' } elseif ($nativeStatus -eq 'NOT BUILT') { 'NOT BUILT' } else { 'CURRENT' }
  $buildColor = if ($nativeStatus -eq 'NOT BUILT') { $script:colors.red } elseif ($nativeStatus -eq 'UPDATE AVAILABLE') { $script:colors.cyan } else { $script:colors.green }
  $buildValue = New-Label $buildValueText 10 $true $buildColor
  $buildValue.Location = New-Object Drawing.Point(19,47); $statusCard.Controls.Add($buildValue)
  $discTitle = New-Label 'GAME IMAGE' 8 $true $script:colors.muted
  $discTitle.Location = New-Object Drawing.Point(220,18); $statusCard.Controls.Add($discTitle)
  $discValue = if (Test-FilePath ([string]$script:settings.disc)) { 'IMAGE FOUND' } else { 'NOT SELECTED' }
  $discColor = if ($discValue -eq 'IMAGE FOUND') { $script:colors.green } else { $script:colors.red }
  $discLabel = New-Label $discValue 10 $true $discColor
  $discLabel.Location = New-Object Drawing.Point(220,47); $statusCard.Controls.Add($discLabel)
  $separator=New-Object Windows.Forms.Panel; $separator.Location=New-Object Drawing.Point(200,18); $separator.Size=New-Object Drawing.Size(1,75); $separator.BackColor=$script:colors.line; $statusCard.Controls.Add($separator)
  $targetTitle=New-Label 'TARGET' 8 $true $script:colors.muted; $targetTitle.Location=New-Object Drawing.Point(19,78); $statusCard.Controls.Add($targetTitle)
  $targetValue=New-Label 'USA · GF7E01' 10 $true $script:colors.text; $targetValue.Location=New-Object Drawing.Point(19,98); $statusCard.Controls.Add($targetValue)
  $statusTip=New-Label ('PLAY TIME  ·  {0}' -f (Get-PlaytimeText)) 8 $false $script:colors.muted
  $statusTip.Location=New-Object Drawing.Point(220,82); $statusCard.Controls.Add($statusTip)

  $hasDisc = Test-FilePath $script:discValue
  $hasNative = Test-Path -LiteralPath $script:nativePath -PathType Leaf
  $playText = if (-not $hasDisc) { 'SELECT GAME IMAGE' } elseif (-not $hasNative) { 'BUILD NATIVE' } elseif ($nativeStatus -eq 'UPDATE AVAILABLE') { 'REBUILD NATIVE' } else { 'LAUNCH GAME' }
  $play = New-Button $playText 190 $true
  $playX = $pageWidth - 230; $playY = $cardY + 16
  $play.Size = New-Object Drawing.Size(194,54); $play.Location = New-Object Drawing.Point($playX,$playY)
  $play.Anchor = 'Bottom,Right'; $play.Add_Click({
    if (-not (Test-FilePath $script:discValue)) { [void](Select-GameImage $true) }
    elseif (-not (Test-Path -LiteralPath $script:nativePath -PathType Leaf) -or (Get-NativeStatus) -eq 'UPDATE AVAILABLE') { Start-NativeBuild }
    else { Start-NativeGame }
  }); $scene.Controls.Add($play)
  $dolphin = New-Button 'OPEN IN DOLPHIN' 194
  $dolphinX = $pageWidth - 230; $dolphinY = $playY + 64
  $dolphin.Size = New-Object Drawing.Size(194,42); $dolphin.Location = New-Object Drawing.Point($dolphinX,$dolphinY)
  $dolphin.Anchor = 'Bottom,Right'; $dolphin.Add_Click({ Start-DolphinGame }); $dolphin.Visible = (Test-FilePath $script:dolphinValue); $scene.Controls.Add($dolphin)
  $quick = New-Label 'SPACE CONTINUE  /  F9 MOUSE' 8 $true $script:colors.cyan
  $quick.Location=New-Object Drawing.Point($playX,($cardY-35)); $quick.Anchor='Bottom,Right'; $scene.Controls.Add($quick)
}

function Get-ContentPageWidth { [Math]::Max(880,$script:content.ClientSize.Width - 60) }

function Refresh-CrashLogs($list) {
  $list.Items.Clear()
  $script:crashLogPaths = @()
  if (-not (Test-Path -LiteralPath $script:nativeRunDir)) { return }
  $logs = Get-ChildItem -LiteralPath $script:nativeRunDir -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { ($_.Extension -in @('.log','.err') -or ($_.Extension -eq '.txt' -and $_.Name -match 'crash|error')) -and $_.Length -gt 0 } |
    Sort-Object LastWriteTimeUtc -Descending
  foreach ($log in $logs) {
    [void]$list.Items.Add(('{0}  ·  {1:yyyy-MM-dd HH:mm}' -f $log.Name,$log.LastWriteTime))
    $script:crashLogPaths += $log.FullName
  }
  if ($script:crashEmptyLabel) { $script:crashEmptyLabel.Visible = ($list.Items.Count -eq 0) }
  if ($list.Items.Count -gt 0) { $list.SelectedIndex = 0 }
}

function Build-CrashesPage {
  Add-SectionHeader $script:content 'Crash reports' 'Inspect native runtime logs saved in this project''s isolated run folder.'
  $pageWidth = Get-ContentPageWidth
  $card = New-Card 30 112 $pageWidth 650
  $list = New-Object Windows.Forms.ListBox
  $list.Location = New-Object Drawing.Point(24,24); $list.Size = New-Object Drawing.Size(340,540)
  $list.BackColor = $script:colors.panel2; $list.ForeColor = $script:colors.text; $list.BorderStyle = 'FixedSingle'
  $list.Anchor = 'Top,Bottom,Left'; $card.Controls.Add($list)
  $script:crashEmptyLabel = New-Label 'No crash logs yet' 10 $true $script:colors.muted
  $script:crashEmptyLabel.AutoSize = $false; $script:crashEmptyLabel.TextAlign = 'MiddleCenter'
  $script:crashEmptyLabel.Location = New-Object Drawing.Point(24,220); $script:crashEmptyLabel.Size = New-Object Drawing.Size(340,38); $card.Controls.Add($script:crashEmptyLabel)
  $detail = New-Object Windows.Forms.TextBox
  $detailWidth = [Math]::Max(300,$pageWidth - 430)
  $detail.Location = New-Object Drawing.Point(382,24); $detail.Size = New-Object Drawing.Size($detailWidth,540)
  $detail.Multiline = $true; $detail.ReadOnly = $true; $detail.WordWrap = $true; $detail.ScrollBars = 'Vertical'; $detail.BorderStyle = 'None'
  $detail.BackColor = $script:colors.base; $detail.ForeColor = $script:colors.text
  $detail.Font = New-Object Drawing.Font('Consolas',9); $detail.Anchor = 'Top,Bottom,Left,Right'; $card.Controls.Add($detail)
  $script:crashLogList = $list; $script:crashLogDetail = $detail
  $list.Add_SelectedIndexChanged({
    if ($script:crashLogList.SelectedIndex -ge 0 -and $script:crashLogList.SelectedIndex -lt $script:crashLogPaths.Count) {
      try {
        $selectedLog = $script:crashLogPaths[$script:crashLogList.SelectedIndex]
        $script:crashLogDetail.Text = Get-Content -LiteralPath $selectedLog -Raw -ErrorAction Stop
        $ramDump = [IO.Path]::ChangeExtension($selectedLog,'.ram.bin')
        if (Test-Path -LiteralPath $ramDump -PathType Leaf) {
          $script:crashLogDetail.AppendText(("`r`n`r`nRAM dump available:`r`n{0}" -f $ramDump))
        }
      }
      catch { $script:crashLogDetail.Text = $_.Exception.Message }
    }
  })
  Refresh-CrashLogs $list
  $refresh = New-Button 'REFRESH' 110; $refresh.Location = New-Object Drawing.Point(24,584)
  $refresh.Add_Click({ Refresh-CrashLogs $script:crashLogList }); $card.Controls.Add($refresh)
  $open = New-Button 'OPEN LOG FOLDER' 155; $open.Location = New-Object Drawing.Point(145,584)
  $open.Add_Click({ Open-Folder $script:nativeRunDir }); $card.Controls.Add($open)
  $script:content.Controls.Add($card)
}

function Build-LibraryPage {
  Add-SectionHeader $script:content 'Your game' 'Choose and inspect your own USA game image. The image is only read, never modified.'
  $pageWidth = Get-ContentPageWidth
  $card = New-Card 30 110 $pageWidth 230
  $label = New-Label 'STAR FOX ASSAULT' 20 $true; $label.Location = New-Object Drawing.Point(24,24); $card.Controls.Add($label)
  $sub = New-Label 'GameCube · Star Fox Assault · USA (GF7E01)' 10 $false $script:colors.muted; $sub.Location = New-Object Drawing.Point(26,62); $card.Controls.Add($sub)
  $script:discValue = $script:settings.disc
  $box = New-Object Windows.Forms.TextBox; $box.Text = $script:discValue; $box.Location = New-Object Drawing.Point(26,104); $box.Size = New-Object Drawing.Size(640,30)
  $box.BackColor = $script:colors.panel2; $box.ForeColor = $script:colors.text; $box.BorderStyle = 'FixedSingle'; $box.Anchor='Top,Left,Right'; $card.Controls.Add($box)
  $script:discBox = $box
  $browseX = $card.Width - 131; $box.Width = $browseX - 40
  $browse = New-Button 'BROWSE' 105; $browse.Location = New-Object Drawing.Point($browseX,100); $browse.Anchor='Top,Right'
  $browse.Add_Click({ $d=New-Object Windows.Forms.OpenFileDialog; $d.Filter='GameCube images (*.iso;*.ciso)|*.iso;*.ciso'; $d.RestoreDirectory=$true; if($d.ShowDialog($script:form) -eq 'OK'){ try{$null=Test-GameImage $d.FileName; $script:discBox.Text=$d.FileName; $script:discValue=$d.FileName; Save-Settings; Set-Status 'Game image accepted.' $true}catch{Set-Status $_.Exception.Message} } }); $card.Controls.Add($browse)
  $verify = New-Button 'VERIFY GAME IMAGE' 172 $true; $verify.Location = New-Object Drawing.Point(26,159)
  $verify.Add_Click({ try { $script:discValue=$script:discBox.Text; $i=Test-GameImage $script:discValue; Save-Settings; Set-Status "Verified · $($i.internal_name) · $($i.region) · revision $($i.revision)" $true } catch { Set-Status $_.Exception.Message } })
  $card.Controls.Add($verify)
  $launchNative = New-Button 'PLAY NATIVE' 142; $launchNative.Location = New-Object Drawing.Point(214,159); $launchNative.Add_Click({ $script:discValue=$script:discBox.Text; Start-NativeGame }); $card.Controls.Add($launchNative)
  $launchDolphin = New-Button 'PLAY IN DOLPHIN' 158; $launchDolphin.Location = New-Object Drawing.Point(370,159); $launchDolphin.Add_Click({ $script:discValue=$script:discBox.Text; Start-DolphinGame }); $launchDolphin.Visible=(Test-FilePath $script:dolphinValue); $card.Controls.Add($launchDolphin)
  $script:content.Controls.Add($card)
  $build = New-Card 30 365 $pageWidth 130
  $bt = New-Label 'LOCAL BUILD & UPDATES' 9 $true $script:colors.cyan; $bt.Location = New-Object Drawing.Point(23,20); $build.Controls.Add($bt)
  $bd = New-Label ("Status: {0}. Build from local source or install a local prototype ZIP; there is no online updater." -f (Get-NativeStatus)) 10 $false $script:colors.text
  $bd.Location = New-Object Drawing.Point(24,55); $build.Controls.Add($bd)
  $bbText = if (Test-Path -LiteralPath $script:nativePath -PathType Leaf) { 'REBUILD NATIVE' } else { 'IMPORT & BUILD' }
  $bb = New-Button $bbText 160 $true; $bb.Location = New-Object Drawing.Point(24,82); $bb.Add_Click({ $script:discValue=$script:discBox.Text; Start-NativeBuild }); $build.Controls.Add($bb)
  $packageButton = New-Button 'INSTALL LOCAL ZIP' 178; $packageButton.Location = New-Object Drawing.Point(198,82)
  $packageButton.Add_Click({ Open-PrototypeUpdateDialog }); $build.Controls.Add($packageButton)
  $script:content.Controls.Add($build)
}

function Get-BackupFilePath($item) {
  if ($null -eq $item -or [string]::IsNullOrWhiteSpace([string]$item.FileName)) { throw 'Select a save backup first.' }
  $fileName = [string]$item.FileName
  if ([IO.Path]::GetFileName($fileName) -cne $fileName) { throw 'The selected backup name is invalid.' }
  $root = [IO.Path]::GetFullPath($script:backupDir).TrimEnd('\') + '\'
  $path = [IO.Path]::GetFullPath((Join-Path $root $fileName))
  if (-not $path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'The selected backup is outside the backup folder.' }
  return $path
}

function Get-BackupMetadata([string]$rawPath) {
  $file = Get-Item -LiteralPath $rawPath -ErrorAction Stop
  $defaultLabel = [IO.Path]::GetFileNameWithoutExtension($file.Name) -replace '^memcard-',''
  $result = [ordered]@{
    schemaVersion = 1
    fileName = $file.Name
    label = $defaultLabel
    tags = @()
    createdUtc = $file.LastWriteTimeUtc.ToString('o')
    sizeBytes = [long]$file.Length
    sha256 = ''
    source = 'existing backup'
  }
  $metaPath = $rawPath + '.meta.json'
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

function Write-BackupMetadata([string]$rawPath,[string]$label,[string[]]$tags,[string]$source,[string]$createdUtc) {
  $file = Get-Item -LiteralPath $rawPath -ErrorAction Stop
  $hash = (Get-FileHash -LiteralPath $rawPath -Algorithm SHA256).Hash
  $meta = [ordered]@{
    schemaVersion = 1
    fileName = $file.Name
    label = $label
    tags = @($tags)
    createdUtc = $createdUtc
    sizeBytes = [long]$file.Length
    sha256 = $hash
    source = $source
  }
  $json = $meta | ConvertTo-Json -Depth 4
  [IO.File]::WriteAllText(($rawPath + '.meta.json'),$json,(New-Object System.Text.UTF8Encoding($false)))
}

function New-SaveBackup([string]$sourcePath,[string]$label,[string[]]$tags,[string]$source,[bool]$requireRuntimeSize = $false) {
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw 'The active memory card was not found.' }
  $file = Get-Item -LiteralPath $sourcePath -ErrorAction Stop
  $expectedSize = 4 * 1024 * 1024 / 8
  if ($requireRuntimeSize -and $file.Length -ne $expectedSize) { throw "This memory card is $($file.Length) bytes. The native runtime uses a $expectedSize-byte (4 Mbit) card, so it was not backed up." }
  [IO.Directory]::CreateDirectory($script:backupDir) | Out-Null
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
  $name = 'memcard-{0}-{1}.raw' -f $stamp,[Guid]::NewGuid().ToString('N')
  $dest = Join-Path $script:backupDir $name
  [IO.File]::Copy($sourcePath,$dest,$false)
  $created = [DateTime]::UtcNow.ToString('o')
  try { Write-BackupMetadata -rawPath $dest -label $label -tags $tags -source $source -createdUtc $created }
  catch { throw "Backup data was copied to $name, but its metadata could not be written: $($_.Exception.Message)" }
  return $dest
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
  Add-SectionHeader $script:content 'Save backups' 'Label and tag snapshots of the native runtime memory card. Backups are blocked while the game is running.'
  $pageWidth = Get-ContentPageWidth
  $card = New-Card 30 112 $pageWidth 485
  $pathLabel = New-Label 'ACTIVE MEMORY CARD' 9 $true $script:colors.cyan; $pathLabel.Location = New-Object Drawing.Point(24,18); $card.Controls.Add($pathLabel)
  $p = New-Label $script:memcardPath 8 $false $script:colors.muted; $p.AutoSize=$false; $p.AutoEllipsis=$true
  $p.Location = New-Object Drawing.Point(25,42); $p.Size=New-Object Drawing.Size(($card.Width - 50),20); $card.Controls.Add($p)
  $script:savePathToolTip = New-Object Windows.Forms.ToolTip; $script:savePathToolTip.SetToolTip($p,$script:memcardPath)

  $script:backupList = New-Object Windows.Forms.ListBox
  $script:backupList.DisplayMember = 'DisplayName'
  $script:backupList.Location=New-Object Drawing.Point(25,75); $script:backupList.Size=New-Object Drawing.Size(420,300)
  $script:backupList.BackColor=$script:colors.panel2; $script:backupList.ForeColor=$script:colors.text; $script:backupList.BorderStyle='FixedSingle'
  $script:backupList.HorizontalScrollbar=$true; $script:backupList.Anchor='Top,Left,Bottom'; $card.Controls.Add($script:backupList)
  $script:backupEmptyLabel=New-Label 'No backups yet' 10 $true $script:colors.muted
  $script:backupEmptyLabel.AutoSize=$false; $script:backupEmptyLabel.TextAlign='MiddleCenter'
  $script:backupEmptyLabel.Location=New-Object Drawing.Point(25,198); $script:backupEmptyLabel.Size=New-Object Drawing.Size(420,38); $card.Controls.Add($script:backupEmptyLabel)

  $detailPanel = New-Card 465 75 ([Math]::Max(360,$pageWidth-490)) 300; $card.Controls.Add($detailPanel)
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
      if (Get-Process -Name assault -ErrorAction SilentlyContinue) { throw 'Close the native game before making a backup so the snapshot is consistent.' }
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
      if (Get-Process -Name assault -ErrorAction SilentlyContinue) { throw 'Close the native game before restoring a save.' }
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
      if (Get-Process -Name assault -ErrorAction SilentlyContinue) { throw 'The native game started while the restore confirmation was open. Close it and retry.' }
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
  $script:content.Controls.Add($card)
  $note=New-Label 'Backup metadata is stored beside each snapshot. The native runtime uses a 4 Mbit, 524,288-byte card; mismatched backups cannot be restored.' 9 $false $script:colors.muted
  $note.Location=New-Object Drawing.Point(36,612); $script:content.Controls.Add($note)
}

function Refresh-Mods($list) {
  $list.Items.Clear(); [IO.Directory]::CreateDirectory($script:modsDir) | Out-Null
  Get-ChildItem -LiteralPath $script:modsDir -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'launcher-pack.json') } | Sort-Object Name | ForEach-Object { [void]$list.Items.Add($_.Name) }
  if ($script:modsEmptyLabel) { $script:modsEmptyLabel.Visible = ($list.Items.Count -eq 0) }
}
function Install-TexturePack([string]$zipPath) {
  $temp = Join-Path $script:modsWorkDir ([Guid]::NewGuid().ToString('N'))
  $rootPrefix = [IO.Path]::GetFullPath($temp).TrimEnd('\') + '\'
  $maxArchiveEntries = 50000
  $maxExpandedBytes = [long]2GB
  $totalExpandedBytes = [long]0
  [IO.Directory]::CreateDirectory($temp) | Out-Null
  try {
    $archive=[IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
      if ($archive.Entries.Count -gt $maxArchiveEntries) { throw "This texture pack has more than $maxArchiveEntries files and was not installed." }
      foreach ($entry in $archive.Entries) {
        if ($entry.Length -lt 0 -or $entry.Length -gt $maxExpandedBytes -or ($totalExpandedBytes + $entry.Length) -gt $maxExpandedBytes) {
          throw 'This texture pack expands beyond the 2 GiB safety limit and was not installed.'
        }
        $target=[IO.Path]::GetFullPath((Join-Path $temp $entry.FullName))
        if (-not $target.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'The ZIP contains an unsafe path and was not installed.' }
        if ($entry.FullName.EndsWith('/')) { [IO.Directory]::CreateDirectory($target) | Out-Null; continue }
        [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
        $src=$entry.Open(); $dst=[IO.File]::Open($target,[IO.FileMode]::CreateNew)
        try {
          $buffer=New-Object byte[] (1024*1024); $entryBytes=[long]0
          while (($read=$src.Read($buffer,0,$buffer.Length)) -gt 0) {
            $entryBytes += $read; $totalExpandedBytes += $read
            if ($entryBytes -gt $entry.Length -or $totalExpandedBytes -gt $maxExpandedBytes) { throw 'The texture pack expanded beyond its declared size or the 2 GiB safety limit.' }
            $dst.Write($buffer,0,$read)
          }
          if ($entryBytes -ne $entry.Length) { throw 'A texture pack entry was incomplete; no files were installed.' }
        } finally { $dst.Dispose(); $src.Dispose() }
      }
    } finally { $archive.Dispose() }
    $ini=Get-ChildItem -LiteralPath $temp -Recurse -File | Where-Object { $_.Name -ieq 'textures.ini' } | Select-Object -First 1
    if (-not $ini) { throw 'This is not a Dolphin texture pack ZIP: textures.ini was not found.' }
    $packRoot=$ini.Directory.FullName
    $packName=[IO.Path]::GetFileNameWithoutExtension($zipPath) -replace '[^a-zA-Z0-9 _.-]',''
    if (-not $packName) { $packName='Texture Pack' }
    $targetRoot=Join-Path $script:modsDir $packName
    if (Test-Path -LiteralPath $targetRoot) { $targetRoot=Join-Path $script:modsDir ('{0}-{1}' -f $packName,(Get-Date -Format 'yyyyMMdd-HHmmss')) }
    [IO.Directory]::CreateDirectory($targetRoot) | Out-Null
    Get-ChildItem -LiteralPath $packRoot -Force | Copy-Item -Destination $targetRoot -Recurse -Force
    @{name=$packName;source=[IO.Path]::GetFileName($zipPath);installed=(Get-Date).ToString('s')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $targetRoot 'launcher-pack.json') -Encoding utf8
  } finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}
function Get-PythonExecutable {
  # The first build downloads and hash-verifies a portable Python (tools\portable-toolchain.json),
  # so native asset packs can use that copy instead of requiring a separate install. The
  # recorded hashes are checked again here, so a leftover or edited folder is not trusted.
  $toolRoot = Join-Path $script:projectDir 'user-data\build-tools'
  $manifestPath = Join-Path $script:projectDir 'tools\portable-toolchain.json'
  if ((Test-Path -LiteralPath $toolRoot -PathType Container) -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    try {
      $entry = (Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).tools |
        Where-Object { $_.id -eq 'python' } | Select-Object -First 1
      if ($entry) {
        $folder = Join-Path $toolRoot ('{0}-{1}' -f [string]$entry.id,[string]$entry.version)
        $exe = if ($entry.archive_root) { Join-Path (Join-Path $folder ([string]$entry.archive_root)) ([string]$entry.executable) } else { Join-Path $folder ([string]$entry.executable) }
        $stamp = Join-Path $folder '.ready.json'
        if ((Test-Path -LiteralPath $exe -PathType Leaf) -and (Test-Path -LiteralPath $stamp -PathType Leaf)) {
          $record = Get-Content -LiteralPath $stamp -Raw | ConvertFrom-Json
          if ($record.archive_sha256 -eq $entry.sha256 -and
              $record.executable_sha256 -eq (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash) {
            return $exe
          }
        }
      }
    } catch { }
  }
  $installed = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
  if ($installed) { return $installed }
  return $null
}
function Get-NativeDiscFileIndex {
  $runtimeRecomp = Join-Path $script:projectDir 'runtime\recomp'
  if (-not (Test-Path -LiteralPath $runtimeRecomp -PathType Container)) { throw 'The runtime disc tools are missing; native pack validation cannot continue.' }
  $null = Test-GameImage $script:discValue
  $python = Get-PythonExecutable
  if (-not $python) { throw 'Reading the disc file table needs Python. Run Import & Build once so the portable tools are installed, or install Python 3; the Dolphin texture pack option does not need it.' }
  $code = 'import json,sys;sys.path.insert(0,sys.argv[1]);from rel import disc_files;from dol import DiscImage;img=DiscImage(sys.argv[2]);files=disc_files(img);img.f.close();print(json.dumps({k:v[1] for k,v in files.items()},separators=(",",":")))'
  $raw = & $python -c $code $runtimeRecomp $script:discValue 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Could not read the disc file table: $($raw -join ' ')" }
  try {
    $parsed = ($raw -join "`n") | ConvertFrom-Json
    $index = New-Object 'System.Collections.Generic.Dictionary[string,long]' ([StringComparer]::Ordinal)
    foreach ($property in $parsed.PSObject.Properties) { $index.Add([string]$property.Name,[long]$property.Value) }
    return $index
  } catch { throw 'The disc tools returned an invalid file table; no files were installed.' }
}
function Get-NativeModDirectories {
  $root = Split-Path -Parent $script:nativeModsDir
  $backupRoot = Join-Path $root 'backups'
  if (Test-Path -LiteralPath $backupRoot -PathType Container) {
    return @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
  }
  return @()
}
function Install-NativeModPack([string]$zipPath) {
  if (Get-Process -Name assault -ErrorAction SilentlyContinue) { throw 'Close the native game before changing its active asset pack.' }
  $parent = Split-Path -Parent $script:nativeModsDir
  $stage = Join-Path $parent ('.stage-' + [Guid]::NewGuid().ToString('N'))
  $backupRoot = Join-Path $parent 'backups'
  $metaRoot = Join-Path $parent 'metadata'
  $fileIndex = Get-NativeDiscFileIndex
  [IO.Directory]::CreateDirectory($stage) | Out-Null
  $archive = $null
  $filesWritten = 0
  $totalBytes = [long]0
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  try {
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    if ($archive.Entries.Count -eq 0 -or $archive.Entries.Count -gt 4096) { throw 'The ZIP has no files or contains too many entries.' }
    foreach ($entry in $archive.Entries) {
      $name = $entry.FullName.Replace('\','/')
      if ($name.StartsWith('/') -or $name -match '^[A-Za-z]:' -or $name.Contains(':') -or $name.Contains([char]0)) { throw "Unsafe ZIP path: $name" }
      $parts = $name.Split('/')
      $pathParts = @($parts | Where-Object { $_ -ne '' })
      if (@($pathParts | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) { throw "Unsafe ZIP path: $name" }
      $unixMode = ($entry.ExternalAttributes -shr 16) -band 0xF000
      if ($unixMode -eq 0xA000) { throw "ZIP symlink entries are not accepted: $name" }
      $unixPermissions = ($entry.ExternalAttributes -shr 16) -band 0x1FF
      if (($unixPermissions -band 0x49) -ne 0) { throw "Executable ZIP entries are not accepted: $name" }
      if ($entry.FullName.EndsWith('/')) { continue }
      if (@($parts | Where-Object { $_ -eq '' }).Count -gt 0) { throw "Unsafe ZIP path: $name" }
      if (-not $seen.Add($name)) { throw "Duplicate or case-colliding ZIP path: $name" }
      $normalized = $name
      $extension = [IO.Path]::GetExtension($normalized).ToLowerInvariant()
      if ($normalized.StartsWith('sys/',[StringComparison]::OrdinalIgnoreCase) -or $extension -in @('.dol','.rel','.elf','.exe')) { throw "Unsupported executable/system replacement: $name" }
      $discPath = $null
      foreach ($candidate in $fileIndex.Keys) { if ([string]$candidate -ceq $normalized) { $discPath = [string]$candidate; break } }
      if ($null -eq $discPath) { throw "The disc does not contain '$name'. Use exact FST paths; wrapper folders and extra files are not accepted." }
      $expected = [long]$fileIndex[$discPath]
      if ($expected -le 0 -or [long]$entry.Length -ne $expected) { throw "Size mismatch for '$name': disc expects $expected bytes, ZIP contains $($entry.Length)." }
      $totalBytes += [long]$entry.Length
      if ($totalBytes -gt 4294967296) { throw 'The native pack exceeds the 4 GiB safety limit.' }
      $target = Join-Path $stage ($parts -join '\')
      $fullTarget = [IO.Path]::GetFullPath($target)
      $stagePrefix = [IO.Path]::GetFullPath($stage).TrimEnd('\') + '\'
      if (-not $fullTarget.StartsWith($stagePrefix,[StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe ZIP path: $name" }
      [IO.Directory]::CreateDirectory((Split-Path -Parent $fullTarget)) | Out-Null
      $src = $entry.Open()
      $dst = [IO.File]::Open($fullTarget,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
      try { $src.CopyTo($dst) } finally { $dst.Dispose(); $src.Dispose() }
      if ((Get-Item -LiteralPath $fullTarget).Length -ne $expected) { throw "Extracted size verification failed for '$name'." }
      $filesWritten++
    }
    if ($filesWritten -eq 0) { throw 'The ZIP contains no native asset files.' }
    [IO.Directory]::CreateDirectory($backupRoot) | Out-Null
    [IO.Directory]::CreateDirectory($metaRoot) | Out-Null
    $packName = [IO.Path]::GetFileNameWithoutExtension($zipPath)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $backupName = $stamp + '-' + [Guid]::NewGuid().ToString('N').Substring(0,6)
    $hadActive = Test-Path -LiteralPath $script:nativeModsDir -PathType Container
    if ($hadActive -and ([IO.File]::GetAttributes($script:nativeModsDir) -band [IO.FileAttributes]::ReparsePoint)) { throw 'The active native mods folder is a reparse point; import was stopped safely.' }
    $previousMetadata = $null
    $activeMetadataPath = Join-Path $metaRoot 'active.json'
    if ($hadActive -and (Test-Path -LiteralPath $activeMetadataPath -PathType Leaf)) { $previousMetadata = Get-Content -LiteralPath $activeMetadataPath -Raw }
    if ($hadActive) { [IO.Directory]::Move($script:nativeModsDir,(Join-Path $backupRoot $backupName)) }
    try { [IO.Directory]::Move($stage,$script:nativeModsDir) }
    catch {
      if ($hadActive -and -not (Test-Path -LiteralPath $script:nativeModsDir)) { [IO.Directory]::Move((Join-Path $backupRoot $backupName),$script:nativeModsDir) }
      throw
    }
    $meta = @{ name=$packName; source=[IO.Path]::GetFileName($zipPath); installed=(Get-Date).ToString('s'); files=$filesWritten; bytes=$totalBytes; disc='GF7E01' }
    $meta | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $metaRoot 'active.json') -Encoding utf8
    if ($hadActive -and $previousMetadata) { Set-Content -LiteralPath (Join-Path $metaRoot ($backupName + '.json')) -Value $previousMetadata -Encoding utf8 }
    return $meta
  } finally {
    if ($archive) { $archive.Dispose() }
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
  }
}
function Restore-PreviousNativeModPack {
  if (Get-Process -Name assault -ErrorAction SilentlyContinue) { throw 'Close the native game before rolling back its active asset pack.' }
  $previous = Get-NativeModDirectories | Select-Object -First 1
  if (-not $previous) { throw 'There is no previous native pack to restore.' }
  if (([IO.File]::GetAttributes($previous.FullName) -band [IO.FileAttributes]::ReparsePoint)) { throw 'The saved native pack is a reparse point; rollback was stopped safely.' }
  $parent = Split-Path -Parent $script:nativeModsDir
  $backupRoot = Join-Path $parent 'backups'
  $metaRoot = Join-Path $parent 'metadata'
  $swapName = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-rollback-' + [Guid]::NewGuid().ToString('N').Substring(0,6)
  $currentMoved = $false
  $currentMetadata = Join-Path $metaRoot 'active.json'
  $currentMetadataText = if(Test-Path -LiteralPath $currentMetadata -PathType Leaf){Get-Content -LiteralPath $currentMetadata -Raw}else{$null}
  if (Test-Path -LiteralPath $script:nativeModsDir -PathType Container) { [IO.Directory]::Move($script:nativeModsDir,(Join-Path $backupRoot $swapName)); $currentMoved = $true }
  try { [IO.Directory]::Move($previous.FullName,$script:nativeModsDir) }
  catch {
    if ($currentMoved -and -not (Test-Path -LiteralPath $script:nativeModsDir)) { [IO.Directory]::Move((Join-Path $backupRoot $swapName),$script:nativeModsDir) }
    throw
  }
  if ($currentMoved -and $currentMetadataText) { Set-Content -LiteralPath (Join-Path $metaRoot ($swapName + '.json')) -Value $currentMetadataText -Encoding utf8 }
  $oldMeta = Join-Path $metaRoot ($previous.Name + '.json')
  if (Test-Path -LiteralPath $oldMeta) { Copy-Item -LiteralPath $oldMeta -Destination (Join-Path $metaRoot 'active.json') -Force }
}
function Build-ModsPage {
  Add-SectionHeader $script:content 'Mod library' 'Import and manage local Dolphin texture packs in this launcher''s isolated profile.'
  $pageWidth = Get-ContentPageWidth
  $card=New-Card 30 112 $pageWidth 370
  $list=New-Object Windows.Forms.ListBox; $list.Location=New-Object Drawing.Point(25,25); $list.Size=New-Object Drawing.Size(($pageWidth - 50),220)
  $list.BackColor=$script:colors.panel2; $list.ForeColor=$script:colors.text; $list.BorderStyle='FixedSingle'; $list.Anchor='Top,Left,Right'; $card.Controls.Add($list)
  $script:modsEmptyLabel=New-Label 'No Dolphin texture packs installed' 10 $true $script:colors.muted
  $script:modsEmptyLabel.AutoSize=$false; $script:modsEmptyLabel.TextAlign='MiddleCenter'
  $script:modsEmptyLabel.Location=New-Object Drawing.Point(25,104); $script:modsEmptyLabel.Size=New-Object Drawing.Size(($pageWidth - 50),36); $card.Controls.Add($script:modsEmptyLabel)
  Refresh-Mods $list; $script:modsList=$list
  $install=New-Button 'INSTALL ZIP PACK' 162 $true; $install.Location=New-Object Drawing.Point(25,265)
  $install.Add_Click({
    $d=New-Object Windows.Forms.OpenFileDialog; $d.Filter='Dolphin texture pack (*.zip)|*.zip'
    if ($d.ShowDialog() -eq 'OK') { try { Install-TexturePack $d.FileName; Refresh-Mods $script:modsList; Set-Status 'Texture pack installed to the isolated Dolphin profile.' $true } catch { Set-Status $_.Exception.Message } }
  }); $card.Controls.Add($install)
  $remove=New-Button 'REMOVE SELECTED' 160; $remove.Location=New-Object Drawing.Point(202,265)
  $remove.Add_Click({
    if (-not $script:modsList.SelectedItem) { Set-Status 'Select an installed texture pack first.'; return }
    $target=Join-Path $script:modsDir ([string]$script:modsList.SelectedItem)
    $answer=[Windows.Forms.MessageBox]::Show("Remove $($script:modsList.SelectedItem) from the isolated Dolphin profile?",'Remove texture pack','YesNo','Warning')
    if ($answer -eq 'Yes') { Remove-Item -LiteralPath $target -Recurse -Force; Refresh-Mods $script:modsList; Set-Status 'Texture pack removed.' $true }
  }); $card.Controls.Add($remove)
  $folder=New-Button 'OPEN MOD FOLDER' 160; $folder.Location=New-Object Drawing.Point(377,265); $folder.Add_Click({ Open-Folder $script:modsDir }); $card.Controls.Add($folder)
  $script:content.Controls.Add($card)
  $nativeCard=New-Card 30 500 $pageWidth 188
  $n=New-Label 'NATIVE ASSET REPLACEMENTS' 9 $true $script:colors.cyan; $n.Location=New-Object Drawing.Point(22,17); $nativeCard.Controls.Add($n)
  $nd=New-Label 'Exact-size files at matching disc paths only. Executable files, RELs, DOLs, and sys/ are not supported. Dolphin texture packs do not apply to the native build.' 9 $false $script:colors.muted
  $nd.Location=New-Object Drawing.Point(22,42); $nd.MaximumSize=New-Object Drawing.Size(($pageWidth - 48),0); $nativeCard.Controls.Add($nd)
  $nativeCheck=New-Object Windows.Forms.CheckBox; $nativeCheck.Text='Enable native asset replacements'; $nativeCheck.AutoSize=$true; $nativeCheck.Location=New-Object Drawing.Point(22,76); $nativeCheck.ForeColor=$script:colors.text; $nativeCheck.BackColor=[Drawing.Color]::Transparent; $nativeCheck.Checked=[bool]$script:nativeModsValue
  $nativeCheck.Add_CheckedChanged({ $script:nativeModsValue=[bool]$script:nativeModsCheck.Checked; Save-Settings; if($script:nativeModsValue -and -not(Test-Path -LiteralPath $script:nativeModsDir -PathType Container)){ Set-Status 'Import a native asset ZIP before starting with replacements enabled.' } else { Set-Status 'Native replacement setting saved.' $true } }); $nativeCard.Controls.Add($nativeCheck); $script:nativeModsCheck=$nativeCheck
  $importNative=New-Button 'IMPORT NATIVE ZIP' 170 $true; $importNative.Location=New-Object Drawing.Point(22,112)
  $importNative.Add_Click({ $d=New-Object Windows.Forms.OpenFileDialog; $d.Filter='Native asset pack (*.zip)|*.zip'; if($d.ShowDialog() -eq 'OK'){ try { $meta=Install-NativeModPack $d.FileName; Save-Settings; Set-Status ('Installed {0}: {1} exact-size disc asset(s). Previous pack retained for rollback.' -f $meta.name,$meta.files) $true } catch { Set-Status $_.Exception.Message } } }); $nativeCard.Controls.Add($importNative)
  $openNative=New-Button 'OPEN ACTIVE FOLDER' 170; $openNative.Location=New-Object Drawing.Point(205,112); $openNative.Add_Click({ [IO.Directory]::CreateDirectory($script:nativeModsDir) | Out-Null; Open-Folder $script:nativeModsDir }); $nativeCard.Controls.Add($openNative)
  $rollback=New-Button 'ROLL BACK' 130; $rollback.Location=New-Object Drawing.Point(388,112); $rollback.Add_Click({ try { Restore-PreviousNativeModPack; Set-Status 'Previous native pack restored. The replaced pack was retained for rollback.' $true } catch { Set-Status $_.Exception.Message } }); $nativeCard.Controls.Add($rollback)
  $metaPath=Join-Path (Join-Path (Split-Path -Parent $script:nativeModsDir) 'metadata') 'active.json'
  $nativeState=if(Test-Path -LiteralPath $metaPath){ try { $m=Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json; 'ACTIVE: {0} · {1} files' -f $m.name,$m.files } catch { 'Active folder present; pack details unavailable.' } } else { 'No native replacement pack installed.' }
  $stateLabel=New-Label $nativeState 8 $false $script:colors.muted; $stateLabel.Location=New-Object Drawing.Point(538,122); $nativeCard.Controls.Add($stateLabel)
  $script:content.Controls.Add($nativeCard)
}

function Build-SettingsPage {
  Add-SectionHeader $script:content 'Settings' 'Choose your game, controls and native options. Changes apply on the next launch.'
  $card=New-Card 30 112 (Get-ContentPageWidth) 742
  $script:discValue=$script:settings.disc; $script:dolphinValue=$script:settings.dolphin; $script:controlsValue=$script:settings.controls
  $rows=@(
    @{label='GAME IMAGE';value=$script:discValue;id='disc'},
    @{label='DOLPHIN APP';value=$script:dolphinValue;id='dolphin'},
    @{label='CONTROLS FILE (OPTIONAL)';value=$script:controlsValue;id='controls'}
  )
  $y=25
  foreach ($row in $rows) {
    $l=New-Label $row.label 8 $true $script:colors.muted; $l.Location=New-Object Drawing.Point(24,$y); $card.Controls.Add($l)
    $textY = $y + 24
    $browseY = $y + 20
    $browseX=$card.Width - 128
    $t=New-Object Windows.Forms.TextBox; $t.Text=$row.value; $t.Location=New-Object Drawing.Point(25,$textY); $t.Size=New-Object Drawing.Size(($browseX - 40),28)
    $t.BackColor=$script:colors.panel2; $t.ForeColor=$script:colors.text; $t.BorderStyle='FixedSingle'; $t.Anchor='Top,Left,Right'; $card.Controls.Add($t)
    $b=New-Button 'BROWSE' 105; $b.Location=New-Object Drawing.Point($browseX,$browseY); $b.Anchor='Top,Right'
    $id=$row.id
    $b.Add_Click({
      $d=New-Object Windows.Forms.OpenFileDialog
      if ($id -eq 'disc') { $d.Filter='Supported game images (*.iso;*.ciso)|*.iso;*.ciso|All files (*.*)|*.*' }
      elseif ($id -eq 'dolphin') { $d.Filter='Dolphin executable (Dolphin.exe)|Dolphin.exe|Executable (*.exe)|*.exe' }
      else { $d.Filter='Controller mappings (controls.txt)|controls.txt|Text files (*.txt)|*.txt|All files (*.*)|*.*' }
      if ($d.ShowDialog() -eq 'OK') { $t.Text=$d.FileName }
    }.GetNewClosure())
    $card.Controls.Add($b)
    Set-Variable -Scope Script -Name ("settings_{0}" -f $row.id) -Value $t
    $y += 82
  }
  $columnGap=18; $columnWidth=[int][Math]::Floor(($card.Width - 50 - (2*$columnGap))/3)
  $columnX=@(25,(25+$columnWidth+$columnGap),(25+2*($columnWidth+$columnGap)))
  $displayHeading=New-Label 'PICTURE & DISPLAY' 11 $true $script:colors.cyan; $displayHeading.Location=New-Object Drawing.Point(25,257); $card.Controls.Add($displayHeading)
  $scaleLabel=New-Label 'INTERNAL RESOLUTION' 8 $true $script:colors.muted; $scaleLabel.Location=New-Object Drawing.Point($columnX[0],282); $card.Controls.Add($scaleLabel)
  $script:scaleBox=New-Object Windows.Forms.ComboBox; $script:scaleBox.DropDownStyle='DropDownList'
  $script:scaleBox.Items.AddRange([object[]]@('Auto / match window','1x','1.5x','2x','3x','4x','6x'))
  $scaleValues=[double[]]@(0.0,1.0,1.5,2.0,3.0,4.0,6.0)
  $script:scaleBox.SelectedIndex=[Array]::IndexOf($scaleValues,[double]$script:scaleValue); if($script:scaleBox.SelectedIndex -lt 0){$script:scaleBox.SelectedIndex=3}
  $script:scaleBox.Location=New-Object Drawing.Point($columnX[0],306); $script:scaleBox.Size=New-Object Drawing.Size($columnWidth,30)
  Set-DarkComboBox $script:scaleBox; $card.Controls.Add($script:scaleBox)
  $aspectLabel=New-Label 'ASPECT RATIO' 8 $true $script:colors.muted; $aspectLabel.Location=New-Object Drawing.Point($columnX[1],282); $card.Controls.Add($aspectLabel)
  $script:aspectBox=New-Object Windows.Forms.ComboBox; $script:aspectBox.DropDownStyle='DropDownList'
  $script:aspectBox.Items.AddRange([object[]]@('Original 4:3','Widescreen 16:9 (experimental)','Fill window (stretch)'))
  $aspectValues=@('original','widescreen','stretch'); $script:aspectBox.SelectedIndex=[Array]::IndexOf($aspectValues,$script:aspectValue); if($script:aspectBox.SelectedIndex -lt 0){$script:aspectBox.SelectedIndex=0}
  $script:aspectBox.Location=New-Object Drawing.Point($columnX[1],306); $script:aspectBox.Size=New-Object Drawing.Size($columnWidth,30)
  Set-DarkComboBox $script:aspectBox; $card.Controls.Add($script:aspectBox)
  $aaLabel=New-Label 'ANTI-ALIASING' 8 $true $script:colors.muted; $aaLabel.Location=New-Object Drawing.Point($columnX[2],282); $card.Controls.Add($aaLabel)
  $script:aaBox=New-Object Windows.Forms.ComboBox; $script:aaBox.DropDownStyle='DropDownList'; $script:aaBox.Items.AddRange([object[]]@('Off','FXAA'))
  $script:aaBox.SelectedIndex=[Array]::IndexOf(@('off','fxaa'),$script:aaValue); if($script:aaBox.SelectedIndex -lt 0){$script:aaBox.SelectedIndex=0}
  $script:aaBox.Location=New-Object Drawing.Point($columnX[2],306); $script:aaBox.Size=New-Object Drawing.Size($columnWidth,30)
  Set-DarkComboBox $script:aaBox; $card.Controls.Add($script:aaBox)
  $filterLabel=New-Label 'OUTPUT FILTER' 8 $true $script:colors.muted; $filterLabel.Location=New-Object Drawing.Point($columnX[0],351); $card.Controls.Add($filterLabel)
  $script:filterBox=New-Object Windows.Forms.ComboBox; $script:filterBox.DropDownStyle='DropDownList'
  $script:filterBox.Items.AddRange([object[]]@('Sharp (bicubic)','Smooth (bilinear)'))
  $script:filterBox.SelectedIndex=[Array]::IndexOf(@('sharp','smooth'),$script:filterValue); if($script:filterBox.SelectedIndex -lt 0){$script:filterBox.SelectedIndex=0}
  $script:filterBox.Location=New-Object Drawing.Point($columnX[0],375); $script:filterBox.Size=New-Object Drawing.Size($columnWidth,30)
  Set-DarkComboBox $script:filterBox; $card.Controls.Add($script:filterBox)
  $dzLabel=New-Label 'STICK DEADZONE' 8 $true $script:colors.muted; $dzLabel.Location=New-Object Drawing.Point($columnX[1],351); $card.Controls.Add($dzLabel)
  $script:deadzoneBox=New-Object Windows.Forms.ComboBox; $script:deadzoneBox.DropDownStyle='DropDownList'
  $script:deadzoneBox.Items.AddRange([object[]]@('Runtime default','Off (0%)','5%','10%','15%','20%','30%'))
  $dzValues=@('','0','5','10','15','20','30'); $script:deadzoneBox.SelectedIndex=[Array]::IndexOf($dzValues,$script:deadzoneValue); if($script:deadzoneBox.SelectedIndex -lt 0){$script:deadzoneBox.SelectedIndex=0}
  $script:deadzoneBox.Location=New-Object Drawing.Point($columnX[1],375); $script:deadzoneBox.Size=New-Object Drawing.Size($columnWidth,30)
  Set-DarkComboBox $script:deadzoneBox; $card.Controls.Add($script:deadzoneBox)
  $dzNote=New-Label 'Optional steering precision.' 8 $false $script:colors.muted; $dzNote.AutoSize=$false; $dzNote.Size=New-Object Drawing.Size($columnWidth,24); $dzNote.Location=New-Object Drawing.Point($columnX[1],409); $card.Controls.Add($dzNote)
  $volumeLabel=New-Label 'MASTER VOLUME (%)' 8 $true $script:colors.muted; $volumeLabel.Location=New-Object Drawing.Point($columnX[2],351); $card.Controls.Add($volumeLabel)
  $script:volumeBox=New-Object Windows.Forms.NumericUpDown
  $script:volumeBox.Minimum=0; $script:volumeBox.Maximum=100; $script:volumeBox.Increment=5
  $script:volumeBox.Value=$script:volumeValue; $script:volumeBox.Location=New-Object Drawing.Point($columnX[2],375); $script:volumeBox.Size=New-Object Drawing.Size([Math]::Min(160,$columnWidth),30)
  $script:volumeBox.BackColor=$script:colors.panel2; $script:volumeBox.ForeColor=$script:colors.text; $card.Controls.Add($script:volumeBox)
  $aspectBadge=New-Object Windows.Forms.Label; $aspectBadge.Text='F8   TOGGLE ASPECT'; $aspectBadge.Location=New-Object Drawing.Point($columnX[0],409); $aspectBadge.Size=New-Object Drawing.Size($columnWidth,24)
  $aspectBadge.TextAlign='MiddleCenter'; $aspectBadge.BackColor=$script:colors.selection; $aspectBadge.ForeColor=$script:colors.cyan
  $aspectBadge.BorderStyle='FixedSingle'; $aspectBadge.Font=New-Object Drawing.Font('Bahnschrift SemiBold',9); $card.Controls.Add($aspectBadge)
  $filterNote=New-Label 'FXAA softens; Sharp + AA Off keeps text crisp.' 8 $false $script:colors.muted; $filterNote.AutoSize=$false; $filterNote.Size=New-Object Drawing.Size($columnWidth,30); $filterNote.Location=New-Object Drawing.Point($columnX[2],409); $card.Controls.Add($filterNote)
  $rendererRule=New-Object Windows.Forms.Panel; $rendererRule.Location=New-Object Drawing.Point(25,441); $rendererRule.Size=New-Object Drawing.Size($card.Width-50,1); $rendererRule.BackColor=$script:colors.line; $card.Controls.Add($rendererRule)
  $rendererLabel=New-Label 'RENDERER & PRESENTATION' 11 $true $script:colors.cyan; $rendererLabel.Location=New-Object Drawing.Point(25,454); $card.Controls.Add($rendererLabel)
  $script:fullscreenBox=New-Object Windows.Forms.CheckBox; $script:fullscreenBox.Text='Start fullscreen (Alt+Enter to toggle)'
  $script:fullscreenBox.Checked=$script:fullscreenValue; $script:fullscreenBox.Location=New-Object Drawing.Point(25,481); $script:fullscreenBox.AutoSize=$true; $script:fullscreenBox.ForeColor=$script:colors.text; $card.Controls.Add($script:fullscreenBox)
  $script:vsyncBox=New-Object Windows.Forms.CheckBox; $script:vsyncBox.Text='Prevent screen tearing (VSync)'
  $script:vsyncBox.Checked=$script:vsyncValue; $script:vsyncBox.Location=New-Object Drawing.Point(355,481); $script:vsyncBox.AutoSize=$true; $script:vsyncBox.ForeColor=$script:colors.text; $card.Controls.Add($script:vsyncBox)
  $audioTitle=New-Label 'AUDIO & INPUT' 11 $true $script:colors.cyan; $audioTitle.Location=New-Object Drawing.Point(25,518); $card.Controls.Add($audioTitle)
  $script:muteBox=New-Object Windows.Forms.CheckBox; $script:muteBox.Text='Mute game music'; $script:muteBox.Checked=[bool]$script:settings.muteMusic
  $script:muteBox.Location=New-Object Drawing.Point(25,546); $script:muteBox.AutoSize=$true; $script:muteBox.ForeColor=$script:colors.text; $card.Controls.Add($script:muteBox)
  $script:logBox=New-Object Windows.Forms.CheckBox; $script:logBox.Text='Record controller input for diagnostics'; $script:logBox.Checked=[bool]$script:settings.inputLog
  $script:logBox.Location=New-Object Drawing.Point(215,546); $script:logBox.AutoSize=$true; $script:logBox.ForeColor=$script:colors.text; $card.Controls.Add($script:logBox)
  $save=New-Button 'SAVE SETTINGS' 155 $true; $save.Location=New-Object Drawing.Point(25,582)
  $save.Add_Click({
    $script:discValue=$script:settings_disc.Text; $script:dolphinValue=$script:settings_dolphin.Text; $script:controlsValue=$script:settings_controls.Text
    $scaleOptions=[double[]]@(0.0,1.0,1.5,2.0,3.0,4.0,6.0); $script:scaleValue=$scaleOptions[$script:scaleBox.SelectedIndex]
    $aspectOptions=@('original','widescreen','stretch'); $script:aspectValue=$aspectOptions[$script:aspectBox.SelectedIndex]
    $aaOptions=@('off','fxaa'); $script:aaValue=$aaOptions[$script:aaBox.SelectedIndex]
    $filterOptions=@('sharp','smooth'); $script:filterValue=$filterOptions[$script:filterBox.SelectedIndex]
    $script:muteValue=$script:muteBox.Checked; $script:logValue=$script:logBox.Checked
    $script:fullscreenValue=$script:fullscreenBox.Checked; $script:vsyncValue=$script:vsyncBox.Checked; $script:volumeValue=[int]$script:volumeBox.Value
    $dzOptions=@('','0','5','10','15','20','30'); $script:deadzoneValue=$dzOptions[$script:deadzoneBox.SelectedIndex]
    Save-Settings; Set-Status 'Settings saved.' $true
  }); $card.Controls.Add($save)
  $controllerRule=New-Object Windows.Forms.Panel; $controllerRule.Location=New-Object Drawing.Point(25,634); $controllerRule.Size=New-Object Drawing.Size($card.Width-50,1); $controllerRule.BackColor=$script:colors.line; $card.Controls.Add($controllerRule)
  $controllerTitle=New-Label 'CONTROLLER DETECTOR' 12 $true $script:colors.cyan
  $controllerTitle.Location=New-Object Drawing.Point(25,646); $card.Controls.Add($controllerTitle)
  $controllerText=New-Label 'Press a pad button or move an axis; detected SDL names can be used in your optional controls mapping.' 9 $false $script:colors.muted
  $controllerText.Location=New-Object Drawing.Point(25,673); $card.Controls.Add($controllerText)
  $detect=New-Button 'DETECT CONTROLLER' 190 $true; $detect.Location=New-Object Drawing.Point(25,700)
  $detect.Add_Click({ Start-ControllerDetector }); $card.Controls.Add($detect)
  $viewLog=New-Button 'VIEW LAST RESULTS' 168; $viewLog.Location=New-Object Drawing.Point(231,700)
  $viewLog.Add_Click({ Open-ControllerLog }); $card.Controls.Add($viewLog)
  $editControls=New-Button 'CREATE / EDIT MAPPING' 190; $editControls.Location=New-Object Drawing.Point(414,700)
  $editControls.Add_Click({ Open-ControlsFile }); $card.Controls.Add($editControls)
  $script:content.Controls.Add($card)
}

function Build-AboutPage {
  Add-SectionHeader $script:content 'About this project' 'A community-built native recompilation prototype for Star Fox Assault.'
  $pageWidth=Get-ContentPageWidth
  $card=New-Card 30 112 $pageWidth 500
  $heading=New-Label $script:launcherBrand.ToUpperInvariant() 22 $true $script:colors.cyan; $heading.Location=New-Object Drawing.Point(25,24); $card.Controls.Add($heading)
  $release=New-Label 'Version 0.2.0-rc.3 · native build prototype · validation is ongoing' 11 $true $script:colors.text; $release.Location=New-Object Drawing.Point(27,68); $card.Controls.Add($release)
  $body=New-Label ("{0} is the launcher brand for {1}, an independent fan project. It can inspect your own USA ISO/CISO, prepare its portable build tools, compile the native application, and keep launcher settings and runtime data in this project folder. Your game image is read in place and is never copied, patched, or modified." -f $script:launcherBrand,$script:projectTitle) 10 $false $script:colors.muted
  $body.Location=New-Object Drawing.Point(27,112); $body.MaximumSize=New-Object Drawing.Size(($pageWidth-80),68); $body.AutoSize=$true; $card.Controls.Add($body)
  $limit=New-Label 'Known limitation: the current native runtime has not been verified through a complete playthrough and is known to fail during a boss encounter. This is not a finished or fully compatible game release.' 10 $false $script:colors.text
  $limit.Location=New-Object Drawing.Point(27,196); $limit.MaximumSize=New-Object Drawing.Size(($pageWidth-80),65); $limit.AutoSize=$true; $limit.ForeColor=$script:colors.text; $card.Controls.Add($limit)
  $legal=New-Label ("You provide your own game image. No game image or Nintendo game assets are included. This community project is not affiliated with or endorsed by Nintendo or Namco. {0} is an unregistered project brand." -f $script:launcherBrand) 10 $false $script:colors.muted
  $legal.Location=New-Object Drawing.Point(27,275); $legal.MaximumSize=New-Object Drawing.Size(($pageWidth-80),55); $legal.AutoSize=$true; $card.Controls.Add($legal)
  $credits=New-Label 'Artwork: original generated concept art; its prompt and provenance are included beside the asset. App icon: original launcher artwork. Runtime fonts: replacement fonts based on Droid Sans, Copyright 2006–2014 Google Corporation, Apache License 2.0.' 9 $false $script:colors.muted
  $credits.Location=New-Object Drawing.Point(27,344); $credits.MaximumSize=New-Object Drawing.Size(($pageWidth-80),52); $credits.AutoSize=$true; $card.Controls.Add($credits)
  $notice=New-Button 'VIEW THIRD-PARTY NOTICES' 220; $notice.Location=New-Object Drawing.Point(27,422)
  $notice.Add_Click({ $noticePath=Join-Path $script:projectDir 'THIRD_PARTY_NOTICES.md'; if(Test-Path -LiteralPath $noticePath){Start-Process notepad.exe -ArgumentList (ConvertTo-NativeArgument $noticePath)|Out-Null}else{Set-Status 'Third-party notice file is missing from this package.'} }); $card.Controls.Add($notice)
  $notes=New-Button 'VIEW RELEASE NOTES' 180; $notes.Location=New-Object Drawing.Point(265,422)
  $notes.Add_Click({ $notesPath=Join-Path $script:projectDir 'RELEASE-NOTES.md'; if(Test-Path -LiteralPath $notesPath){Start-Process notepad.exe -ArgumentList (ConvertTo-NativeArgument $notesPath)|Out-Null}else{Set-Status 'Release notes file is missing from this package.'} }); $card.Controls.Add($notes)
  $folder=New-Button 'OPEN PROJECT FOLDER' 190; $folder.Location=New-Object Drawing.Point(464,422)
  $folder.Add_Click({ Open-Folder $script:projectDir }); $card.Controls.Add($folder)
  $script:content.Controls.Add($card)
}

Show-Page 'Home'
[void]$script:form.ShowDialog()

