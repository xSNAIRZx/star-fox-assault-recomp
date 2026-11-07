# Launcher page: Mod Library. Dot-sourced by Launch-StarFoxAssault.ps1 into its script scope,
# so it uses the launcher's $script: state and helpers. Defines functions only.

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
# An HD texture pack for the native build: PNGs named by texture hash (Test-HdTextureName),
# anywhere in the ZIP. Only those are extracted, flattened into one folder; everything else
# is ignored. Installed through a staging folder, so a bad ZIP leaves the current pack alone,
# and the pack it replaces is kept as `previous`.
function Install-HdTexturePack([string]$zipPath) {
  if (Get-RunningNativeGame) { throw 'Close the native game before changing its HD texture pack.' }
  $maxEntries = 200000; $maxExpandedBytes = [long]8GB; $total = [long]0; $count = 0
  [IO.Directory]::CreateDirectory($script:hdTextureRoot) | Out-Null
  $stage = Join-Path $script:hdTextureRoot ('staging-' + [Guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($stage) | Out-Null
  try {
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
      if ($archive.Entries.Count -gt $maxEntries) { throw "This pack has more than $maxEntries files and was not installed." }
      foreach ($entry in $archive.Entries) {
        $name = $entry.Name
        if (-not (Test-HdTextureName $name)) { continue }
        if ($entry.Length -lt 0 -or ($total + $entry.Length) -gt $maxExpandedBytes) { throw 'This pack expands beyond the 8 GiB safety limit and was not installed.' }
        $target = Join-Path $stage $name.ToLowerInvariant()
        if (Test-Path -LiteralPath $target) { continue }  # the same texture twice: the first wins
        $src = $entry.Open(); $dst = [IO.File]::Open($target,[IO.FileMode]::CreateNew)
        try {
          $buffer = New-Object byte[] (1024*1024); $entryBytes = [long]0
          while (($read = $src.Read($buffer,0,$buffer.Length)) -gt 0) {
            $entryBytes += $read; $total += $read
            if ($entryBytes -gt $entry.Length -or $total -gt $maxExpandedBytes) { throw 'This pack expanded beyond its declared size or the 8 GiB safety limit.' }
            $dst.Write($buffer,0,$read)
          }
          if ($entryBytes -ne $entry.Length) { throw 'A pack entry was incomplete; nothing was installed.' }
        } finally { $dst.Dispose(); $src.Dispose() }
        $count++
      }
    } finally { $archive.Dispose() }
    if (-not $count) { throw 'No textures were found. An HD pack holds PNGs named by texture hash (0123456789abcdef.png, as the dump names them) or by Dolphin (tex1_....png).' }
    @{ name = [IO.Path]::GetFileNameWithoutExtension($zipPath); files = $count; installed = (Get-Date).ToString('s') } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage 'pack.json') -Encoding utf8
    $previous = Join-Path $script:hdTextureRoot 'previous'
    if (Test-Path -LiteralPath $script:hdTextureDir) {
      if (Test-Path -LiteralPath $previous) { Remove-Item -LiteralPath $previous -Recurse -Force }
      Move-Item -LiteralPath $script:hdTextureDir -Destination $previous
    }
    Move-Item -LiteralPath $stage -Destination $script:hdTextureDir
    return $count
  } finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue } }
}
function Get-HdTexturePackText {
  $meta = Join-Path $script:hdTextureDir 'pack.json'
  if (-not (Test-Path -LiteralPath $script:hdTextureDir -PathType Container)) { return 'No HD texture pack installed.' }
  try { $m = Get-Content -LiteralPath $meta -Raw | ConvertFrom-Json; return ('INSTALLED: {0} · {1} textures' -f $m.name,$m.files) } catch { return 'Pack folder present; details unavailable.' }
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
  if (Get-RunningNativeGame) { throw 'Close the native game before changing its active asset pack.' }
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
  if (Get-RunningNativeGame) { throw 'Close the native game before rolling back its active asset pack.' }
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
  $card=New-Card 30 112 $pageWidth 330
  $list=New-Object Windows.Forms.ListBox; $list.Location=New-Object Drawing.Point(25,25); $list.Size=New-Object Drawing.Size(($pageWidth - 50),220)
  $list.BackColor=$script:colors.panel2; $list.ForeColor=$script:colors.text; $list.BorderStyle='FixedSingle'; $list.Anchor='Top,Left,Right'; $card.Controls.Add($list)
  $script:modsEmptyLabel=New-Label 'No Dolphin texture packs installed' 10 $true $script:colors.muted
  $script:modsEmptyLabel.AutoSize=$false; $script:modsEmptyLabel.TextAlign='MiddleCenter'
  $script:modsEmptyLabel.BackColor=$script:colors.panel2; $script:modsEmptyLabel.Anchor='Top,Left,Right'
  $script:modsEmptyLabel.Location=New-Object Drawing.Point(26,104); $script:modsEmptyLabel.Size=New-Object Drawing.Size(($pageWidth - 52),36); $card.Controls.Add($script:modsEmptyLabel)
  $script:modsEmptyLabel.BringToFront()
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
  $nativeCard=New-Card 30 462 $pageWidth 200
  $n=New-Label 'NATIVE ASSET REPLACEMENTS' 9 $true $script:colors.cyan; $n.Location=New-Object Drawing.Point(22,17); $nativeCard.Controls.Add($n)
  $nd=New-Label 'Exact-size files at matching disc paths only. Executable files, RELs, DOLs, and sys/ are not supported. Dolphin texture packs do not apply to the native build.' 9 $false $script:colors.muted
  $nd.Location=New-Object Drawing.Point(22,42); $nd.MaximumSize=New-Object Drawing.Size(($pageWidth - 48),0); $nativeCard.Controls.Add($nd)
  $nativeCheck=New-Object Windows.Forms.CheckBox; $nativeCheck.Text='Enable native asset replacements'; $nativeCheck.AutoSize=$true; $nativeCheck.Location=New-Object Drawing.Point(22,88); $nativeCheck.ForeColor=$script:colors.text; $nativeCheck.BackColor=[Drawing.Color]::Transparent; $nativeCheck.Checked=[bool]$script:nativeModsValue
  $nativeCheck.Add_CheckedChanged({ $script:nativeModsValue=[bool]$script:nativeModsCheck.Checked; Save-Settings; if($script:nativeModsValue -and -not(Test-Path -LiteralPath $script:nativeModsDir -PathType Container)){ Set-Status 'Import a native asset ZIP before starting with replacements enabled.' } else { Set-Status 'Native replacement setting saved.' $true } }); $nativeCard.Controls.Add($nativeCheck); $script:nativeModsCheck=$nativeCheck
  $importNative=New-Button 'IMPORT NATIVE ZIP' 170 $true; $importNative.Location=New-Object Drawing.Point(22,126)
  $importNative.Add_Click({ $d=New-Object Windows.Forms.OpenFileDialog; $d.Filter='Native asset pack (*.zip)|*.zip'; if($d.ShowDialog() -eq 'OK'){ try { $meta=Install-NativeModPack $d.FileName; Save-Settings; Set-Status ('Installed {0}: {1} exact-size disc asset(s). Previous pack retained for rollback.' -f $meta.name,$meta.files) $true } catch { Set-Status $_.Exception.Message } } }); $nativeCard.Controls.Add($importNative)
  $openNative=New-Button 'OPEN ACTIVE FOLDER' 170; $openNative.Location=New-Object Drawing.Point(205,126); $openNative.Add_Click({ [IO.Directory]::CreateDirectory($script:nativeModsDir) | Out-Null; Open-Folder $script:nativeModsDir }); $nativeCard.Controls.Add($openNative)
  $rollback=New-Button 'ROLL BACK' 130; $rollback.Location=New-Object Drawing.Point(388,126); $rollback.Add_Click({ try { Restore-PreviousNativeModPack; Set-Status 'Previous native pack restored. The replaced pack was retained for rollback.' $true } catch { Set-Status $_.Exception.Message } }); $nativeCard.Controls.Add($rollback)
  $metaPath=Join-Path (Join-Path (Split-Path -Parent $script:nativeModsDir) 'metadata') 'active.json'
  $nativeState=if(Test-Path -LiteralPath $metaPath){ try { $m=Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json; 'ACTIVE: {0} · {1} files' -f $m.name,$m.files } catch { 'Active folder present; pack details unavailable.' } } else { 'No native replacement pack installed.' }
  $stateLabel=New-Label $nativeState 8 $false $script:colors.muted; $stateLabel.Location=New-Object Drawing.Point(538,137); $nativeCard.Controls.Add($stateLabel)
  $script:content.Controls.Add($nativeCard)

  # HD texture packs for the native build (runtime gx/texture_pack.h).
  $hdCard=New-Card 30 680 $pageWidth 200
  $h=New-Label 'HD TEXTURE PACK (NATIVE)' 9 $true $script:colors.cyan; $h.Location=New-Object Drawing.Point(22,17); $hdCard.Controls.Add($h)
  $hd=New-Label 'PNGs named by texture hash (from the dump) or Dolphin-style tex1_ names, at a whole multiple of the original size: Dolphin HD packs for this game install as they are (PNG or DDS). Switch the pack on in Systems & Controls.' 9 $false $script:colors.muted
  $hd.Location=New-Object Drawing.Point(22,42); $hd.MaximumSize=New-Object Drawing.Size(($pageWidth - 48),0); $hdCard.Controls.Add($hd)
  $script:dumpTexturesCheck=New-Object Windows.Forms.CheckBox; $script:dumpTexturesCheck.Text='Dump textures while playing (to user-data\texture-dump)'; $script:dumpTexturesCheck.AutoSize=$true
  $script:dumpTexturesCheck.Location=New-Object Drawing.Point(22,88); $script:dumpTexturesCheck.ForeColor=$script:colors.text; $script:dumpTexturesCheck.BackColor=[Drawing.Color]::Transparent; $script:dumpTexturesCheck.Checked=[bool]$script:dumpTexturesValue
  $script:dumpTexturesCheck.Add_CheckedChanged({ $script:dumpTexturesValue=[bool]$script:dumpTexturesCheck.Checked; Save-Settings; Set-Status ($(if($script:dumpTexturesValue){'Textures will be dumped on the next launch.'}else{'Texture dump off.'})) $true })
  $hdCard.Controls.Add($script:dumpTexturesCheck)
  $installHd=New-Button 'INSTALL HD PACK ZIP' 180 $true; $installHd.Location=New-Object Drawing.Point(22,126)
  $installHd.Add_Click({
    $d=New-Object Windows.Forms.OpenFileDialog; $d.Filter='HD texture pack (*.zip)|*.zip'
    if ($d.ShowDialog($script:form) -eq 'OK') {
      try { $n=Install-HdTexturePack $d.FileName; $script:hdPackLabel.Text=Get-HdTexturePackText; Set-Status ("Installed {0} HD textures. Switch the pack on in Systems & Controls." -f $n) $true }
      catch { Set-Status $_.Exception.Message }
    }
  }); $hdCard.Controls.Add($installHd)
  $openDump=New-Button 'OPEN DUMP FOLDER' 170; $openDump.Location=New-Object Drawing.Point(215,126); $openDump.Add_Click({ Open-Folder $script:textureDumpDir }); $hdCard.Controls.Add($openDump)
  $openHd=New-Button 'OPEN PACK FOLDER' 170; $openHd.Location=New-Object Drawing.Point(398,126); $openHd.Add_Click({ Open-Folder $script:hdTextureDir }); $hdCard.Controls.Add($openHd)
  $script:hdPackLabel=New-Label (Get-HdTexturePackText) 8 $false $script:colors.muted; $script:hdPackLabel.Location=New-Object Drawing.Point(583,137); $hdCard.Controls.Add($script:hdPackLabel)
  $script:content.Controls.Add($hdCard)
}
