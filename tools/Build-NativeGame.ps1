param(
  [Parameter(Mandatory=$true)][string]$GameImage,
  [switch]$UsePortableToolchain,
  [string]$ProgressFile='', [string]$CancelFile='', [string]$BuildDirectory='',
  # 0 picks a count from the CPU and free memory (Get-BuildJobCount).
  [ValidateRange(0,32)][int]$Jobs=0,
  [switch]$Offline, [switch]$DiagnosticBuild
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Build-CacheSignature.ps1')
$project=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$GameImage=[IO.Path]::GetFullPath($GameImage)
if(-not $BuildDirectory){$BuildDirectory=Join-Path $project 'user-data\build-cache\llvm-x64'}
$BuildDirectory=[IO.Path]::GetFullPath($BuildDirectory)
$executable=Join-Path $project 'build-desktop\Release\assault.exe'
$oldPath=$env:PATH
$lock=$null; $script:active=$null; $pending=$null
function Set-BuildStatus([string]$state,[string]$phase,[string]$message,$percent=$null){
  Write-Host ("[{0}] {1}" -f $phase,$message)
  if($ProgressFile){
    $full=[IO.Path]::GetFullPath($ProgressFile)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $full))
    $pendingStatus=$full+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    [IO.File]::WriteAllText($pendingStatus,([ordered]@{schema_version=1;state=$state;phase=$phase;message=$message;percent=$percent;executable=$(if($state -eq 'succeeded'){$executable}else{$null})} | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    # The launcher reads this file several times a second, and File.Replace fails while a
    # reader has it open. Retry briefly; a progress update that still cannot land is dropped
    # rather than failing the build, but the final state must be written.
    $final=$state -ne 'running'
    $attempts=if($final){40}else{5}
    for($try=1;$try -le $attempts;$try++){
      try {
        if(Test-Path -LiteralPath $full){[IO.File]::Replace($pendingStatus,$full,$full+'.previous')}else{[IO.File]::Move($pendingStatus,$full)}
        break
      } catch [IO.IOException] {
        if($try -eq $attempts){
          Remove-Item -LiteralPath $pendingStatus -Force -ErrorAction SilentlyContinue
          if($final){throw}
        } else {Start-Sleep -Milliseconds 50}
      }
    }
  }
}
# Parallel compile jobs: one per hardware thread less two, and no more than free memory allows
# at about 512 MB each (the largest recompiled file peaked near 200 MB per compiler).
function Get-BuildJobCount {
  $byCpu=[Math]::Max(1,[Environment]::ProcessorCount-2)
  $byMemory=$byCpu
  try {
    $freeMb=[double](Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).FreePhysicalMemory/1024
    $byMemory=[Math]::Max(1,[int][Math]::Floor($freeMb/512))
  } catch { $byMemory=[Math]::Min(8,$byCpu) }
  return [int][Math]::Max(1,[Math]::Min(32,[Math]::Min($byCpu,$byMemory)))
}
# Only this project's game counts as running: another program called assault.exe must not
# block a build. A process whose path cannot be read is still treated as running.
function Test-NativeGameRunning {
  $target=[IO.Path]::GetFullPath($executable)
  return [bool]@(Get-Process -Name assault -ErrorAction SilentlyContinue | Where-Object {
    $path=$null; try{$path=$_.Path}catch{}
    [string]::IsNullOrEmpty($path) -or [string]::Equals([IO.Path]::GetFullPath($path),$target,[StringComparison]::OrdinalIgnoreCase)
  }).Count
}
function Test-BuildCancel {
  if($CancelFile -and (Test-Path -LiteralPath $CancelFile)){throw [OperationCanceledException]::new('Build cancelled.')}
}
function Quote-Argument([string]$value){'"'+([regex]::Replace([regex]::Replace($value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1'))+'"'}
function Invoke-BuildProcess([string]$FilePath,[string[]]$Arguments,[string]$Phase){
  Test-BuildCancel
  $id=[guid]::NewGuid().ToString('N')
  $stdout=Join-Path $BuildDirectory ($id+'.out.log'); $stderr=Join-Path $BuildDirectory ($id+'.err.log')
  $quoted=($Arguments | ForEach-Object {Quote-Argument $_}) -join ' '
  $script:active=Start-Process -FilePath $FilePath -ArgumentList $quoted -WorkingDirectory $project -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
  $null=$script:active.Handle
  $last=''
  while(-not $script:active.HasExited){
    Test-BuildCancel
    # Always one string: -match on an array filters it and leaves $Matches unset, which
    # failed short incremental builds with "Cannot index into a null array".
    $line=[string](@(Get-Content -LiteralPath $stdout -Tail 1 -ErrorAction SilentlyContinue) | Select-Object -Last 1)
    if($line -and $line -ne $last){
      $last=$line
      # Only progress is reported while the step runs; its whole output is written once when
      # it ends. Echoing other sampled lines here as well printed part of a long configure
      # twice, which read like CMake configuring twice.
      $progress=[regex]::Match($line,'^\[(\d+)/(\d+)\]')
      if($progress.Success -and [int]$progress.Groups[2].Value -gt 0){Set-BuildStatus 'running' $Phase $line ([Math]::Round(100.0*[int]$progress.Groups[1].Value/[int]$progress.Groups[2].Value,1))}
    }
    Start-Sleep -Milliseconds 180
    $script:active.Refresh()
  }
  $script:active.WaitForExit();$script:active.Refresh();$code=$script:active.ExitCode
  if($null -eq $code){throw "$Phase ended without a readable process exit code."}
  Get-Content -LiteralPath $stdout | ForEach-Object {Write-Host $_}
  Get-Content -LiteralPath $stderr | ForEach-Object {Write-Host $_}
  $script:active.Dispose();$script:active=$null
  if($code -ne 0){throw "$Phase failed (exit $code). See the build log for details."}
}
# -ConfigureOnly limits the set to what the CMake configure step itself reads: build scripts,
# CMake files, the recompiler and its tables. C/C++ and shader sources are left to Ninja, which
# tracks them (runtime sources are a CONFIGURE_DEPENDS glob), so editing one no longer reruns
# the whole configure and recompilation from the image. The full set is the build record.
function Get-SourceFingerprint([switch]$ConfigureOnly) {
  $paths=@('CMakeLists.txt','tools\portable-toolchain.json','tools\Build-NativeGame.ps1','tools\Build-StarFoxAssault.ps1','tools\Ensure-PortableToolchain.ps1','tools\Build-CacheSignature.ps1')
  $extensions=@('.py','.txt','.cmake','.in','.rc','.manifest')
  if(-not $ConfigureOnly){$extensions+=@('.c','.cc','.cpp','.h','.hpp','.inc','.glsl','.glslinc','.frag','.vert','.geom','.comp')}
  foreach($folder in @('runtime','recomp','decomp\config\GF7E01')){
    $paths+=@(Get-ChildItem -LiteralPath (Join-Path $project $folder) -Recurse -File | Where-Object {$_.Extension -in $extensions -and $_.FullName -notmatch '[\\/](build|__pycache__)[\\/]'} | ForEach-Object {$_.FullName.Substring($project.Length+1)})
  }
  return Get-FileSetFingerprint $project $paths
}
try {
  Set-BuildStatus 'running' 'Checking image' 'Validating your local ISO/CISO.'
  if(-not(Test-Path -LiteralPath $GameImage -PathType Leaf)){throw 'The selected game image was not found.'}
  if(Test-NativeGameRunning){throw 'Close the running game before rebuilding.'}
  $inspector=Join-Path $project 'tools\native\assault-image-tool.exe'
  if(-not(Test-Path -LiteralPath $inspector)){throw 'The image inspector is missing. Restore the complete launcher package.'}
  $inspection=& $inspector ("--inspect-image=$GameImage")
  if($LASTEXITCODE -ne 0){throw 'Select a supported USA Star Fox Assault image (GF7E01).'}
  $imageInfo=$inspection | ConvertFrom-Json
  if(-not $imageInfo.valid -or $imageInfo.game_id -ne 'GF7E01'){throw 'Unsupported game image.'}
  Set-BuildStatus 'running' 'Checking image' 'Calculating a checksum so changed image contents cannot reuse a stale build cache.'
  $imageSha256=Get-ImageContentFingerprint $GameImage
  Test-BuildCancel
  $image=Get-Item -LiteralPath $GameImage
  $space=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($BuildDirectory))
  if($space.AvailableFreeSpace -lt 3GB){throw 'At least 3 GB of free space is required for build tools and generated files.'}
  [void][IO.Directory]::CreateDirectory($BuildDirectory)
  $owner=Join-Path $BuildDirectory '.assault-build-cache'
  if(-not(Test-Path -LiteralPath $owner)){
    if(@(Get-ChildItem -LiteralPath $BuildDirectory -Force).Count){throw 'Choose an empty build folder; this is not an Assault build cache.'}
    [IO.File]::WriteAllText($owner,'Star Fox Assault Recomp build cache')
  }
  try {$lock=[IO.File]::Open((Join-Path $BuildDirectory '.build.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
  catch {throw 'Another build is already using this cache.'}
  Set-BuildStatus 'running' 'Preparing tools' 'Using the pinned portable compiler and build tools.'
  $tools=& (Join-Path $PSScriptRoot 'Ensure-PortableToolchain.ps1') -ProgressFile $ProgressFile -CancelFile $CancelFile -Offline:$Offline
  $sdlPrefix=Join-Path $tools.root 'SDL2-2.30.9-llvm-20261020'
  if($Offline -and (-not(Test-Path -LiteralPath (Join-Path $sdlPrefix 'lib\libSDL2.a')) -or -not(Test-Path -LiteralPath (Join-Path $sdlPrefix 'built')))){
    throw 'Offline build needs the SDL cache from a completed online build. Run the first build with internet access.'
  }
  $env:PATH=$tools.compilerDirectory+';'+(Split-Path $tools.cmake)+';'+(Split-Path $tools.ninja)+';'+(Split-Path $tools.python)+';'+$oldPath
  $fingerprint=Get-SourceFingerprint
  $configureFingerprint=Get-SourceFingerprint -ConfigureOnly
  $settings=[ordered]@{project=$project;image=$GameImage;image_size=$image.Length;image_modified=$image.LastWriteTimeUtc.Ticks;image_sha256=$imageSha256;configure_inputs=$configureFingerprint;compiler=$tools.cc;diagnostic=[bool]$DiagnosticBuild}
  $signature=$settings | ConvertTo-Json -Compress
  $statePath=Join-Path $BuildDirectory 'configure-state.json';$configureNeeded=$true;$freshConfigure=$false
  if((Test-Path -LiteralPath $statePath) -and (Test-Path -LiteralPath (Join-Path $BuildDirectory 'CMakeCache.txt'))){
    $old=Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $configureNeeded=$old.signature -ne $signature
    if($old.project -ne $project -or $old.compiler -ne $tools.cc){$freshConfigure=$true}
  }
  if($configureNeeded){
    Set-BuildStatus 'running' 'Recompiling game' 'Extracting and recompiling from your image; preparing the native build.'
    $diag=if($DiagnosticBuild){'ON'}else{'OFF'}
    $configure=@('-S',$project,'-B',$BuildDirectory,'-G','Ninja','-DCMAKE_BUILD_TYPE=Release',"-DCMAKE_MAKE_PROGRAM=$($tools.ninja)","-DCMAKE_C_COMPILER=$($tools.cc)","-DCMAKE_CXX_COMPILER=$($tools.cxx)","-DCMAKE_RC_COMPILER=$($tools.rc)","-DPython3_EXECUTABLE=$($tools.python)","-DGAME_ISO=$GameImage",'-DGCN_BENCH_ONLY=OFF','-DGCN_OPENXR=OFF',"-DGCN_TRACE_CALLS=$diag",'-DGCN_WATCH=OFF',"-DGCN_THREAD_WATCH=$diag",'-DCMAKE_EXE_LINKER_FLAGS=-static',"-DGCN_SDL2_PREFIX=$sdlPrefix")
    $configure=@($configure | ForEach-Object {$_.Replace('\','/')})
    if($freshConfigure -or (-not(Test-Path -LiteralPath $statePath) -and (Test-Path -LiteralPath (Join-Path $BuildDirectory 'CMakeCache.txt')))){$configure+='--fresh'}
    Invoke-BuildProcess $tools.cmake $configure 'Recompiling game'
    [ordered]@{signature=$signature;project=$project;compiler=$tools.cc} | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
  } else {Set-BuildStatus 'running' 'Using build cache' 'Build settings and image are unchanged; compiling only what changed.'}
  if($Jobs -le 0){$Jobs=Get-BuildJobCount}
  Set-BuildStatus 'running' 'Compiling native executable' ('Compiling the recompiled game and runtime ({0} parallel jobs).' -f $Jobs)
  Invoke-BuildProcess $tools.cmake @('--build',$BuildDirectory,'--target','assault','--parallel',[string]$Jobs) 'Compiling native executable'
  Test-BuildCancel
  $built=Join-Path $BuildDirectory 'assault.exe'
  if(-not(Test-Path -LiteralPath $built -PathType Leaf)){throw 'The build did not produce assault.exe.'}
  $imageAfterBuild=Get-Item -LiteralPath $GameImage -ErrorAction Stop
  if($imageAfterBuild.Length -ne $image.Length -or $imageAfterBuild.LastWriteTimeUtc.Ticks -ne $image.LastWriteTimeUtc.Ticks){throw 'The selected game image changed during the build. The previous native executable was kept; run the build again with the unchanged image.'}
  if(Test-NativeGameRunning){throw 'Close the game before installing the new build.'}
  Set-BuildStatus 'running' 'Installing native build' 'Keeping the previous executable until the new build is ready.'
  $destination=Split-Path -Parent $executable
  [void][IO.Directory]::CreateDirectory($destination)
  $hash=(Get-FileHash -LiteralPath $built -Algorithm SHA256).Hash
  $alreadyInstalled=(Test-Path -LiteralPath $executable) -and $hash -eq (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash
  if($alreadyInstalled){Write-Host 'The installed executable already matches; retaining the previous-build backup.'}
  else {
    $pending=Join-Path $destination ('assault.new-'+[guid]::NewGuid().ToString('N')+'.exe')
    Copy-Item -LiteralPath $built -Destination $pending
    if($hash -ne (Get-FileHash -LiteralPath $pending -Algorithm SHA256).Hash){throw 'Native executable copy verification failed.'}
    Test-BuildCancel
    if(Test-Path -LiteralPath $executable){[IO.File]::Replace($pending,$executable,(Join-Path $destination 'assault.previous.exe'))}
    else {Move-Item -LiteralPath $pending -Destination $executable}
  }
  [ordered]@{schema_version=2;built_at=(Get-Date).ToUniversalTime().ToString('o');source_sha256=$fingerprint;image=$GameImage;image_size=[long]$image.Length;image_modified_utc_ticks=[long]$image.LastWriteTimeUtc.Ticks;image_sha256=$imageSha256;game_id=$imageInfo.game_id;executable_sha256=$hash;compiler=$tools.cc;diagnostic=[bool]$DiagnosticBuild} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $project 'user-data\native-build-info.json') -Encoding UTF8
  Set-BuildStatus 'succeeded' 'Ready to play' 'The native build is complete.' 100
} catch [OperationCanceledException] {
  Set-BuildStatus 'cancelled' 'Cancelled' 'Build cancelled; the previous executable and saves were retained.'
  exit 2
} catch {
  Set-BuildStatus 'failed' 'Build failed' $_.Exception.Message
  Write-Error $_.Exception.Message -ErrorAction Continue
  exit 1
} finally {
  if($script:active){
    if(-not $script:active.HasExited){& ([IO.Path]::Combine([Environment]::SystemDirectory,'taskkill.exe')) /PID $script:active.Id /T /F | Out-Null}
    $script:active.Dispose()
  }
  if($lock){$lock.Dispose()}
  if($pending -and (Test-Path -LiteralPath $pending)){Remove-Item -LiteralPath $pending -Force}
  $env:PATH=$oldPath
}
