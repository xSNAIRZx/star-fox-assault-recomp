param(
  [Parameter(Mandatory=$true)][string]$GameImage,
  [switch]$UsePortableToolchain,
  [string]$ProgressFile='', [string]$CancelFile='', [string]$BuildDirectory='',
  [ValidateRange(1,32)][int]$Jobs=([Math]::Min(8,[Math]::Max(1,[Environment]::ProcessorCount-2))),
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
    if(Test-Path -LiteralPath $full){[IO.File]::Replace($pendingStatus,$full,$full+'.previous')}else{[IO.File]::Move($pendingStatus,$full)}
  }
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
    $line=Get-Content -LiteralPath $stdout -Tail 1 -ErrorAction SilentlyContinue
    if($line -and $line -ne $last){
      $last=$line
      if($line -match '^\[(\d+)/(\d+)\]'){Set-BuildStatus 'running' $Phase $line ([Math]::Round(100.0*[int]$Matches[1]/[int]$Matches[2],1))}
      else {Write-Host $line}
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
function Get-SourceFingerprint {
  $paths=@('CMakeLists.txt','tools\portable-toolchain.json','tools\Build-NativeGame.ps1','tools\Build-StarFoxAssault.ps1','tools\Ensure-PortableToolchain.ps1','tools\Build-CacheSignature.ps1')
  foreach($folder in @('runtime','recomp','decomp\config\GF7E01')){
    $paths+=@(Get-ChildItem -LiteralPath (Join-Path $project $folder) -Recurse -File | Where-Object {$_.Extension -in @('.c','.cc','.cpp','.h','.hpp','.py','.txt','.cmake','.in','.rc','.manifest','.inc','.glsl','.glslinc','.frag','.vert','.geom','.comp') -and $_.FullName -notmatch '[\\/](build|__pycache__)[\\/]'} | ForEach-Object {$_.FullName.Substring($project.Length+1)})
  }
  return Get-FileSetFingerprint $project $paths
}
try {
  Set-BuildStatus 'running' 'Checking image' 'Validating your local ISO/CISO.'
  if(-not(Test-Path -LiteralPath $GameImage -PathType Leaf)){throw 'The selected game image was not found.'}
  if(Get-Process -Name assault -ErrorAction SilentlyContinue){throw 'Close the running game before rebuilding.'}
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
  $settings=[ordered]@{project=$project;image=$GameImage;image_size=$image.Length;image_modified=$image.LastWriteTimeUtc.Ticks;image_sha256=$imageSha256;source=$fingerprint;compiler=$tools.cc;diagnostic=[bool]$DiagnosticBuild}
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
  } else {Set-BuildStatus 'running' 'Using build cache' 'Source and image are unchanged; checking the cached native build.'}
  Set-BuildStatus 'running' 'Compiling native executable' 'Compiling the recompiled game and runtime.'
  Invoke-BuildProcess $tools.cmake @('--build',$BuildDirectory,'--target','assault','--parallel',[string]$Jobs) 'Compiling native executable'
  Test-BuildCancel
  $built=Join-Path $BuildDirectory 'assault.exe'
  if(-not(Test-Path -LiteralPath $built -PathType Leaf)){throw 'The build did not produce assault.exe.'}
  if(Get-Process -Name assault -ErrorAction SilentlyContinue){throw 'Close the game before installing the new build.'}
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
  [ordered]@{schema_version=1;built_at=(Get-Date).ToUniversalTime().ToString('o');source_sha256=$fingerprint;image=$GameImage;game_id=$imageInfo.game_id;executable_sha256=$hash;compiler=$tools.cc;diagnostic=[bool]$DiagnosticBuild} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $project 'user-data\native-build-info.json') -Encoding UTF8
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
