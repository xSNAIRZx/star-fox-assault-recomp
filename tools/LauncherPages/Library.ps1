# Launcher page: Game Library. Dot-sourced by Launch-StarFoxAssault.ps1 into its script scope,
# so it uses the launcher's $script: state and helpers. Defines functions only.

function Build-LibraryPage {
  Add-SectionHeader $script:content 'Game library' 'Choose and inspect your own USA game image. The image is only read, never modified.'
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
  $libraryStatus = Get-NativeStatus
  if ($script:nativeStatusReason) { $libraryStatus = '{0} ({1})' -f $libraryStatus,$script:nativeStatusReason }
  $bd = New-Label ("Status: {0}. Build from local source or install a local prototype ZIP; there is no online updater." -f $libraryStatus) 10 $false $script:colors.text
  $bd.Location = New-Object Drawing.Point(24,55); $build.Controls.Add($bd)
  $bbText = if (Test-Path -LiteralPath $script:nativePath -PathType Leaf) { 'REBUILD NATIVE' } else { 'IMPORT & BUILD' }
  $bb = New-Button $bbText 160 $true; $bb.Location = New-Object Drawing.Point(24,82); $bb.Add_Click({ $script:discValue=$script:discBox.Text; Start-NativeBuild }); $build.Controls.Add($bb)
  $packageButton = New-Button 'INSTALL LOCAL ZIP' 178; $packageButton.Location = New-Object Drawing.Point(198,82)
  $packageButton.Add_Click({ Open-PrototypeUpdateDialog }); $build.Controls.Add($packageButton)
  $script:content.Controls.Add($build)
}
