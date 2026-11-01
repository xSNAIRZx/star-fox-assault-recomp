param(
  [Parameter(Mandatory=$true)][string]$GameImage,
  [string]$NativeExecutable='',
  [ValidateRange(1,300)][int]$Seconds=20,
  [string]$InputScript='120:START:30,1200:START:30,2200:START:30',
  [ValidateRange(100,10000)][int]$DumpEvery=500,
  [ValidateSet(0,1)][int]$VSync=0,
  [ValidateRange(0,100)][int]$Volume=100,
  [ValidateRange(0,8)][double]$Scale=1,
  [ValidateSet('original','widescreen','stretch')][string]$Aspect='original',
  [ValidateSet('off','fxaa')][string]$AntiAliasing='off',
  [ValidateSet('sharp','smooth')][string]$OutputFilter='sharp',
  [switch]$CaptureOutput,
  [string]$SeedMemoryCard='',
  [switch]$Fast,
  [switch]$ShowWindow
)
$ErrorActionPreference='Stop'
if($Fast -and $ShowWindow){throw 'Accelerated checks must remain hidden. Omit -ShowWindow.'}
$project=Split-Path -Parent $PSScriptRoot
$native=Join-Path $project 'build-desktop\Release\assault.exe'
if($NativeExecutable){$native=[IO.Path]::GetFullPath($NativeExecutable)}
if(-not(Test-Path -LiteralPath $native -PathType Leaf)){throw 'Build the native game first.'}
if(-not(Test-Path -LiteralPath $GameImage -PathType Leaf)){throw 'The selected disc image is missing.'}
$stamp=('{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),[Guid]::NewGuid().ToString('N').Substring(0,8))
$run=Join-Path $project ('user-data\validation-runs\'+$stamp)
$frames=Join-Path $run 'frames'
[void][IO.Directory]::CreateDirectory($frames)
$seedHash=$null
if($SeedMemoryCard){
  $seed=Get-Item -LiteralPath $SeedMemoryCard -ErrorAction Stop
  if($seed.PSIsContainer -or $seed.Length -ne 524288){throw 'A seed card must be an existing 524,288-byte native memory card.'}
  $seedHash=(Get-FileHash -LiteralPath $seed.FullName -Algorithm SHA256).Hash
  $saveDir=Join-Path $run 'saves'
  [void][IO.Directory]::CreateDirectory($saveDir)
  Copy-Item -LiteralPath $seed.FullName -Destination (Join-Path $saveDir 'memcard_a.raw')
}
$oldInput=[Environment]::GetEnvironmentVariable('GCN_INPUT','Process')
$oldFonts=[Environment]::GetEnvironmentVariable('GCN_FONT_DIR','Process')
$oldMods=[Environment]::GetEnvironmentVariable('GCN_MODS_DIR','Process')
$oldTimeScale=[Environment]::GetEnvironmentVariable('GCN_TIMESCALE','Process')
$oldAudioDriver=[Environment]::GetEnvironmentVariable('SDL_AUDIODRIVER','Process')
$oldRamDump=[Environment]::GetEnvironmentVariable('GCN_RAM_DUMP','Process')
$oldDumpOutput=[Environment]::GetEnvironmentVariable('GCN_DUMP_OUTPUT','Process')
try {
  [Environment]::SetEnvironmentVariable('GCN_DUMP_OUTPUT',$(if($CaptureOutput){'1'}else{'0'}),'Process')
  [Environment]::SetEnvironmentVariable('GCN_RAM_DUMP',(Join-Path $run 'guest-crash-ram.bin'),'Process')
  if(-not $ShowWindow){[Environment]::SetEnvironmentVariable('SDL_AUDIODRIVER','dummy','Process')}
  [Environment]::SetEnvironmentVariable('GCN_TIMESCALE','1','Process')
  [Environment]::SetEnvironmentVariable('GCN_INPUT',$InputScript,'Process')
  [Environment]::SetEnvironmentVariable('GCN_FONT_DIR',(Join-Path $project 'assets\fonts'),'Process')
  [Environment]::SetEnvironmentVariable('GCN_MODS_DIR',$null,'Process')
  $scaleArgument=$Scale.ToString('0.###',[Globalization.CultureInfo]::InvariantCulture)
  $arguments=@("--scale=$scaleArgument","--aspect=$Aspect","--aa=$AntiAliasing","--filter=$OutputFilter",'--no-music','--log=os,exi','--input-log=input',('--dump-dir="'+$frames+'"'),("--dump-every=$DumpEvery"),('"'+[IO.Path]::GetFullPath($GameImage)+'"'))
  $arguments+=@("--vsync=$VSync","--volume=$Volume")
  if($Fast){$arguments+='--fast'}
  if(-not $ShowWindow){$arguments+=@('--hidden','--script-only')}
  $game=Start-Process -FilePath $native -ArgumentList $arguments -WorkingDirectory $run -RedirectStandardError (Join-Path $run 'run.err') -RedirectStandardOutput (Join-Path $run 'run.out') -PassThru
} finally {
  [Environment]::SetEnvironmentVariable('GCN_INPUT',$oldInput,'Process')
  [Environment]::SetEnvironmentVariable('GCN_FONT_DIR',$oldFonts,'Process')
  [Environment]::SetEnvironmentVariable('GCN_MODS_DIR',$oldMods,'Process')
  [Environment]::SetEnvironmentVariable('GCN_TIMESCALE',$oldTimeScale,'Process')
  [Environment]::SetEnvironmentVariable('SDL_AUDIODRIVER',$oldAudioDriver,'Process')
  [Environment]::SetEnvironmentVariable('GCN_RAM_DUMP',$oldRamDump,'Process')
  [Environment]::SetEnvironmentVariable('GCN_DUMP_OUTPUT',$oldDumpOutput,'Process')
}
$watch=[Diagnostics.Stopwatch]::StartNew()
while(-not $game.HasExited -and $watch.Elapsed.TotalSeconds -lt $Seconds){Start-Sleep -Milliseconds 200; $game.Refresh()}
$survived=-not $game.HasExited
$forced=$false
if($survived){
  [void]$game.CloseMainWindow()
  if(-not $game.WaitForExit(3000)){$game.Kill();$game.WaitForExit();$forced=$true}
}
$game.Refresh()
$report=[ordered]@{
  scope='Bounded native run and artifact collection; gameplay and visual correctness require inspecting the frames.'
  executableSha256=(Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash
  executablePath=$native
  runDirectory=$run; processId=$game.Id; durationSeconds=[Math]::Round($watch.Elapsed.TotalSeconds,2)
  requestedSeconds=$Seconds; survivedUntilTimeLimit=$survived; forcedTermination=$forced; exitCode=$game.ExitCode
  inputScript=$InputScript; fast=[bool]$Fast
  hidden=(-not [bool]$ShowWindow)
  silent=(-not [bool]$ShowWindow)
  seedCardSha256=$seedHash
  requestedVSync=$VSync
  requestedVolume=$Volume
  requestedScale=$Scale
  requestedAspect=$Aspect
  requestedAntiAliasing=$AntiAliasing
  requestedOutputFilter=$OutputFilter
  capturedOutput=[bool]$CaptureOutput
  crashRamDump=(Test-Path -LiteralPath (Join-Path $run 'guest-crash-ram.bin'))
  capturedFrames=@(Get-ChildItem -LiteralPath $frames -Filter 'frame_*.png' -File).Count
  capturedOutputFrames=@(Get-ChildItem -LiteralPath $frames -Filter 'output_*.png' -File).Count
}
$report | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding UTF8
Write-Output "Run artifacts: $run"
$report | ConvertTo-Json
if(-not $survived -and $game.ExitCode -ne 0){exit 1}
