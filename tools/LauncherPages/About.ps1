# Launcher page: About. Dot-sourced by Launch-StarFoxAssault.ps1 into its script scope,
# so it uses the launcher's $script: state and helpers. Defines functions only.

function Build-AboutPage {
  Add-SectionHeader $script:content 'About Peregrine Forge' 'A community-built native recompilation prototype for Star Fox Assault.'
  $pageWidth=Get-ContentPageWidth
  $card=New-Card 30 112 $pageWidth 500
  $heading=New-Label $script:launcherBrand.ToUpperInvariant() 22 $true $script:colors.cyan; $heading.Location=New-Object Drawing.Point(25,24); $card.Controls.Add($heading)
  $release=New-Label ('Version {0} · experimental native build · validation is ongoing' -f (Get-LauncherVersionText)) 11 $true $script:colors.text; $release.Location=New-Object Drawing.Point(27,68); $card.Controls.Add($release)
  $body=New-Label ("{0} is the launcher brand for {1}, an independent fan project. It can inspect your own USA ISO/CISO, prepare its portable build tools, compile the native application, and keep launcher settings and runtime data in this project folder. Your game image is read in place and is never copied, patched, or modified." -f $script:launcherBrand,$script:projectTitle) 10 $false $script:colors.muted
  $body.Location=New-Object Drawing.Point(27,112); $body.MaximumSize=New-Object Drawing.Size(($pageWidth-80),68); $body.AutoSize=$true; $card.Controls.Add($body)
  $limit=New-Label 'Known limitations: first-mission flight, menus and saves have been tested. A crash on a mission''s third load is fixed; the reported current-thread-pointer crash has not reproduced in testing, the first-boss fix still needs live confirmation, and later missions are unverified. This is not a finished or fully compatible game release.' 10 $false $script:colors.text
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
