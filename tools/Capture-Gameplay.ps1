# Capture evidence only; this script does not repair either gameplay defect.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$GameImage,
  [ValidateSet('Both','Thread','Boss')][string]$Mode='Both',
  [string]$Executable='', [string]$ReplayDirectory='', [string]$MemoryCard='',
  [string]$OutputRoot='',
  [ValidateSet('original','widescreen')][string]$Aspect='original',
  [Nullable[uint32]]$DrawFrame=$null,
  [uint32[]]$RamFrames=@(),
  [ValidateRange(0,86400)][int]$StopAfterSeconds=0,
  [string]$InputScript='',
  [switch]$LogHostKeys,
  [switch]$Hidden,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if(-not $Executable){$Executable=Join-Path $project 'build-desktop\Release\assault.exe'}
if(-not $OutputRoot){$OutputRoot=Join-Path $project 'user-data\captures'}
$Executable=[IO.Path]::GetFullPath($Executable)
$GameImage=[IO.Path]::GetFullPath($GameImage)
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
if($ReplayDirectory -and $MemoryCard){throw 'Use ReplayDirectory or MemoryCard, not both.'}
if($Mode -eq 'Thread' -and ($null -ne $DrawFrame -or $RamFrames.Count)){throw 'Frame capture options require Boss or Both mode.'}
if($null -ne $DrawFrame -and $DrawFrame -eq 0){throw 'DrawFrame must be positive; zero disables draw logging in the runtime.'}
$session=Join-Path $OutputRoot ((Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
$run=Join-Path $session 'run'
$argsList=@('--scale=1',"--aspect=$Aspect",'--aa=off','--filter=sharp','--vsync=1',('--input-log='+ (Join-Path $session 'inputs')))
if($ReplayDirectory){$argsList+=('--replay='+ (Join-Path $session 'replay'))}
$captureEnv=[ordered]@{GCN_TIMESCALE='1';GCN_CLOCKLOG='1';GCN_FONT_DIR=(Join-Path $project 'assets\fonts');GCN_RAM_DUMP=(Join-Path $session 'crash.ram.bin')}
if($InputScript){
  if($ReplayDirectory){throw 'Use InputScript or ReplayDirectory, not both.'}
  $captureEnv.GCN_INPUT=$InputScript
}
if($LogHostKeys){$captureEnv.GCN_LOG_HOST_KEYS='1'}
if($Hidden){
  $argsList+=@('--hidden','--script-only')
  $captureEnv.SDL_AUDIODRIVER='dummy'
}
if($Mode -in @('Thread','Both')){$captureEnv.GCN_GUARD='800000E4';$captureEnv.GCN_WATCH_ADDR='800000E4'}
if($Mode -in @('Boss','Both')){$captureEnv.GCN_VERTCHECK='1'}
if($null -ne $DrawFrame){
  $captureEnv.GCN_DRAWLOG=[string]$DrawFrame
  $captureEnv.GCN_MTXLOG=[string]$DrawFrame
  $captureEnv.GCN_DUMP_RANGE=('{0}-{0}' -f $DrawFrame)
  $argsList+=@('--dump-every=1',('--dump-dir='+ (Join-Path $session 'frames')))
}
if($RamFrames.Count){$captureEnv.GCN_RAM_DUMP_AT=($RamFrames -join ',');$captureEnv.GCN_RAM_DUMP_DIR=(Join-Path $session 'ram')}
$argsList+=$GameImage
$plan=[ordered]@{schema_version=1;mode=$Mode;executable=$Executable;image=$GameImage;session=$session;working_directory=$run;arguments=$argsList;environment=$captureEnv;stop_after_seconds=$StopAfterSeconds;validation='Capture tooling only; neither gameplay bug is claimed fixed.'}
if($PlanOnly){$plan | ConvertTo-Json -Depth 6; return}
foreach($path in @($Executable,$GameImage)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Required file missing: $path"}}
if($ReplayDirectory){
  $ReplayDirectory=[IO.Path]::GetFullPath($ReplayDirectory)
  if(-not(Test-Path -LiteralPath (Join-Path $ReplayDirectory 'inputs.txt') -PathType Leaf)){throw 'ReplayDirectory must contain inputs.txt; preserve its starting card too.'}
  if(-not(Test-Path -LiteralPath (Join-Path $ReplayDirectory 'memcard_a.raw') -PathType Leaf)){throw 'ReplayDirectory lacks its starting memcard_a.raw snapshot; the runtime refuses replay without it. Record again with MemoryCard set before launch.'}
}
if(-not $ReplayDirectory -and -not $MemoryCard){
  $existing=Join-Path $project 'user-data\native-run\saves\memcard_a.raw'
  if(Test-Path -LiteralPath $existing -PathType Leaf){$MemoryCard=$existing}
}
if($MemoryCard -and -not(Test-Path -LiteralPath $MemoryCard -PathType Leaf)){throw 'MemoryCard was not found.'}
if(-not $ReplayDirectory -and -not $MemoryCard){Write-Warning 'Fresh-card run: the runtime records input before creating its card, so this recording will lack a replay snapshot. For a replayable recording, repeat with -MemoryCard pointing to this session run\saves\memcard_a.raw. Do not substitute the later card into the earlier recording.'}
if(Get-Process -Name assault -ErrorAction SilentlyContinue){throw 'Close the game before capturing.'}
foreach($dir in @($run,(Join-Path $run 'saves'),(Join-Path $session 'ram'),(Join-Path $session 'frames'))){[void][IO.Directory]::CreateDirectory($dir)}
if($ReplayDirectory){
  # The runtime writes memcard_replay.raw beside inputs.txt. Use a private copy.
  $replay=Join-Path $session 'replay';[void][IO.Directory]::CreateDirectory($replay)
  foreach($name in @('inputs.txt','memcard_a.raw')){
    $source=Join-Path $ReplayDirectory $name
    if(Test-Path -LiteralPath $source -PathType Leaf){Copy-Item -LiteralPath $source -Destination (Join-Path $replay $name)}
  }
} elseif($MemoryCard){Copy-Item -LiteralPath $MemoryCard -Destination (Join-Path $run 'saves\memcard_a.raw')}
$controls=Join-Path $project 'user-data\native-run\controls.txt'
if(Test-Path -LiteralPath $controls -PathType Leaf){Copy-Item -LiteralPath $controls -Destination (Join-Path $run 'controls.txt')}
$plan.executable_sha256=(Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash
$plan.starting_card_present=[bool]($ReplayDirectory -or $MemoryCard)
$image=Get-Item -LiteralPath $GameImage
$plan.image_size=$image.Length;$plan.image_modified_utc=$image.LastWriteTimeUtc.ToString('o')
$buildInfo=Join-Path $project 'user-data\native-build-info.json'
if(Test-Path -LiteralPath $buildInfo -PathType Leaf){
  Copy-Item -LiteralPath $buildInfo -Destination (Join-Path $session 'native-build-info.json')
  $info=Get-Content -LiteralPath $buildInfo -Raw | ConvertFrom-Json
  if($Mode -in @('Thread','Both') -and -not $info.diagnostic){Write-Warning 'Build record is not diagnostic: guard works, but per-store thread-watch output is unavailable.'}
}
$plan | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $session 'capture.json') -Encoding UTF8
function Quote-NativeArgument([string]$value){'"'+([regex]::Replace([regex]::Replace($value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1'))+'"'}
$psi=New-Object Diagnostics.ProcessStartInfo
$psi.FileName=$Executable;$psi.WorkingDirectory=$run;$psi.UseShellExecute=$false
$psi.Arguments=($argsList | ForEach-Object {Quote-NativeArgument $_}) -join ' '
$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
# Keep unrelated debugging, speed, input and mod settings out of this capture.
foreach($key in @($psi.EnvironmentVariables.Keys)){if($key -like 'GCN_*'){$psi.EnvironmentVariables.Remove($key)}}
foreach($key in $captureEnv.Keys){$psi.EnvironmentVariables[$key]=[string]$captureEnv[$key]}
$process=New-Object Diagnostics.Process;$process.StartInfo=$psi
$stdout=$null;$stderr=$null;$forced=$false;$started=$false
Write-Host "Capture folder: $session"
try {
  # Permit live readers, but prevent another writer or deletion during capture.
  $stdout=[IO.File]::Open((Join-Path $session 'stdout.log'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  $stderr=[IO.File]::Open((Join-Path $session 'stderr.log'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  if(-not $process.Start()){throw 'Could not start native executable.'}
  $started=$true
  $outTask=$process.StandardOutput.BaseStream.CopyToAsync($stdout)
  $errTask=$process.StandardError.BaseStream.CopyToAsync($stderr)
  $watch=[Diagnostics.Stopwatch]::StartNew()
  while(-not $process.WaitForExit(200)){
    if($StopAfterSeconds -gt 0 -and $watch.Elapsed.TotalSeconds -ge $StopAfterSeconds){
      $forced=$true;$process.Kill();break
    }
  }
  $process.WaitForExit();$null=$outTask.GetAwaiter().GetResult();$null=$errTask.GetAwaiter().GetResult()
  [ordered]@{exit_code=$process.ExitCode;forced_stop=$forced;finished_utc=[DateTime]::UtcNow.ToString('o');note='A forced stop may leave input logs incomplete and does not establish gameplay success.'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $session 'result.json') -Encoding UTF8
  Write-Host "Capture finished: exit $($process.ExitCode), forced stop: $forced"
} finally {
  # Disposing Process only releases its handle. Do not leave this capture's
  # child running if collection fails or the PowerShell invocation is cancelled.
  if($started -and -not $process.HasExited){$process.Kill();$process.WaitForExit()}
  if($stdout){$stdout.Dispose()};if($stderr){$stderr.Dispose()};$process.Dispose()
}
