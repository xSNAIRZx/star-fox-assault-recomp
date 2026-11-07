# Launcher page: Systems & Controls. Dot-sourced by Launch-StarFoxAssault.ps1 into its script scope,
# so it uses the launcher's $script: state and helpers. Defines functions only.

# Reads every Settings control into the profile and saves it.
function Save-SettingsPage {
  if (-not $script:settings_disc -or $script:settings_disc.IsDisposed) { return }
  $script:discValue=$script:settings_disc.Text; $script:dolphinValue=$script:settings_dolphin.Text; $script:controlsValue=$script:settings_controls.Text
  $script:scaleValue=[double](Get-LauncherSettingAllowed 'scale')[$script:scaleBox.SelectedIndex]
  $script:aspectValue=(Get-LauncherSettingAllowed 'aspect')[$script:aspectBox.SelectedIndex]
  $script:aaValue=(Get-LauncherSettingAllowed 'aa')[$script:aaBox.SelectedIndex]
  $script:filterValue=(Get-LauncherSettingAllowed 'filter')[$script:filterBox.SelectedIndex]
  $script:deadzoneValue=(Get-LauncherSettingAllowed 'deadzone')[$script:deadzoneBox.SelectedIndex]
  $script:volumeValue=[int]$script:volumeOptions[$script:volumeBox.SelectedIndex]
  $script:muteValue=$script:muteBox.Checked; $script:logValue=$script:logBox.Checked
  $script:fullscreenValue=$script:fullscreenBox.Checked; $script:vsyncValue=$script:vsyncBox.Checked
  $script:anisotropyValue=(Get-LauncherSettingAllowed 'anisotropy')[$script:anisotropyBox.SelectedIndex]
  $script:trilinearValue=$script:trilinearBox.Checked; $script:softParticlesValue=$script:softBox.Checked; $script:hdTexturesValue=$script:hdTexturesBox.Checked
  Save-Settings
  Set-SettingsDirty $false
  Set-Status 'Settings saved.' $true
}
# Fills the Settings controls from a preset (Get-DisplayPreset); only the settings it names
# change, and nothing is saved until Save.
function Set-SettingsPreset([string]$name) {
  $p = Get-DisplayPreset $name
  if ($p.Contains('scale')) { $script:scaleBox.SelectedIndex = [Array]::IndexOf([double[]](Get-LauncherSettingAllowed 'scale'),[double]$p.scale) }
  if ($p.Contains('aspect')) { $script:aspectBox.SelectedIndex = [Array]::IndexOf((Get-LauncherSettingAllowed 'aspect'),$p.aspect) }
  if ($p.Contains('aa')) { $script:aaBox.SelectedIndex = [Array]::IndexOf((Get-LauncherSettingAllowed 'aa'),$p.aa) }
  if ($p.Contains('filter')) { $script:filterBox.SelectedIndex = [Array]::IndexOf((Get-LauncherSettingAllowed 'filter'),$p.filter) }
  if ($p.Contains('anisotropy')) { $script:anisotropyBox.SelectedIndex = [Array]::IndexOf((Get-LauncherSettingAllowed 'anisotropy'),$p.anisotropy) }
  if ($p.Contains('trilinear')) { $script:trilinearBox.Checked = [bool]$p.trilinear }
  if ($p.Contains('softParticles')) { $script:softBox.Checked = [bool]$p.softParticles }
  Set-Status ('{0} preset applied. Save settings to keep it.' -f (Get-Culture).TextInfo.ToTitleCase($name)) $true
}
function Set-SettingsDirty([bool]$dirty) {
  $script:settingsDirty = $dirty
  if ($script:settingsDirtyLabel -and -not $script:settingsDirtyLabel.IsDisposed) { $script:settingsDirtyLabel.Visible = $dirty }
}
function Build-SettingsPage {
  Add-SectionHeader $script:content 'Systems & controls' 'Choose your game, controls and native options. Changes apply on the next launch.'
  $pageWidth = Get-ContentPageWidth
  # Save sits in the header, so it is reachable without scrolling to the end of the page.
  $save=New-Button 'SAVE SETTINGS' 160 $true; $save.Location=New-Object Drawing.Point((30 + $pageWidth - 160),44)
  $save.Add_Click({ Save-SettingsPage }); $script:content.Controls.Add($save)
  $script:settingsDirtyLabel=New-Label 'UNSAVED CHANGES' 8 $true $script:colors.cyan
  $script:settingsDirtyLabel.AutoSize=$false; $script:settingsDirtyLabel.TextAlign='MiddleRight'
  $script:settingsDirtyLabel.Location=New-Object Drawing.Point((30 + $pageWidth - 360),44); $script:settingsDirtyLabel.Size=New-Object Drawing.Size(188,40)
  $script:settingsDirtyLabel.Visible=$false; $script:content.Controls.Add($script:settingsDirtyLabel)

  $card=New-Card 30 112 $pageWidth 842
  $script:discValue=$script:settings.disc; $script:dolphinValue=$script:settings.dolphin; $script:controlsValue=$script:settings.controls
  $rows=@(
    @{label='GAME IMAGE';value=$script:discValue;id='disc'},
    @{label='DOLPHIN APP (OPTIONAL)';value=$script:dolphinValue;id='dolphin'},
    @{label='CONTROLS FILE (OPTIONAL)';value=$script:controlsValue;id='controls'}
  )
  $y=25
  foreach ($row in $rows) {
    $l=New-Label $row.label 8 $true $script:colors.muted; $l.Location=New-Object Drawing.Point(24,$y); $card.Controls.Add($l)
    $browseX=$card.Width - 130
    $t=New-Object Windows.Forms.TextBox; $t.Text=$row.value; $t.Location=New-Object Drawing.Point(25,($y + 24)); $t.Size=New-Object Drawing.Size(($browseX - 40),28)
    $t.BackColor=$script:colors.panel2; $t.ForeColor=$script:colors.text; $t.BorderStyle='FixedSingle'; $t.Anchor='Top,Left,Right'; $card.Controls.Add($t)
    $b=New-Button 'BROWSE' 105; $b.Location=New-Object Drawing.Point($browseX,($y + 18)); $b.Anchor='Top,Right'
    $id=$row.id
    $b.Add_Click({
      $d=New-Object Windows.Forms.OpenFileDialog
      if ($id -eq 'disc') { $d.Filter='Supported game images (*.iso;*.ciso)|*.iso;*.ciso|All files (*.*)|*.*' }
      elseif ($id -eq 'dolphin') { $d.Filter='Dolphin executable (Dolphin.exe)|Dolphin.exe|Executable (*.exe)|*.exe' }
      else { $d.Filter='Controller mappings (controls.txt)|controls.txt|Text files (*.txt)|*.txt|All files (*.*)|*.*' }
      if ($d.ShowDialog($script:form) -eq 'OK') { $t.Text=$d.FileName }
    }.GetNewClosure())
    $card.Controls.Add($b)
    Set-Variable -Scope Script -Name ("settings_{0}" -f $row.id) -Value $t
    $y += 78
  }
  $columnGap=18; $columnWidth=[int][Math]::Floor(($card.Width - 50 - (2*$columnGap))/3)
  $columnX=@(25,(25+$columnWidth+$columnGap),(25+2*($columnWidth+$columnGap)))
  function Add-SettingCombo([string]$caption,[int]$column,[int]$top,[object[]]$items,[int]$selected,[string]$note) {
    $cap=New-Label $caption 8 $true $script:colors.muted; $cap.Location=New-Object Drawing.Point($columnX[$column],$top); $card.Controls.Add($cap)
    $combo=New-Object Windows.Forms.ComboBox; $combo.DropDownStyle='DropDownList'; $combo.Items.AddRange($items)
    $combo.SelectedIndex=[Math]::Max(0,$selected); $combo.Location=New-Object Drawing.Point($columnX[$column],($top + 22)); $combo.Size=New-Object Drawing.Size($columnWidth,30)
    Set-DarkComboBox $combo; $card.Controls.Add($combo)
    if ($note) {
      $n=New-Label $note 8 $false $script:colors.muted; $n.AutoSize=$false; $n.AutoEllipsis=$true
      $n.Size=New-Object Drawing.Size($columnWidth,18); $n.Location=New-Object Drawing.Point($columnX[$column],($top + 56)); $card.Controls.Add($n)
    }
    return $combo
  }
  $displayHeading=New-Label 'PICTURE & DISPLAY' 11 $true $script:colors.cyan; $displayHeading.Location=New-Object Drawing.Point(25,256); $card.Controls.Add($displayHeading)
  $script:scaleBox = Add-SettingCombo 'INTERNAL RESOLUTION' 0 286 @('Auto / match window','1x','1.5x','2x','3x','4x','6x') ([Array]::IndexOf([double[]](Get-LauncherSettingAllowed 'scale'),[double]$script:scaleValue)) ''
  $script:aspectBox = Add-SettingCombo 'ASPECT RATIO' 1 286 @('Original 4:3','Widescreen 16:9 (experimental)','Fill window (stretch)') ([Array]::IndexOf((Get-LauncherSettingAllowed 'aspect'),$script:aspectValue)) 'Press F8 in game to switch.'
  $script:aaBox = Add-SettingCombo 'ANTI-ALIASING' 2 286 @('Off','FXAA') ([Array]::IndexOf((Get-LauncherSettingAllowed 'aa'),$script:aaValue)) 'FXAA softens edges and text.'
  $script:filterBox = Add-SettingCombo 'OUTPUT FILTER' 0 366 @('Sharp (bicubic)','Smooth (bilinear)') ([Array]::IndexOf((Get-LauncherSettingAllowed 'filter'),$script:filterValue)) 'Sharp with AA off keeps text crisp.'
  $script:deadzoneBox = Add-SettingCombo 'STICK DEADZONE' 1 366 @('Runtime default','Off (0%)','5%','10%','15%','20%','30%') ([Array]::IndexOf((Get-LauncherSettingAllowed 'deadzone'),$script:deadzoneValue)) 'Optional steering precision.'
  # A dark dropdown in steps of 5; a value saved by hand that is not a step is kept as its own entry.
  $script:volumeOptions = New-Object System.Collections.Generic.List[int]
  for ($v=0; $v -le 100; $v+=5) { $script:volumeOptions.Add($v) }
  if (-not $script:volumeOptions.Contains([int]$script:volumeValue)) { $script:volumeOptions.Add([int]$script:volumeValue); $script:volumeOptions.Sort() }
  $script:volumeBox = Add-SettingCombo 'MASTER VOLUME' 2 366 ([object[]]@($script:volumeOptions | ForEach-Object { '{0}%' -f $_ })) ($script:volumeOptions.IndexOf([int]$script:volumeValue)) ''

  # HD enhancements: renderer options past what the console drew, all off by default.
  $hdRule=New-Object Windows.Forms.Panel; $hdRule.Location=New-Object Drawing.Point(25,450); $hdRule.Size=New-Object Drawing.Size(($card.Width-50),1); $hdRule.BackColor=$script:colors.line; $card.Controls.Add($hdRule)
  $hdHeading=New-Label 'HD ENHANCEMENTS' 11 $true $script:colors.cyan; $hdHeading.Location=New-Object Drawing.Point(25,464); $card.Controls.Add($hdHeading)
  # Presets fill in the controls; Save keeps them (Set-SettingsPreset).
  $presetTip=New-Object Windows.Forms.ToolTip
  $presetLabel=New-Label 'PRESET' 8 $true $script:colors.muted; $presetLabel.Location=New-Object Drawing.Point(($card.Width-470),470); $presetLabel.Anchor='Top,Right'; $card.Controls.Add($presetLabel)
  $presetX=$card.Width-415
  foreach ($p in @(@{key='original';text='ORIGINAL';tip='As the console drew it: 4:3, 2x, sharp, no anti-aliasing, no enhancements.'},
                   @{key='hd';text='HD';tip='4x resolution, 16x anisotropic filtering, trilinear mips, sharp output. Aspect unchanged.'},
                   @{key='widescreen';text='WIDESCREEN';tip='The HD preset at 16:9 (experimental).'})) {
    $b=New-Button $p.text 125 ($p.key -eq 'hd'); $b.Tag=$p.key; $b.Location=New-Object Drawing.Point($presetX,458); $b.Anchor='Top,Right'
    $b.Add_Click({ Set-SettingsPreset ([string]$this.Tag) }); $presetTip.SetToolTip($b,$p.tip); $card.Controls.Add($b)
    $presetX += 132
  }
  $script:anisotropyBox = Add-SettingCombo 'ANISOTROPIC FILTERING' 0 486 @('Off','2x','4x','8x','16x') ([Array]::IndexOf((Get-LauncherSettingAllowed 'anisotropy'),$script:anisotropyValue)) 'Sharper ground and walls at an angle.'
  $script:trilinearBox=New-Object Windows.Forms.CheckBox; $script:trilinearBox.Text='Smooth mip transitions (trilinear)'; $script:trilinearBox.Checked=$script:trilinearValue
  $script:trilinearBox.Location=New-Object Drawing.Point($columnX[1],494); $script:trilinearBox.AutoSize=$true; $script:trilinearBox.ForeColor=$script:colors.text; $card.Controls.Add($script:trilinearBox)
  $script:softBox=New-Object Windows.Forms.CheckBox; $script:softBox.Text='Soft particles (experimental)'; $script:softBox.Checked=$script:softParticlesValue
  $script:softBox.Location=New-Object Drawing.Point($columnX[1],522); $script:softBox.AutoSize=$true; $script:softBox.ForeColor=$script:colors.text; $card.Controls.Add($script:softBox)
  $script:hdTexturesBox=New-Object Windows.Forms.CheckBox; $script:hdTexturesBox.Text='Use HD texture pack'; $script:hdTexturesBox.Checked=$script:hdTexturesValue
  $script:hdTexturesBox.Location=New-Object Drawing.Point($columnX[2],494); $script:hdTexturesBox.AutoSize=$true; $script:hdTexturesBox.ForeColor=$script:colors.text; $card.Controls.Add($script:hdTexturesBox)
  $hdPackState = if (Test-Path -LiteralPath $script:hdTextureDir -PathType Container) { 'Pack installed. Manage it in Mod Library.' } else { 'No pack installed; see Mod Library.' }
  $hdNote=New-Label $hdPackState 8 $false $script:colors.muted; $hdNote.AutoSize=$false; $hdNote.AutoEllipsis=$true; $hdNote.Size=New-Object Drawing.Size($columnWidth,18); $hdNote.Location=New-Object Drawing.Point($columnX[2],524); $card.Controls.Add($hdNote)
  $rendererRule=New-Object Windows.Forms.Panel; $rendererRule.Location=New-Object Drawing.Point(25,562); $rendererRule.Size=New-Object Drawing.Size(($card.Width-50),1); $rendererRule.BackColor=$script:colors.line; $card.Controls.Add($rendererRule)
  $rendererLabel=New-Label 'RENDERER & PRESENTATION' 11 $true $script:colors.cyan; $rendererLabel.Location=New-Object Drawing.Point(25,576); $card.Controls.Add($rendererLabel)
  $script:fullscreenBox=New-Object Windows.Forms.CheckBox; $script:fullscreenBox.Text='Start fullscreen (Alt+Enter to toggle)'
  $script:fullscreenBox.Checked=$script:fullscreenValue; $script:fullscreenBox.Location=New-Object Drawing.Point($columnX[0],604); $script:fullscreenBox.AutoSize=$true; $script:fullscreenBox.ForeColor=$script:colors.text; $card.Controls.Add($script:fullscreenBox)
  $script:vsyncBox=New-Object Windows.Forms.CheckBox; $script:vsyncBox.Text='Prevent screen tearing (VSync)'
  $script:vsyncBox.Checked=$script:vsyncValue; $script:vsyncBox.Location=New-Object Drawing.Point($columnX[1],604); $script:vsyncBox.AutoSize=$true; $script:vsyncBox.ForeColor=$script:colors.text; $card.Controls.Add($script:vsyncBox)
  $audioTitle=New-Label 'AUDIO & INPUT' 11 $true $script:colors.cyan; $audioTitle.Location=New-Object Drawing.Point(25,640); $card.Controls.Add($audioTitle)
  $script:muteBox=New-Object Windows.Forms.CheckBox; $script:muteBox.Text='Mute game music'; $script:muteBox.Checked=[bool]$script:muteValue
  $script:muteBox.Location=New-Object Drawing.Point($columnX[0],668); $script:muteBox.AutoSize=$true; $script:muteBox.ForeColor=$script:colors.text; $card.Controls.Add($script:muteBox)
  $script:logBox=New-Object Windows.Forms.CheckBox; $script:logBox.Text='Record controller input for diagnostics'; $script:logBox.Checked=[bool]$script:logValue
  $script:logBox.Location=New-Object Drawing.Point($columnX[1],668); $script:logBox.AutoSize=$true; $script:logBox.ForeColor=$script:colors.text; $card.Controls.Add($script:logBox)

  $controllerRule=New-Object Windows.Forms.Panel; $controllerRule.Location=New-Object Drawing.Point(25,706); $controllerRule.Size=New-Object Drawing.Size(($card.Width-50),1); $controllerRule.BackColor=$script:colors.line; $card.Controls.Add($controllerRule)
  $controllerTitle=New-Label 'CONTROLLER DETECTOR' 11 $true $script:colors.cyan
  $controllerTitle.Location=New-Object Drawing.Point(25,720); $card.Controls.Add($controllerTitle)
  $controllerText=New-Label 'Press a pad button or move an axis; detected SDL names can be used in your optional controls mapping.' 9 $false $script:colors.muted
  $controllerText.Location=New-Object Drawing.Point(25,748); $controllerText.MaximumSize=New-Object Drawing.Size(($card.Width-50),0); $card.Controls.Add($controllerText)
  $detect=New-Button 'DETECT CONTROLLER' 190 $true; $detect.Location=New-Object Drawing.Point(25,778)
  $detect.Add_Click({ Start-ControllerDetector }); $card.Controls.Add($detect)
  $viewLog=New-Button 'VIEW LAST RESULTS' 168; $viewLog.Location=New-Object Drawing.Point(231,778)
  $viewLog.Add_Click({ Open-ControllerLog }); $card.Controls.Add($viewLog)
  $editControls=New-Button 'CREATE / EDIT MAPPING' 190; $editControls.Location=New-Object Drawing.Point(414,778)
  $editControls.Add_Click({ Open-ControlsFile }); $card.Controls.Add($editControls)

  # Any edit marks the page unsaved; attached after the initial values are filled in.
  foreach ($box in @($script:settings_disc,$script:settings_dolphin,$script:settings_controls)) { $box.Add_TextChanged({ Set-SettingsDirty $true }) }
  foreach ($combo in @($script:scaleBox,$script:aspectBox,$script:aaBox,$script:filterBox,$script:deadzoneBox,$script:volumeBox,$script:anisotropyBox)) { $combo.Add_SelectedIndexChanged({ Set-SettingsDirty $true }) }
  foreach ($check in @($script:fullscreenBox,$script:vsyncBox,$script:muteBox,$script:logBox,$script:trilinearBox,$script:softBox,$script:hdTexturesBox)) { $check.Add_CheckedChanged({ Set-SettingsDirty $true }) }
  $script:content.Controls.Add($card)
}
