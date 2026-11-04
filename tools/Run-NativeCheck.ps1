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
function Quote-NativeArgument([string]$value) {
  '"'+([regex]::Replace([regex]::Replace($value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1'))+'"'
}
$scaleArgument=$Scale.ToString('0.###',[Globalization.CultureInfo]::InvariantCulture)
$arguments=@("--scale=$scaleArgument","--aspect=$Aspect","--aa=$AntiAliasing","--filter=$OutputFilter",'--no-music','--log=os,exi','--input-log=input',('--dump-dir='+$frames),("--dump-every=$DumpEvery"),[IO.Path]::GetFullPath($GameImage))
$arguments+=@("--vsync=$VSync","--volume=$Volume")
if($Fast){$arguments+='--fast'}
if(-not $ShowWindow){$arguments+=@('--hidden','--script-only')}
$psi=New-Object Diagnostics.ProcessStartInfo
$psi.FileName=$native
$psi.Arguments=($arguments | ForEach-Object {Quote-NativeArgument $_}) -join ' '
$psi.WorkingDirectory=$run
$psi.UseShellExecute=$false
$psi.RedirectStandardOutput=$true
$psi.RedirectStandardError=$true
if(-not $ShowWindow){
  $psi.CreateNoWindow=$true
  $psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
}
# Configure only the child environment. Unrelated diagnostics, replay/input paths,
# speed overrides and mods must not influence a supposedly isolated smoke run.
foreach($key in @($psi.EnvironmentVariables.Keys)){
  if($key -like 'GCN_*'){$psi.EnvironmentVariables.Remove($key)}
}
$psi.EnvironmentVariables['GCN_DUMP_OUTPUT']=$(if($CaptureOutput){'1'}else{'0'})
$psi.EnvironmentVariables['GCN_RAM_DUMP']=Join-Path $run 'guest-crash-ram.bin'
$psi.EnvironmentVariables['GCN_TIMESCALE']='1'
$psi.EnvironmentVariables['GCN_INPUT']=$InputScript
$psi.EnvironmentVariables['GCN_FONT_DIR']=Join-Path $project 'assets\fonts'
if(-not $ShowWindow){$psi.EnvironmentVariables['SDL_AUDIODRIVER']='dummy'}
$game=New-Object Diagnostics.Process
$game.StartInfo=$psi
$stdout=$null;$stderr=$null;$started=$false;$forced=$false
$watch=[Diagnostics.Stopwatch]::new()
try {
  $stdout=[IO.File]::Open((Join-Path $run 'run.out'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  $stderr=[IO.File]::Open((Join-Path $run 'run.err'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  if(-not $game.Start()){throw 'Could not start the native check process.'}
  $started=$true
  $watch.Start()
  $outTask=$game.StandardOutput.BaseStream.CopyToAsync($stdout)
  $errTask=$game.StandardError.BaseStream.CopyToAsync($stderr)
  # Keep the original process handle through exit: Start-Process followed by Refresh
  # can lose ExitCode on Windows PowerShell 5.1, especially after forced termination.
  $survived=-not $game.WaitForExit($Seconds*1000)
  if($survived){
    [void]$game.CloseMainWindow()
    if(-not $game.WaitForExit(3000)){$game.Kill();$forced=$true}
  }
  $game.WaitForExit()
  $null=$outTask.GetAwaiter().GetResult()
  $null=$errTask.GetAwaiter().GetResult()
  $watch.Stop()
  $exitCode=$game.ExitCode
  $report=[ordered]@{
    scope='Bounded native run and artifact collection; gameplay and visual correctness require inspecting the frames.'
    executableSha256=(Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash
    executablePath=$native
    runDirectory=$run; processId=$game.Id; durationSeconds=[Math]::Round($watch.Elapsed.TotalSeconds,2)
    requestedSeconds=$Seconds; survivedUntilTimeLimit=$survived; forcedTermination=$forced; exitCode=$exitCode
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
} finally {
  if($started -and -not $game.HasExited){$game.Kill();$game.WaitForExit()}
  if($stdout){$stdout.Dispose()}
  if($stderr){$stderr.Dispose()}
  $game.Dispose()
}
# An early zero exit is not a successful bounded smoke run either.
if(-not $survived -or (-not $forced -and $exitCode -ne 0)){exit 1}
