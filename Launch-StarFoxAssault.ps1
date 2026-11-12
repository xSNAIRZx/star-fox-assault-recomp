# Star Fox Assault Recomp launcher. The UI is original; game assets remain user supplied.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
# Declare DPI awareness before any window exists, so Windows renders text at the display's real
# resolution instead of stretching a 96-DPI bitmap (which blurs everything at 125% and above).
# Layout is written in 96-DPI units and scaled once per page by Set-UiScale.
try {
  Add-Type -Namespace PeregrineForge -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[StructLayout(LayoutKind.Sequential)] public struct XInputGamepad { public ushort wButtons; public byte bLeftTrigger; public byte bRightTrigger; public short sThumbLX; public short sThumbLY; public short sThumbRX; public short sThumbRY; }
[StructLayout(LayoutKind.Sequential)] public struct XInputState { public uint dwPacketNumber; public XInputGamepad Gamepad; }
[DllImport("xinput1_4.dll")] public static extern int XInputGetState(int userIndex, out XInputState state);
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
'@
  [void][PeregrineForge.Native]::SetProcessDPIAware()
} catch {}
$script:uiScale = 1.0
try { $dpiProbe = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero); try { $script:uiScale = [Math]::Max(1.0,$dpiProbe.DpiX / 96.0) } finally { $dpiProbe.Dispose() } } catch {}
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
$script:updateState = @{ Process=$null; Timer=$null }
$script:currentPage = 'Home'
$script:startupNotice = $null
$script:sourceFreshness = $null
$script:sessionLogKeep = 20
[IO.Directory]::CreateDirectory($script:appDir) | Out-Null
if ($script:portableMode -and -not (Test-Path -LiteralPath $script:settingsPath -PathType Leaf) -and (Test-Path -LiteralPath $script:legacySettingsPath -PathType Leaf)) {
  try { Copy-Item -LiteralPath $script:legacySettingsPath -Destination $script:settingsPath -ErrorAction Stop } catch {}
}

# Logic kept free of WinForms so tools/Test-LauncherCore.ps1 can test it without opening this
# window: settings schema, build progress, pre-flight and failure reports (LauncherCore),
# native build status (LauncherNative) and save backups (LauncherSaves).
foreach ($launcherModule in @('LauncherCore.ps1','LauncherNative.ps1','LauncherSaves.ps1')) {
  $launcherModulePath = Join-Path $script:projectDir ('tools\' + $launcherModule)
  if (-not (Test-Path -LiteralPath $launcherModulePath -PathType Leaf)) {
    [Windows.Forms.MessageBox]::Show(('A launcher file is missing: {0}{1}{1}Reinstall the complete launcher package.' -f $launcherModulePath,[Environment]::NewLine),'Peregrine Forge','OK','Error') | Out-Null
    exit 1
  }
  . $launcherModulePath
}

$script:settings = Get-LauncherSettingDefaults
if (Test-Path -LiteralPath $script:settingsPath) {
  try {
    $saved = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
    if ($null -eq $saved) { throw 'The settings file is empty.' }
    $script:settings = Read-LauncherSettings $saved
  } catch {
    # Keep the unreadable profile for inspection instead of silently overwriting it on the
    # next save, and tell the user once the window is up.
    $script:startupNotice = 'Settings file was unreadable; defaults loaded.'
    try {
      $corruptPath = Join-Path $script:appDir ('settings.corrupt-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
      Move-Item -LiteralPath $script:settingsPath -Destination $corruptPath -ErrorAction Stop
      $script:startupNotice = 'Settings file was unreadable; defaults loaded. Old copy kept as {0}.' -f (Split-Path -Leaf $corruptPath)
    } catch {}
  }
}
# Read-LauncherSettings has already replaced every missing or invalid value with its default.
$script:discValue = [string]$script:settings.disc
$script:dolphinValue = [string]$script:settings.dolphin
$script:controlsValue = [string]$script:settings.controls
$script:scaleValue = [double]$script:settings.scale
$script:aspectValue = [string]$script:settings.aspect
$script:aaValue = [string]$script:settings.aa
$script:filterValue = [string]$script:settings.filter
$script:deadzoneValue = [string]$script:settings.deadzone
$script:muteValue = [bool]$script:settings.muteMusic
$script:logValue = [bool]$script:settings.inputLog
$script:nativeModsValue = [bool]$script:settings.nativeMods
$script:fullscreenValue = [bool]$script:settings.fullscreen
$script:vsyncValue = [bool]$script:settings.vsync
$script:volumeValue = [int]$script:settings.volume
$script:anisotropyValue = [string]$script:settings.anisotropy
$script:trilinearValue = [bool]$script:settings.trilinear
$script:softParticlesValue = [bool]$script:settings.softParticles
$script:hdTexturesValue = [bool]$script:settings.hdTextures
$script:dumpTexturesValue = [bool]$script:settings.dumpTextures
# HD texture packs (runtime gx/texture_pack.h): the installed pack, the one it replaced, and
# where the texture dump for making packs goes.
$script:hdTextureRoot = Join-Path $script:projectDir 'user-data\hd-textures'
$script:hdTextureDir = Join-Path $script:hdTextureRoot 'active'
$script:textureDumpDir = Join-Path $script:projectDir 'user-data\texture-dump'

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
# Bahnschrift ships with Windows 10 1709 and later, but trimmed or older installs can lack it,
# and GDI+ would then fall back to Microsoft Sans Serif. Prefer Segoe UI Semibold instead.
$script:headingFontName = 'Bahnschrift SemiBold'
try {
  $installedFonts = [Drawing.Text.InstalledFontCollection]::new()
  try { $installedNames = @($installedFonts.Families | ForEach-Object { $_.Name }) } finally { $installedFonts.Dispose() }
  if ($installedNames -notcontains 'Bahnschrift SemiBold' -and $installedNames -notcontains 'Bahnschrift') { $script:headingFontName = 'Segoe UI Semibold' }
} catch {}
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
  $script:settings.anisotropy = [string]$script:anisotropyValue
  $script:settings.trilinear = [bool]$script:trilinearValue
  $script:settings.softParticles = [bool]$script:softParticlesValue
  $script:settings.hdTextures = [bool]$script:hdTexturesValue
  $script:settings.dumpTextures = [bool]$script:dumpTexturesValue
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
  # Without this, '&' is taken as a keyboard-shortcut marker and disappears ("SYSTEMS  CONTROLS").
  $l.UseMnemonic = $false
  $l.Text = $text
  $l.AutoSize = $true
  $fontSize = [Math]::Max(8,$size)
  $fontFamily = if ($bold -or $fontSize -ge 20) { $script:headingFontName } else { 'Segoe UI' }
  $l.Font = New-Object Drawing.Font($fontFamily, $fontSize, [Drawing.FontStyle]::Regular)
  $l.ForeColor = if ($null -eq $color -or $color.IsEmpty) { $script:colors.text } else { $color }
  $l.BackColor = [Drawing.Color]::Transparent
  return $l
}
function New-Button([string]$text, [int]$width = 150, [bool]$primary = $false) {
  $b = New-Object Windows.Forms.Button
  $b.UseMnemonic = $false
  $b.Text = $text
  $b.TextAlign = 'MiddleCenter'
  # WinForms draws disabled flat buttons with near-black text on this palette; repaint them so
  # the label stays readable while still looking unavailable.
  $b.Add_Paint({
    param($sender,$e)
    if ($sender.Enabled) { return }
    $back = [Drawing.SolidBrush]::new($script:colors.panel)
    $border = [Drawing.Pen]::new($script:colors.steelShade,1)
    try {
      $e.Graphics.FillRectangle($back,$sender.ClientRectangle)
      $e.Graphics.DrawRectangle($border,0,0,$sender.Width - 1,$sender.Height - 1)
      $flags = [Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [Windows.Forms.TextFormatFlags]::VerticalCenter -bor [Windows.Forms.TextFormatFlags]::NoPrefix -bor [Windows.Forms.TextFormatFlags]::SingleLine
      [Windows.Forms.TextRenderer]::DrawText($e.Graphics,$sender.Text,$sender.Font,$sender.ClientRectangle,$script:colors.line,$flags)
    } finally { $back.Dispose(); $border.Dispose() }
  })
  $b.Size = New-Object Drawing.Size($width, 40)
  $b.FlatStyle = 'Flat'
  $b.UseVisualStyleBackColor = $false
  $b.FlatAppearance.BorderSize = 1
  $b.FlatAppearance.BorderColor = if ($primary) { $script:colors.cyan } else { $script:colors.line }
  $b.BackColor = if ($primary) { [Drawing.Color]::FromArgb(10,104,119) } else { $script:colors.panel2 }
  $b.FlatAppearance.MouseOverBackColor = if ($primary) { [Drawing.Color]::FromArgb(12,126,142) } else { [Drawing.Color]::FromArgb(20,56,65) }
  $b.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(10,82,94)
  $b.ForeColor = $script:colors.text
  $b.Font = New-Object Drawing.Font($script:headingFontName, 10)
  $b.Cursor = [Windows.Forms.Cursors]::Hand
  # Flat buttons draw no focus cue, so keyboard and controller users could not see where they
  # were. A focused button gets a brighter, thicker border.
  $restBorder = $b.FlatAppearance.BorderColor
  $b.Add_GotFocus({ $this.FlatAppearance.BorderColor = $script:colors.text; $this.FlatAppearance.BorderSize = 2 })
  $b.Add_LostFocus({ $this.FlatAppearance.BorderColor = $restBorder; $this.FlatAppearance.BorderSize = 1 }.GetNewClosure())
  return $b
}
# 96-DPI layout units to physical pixels, for code that runs after a page has been scaled.
function Get-Px([double]$value) { return [int][Math]::Round($value * $script:uiScale) }
# Scales a control tree built in 96-DPI units. Call once per tree, after it is fully built.
function Set-UiScale($control) {
  if ($script:uiScale -gt 1.0) { $control.Scale([Drawing.SizeF]::new([single]$script:uiScale,[single]$script:uiScale)) }
}
# A progress bar in the launcher's colours: the stock control draws Windows' green on white
# whatever its colours say. State is in .Tag: Value (0-100), Marquee (a block sweeping while
# a phase reports no percentage) and Failed (red). Call .Invalidate() after changing it.
function New-ThemedProgressBar([int]$w, [int]$h) {
  $p = New-Object Windows.Forms.Panel
  $p.Size = New-Object Drawing.Size($w,$h); $p.BackColor = $script:colors.panel2
  $p.GetType().GetProperty('DoubleBuffered',[Reflection.BindingFlags]'Instance,NonPublic').SetValue($p,$true,$null)
  $p.Tag = @{ Value = 0; Marquee = $true; Failed = $false; Offset = 0.0 }
  $fill = $script:colors.cyan; $failed = $script:colors.red; $edge = $script:colors.line
  $p.Add_Paint({
    param($sender,$e)
    $st = $sender.Tag; $w = $sender.ClientSize.Width; $h = $sender.ClientSize.Height
    $brush = [Drawing.SolidBrush]::new($(if ($st.Failed) { $failed } else { $fill }))
    $pen = [Drawing.Pen]::new($edge,1)
    try {
      if ($st.Marquee) {
        $block = [int]($w * 0.22); $x = [int](($st.Offset % 1.0) * ($w + $block)) - $block
        $e.Graphics.FillRectangle($brush,[Math]::Max(0,$x),0,[Math]::Min($block,$w - [Math]::Max(0,$x)) + [Math]::Min(0,$x),$h)
      } else {
        $e.Graphics.FillRectangle($brush,0,0,[int]($w * [Math]::Max(0,[Math]::Min(100,$st.Value)) / 100),$h)
      }
      $e.Graphics.DrawRectangle($pen,0,0,$w - 1,$h - 1)
    } finally { $brush.Dispose(); $pen.Dispose() }
  }.GetNewClosure())
  $sweep = New-Object Windows.Forms.Timer; $sweep.Interval = 40
  $sweep.Add_Tick({ if ($p.Tag.Marquee) { $p.Tag.Offset += 0.018; $p.Invalidate() } }.GetNewClosure())
  $p.Add_Disposed({ $sweep.Stop(); $sweep.Dispose() }.GetNewClosure())
  $sweep.Start()
  return $p
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
  $combo.ItemHeight = Get-Px 22
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
function Get-LatestSourceWriteUtc {
  # Cached for the launcher session; cleared after a build or a local package update.
  if ($null -eq $script:sourceFreshness) { $script:sourceFreshness = Get-NativeSourceWriteUtc $script:projectDir }
  return $script:sourceFreshness
}
function Reset-NativeStatusCache { $script:sourceFreshness = $null }
function Get-NativeStatus {
  # Returns NOT BUILT, REBUILD REQUIRED or READY. $script:nativeStatusReason explains a rebuild.
  $result = Get-NativeBuildStatus $script:nativePath (Read-NativeBuildRecord $script:projectDir) ([string]$script:discValue) { Get-LatestSourceWriteUtc }
  $script:nativeStatusReason = $result.Reason
  return $result.Status
}
function Get-RunningNativeGame { return (Get-NativeGameProcess $script:nativePath) }
function Test-NativeBuildImage([string]$imagePath) { return (Test-NativeBuildForImage $script:nativePath (Read-NativeBuildRecord $script:projectDir) $imagePath) }
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
function Get-PlaytimeText {
  $seconds = 0.0
  $historyDir = Join-Path $script:projectDir 'user-data\play-history'
  # Sessions started from RecompLauncher have a log but no tracker record; count them from
  # their [session] lines. A session still running is left until it ends.
  $skip = @()
  if (Get-RunningNativeGame) {
    $newest = Get-ChildItem -LiteralPath (Join-Path $script:nativeRunDir 'logs') -Filter 'native-*.log' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($newest) { $skip = @([IO.Path]::GetFileNameWithoutExtension($newest.Name)) }
  }
  try { [void](Sync-PlayHistoryFromSessionLogs (Join-Path $script:nativeRunDir 'logs') $historyDir $skip) } catch {}
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
function Invoke-WithProcessEnvironment([System.Collections.IDictionary]$variables, [scriptblock]$action) {
  # Start-Process passes the launcher's own environment to the child, so set the session's
  # variables for the duration of the start only and always put the previous values back.
  $previous = @{}
  foreach ($name in $variables.Keys) { $previous[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
  try {
    foreach ($name in $variables.Keys) { [Environment]::SetEnvironmentVariable($name,$variables[$name],'Process') }
    & $action
  } finally {
    foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name,$previous[$name],'Process') }
  }
}
function Remove-OldSessionLogs([string]$logsDir) {
  # Each launch adds native-<stamp>-<id>.log/.err (and a .ram.bin when the game dumps memory).
  # Keep the newest sessions plus the newest sessions whose error log recorded a guard,
  # vertex-check or fatal line, so crash evidence outlives ordinary play.
  try {
    $sessions = @(Get-ChildItem -LiteralPath $logsDir -File -Filter 'native-*' -ErrorAction Stop |
      Group-Object { $_.Name -replace '\.(log|err|ram\.bin)$','' } |
      Sort-Object Name -Descending)  # names start with a sortable native-yyyyMMdd-HHmmss-fff stamp
    if ($sessions.Count -le $script:sessionLogKeep) { return }
    $flaggedKept = 0
    foreach ($session in ($sessions | Select-Object -Skip $script:sessionLogKeep)) {
      $err = $session.Group | Where-Object { $_.Extension -eq '.err' } | Select-Object -First 1
      $flagged = $err -and (Select-String -LiteralPath $err.FullName -Pattern '\[guard\]|\[vertcheck\]|\[thread-watch\]|fatal' -List -Quiet -ErrorAction SilentlyContinue)
      if ($flagged -and $flaggedKept -lt $script:sessionLogKeep) { $flaggedKept++; continue }
      foreach ($file in $session.Group) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue }
    }
  } catch {}
}
function Start-NativeGame {
  try {
    if (Get-RunningNativeGame) { throw 'The native game is already running. Close it before starting another session.' }
    if (-not (Test-Path -LiteralPath $script:nativePath -PathType Leaf)) { throw 'Build the native app first with Build / Update.' }
    $info = Test-GameImage $script:discValue
    if (-not (Test-NativeBuildImage $script:discValue)) { throw 'This native build does not match the selected game image, or its build record is missing. Rebuild from the selected image before playing.' }
    Save-Settings
    [IO.Directory]::CreateDirectory($script:nativeRunDir) | Out-Null
    # Save-Settings has just copied every setting into $script:settings.
    $nativeArgs = Get-NativeSessionArgumentList $script:settings $script:hdTextureDir $script:textureDumpDir
    $logsDir = Join-Path $script:nativeRunDir 'logs'
    [IO.Directory]::CreateDirectory($logsDir) | Out-Null
    Remove-OldSessionLogs $logsDir
    $sessionName = 'native-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'),([Guid]::NewGuid().ToString('N').Substring(0,6))
    $stderr = Join-Path $logsDir ($sessionName + '.err')
    $stdout = Join-Path $logsDir ($sessionName + '.log')
    $ramDump = Join-Path $logsDir ($sessionName + '.ram.bin')
    $modsDir = ''
    if($script:nativeModsValue) {
      if(-not(Test-Path -LiteralPath $script:nativeModsDir -PathType Container)){throw 'Install a native asset pack before enabling native mods.'}
      $modsDir = $script:nativeModsDir
    }
    $sessionEnv = Get-NativeSessionEnvironment $script:projectDir $ramDump $modsDir
    $gameProcess = Invoke-WithProcessEnvironment $sessionEnv {
      Start-Process -FilePath $script:nativePath -ArgumentList $nativeArgs -WorkingDirectory $script:nativeRunDir -RedirectStandardError $stderr -RedirectStandardOutput $stdout -PassThru
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
  return Get-NativeGraphicsArgumentList $script:scaleValue $script:aspectValue $script:aaValue $script:filterValue
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
# Checks the things that would otherwise fail minutes into a build. Returns $true to go ahead.
function Confirm-BuildPreflight {
  if ($script:form) { $script:form.UseWaitCursor = $true }
  Set-Status 'Checking disk space, folder access and tool downloads…' $true
  try { $issues = Get-BuildPreflightIssues (Get-BuildPreflightFacts $script:projectDir) }
  finally { if ($script:form) { $script:form.UseWaitCursor = $false } }
  if (-not $issues.Count) { return $true }
  $blocking = @($issues | Where-Object { $_.Severity -eq 'block' })
  $lines = ($issues | ForEach-Object { '• ' + $_.Message }) -join ([Environment]::NewLine + [Environment]::NewLine)
  if ($blocking.Count) {
    Set-Status ('Build not started · {0}' -f $blocking[0].Message)
    [Windows.Forms.MessageBox]::Show($script:form,$lines,'Build cannot start yet','OK','Warning') | Out-Null
    return $false
  }
  $answer = [Windows.Forms.MessageBox]::Show($script:form,($lines + [Environment]::NewLine + [Environment]::NewLine + 'Start the build anyway?'),'Before you build','YesNo','Warning','Button2')
  if ($answer -ne [Windows.Forms.DialogResult]::Yes) { Set-Status 'Build not started.'; return $false }
  return $true
}
function Get-LauncherVersionText {
  try { return [string]((Get-Content -LiteralPath (Join-Path $script:projectDir 'release.json') -Raw | ConvertFrom-Json).version) } catch { return 'unknown' }
}
function Start-NativeBuild {
  try {
    $null = Test-GameImage $script:discValue
    Save-Settings
    if ($script:buildState.Process -and -not $script:buildState.Process.HasExited) { Set-Status 'A native build is already running.'; return }
    if ($script:updateState.Process -and -not $script:updateState.Process.HasExited) { Set-Status 'Wait for the local package update to finish before building.'; return }
    if (-not (Confirm-BuildPreflight)) { return }
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
    $bar = New-ThemedProgressBar 640 26; $bar.Location = New-Object Drawing.Point(27,94); $dialog.Controls.Add($bar)
    $progressText = New-Label 'STEP 1 OF 5  ·  CHECKING GAME IMAGE' 9 $true $script:colors.cyan
    $progressText.AutoSize = $false; $progressText.Location = New-Object Drawing.Point(27,130); $progressText.Size = New-Object Drawing.Size(400,22); $dialog.Controls.Add($progressText)
    $timeText = New-Label 'TOTAL 0:00' 9 $false $script:colors.muted
    $timeText.AutoSize = $false; $timeText.TextAlign = 'MiddleRight'; $timeText.Location = New-Object Drawing.Point(430,130); $timeText.Size = New-Object Drawing.Size(237,22); $dialog.Controls.Add($timeText)
    $safetyText = New-Label 'The original game image and existing saves are kept unchanged.' 9 $false $script:colors.muted
    $safetyText.Location = New-Object Drawing.Point(27,164); $safetyText.Size = New-Object Drawing.Size(490,22); $dialog.Controls.Add($safetyText)
    $cancel = New-Button 'CANCEL BUILD' 135; $cancel.Location = New-Object Drawing.Point(532,163); $dialog.Controls.Add($cancel)
    $dialog.CancelButton = $cancel  # Esc cancels the build, or closes the dialog once it is done
    if ($script:formIcon) { $dialog.Icon = $script:formIcon }
    # Shown only when the build fails: the stage, the first errors and ways to share them.
    $errorBox = New-Object Windows.Forms.TextBox; $errorBox.Multiline = $true; $errorBox.ReadOnly = $true; $errorBox.WordWrap = $true; $errorBox.ScrollBars = 'Vertical'
    $errorBox.Location = New-Object Drawing.Point(27,206); $errorBox.Size = New-Object Drawing.Size(640,150); $errorBox.BorderStyle = 'FixedSingle'
    $errorBox.BackColor = $script:colors.panel2; $errorBox.ForeColor = $script:colors.text; $errorBox.Font = New-Object Drawing.Font('Consolas',9); $errorBox.Visible = $false; $dialog.Controls.Add($errorBox)
    $openLog = New-Button 'OPEN LOG' 125; $openLog.Location = New-Object Drawing.Point(27,368); $openLog.Visible = $false; $dialog.Controls.Add($openLog)
    $copyReport = New-Button 'COPY REPORT' 140; $copyReport.Location = New-Object Drawing.Point(164,368); $copyReport.Visible = $false; $dialog.Controls.Add($copyReport)
    $openJob = New-Button 'OPEN JOB FOLDER' 165; $openJob.Location = New-Object Drawing.Point(316,368); $openJob.Visible = $false; $dialog.Controls.Add($openJob)
    $track = @{ Start = [DateTime]::UtcNow; PhaseKey = ''; PhaseStart = [DateTime]::UtcNow; LastActivePhase = ''; Report = '' }
    $openLog.Add_Click({ try { Start-Process -FilePath (Join-Path $env:SystemRoot 'notepad.exe') -ArgumentList (ConvertTo-NativeArgument $stdoutPath) | Out-Null } catch { $detail.Text = $_.Exception.Message } }.GetNewClosure())
    $openJob.Add_Click({ Open-Folder $jobDir }.GetNewClosure())
    $copyReport.Add_Click({
      try { [Windows.Forms.Clipboard]::SetText($track.Report); $copyReport.Text = 'COPIED' }
      catch { $detail.Text = 'Could not copy the report: ' + $_.Exception.Message }
    }.GetNewClosure())
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
        $now = [DateTime]::UtcNow
        if ($state) {
          $message.Text = [string]$state.message
          $detail.Text = [string]$state.phase
          $phaseName = [string]$state.phase
          $step = Get-BuildPhaseStep $phaseName
          # Both tool-preparation phase names are step 2, so they share one phase timer.
          $phaseKey = if ($step -gt 0) { 'step' + $step } else { $phaseName }
          if ($phaseKey -ne $track.PhaseKey) { $track.PhaseKey = $phaseKey; $track.PhaseStart = $now }
          if ($step -gt 0 -and $phaseName -ne 'Ready to play') { $track.LastActivePhase = $phaseName }
          $stepText = if($step -gt 0){'STEP {0} OF 5  ·  {1}' -f $step,$phaseName.ToUpperInvariant()}else{$phaseName.ToUpperInvariant()}
          if ($null -ne $state.percent) {
            $overallPercent = Get-BuildOverallPercent $phaseName $state.percent
            $bar.Tag.Marquee=$false; $bar.Tag.Value=[Math]::Max($bar.Tag.Value,[Math]::Min(99,$overallPercent)); $bar.Invalidate()
            $progressText.Text = '{0}  ·  {1}%' -f $stepText,$overallPercent
          } else {
            $bar.Tag.Marquee=$true
            $progressText.Text = if($step -gt 0){$stepText + '  ·  WORKING'}else{$stepText}
          }
        }
        $timeText.Text = if ($track.PhaseKey) { 'PHASE {0}  ·  TOTAL {1}' -f (Format-Elapsed ($now - $track.PhaseStart)),(Format-Elapsed ($now - $track.Start)) } else { 'TOTAL ' + (Format-Elapsed ($now - $track.Start)) }
        if ($buildState.Process.HasExited) {
          $timeText.Text = 'TOTAL ' + (Format-Elapsed ($now - $track.Start))
          $timer.Stop(); $timer.Dispose()
          $buildState.Process.WaitForExit()
          $buildState.Process.Refresh()
          $exitCode = $buildState.Process.ExitCode
          $buildState.Process.Dispose(); $buildState.Process = $null
          $nativeOutputExists = Test-Path -LiteralPath $nativePath -PathType Leaf
          $success = ($exitCode -eq 0 -and $state -and $state.state -eq 'succeeded' -and $nativeOutputExists)
          if ($success) { $message.Text='Native build completed'; $detail.Text='The game image and existing saves were left unchanged.'; $bar.Tag.Marquee=$false; $bar.Tag.Value=100; $bar.Invalidate(); $progressText.Text='BUILD COMPLETE  ·  100%'; $progressText.ForeColor=$colors.green; $statusLabel.Text='Native build ready.'; $statusLabel.ForeColor=$colors.green; Reset-NativeStatusCache; if($navButtons.ContainsKey('Home')){Build-PageRefresh} }
          else {
            $phase = if($state -and $state.state -in @('failed','cancelled')){[string]$state.state}else{'worker stopped'}
            $bar.Tag.Marquee=$false; $bar.Tag.Failed=($phase -ne 'cancelled'); $bar.Invalidate(); $progressText.Text=if($phase -eq 'cancelled'){'BUILD CANCELLED'}else{'BUILD FAILED'}; $progressText.ForeColor=$colors.red
            if ($phase -eq 'cancelled') {
              $message.Text = 'Build cancelled'
              $detail.Text = "Details are saved in $jobDir"
            } else {
              # Name the stage that failed and its first errors, instead of only a folder path.
              $failedPhase = if ($track.LastActivePhase) { $track.LastActivePhase } else { 'Starting the build worker' }
              $reason = if ($state -and $state.state -eq 'failed' -and $state.message) { [string]$state.message } else { "The build worker stopped (exit $exitCode) without reporting a result." }
              $stdoutLines = @(); $stderrLines = @()
              try { $stdoutLines = [IO.File]::ReadAllLines($stdoutPath) } catch {}
              try { $stderrLines = [IO.File]::ReadAllLines($stderrPath) } catch {}
              $errorLines = Get-BuildErrorLines $stdoutLines $stderrLines 5 @($reason)
              $message.Text = 'Build failed while: ' + $failedPhase.ToLowerInvariant()
              $detail.Text = $reason
              $nl = [Environment]::NewLine
              $errorText = if ($errorLines.Count) { 'First errors:' + $nl + (($errorLines | ForEach-Object { '  ' + $_ }) -join $nl) } else { 'No compiler or tool error line was recognised; open the log for the full output.' }
              $errorBox.Text = $errorText + $nl + $nl + 'Full logs: ' + $jobDir
              $tail = @($stdoutLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 30) + @($stderrLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 10)
              $replacements = @{}
              if ($script:discValue) { $replacements[[string]$script:discValue] = '<game image>' }
              $replacements[[string]$script:projectDir] = '<launcher folder>'
              if ($env:USERPROFILE) { $replacements[[string]$env:USERPROFILE] = '%USERPROFILE%' }
              $track.Report = New-BuildFailureReport @{
                Version = (Get-LauncherVersionText); OsVersion = [Environment]::OSVersion.VersionString
                Phase = $failedPhase; Message = $reason; ExitCode = $exitCode
                Elapsed = (Format-Elapsed ($now - $track.Start)); Errors = $errorLines; Tail = $tail
              } $replacements
              $dialog.Size = New-Object Drawing.Size((Get-Px 700),(Get-Px 460))
              $errorBox.Visible = $true; $openLog.Visible = $true; $copyReport.Visible = $true; $openJob.Visible = $true
            }
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
    Set-UiScale $dialog; $timer.Start(); $dialog.Show($script:form) | Out-Null
    Set-Status 'Building native game…' $true
  } catch { Set-Status $_.Exception.Message }
}
function Build-PageRefresh {
  $page = if ($script:currentPage) { [string]$script:currentPage } else { 'Home' }
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
  if ($script:updateState.Process -and -not $script:updateState.Process.HasExited) { Set-Status 'A local package update is already being installed.'; return }
  if ($script:buildState.Process -and -not $script:buildState.Process.HasExited) { Set-Status 'Wait for the native build to finish before installing a package.'; return }
  $dialog = New-Object Windows.Forms.OpenFileDialog
  $dialog.Title = 'Choose a local Star Fox Assault prototype package'
  $dialog.Filter = 'Prototype update package (*.zip)|*.zip'
  $dialog.CheckFileExists = $true
  try {
    if ($dialog.ShowDialog($script:form) -ne [Windows.Forms.DialogResult]::OK) { return }
    $archivePath = $dialog.FileName
  } finally { $dialog.Dispose() }
  try {
    # Run the installer as its own process, like the build worker, so extracting and hashing a
    # large package never freezes the launcher window.
    $jobDir = Join-Path (Join-Path $script:projectDir 'user-data\update-jobs') ('{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'),([Guid]::NewGuid().ToString('N').Substring(0,8)))
    [IO.Directory]::CreateDirectory($jobDir) | Out-Null
    $resultPath = Join-Path $jobDir 'result.json'
    $stdoutPath = Join-Path $jobDir 'stdout.log'; $stderrPath = Join-Path $jobDir 'stderr.log'
    $installArgs = '-NoProfile -ExecutionPolicy Bypass -File ' + (ConvertTo-NativeArgument $installer) +
      ' -ArchivePath ' + (ConvertTo-NativeArgument $archivePath) +
      ' -ResultPath ' + (ConvertTo-NativeArgument $resultPath)
    $script:updateState.Process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
      -ArgumentList $installArgs -WorkingDirectory $script:projectDir -RedirectStandardOutput $stdoutPath `
      -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
    if (-not $script:updateState.Process) { throw 'Could not start the local package installer.' }
    $null = $script:updateState.Process.Handle
  } catch {
    $script:updateState.Process = $null
    Set-Status ('Update not applied · {0}' -f $_.Exception.Message)
    [Windows.Forms.MessageBox]::Show($script:form,$_.Exception.Message,'Local package update failed','OK','Warning') | Out-Null
    return
  }
  $script:form.UseWaitCursor = $true
  Set-Status 'Installing local package…' $true
  $timer = New-Object Windows.Forms.Timer; $timer.Interval = 300
  $script:updateState.Timer = $timer
  $timer.Add_Tick({ Complete-PrototypeUpdate $resultPath $stderrPath }.GetNewClosure())
  $timer.Start()
}
function Complete-PrototypeUpdate([string]$resultPath, [string]$stderrPath) {
  $proc = $script:updateState.Process
  if ($proc -and -not $proc.HasExited) { return }
  if ($script:updateState.Timer) { $script:updateState.Timer.Stop(); $script:updateState.Timer.Dispose(); $script:updateState.Timer = $null }
  $script:form.UseWaitCursor = $false
  $exitCode = -1
  if ($proc) { try { $proc.WaitForExit(); $exitCode = $proc.ExitCode } catch {}; $proc.Dispose() }
  $script:updateState.Process = $null
  $result = $null
  try { if (Test-Path -LiteralPath $resultPath -PathType Leaf) { $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json } } catch {}
  if ($exitCode -eq 0 -and $result -and $result.Status -eq 'installed') {
    Reset-NativeStatusCache
    Set-Status ('Installed local package · {0} files · restart launcher to use update' -f $result.FilesChanged) $true
    $message = "Updated $($result.FilesChanged) application files.`r`n`r`nPrevious files are backed up at:`r`n$($result.BackupPath)`r`n`r`nReview log:`r`n$($result.LogPath)`r`n`r`nRestart the launcher to load the update. Your current Settings and user data were left in place. SHA-256 checks detect package changes but do not authenticate its publisher."
    [Windows.Forms.MessageBox]::Show($script:form,$message,'Local package update','OK','Information') | Out-Null
    return
  }
  $reason = if ($result -and $result.Message) { [string]$result.Message } else { '' }
  if (-not $reason) { try { $reason = ([IO.File]::ReadAllText($stderrPath)).Trim() } catch {} }
  if (-not $reason) { $reason = 'The package installer did not report a completed update.' }
  Set-Status ('Update not applied · {0}' -f $reason)
  [Windows.Forms.MessageBox]::Show($script:form,$reason,'Local package update failed','OK','Warning') | Out-Null
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

# One-press binding: runs the game's `--list-pads` probe (controllers only, no window) in the
# background and asks for one control at a time; each new input it reports is bound to that
# control (Step-PadBinding in LauncherCore.ps1). The line under the prompt shows every input as
# it arrives, so the dialog doubles as a test view. Returns the bindings, or $null if cancelled.
function Open-PadBindingWizard {
  if (-not (Test-Path -LiteralPath $script:nativePath -PathType Leaf)) {
    [Windows.Forms.MessageBox]::Show('Build the native game first: the controller check uses it.','Controller binding','OK','Information') | Out-Null
    return $null
  }
  [IO.Directory]::CreateDirectory($script:controllerLogDir) | Out-Null
  [IO.Directory]::CreateDirectory($script:nativeRunDir) | Out-Null
  $logPath = Join-Path $script:controllerLogDir ('pads-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
  $steps = @(Get-PadBindingSteps)
  $state = New-PadBindingState
  $result = @{ Bound = $null }

  $dialog = New-Object Windows.Forms.Form
  $dialog.Text = 'Bind with your controller'
  $dialog.StartPosition = 'CenterParent'
  $dialog.ClientSize = New-Object Drawing.Size(640,330)
  $dialog.FormBorderStyle = 'FixedDialog'; $dialog.MaximizeBox = $false; $dialog.MinimizeBox = $false
  $dialog.BackColor = $script:colors.base; $dialog.ForeColor = $script:colors.text
  $dialog.Font = New-Object Drawing.Font('Segoe UI',10); $dialog.AutoScaleMode = 'None'
  if ($script:formIcon) { $dialog.Icon = $script:formIcon }
  $stepLabel = New-Label '' 9 $true $script:colors.cyan
  $stepLabel.Location = New-Object Drawing.Point(26,22); $dialog.Controls.Add($stepLabel)
  $prompt = New-Label '' 20 $true $script:colors.text
  $prompt.Location = New-Object Drawing.Point(24,50); $dialog.Controls.Add($prompt)
  $lastLabel = New-Label 'LAST INPUT' 8 $true $script:colors.muted
  $lastLabel.Location = New-Object Drawing.Point(26,124); $dialog.Controls.Add($lastLabel)
  $last = New-Label 'Waiting for the controller...' 10 $false $script:colors.text
  $last.UseMnemonic = $false
  $last.AutoSize = $false; $last.Size = New-Object Drawing.Size(590,24); $last.AutoEllipsis = $true
  $last.Location = New-Object Drawing.Point(26,146); $dialog.Controls.Add($last)
  $message = New-Label 'Hold the controller and press each control as it is asked for. Keyboard keys are not read here.' 9 $false $script:colors.muted
  $message.UseMnemonic = $false
  $message.AutoSize = $false; $message.Size = New-Object Drawing.Size(590,44)
  $message.Location = New-Object Drawing.Point(26,184); $dialog.Controls.Add($message)
  $skip = New-Button 'SKIP' 110; $skip.Location = New-Object Drawing.Point(26,262); $dialog.Controls.Add($skip)
  $cancel = New-Button 'CANCEL' 110; $cancel.Location = New-Object Drawing.Point(368,262); $dialog.Controls.Add($cancel)
  $done = New-Button 'USE THESE' 140 $true; $done.Location = New-Object Drawing.Point(488,262); $dialog.Controls.Add($done)
  $dialog.CancelButton = $cancel

  $show = {
    if ($state.Index -lt $steps.Count) {
      $stepLabel.Text = ('CONTROL {0} OF {1}' -f ($state.Index + 1),$steps.Count)
      $prompt.Text = $steps[$state.Index].Prompt
    } else {
      $stepLabel.Text = 'ALL CONTROLS ASKED'
      $prompt.Text = 'Done. Choose USE THESE.'
      $skip.Enabled = $false
    }
    if ($state.Message) { $message.Text = $state.Message }
  }.GetNewClosure()

  $probe = $null
  try {
    $probe = Start-Process -FilePath $script:nativePath -ArgumentList @('--list-pads') -WorkingDirectory $script:nativeRunDir `
      -RedirectStandardOutput $logPath -RedirectStandardError ($logPath + '.err') -WindowStyle Hidden -PassThru
  } catch {
    [Windows.Forms.MessageBox]::Show(('The controller check could not start: {0}' -f $_.Exception.Message),'Controller binding','OK','Error') | Out-Null
    return $null
  }
  $reader = @{ Stream = $null; Text = '' }
  $timer = New-Object Windows.Forms.Timer; $timer.Interval = 50
  $timer.Add_Tick({
    try {
      if (-not $reader.Stream) {
        if (-not (Test-Path -LiteralPath $logPath)) { return }
        $fs = New-Object IO.FileStream($logPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        $reader.Stream = New-Object IO.StreamReader($fs)
      }
      $reader.Text += $reader.Stream.ReadToEnd()
      while (($nl = $reader.Text.IndexOf("`n")) -ge 0) {
        $line = $reader.Text.Substring(0,$nl).TrimEnd("`r"); $reader.Text = $reader.Text.Substring($nl + 1)
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $source = ConvertFrom-PadProbeLine $line
        if ($source) { $last.Text = $source } elseif ($line -like 'device*') { $last.Text = $line.Trim() }
        [void](Step-PadBinding $state $line)
        & $show
      }
    } catch {}
    if ($probe.HasExited) { $timer.Stop(); $message.Text = 'The controller check stopped. Close this window and try again.' }
  }.GetNewClosure())
  $skip.Add_Click({ [void](Skip-PadBinding $state); & $show }.GetNewClosure())
  $done.Add_Click({ $result.Bound = $state.Bound; $dialog.Close() }.GetNewClosure())
  $cancel.Add_Click({ $dialog.Close() }.GetNewClosure())
  & $show
  try {
    Set-UiScale $dialog
    $timer.Start()
    [void]$dialog.ShowDialog($script:form)
  } finally {
    $timer.Stop(); $timer.Dispose()
    if ($reader.Stream) { $reader.Stream.Dispose() }
    try { if (-not $probe.HasExited) { $probe.Kill() } } catch {}
    $dialog.Dispose()
  }
  if ($result.Bound -and $result.Bound.Count) { return $result.Bound }
  return $null
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
  # Minimum size is set after scaling, just before the dialog is shown.
  $dialog.BackColor = $script:colors.base
  $dialog.ForeColor = $script:colors.text
  $dialog.Font = New-Object Drawing.Font('Segoe UI',10)
  $dialog.AutoScaleMode = 'None'

  $title = New-Label 'MAP YOUR CONTROLLER' 18 $true
  $title.Location = New-Object Drawing.Point(24,20); $dialog.Controls.Add($title)
  $sub = New-Label 'BIND WITH PAD asks for each control in turn; or pick an action and a detected input. Keyboard defaults remain available.' 9 $false $script:colors.muted
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
  # Wraps within the left column instead of running under the mappings list.
  $sourceHelp.MaximumSize = New-Object Drawing.Size(330,0)
  $sourceHelp.Location = New-Object Drawing.Point(26,239); $dialog.Controls.Add($sourceHelp)
  $detect = New-Button 'DETECT INPUTS' 152 $true; $detect.Location = New-Object Drawing.Point(25,284)
  $dialog.Controls.Add($detect)
  $reload = New-Button 'RELOAD LIST' 134; $reload.Location = New-Object Drawing.Point(188,284); $dialog.Controls.Add($reload)
  $add = New-Button 'ADD MAPPING' 152 $true; $add.Location = New-Object Drawing.Point(25,340); $dialog.Controls.Add($add)
  # One press per control instead of detect, close, reload and pick.
  $wizard = New-Button 'BIND WITH PAD' 167 $true; $wizard.Location = New-Object Drawing.Point(188,340); $dialog.Controls.Add($wizard)
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
  $pathText.AutoSize = $false; $pathText.AutoEllipsis = $true; $pathText.Size = New-Object Drawing.Size(600,18)
  $pathText.Location = New-Object Drawing.Point(26,580); $dialog.Controls.Add($pathText)
  $save = New-Button 'SAVE & USE' 150 $true; $save.Location = New-Object Drawing.Point(785,552); $dialog.Controls.Add($save)
  # Cancel beside Save, as a dialog's two answers; Esc and Enter answer it from the keyboard.
  $cancel = New-Button 'CANCEL' 110; $cancel.Location = New-Object Drawing.Point(663,552)
  $cancel.Add_Click({ $dialog.Close() }); $dialog.Controls.Add($cancel)
  $dialog.CancelButton = $cancel
  if ($script:formIcon) { $dialog.Icon = $script:formIcon }
  $bindingEmpty = New-Label 'No mappings yet. Pick an action and a detected input, then ADD MAPPING.' 9 $false $script:colors.muted
  $bindingEmpty.AutoSize = $false; $bindingEmpty.TextAlign = 'MiddleCenter'; $bindingEmpty.BackColor = $script:colors.panel
  $bindingEmpty.Location = New-Object Drawing.Point(395,280); $bindingEmpty.Size = New-Object Drawing.Size(533,40); $dialog.Controls.Add($bindingEmpty)
  $bindingEmpty.BringToFront()
  $updateEmpty = { $bindingEmpty.Visible = ($bindingList.Items.Count -eq 0) }.GetNewClosure()

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
  & $updateEmpty

  $add.Add_Click({
    if ($null -eq $targetBox.SelectedItem -or $null -eq $sourceBox.SelectedItem) {
      [Windows.Forms.MessageBox]::Show('Run controller detection and reload the input list first.','No detected input','OK','Information') | Out-Null
      return
    }
    $mapping = '{0} = {1}' -f [string]$targetBox.SelectedItem,[string]$sourceBox.SelectedItem
    if (-not $bindingList.Items.Contains($mapping)) { [void]$bindingList.Items.Add($mapping) }
    & $updateEmpty
  }.GetNewClosure())
  $remove.Add_Click({ if ($bindingList.SelectedIndex -ge 0) { $bindingList.Items.RemoveAt($bindingList.SelectedIndex) }; & $updateEmpty }.GetNewClosure())
  $wizard.Add_Click({
    $bound = Open-PadBindingWizard
    if (-not $bound) { return }
    $current = @($bindingList.Items | ForEach-Object { [string]$_ })
    $merged = @(Merge-PadBindings $current $bound)
    $bindingList.Items.Clear()
    foreach ($line in $merged) { [void]$bindingList.Items.Add($line) }
    & $updateEmpty
    Set-Status ('{0} controls bound. Choose SAVE & USE to keep them.' -f $bound.Count) $true
  }.GetNewClosure())
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

  Set-UiScale $dialog; $dialog.MinimumSize = $dialog.Size
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
# The work area is in physical pixels; the design sizes below are 96-DPI units.
$initialWidth = [Math]::Min((Get-Px 1480),[Math]::Max((Get-Px 1100),$workArea.Width - (Get-Px 36)))
$initialHeight = [Math]::Min((Get-Px 900),[Math]::Max((Get-Px 680),$workArea.Height - (Get-Px 60)))
$script:form.ClientSize = New-Object Drawing.Size($initialWidth,$initialHeight)
$script:form.MinimumSize = New-Object Drawing.Size([Math]::Min((Get-Px 1180),$initialWidth),[Math]::Min((Get-Px 720),$initialHeight))
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
# Scaling is done explicitly with Set-UiScale, so WinForms must not auto-scale a second time.
$script:form.AutoScaleMode = 'None'
$script:form.Location = New-Object Drawing.Point(($workArea.Left + [Math]::Max(0,($workArea.Width - $initialWidth) / 2)),($workArea.Top + [Math]::Max(0,($workArea.Height - $initialHeight) / 2)))

$script:sidebarWidth = 258
$sidebar = New-Object Windows.Forms.Panel
$script:sidebar = $sidebar
$sidebar.Dock = 'None'; $sidebar.Location = New-Object Drawing.Point(0,0); $sidebar.Size = New-Object Drawing.Size($script:sidebarWidth,[int]($script:form.ClientSize.Height / $script:uiScale))
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
  $script:brandFont = New-Object Drawing.Font($script:headingFontName,23,[Drawing.FontStyle]::Bold)
  $script:brandBrush = New-Object Drawing.SolidBrush($script:colors.text)
  $script:brandAccent = New-Object Drawing.Pen($script:colors.blue,2)
  $brandMark.Add_Paint({
    param($sender,$e)
    $e.Graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $s = $script:uiScale
    $e.Graphics.DrawString('PF',$script:brandFont,$script:brandBrush,(5*$s),(5*$s))
    $e.Graphics.DrawLine($script:brandAccent,(6*$s),(44*$s),(52*$s),(44*$s))
    $e.Graphics.DrawLine($script:brandAccent,(16*$s),(49*$s),(43*$s),(49*$s))
  }.GetNewClosure())
  $sidebar.Controls.Add($brandMark); $script:brandMark = $brandMark

$script:content = New-Object Windows.Forms.Panel
$script:content.Dock = 'None'; $script:content.Location = New-Object Drawing.Point((Get-Px $script:sidebarWidth),0)
$script:content.Size = New-Object Drawing.Size([Math]::Max(320,$script:form.ClientSize.Width-(Get-Px $script:sidebarWidth)),$script:form.ClientSize.Height); $script:content.Anchor = 'Top,Bottom,Left,Right'
$script:content.BackColor = [Drawing.Color]::Transparent; $script:content.AutoScroll = $true
# A dark band behind each page title, so headings stay readable over the bright hangar art.
# Transparent labels repaint their parent, so they pick this band up too.
$script:content.Add_Paint({
  param($sender,$e)
  if ($script:currentPage -eq 'Home') { return }
  $top = $sender.AutoScrollPosition.Y
  $band = [Drawing.Rectangle]::new(0,$top,$sender.ClientSize.Width,(Get-Px 104))
  if ($band.Bottom -le 0 -or $band.Width -le 0) { return }
  $brush = [Drawing.Drawing2D.LinearGradientBrush]::new($band,[Drawing.Color]::FromArgb(236,4,11,15),[Drawing.Color]::FromArgb(150,4,11,15),[Drawing.Drawing2D.LinearGradientMode]::Horizontal)
  $brush.WrapMode = [Drawing.Drawing2D.WrapMode]::TileFlipXY
  try { $e.Graphics.FillRectangle($brush,$band) } finally { $brush.Dispose() }
})
$script:form.Controls.Add($script:content)
$script:form.Add_Resize({
  if ($script:form.WindowState -ne [Windows.Forms.FormWindowState]::Minimized) {
    $script:sidebar.Height = $script:form.ClientSize.Height
    $script:content.Location = New-Object Drawing.Point($script:sidebar.Width,0)
    $script:content.Size = New-Object Drawing.Size([Math]::Max(320,$script:form.ClientSize.Width - $script:sidebar.Width),[Math]::Max(100,$script:form.ClientSize.Height))
    Update-StatusLabelBounds
    if ($script:backgroundResizeTimer) { $script:backgroundResizeTimer.Stop(); $script:backgroundResizeTimer.Start() }
  }
})
$script:form.Add_Shown({
  # Rebuild after the first DPI pass so the overview uses the real client dimensions.
  $script:form.PerformLayout()
  $script:sidebar.Height = $script:form.ClientSize.Height
  $script:content.Location = New-Object Drawing.Point($script:sidebar.Width,0)
  $script:content.Size = New-Object Drawing.Size([Math]::Max(320,$script:form.ClientSize.Width - $script:sidebar.Width),[Math]::Max(100,$script:form.ClientSize.Height))
  Update-LauncherBackground
  Update-StatusLabelBounds
  $script:sidebar.BringToFront()
  Show-Page 'Home'
  if ($script:startupNotice) { Set-Status $script:startupNotice }
  if (-not (Test-FilePath $script:discValue)) {
    $script:form.BeginInvoke([Action]{ [void](Select-GameImage $true) }) | Out-Null
  }
})
$script:backgroundResizeTimer = New-Object Windows.Forms.Timer
$script:backgroundResizeTimer.Interval = 80
$script:backgroundResizeTimer.Add_Tick({
  $script:backgroundResizeTimer.Stop()
  Update-LauncherBackground
  Update-PageAfterResize
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
$railLabel=New-Label 'STATUS' 8 $true $script:colors.muted
$railLabel.Location=New-Object Drawing.Point(20,548); $sidebar.Controls.Add($railLabel); $script:railLabel = $railLabel
$script:statusLabel = New-Label 'Ready' 9 $true $script:colors.cyan
$script:statusLabel.UseMnemonic = $false
$script:statusLabel.AutoSize = $false; $script:statusLabel.TextAlign = 'MiddleLeft'; $script:statusLabel.AutoEllipsis = $true
$script:statusLabel.BackColor=$script:colors.panel; $script:statusLabel.Padding=New-Object Windows.Forms.Padding(10,0,6,0)
$script:statusLabel.BorderStyle='FixedSingle'; $script:statusLabel.Size = New-Object Drawing.Size(220,38)
$sidebar.Controls.Add($script:statusLabel)
$script:statusTip = New-Object Windows.Forms.ToolTip
$script:statusTip.AutoPopDelay = 20000; $script:statusTip.InitialDelay = 400; $script:statusTip.ReshowDelay = 100
# Status messages carry error details; the rail tooltip retains their full text when it clips.
# Runs after the sidebar has been scaled, so it works in physical pixels. The heading sits
# directly above the status box instead of floating halfway down the rail.
function Update-StatusLabelBounds {
  if (-not $script:statusLabel -or -not $script:sidebarScaled) { return }
  $boxTop = [Math]::Max((Get-Px 570),$script:sidebar.Height - (Get-Px 62))
  $script:statusLabel.Location = [Drawing.Point]::new((Get-Px 18),$boxTop)
  $script:statusLabel.Size = [Drawing.Size]::new(($script:sidebar.Width - (Get-Px 36)),(Get-Px 38))
  if ($script:railLabel) { $script:railLabel.Location = [Drawing.Point]::new((Get-Px 20),$boxTop - (Get-Px 22)) }
}

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
  $b.UseMnemonic = $false
  $b.Text = $item.label; $b.Tag = $item.key; $b.Location = New-Object Drawing.Point(14,$navY)
  $b.Size = [Drawing.Size]::new(($script:sidebarWidth - 28),46); $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
  $b.TextAlign = 'MiddleLeft'; $b.Padding=New-Object Windows.Forms.Padding(14,0,4,0)
  $b.BackColor = [Drawing.Color]::Transparent; $b.ForeColor = $script:colors.muted
  $b.FlatAppearance.MouseOverBackColor=[Drawing.Color]::FromArgb(14,38,45)
  $b.Font = New-Object Drawing.Font($script:headingFontName,10); $b.Cursor = [Windows.Forms.Cursors]::Hand
  $b.Add_Click({ Show-Page ([string]$this.Tag) })
  $sidebar.Controls.Add($b); $script:navButtons[$item.key] = $b; $navY += 52
}
Set-UiScale $sidebar
$script:sidebarScaled = $true
$sidebar.Height = $script:form.ClientSize.Height
Update-StatusLabelBounds

function Show-Page([string]$page) {
  if (-not $script:navButtons.ContainsKey($page)) { $page = 'Home' }
  # Leaving Settings with edits that were not saved: offer to save, discard or stay.
  if ($script:currentPage -eq 'Settings' -and $page -ne 'Settings' -and $script:settingsDirty) {
    $answer = [Windows.Forms.MessageBox]::Show($script:form,'Save your changes to Systems & controls before leaving?','Unsaved settings','YesNoCancel','Question')
    if ($answer -eq [Windows.Forms.DialogResult]::Cancel) { return }
    if ($answer -eq [Windows.Forms.DialogResult]::Yes) { Save-SettingsPage }
  }
  $script:settingsDirty = $false
  $script:currentPage = $page
  # Rebuilding a page in a visible panel cost 0.5-1.2 s: every control got a window handle and
  # repainted over the stretched background as it was added and scaled. With the panel hidden,
  # handles are created once when it is shown (0.15-0.4 s). The form stops redrawing meanwhile,
  # so the old page stays on screen instead of flashing the bare background.
  $redrawOff = $false
  if ($script:form.IsHandleCreated) {
    try { [void][PeregrineForge.Native]::SendMessage($script:form.Handle,0x000B,[IntPtr]::Zero,[IntPtr]::Zero); $redrawOff = $true } catch {}  # WM_SETREDRAW off
  }
  try {
    $script:content.Visible = $false
    $script:content.SuspendLayout()
    foreach ($c in @($script:content.Controls)) { $script:content.Controls.Remove($c); $c.Dispose() }
    $script:content.AutoScrollPosition = [Drawing.Point]::new(0,0)
    $script:pageBuiltSize = $script:content.Size
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
    # Pages are laid out in 96-DPI units; scale each new top-level control once.
    foreach ($c in @($script:content.Controls)) { Set-UiScale $c }
  } finally {
    # Always show the panel again, even if a page failed to build.
    $script:content.ResumeLayout()
    $script:content.Visible = $true
    if ($redrawOff) {
      try { [void][PeregrineForge.Native]::SendMessage($script:form.Handle,0x000B,[IntPtr]::new(1),[IntPtr]::Zero) } catch {}  # WM_SETREDRAW on
      $script:form.Refresh()
    } else { $script:content.Invalidate() }
  }
}
# Pages are built for the content size at the time (card widths, Home's bottom row), so after
# the window is resized the current page is rebuilt once the resize settles. Settings with
# unsaved edits is left alone: rebuilding it would discard them.
function Update-PageAfterResize {
  if (-not $script:currentPage -or -not $script:pageBuiltSize) { return }
  if ($script:content.Size -eq $script:pageBuiltSize) { return }
  if ($script:currentPage -eq 'Settings' -and $script:settingsDirty) { return }
  Show-Page $script:currentPage
}
# Page sizes in 96-DPI units, for the page builders.
function Get-ContentLogicalWidth { [int]($script:content.ClientSize.Width / $script:uiScale) }
function Get-ContentLogicalHeight { [int]($script:content.ClientSize.Height / $script:uiScale) }

# Each page lives in tools\LauncherPages\<name>.ps1 and only defines functions.
foreach ($launcherPage in @('Home','Crashes','Library','Saves','Mods','Settings','About')) {
  $launcherPagePath = Join-Path $script:projectDir ('tools\LauncherPages\' + $launcherPage + '.ps1')
  if (-not (Test-Path -LiteralPath $launcherPagePath -PathType Leaf)) {
    [Windows.Forms.MessageBox]::Show(('A launcher file is missing: {0}{1}{1}Reinstall the complete launcher package.' -f $launcherPagePath,[Environment]::NewLine),'Peregrine Forge','OK','Error') | Out-Null
    exit 1
  }
  . $launcherPagePath
}

# Card width in 96-DPI units. The floor fits the 1180-wide minimum window without a horizontal
# scrollbar (content is 922 wide there: 30 left margin + 820 + room for a vertical scrollbar).
function Get-ContentPageWidth { [Math]::Max(820,(Get-ContentLogicalWidth) - 60) }

# ---- Keyboard and controller navigation ----
# The pages in sidebar order, for Ctrl+PageUp/PageDown (or Ctrl+Tab), Ctrl+1-7 and a pad's
# shoulder buttons.
$script:pageOrder = @($navItems | ForEach-Object { $_.key })
function Show-PageStep([int]$step) {
  $i = [Array]::IndexOf($script:pageOrder,[string]$script:currentPage)
  $next = $script:pageOrder[(($i + $step) % $script:pageOrder.Count + $script:pageOrder.Count) % $script:pageOrder.Count]
  Show-Page $next
  if ($script:currentPage -eq $next) { [void]$script:navButtons[$next].Focus() }
}
foreach ($b in $script:navButtons.Values) {
  # The sidebar's own focus cue, as the content buttons have theirs (New-Button).
  $b.Add_GotFocus({ if ([string]$this.Tag -ne $script:currentPage) { $this.BackColor = [Drawing.Color]::FromArgb(14,38,45); $this.ForeColor = $script:colors.text } })
  $b.Add_LostFocus({ if ([string]$this.Tag -ne $script:currentPage) { $this.BackColor = [Drawing.Color]::Transparent; $this.ForeColor = $script:colors.muted } })
}
$script:form.KeyPreview = $true
$script:form.Add_KeyDown({
  param($sender,$e)
  if (-not $e.Control) { return }
  if ($e.KeyCode -eq 'Next' -or ($e.KeyCode -eq 'Tab' -and -not $e.Shift)) { Show-PageStep 1; $e.Handled = $true; $e.SuppressKeyPress = $true }
  elseif ($e.KeyCode -eq 'PageUp' -or ($e.KeyCode -eq 'Tab' -and $e.Shift)) { Show-PageStep -1; $e.Handled = $true; $e.SuppressKeyPress = $true }
  elseif ($e.KeyValue -ge 49 -and $e.KeyValue -le (48 + $script:pageOrder.Count)) { Show-Page $script:pageOrder[$e.KeyValue - 49]; $e.Handled = $true; $e.SuppressKeyPress = $true }
})

# A controller drives the launcher while it is the active window (the game is not): D-pad or
# left stick moves the focus, A presses (a button or check box) or opens a list, B goes back
# (closes a dialog, or returns to the Flight Deck), LB and RB change page. First XInput pad
# only; a held direction repeats.
$script:padState = @{ Last = 0; HeldSince = [DateTime]::MinValue; LastRepeat = [DateTime]::MinValue; Ok = $true }
function Invoke-PadNavigation {
  if (-not $script:padState.Ok) { return }
  $active = [Windows.Forms.Form]::ActiveForm
  if (-not $active) { $script:padState.Last = 0; return }
  $st = New-Object PeregrineForge.Native+XInputState
  try { if ([PeregrineForge.Native]::XInputGetState(0,[ref]$st) -ne 0) { $script:padState.Last = 0; return } }
  catch { $script:padState.Ok = $false; return }  # no XInput on this system
  $g = $st.Gamepad; $buttons = [int]$g.wButtons
  # The stick as D-pad bits (up 1, down 2, left 4, right 8) past half travel.
  if ($g.sThumbLY -gt 16000) { $buttons = $buttons -bor 1 } elseif ($g.sThumbLY -lt -16000) { $buttons = $buttons -bor 2 }
  if ($g.sThumbLX -lt -16000) { $buttons = $buttons -bor 4 } elseif ($g.sThumbLX -gt 16000) { $buttons = $buttons -bor 8 }
  $now = [DateTime]::UtcNow
  $pressed = $buttons -band -bnot $script:padState.Last
  $dirs = $buttons -band 0xF
  if ($dirs -and ($dirs -eq ($script:padState.Last -band 0xF))) {
    # Held: repeat after 400 ms, every 120 ms.
    if (($now - $script:padState.HeldSince).TotalMilliseconds -gt 400 -and ($now - $script:padState.LastRepeat).TotalMilliseconds -gt 120) { $pressed = $pressed -bor $dirs; $script:padState.LastRepeat = $now }
  } elseif ($dirs) { $script:padState.HeldSince = $now }
  $script:padState.Last = $buttons
  if (-not $pressed) { return }
  $focused = $active.ActiveControl
  while ($focused -is [Windows.Forms.ContainerControl] -and $focused.ActiveControl) { $focused = $focused.ActiveControl }
  if ($pressed -band 0x3) {          # up/down
    if ($focused -is [Windows.Forms.ComboBox] -and $focused.DroppedDown) { [Windows.Forms.SendKeys]::Send($(if ($pressed -band 1) { '{UP}' } else { '{DOWN}' })) }
    elseif ($focused -is [Windows.Forms.ListBox]) { [Windows.Forms.SendKeys]::Send($(if ($pressed -band 1) { '{UP}' } else { '{DOWN}' })) }
    else { [void]$active.SelectNextControl($focused,[bool]($pressed -band 2),$true,$true,$true) }
  }
  elseif ($pressed -band 0xC) {      # left/right
    if ($focused -is [Windows.Forms.ComboBox]) { [Windows.Forms.SendKeys]::Send($(if ($pressed -band 4) { '{UP}' } else { '{DOWN}' })) }
    else { [void]$active.SelectNextControl($focused,[bool]($pressed -band 8),$true,$true,$true) }
  }
  if ($pressed -band 0x1000) {       # A
    if ($focused -is [Windows.Forms.ComboBox]) { $focused.DroppedDown = -not $focused.DroppedDown }
    elseif ($focused -is [Windows.Forms.ButtonBase]) { [Windows.Forms.SendKeys]::Send(' ') }
  }
  if ($pressed -band 0x2000) {       # B
    if ($focused -is [Windows.Forms.ComboBox] -and $focused.DroppedDown) { $focused.DroppedDown = $false }
    elseif ($active -ne $script:form) { [Windows.Forms.SendKeys]::Send('{ESC}') }
    elseif ($script:currentPage -ne 'Home') { Show-Page 'Home'; if ($script:currentPage -eq 'Home') { [void]$script:navButtons['Home'].Focus() } }
  }
  if ($active -eq $script:form) {
    if ($pressed -band 0x100) { Show-PageStep -1 }   # LB
    if ($pressed -band 0x200) { Show-PageStep 1 }    # RB
  }
}
$script:padTimer = New-Object Windows.Forms.Timer; $script:padTimer.Interval = 50
$script:padTimer.Add_Tick({ try { Invoke-PadNavigation } catch {} })
$script:form.Add_Shown({ $script:padTimer.Start() })
$script:form.Add_FormClosed({ $script:padTimer.Stop(); $script:padTimer.Dispose() })

Show-Page 'Home'
[void]$script:form.ShowDialog()

