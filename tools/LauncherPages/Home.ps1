# Launcher page: Flight Deck. Dot-sourced by Launch-StarFoxAssault.ps1 into its script scope,
# so it uses the launcher's $script: state and helpers. Defines functions only.

function Build-HomePage {
  $pageWidth = [Math]::Max(880,(Get-ContentLogicalWidth))
  $pageHeight = [Math]::Max(640,(Get-ContentLogicalHeight))
  $scene = New-Object Windows.Forms.Panel
  $scene.Location = New-Object Drawing.Point(0,0); $scene.Size = New-Object Drawing.Size($pageWidth,$pageHeight)
  $scene.Anchor = 'Top,Bottom,Left,Right'; $scene.BackColor = [Drawing.Color]::Transparent
  $scene.Add_Paint({
    param($sender,$e)
    # Work in 96-DPI units and let the transform scale the drawing to the real pixels.
    $s = [single]$script:uiScale
    $e.Graphics.ScaleTransform($s,$s)
    $w = [int]($sender.ClientSize.Width / $s); $h = [int]($sender.ClientSize.Height / $s)
    $left = [Drawing.Rectangle]::new(0,0,[Math]::Min(650,$w),$h)
    $leftBrush = New-Object Drawing.Drawing2D.LinearGradientBrush($left,[Drawing.Color]::FromArgb(218,4,11,15),[Drawing.Color]::FromArgb(0,4,11,15),[Drawing.Drawing2D.LinearGradientMode]::Horizontal)
    # TileFlipXY stops GDI+ wrapping the far colour back onto the first row or column, which
    # showed as a thin line once the drawing is scaled.
    $leftBrush.WrapMode = [Drawing.Drawing2D.WrapMode]::TileFlipXY
    $e.Graphics.FillRectangle($leftBrush,$left); $leftBrush.Dispose()
    $titleY = [Math]::Max(176,[int]($h * 0.32))
    $titleField = [Drawing.Rectangle]::new(16,[Math]::Max(0,$titleY - 42),[Math]::Min(570,$w - 16),204)
    $titleBrush = [Drawing.Drawing2D.LinearGradientBrush]::new($titleField,[Drawing.Color]::FromArgb(196,4,11,15),[Drawing.Color]::FromArgb(18,4,11,15),[Drawing.Drawing2D.LinearGradientMode]::Horizontal)
    $titleBrush.WrapMode = [Drawing.Drawing2D.WrapMode]::TileFlipXY
    $e.Graphics.FillRectangle($titleBrush,$titleField); $titleBrush.Dispose()
    $bottom = [Drawing.Rectangle]::new(0,[Math]::Max(0,$h-260),$w,[Math]::Min(260,$h))
    $bottomBrush = New-Object Drawing.Drawing2D.LinearGradientBrush($bottom,[Drawing.Color]::FromArgb(0,4,11,15),[Drawing.Color]::FromArgb(235,4,11,15),[Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $bottomBrush.WrapMode = [Drawing.Drawing2D.WrapMode]::TileFlipXY
    $e.Graphics.FillRectangle($bottomBrush,$bottom); $bottomBrush.Dispose()
    $rule = New-Object Drawing.Pen([Drawing.Color]::FromArgb(95,61,202,222),1)
    $e.Graphics.DrawLine($rule,36,88,[Math]::Min($w-36,450),88)
    $e.Graphics.DrawLine($rule,36,[Math]::Max(0,$h-224),[Math]::Min($w-36,660),[Math]::Max(0,$h-224))
    $rule.Dispose()
    $e.Graphics.ResetTransform()
  })
  $script:content.Controls.Add($scene)

  $eyebrow = New-Label 'PEREGRINE FORGE  /  FLIGHT SYSTEMS' 9 $true $script:colors.cyan
  $eyebrow.Location = New-Object Drawing.Point(38,35); $scene.Controls.Add($eyebrow)
  $titleY = [Math]::Max(176,[int]($pageHeight * 0.32))
  $eyebrowTitle=New-Label 'GAMECUBE RECOMPILATION' 9 $true $script:colors.muted
  $eyebrowTitle.BackColor = [Drawing.Color]::Transparent
  $eyebrowTitle.Location=New-Object Drawing.Point(40,($titleY-35)); $scene.Controls.Add($eyebrowTitle)
  $name = New-Label 'STAR FOX' 28 $true
  $name.BackColor = [Drawing.Color]::Transparent
  if ($script:flightDisplayFontFamily) { $name.Font = [Drawing.Font]::new($script:flightDisplayFontFamily,28,[Drawing.FontStyle]::Bold) }
  $name.Location = New-Object Drawing.Point(35,$titleY); $scene.Controls.Add($name)
  $name2 = New-Label 'ASSAULT' 30 $true $script:colors.cyan
  $name2.BackColor = [Drawing.Color]::Transparent
  if ($script:flightDisplayFontFamily) { $name2.Font = [Drawing.Font]::new($script:flightDisplayFontFamily,30,[Drawing.FontStyle]::Bold) }
  $name2.Location = New-Object Drawing.Point(35,($titleY+47)); $scene.Controls.Add($name2)
  $validation=New-Label 'EXPERIMENTAL NATIVE BUILD  ·  GAMEPLAY VALIDATION IN PROGRESS' 9 $false $script:colors.muted
  $validation.BackColor = [Drawing.Color]::Transparent
  $validation.Location=New-Object Drawing.Point(40,($titleY+122)); $scene.Controls.Add($validation)

  $cardY=[Math]::Max(470,$pageHeight-206)
  $cardWidth=[Math]::Min(480,$pageWidth-300)
  $statusCard=New-Card 36 $cardY $cardWidth 132; $scene.Controls.Add($statusCard)
  $nativeStatus = Get-NativeStatus
  $buildTitle = New-Label 'NATIVE BUILD' 8 $true $script:colors.muted
  $buildTitle.Location = New-Object Drawing.Point(19,18); $statusCard.Controls.Add($buildTitle)
  $buildValueText = if ($nativeStatus -eq 'REBUILD REQUIRED') { 'REBUILD REQUIRED' } elseif ($nativeStatus -eq 'NOT BUILT') { 'NOT BUILT' } else { 'CURRENT' }
  $buildColor = if ($nativeStatus -eq 'NOT BUILT') { $script:colors.red } elseif ($nativeStatus -eq 'REBUILD REQUIRED') { $script:colors.cyan } else { $script:colors.green }
  $buildValue = New-Label $buildValueText 10 $true $buildColor
  $buildValue.Location = New-Object Drawing.Point(19,47); $statusCard.Controls.Add($buildValue)
  if ($script:nativeStatusReason -and $script:statusTip) { $script:statusTip.SetToolTip($buildValue,('Rebuild required: {0}.' -f $script:nativeStatusReason)) }
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
  $playText = if (-not $hasDisc) { 'SELECT GAME IMAGE' } elseif (-not $hasNative) { 'BUILD NATIVE' } elseif ($nativeStatus -eq 'REBUILD REQUIRED') { 'REBUILD NATIVE' } else { 'LAUNCH GAME' }
  $play = New-Button $playText 190 $true
  $playX = $pageWidth - 230; $playY = $cardY + 16
  $play.Size = New-Object Drawing.Size(194,54); $play.Location = New-Object Drawing.Point($playX,$playY)
  $play.Anchor = 'Bottom,Right'; $play.Add_Click({
    if (-not (Test-FilePath $script:discValue)) { [void](Select-GameImage $true) }
    elseif (-not (Test-Path -LiteralPath $script:nativePath -PathType Leaf) -or (Get-NativeStatus) -eq 'REBUILD REQUIRED') { Start-NativeBuild }
    else { Start-NativeGame }
  }); $scene.Controls.Add($play)
  $dolphin = New-Button 'OPEN IN DOLPHIN' 194
  $dolphinX = $pageWidth - 230; $dolphinY = $playY + 64
  $dolphin.Size = New-Object Drawing.Size(194,42); $dolphin.Location = New-Object Drawing.Point($dolphinX,$dolphinY)
  $dolphin.Anchor = 'Bottom,Right'; $dolphin.Add_Click({ Start-DolphinGame }); $dolphin.Visible = (Test-FilePath $script:dolphinValue); $scene.Controls.Add($dolphin)
  $quick = New-Label 'IN GAME  ·  SPACE CONTINUE  /  F9 MOUSE CAPTURE' 8 $true $script:colors.cyan
  # A translucent backing keeps the hint readable where it crosses the bright ship.
  $quick.BackColor = [Drawing.Color]::FromArgb(200,4,11,15); $quick.Padding = New-Object Windows.Forms.Padding(6,3,6,3)
  # Right-aligned with the buttons. PreferredWidth is measured in physical pixels.
  $quickWidth = [int][Math]::Ceiling($quick.PreferredWidth / $script:uiScale)
  $quick.Location=New-Object Drawing.Point(($playX + 194 - $quickWidth),($cardY-35)); $quick.Anchor='Bottom,Right'; $scene.Controls.Add($quick)
}
