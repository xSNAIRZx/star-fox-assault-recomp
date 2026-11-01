param([Parameter(Mandatory=$true)][string]$GameImage)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$testDir=Join-Path $project ('user-data\verification\build-worker-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testDir)
$native=Join-Path $project 'build-desktop\Release\assault.exe'
$before=if(Test-Path -LiteralPath $native){(Get-FileHash -LiteralPath $native).Hash}else{$null}
$invalid=Join-Path $testDir 'invalid.iso'
[IO.File]::WriteAllBytes($invalid,[byte[]]::new(64))
$shell=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
$ErrorActionPreference='Continue'
& $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Build-StarFoxAssault.ps1') -GameImage $invalid -ProgressFile (Join-Path $testDir 'invalid-status.json') *> (Join-Path $testDir 'invalid.log')
$invalidExit=$LASTEXITCODE
$ErrorActionPreference='Stop'
$cancel=Join-Path $testDir 'cancel'
[IO.File]::WriteAllText($cancel,'cancel')
$ErrorActionPreference='Continue'
& $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Build-StarFoxAssault.ps1') -GameImage $GameImage -BuildDirectory (Join-Path $testDir 'cancel-cache') -ProgressFile (Join-Path $testDir 'cancel-status.json') -CancelFile $cancel *> (Join-Path $testDir 'cancel.log')
$cancelExit=$LASTEXITCODE
$ErrorActionPreference='Stop'
$after=if(Test-Path -LiteralPath $native){(Get-FileHash -LiteralPath $native).Hash}else{$null}
$result=[ordered]@{
  invalid_exit=$invalidExit
  invalid_state=(Get-Content -LiteralPath (Join-Path $testDir 'invalid-status.json') -Raw | ConvertFrom-Json).state
  cancel_exit=$cancelExit
  cancel_state=(Get-Content -LiteralPath (Join-Path $testDir 'cancel-status.json') -Raw | ConvertFrom-Json).state
  previous_executable_unchanged=($before -eq $after)
  report=$testDir
}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $testDir 'results.json')
$result | ConvertTo-Json
if($invalidExit -ne 1 -or $result.invalid_state -ne 'failed' -or $cancelExit -ne 2 -or $result.cancel_state -ne 'cancelled' -or $before -ne $after){exit 1}
