param(
  [Parameter(Mandatory=$true)][int]$GameProcessId,
  [Parameter(Mandatory=$true)][long]$StartTimeUtcTicks,
  [Parameter(Mandatory=$true)][string]$SessionPath
)
$ErrorActionPreference='Stop'
$started=[DateTime]::new($StartTimeUtcTicks,[DateTimeKind]::Utc)
$watch=[Diagnostics.Stopwatch]::StartNew()
$initialSeconds=[Math]::Max(0,([DateTime]::UtcNow-$started).TotalSeconds)
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $SessionPath))
function Write-Session([bool]$finished) {
  $record=[ordered]@{
    version=1; processId=$GameProcessId; startedUtc=$started.ToString('o')
    seconds=[Math]::Round($initialSeconds+$watch.Elapsed.TotalSeconds,2)
    finished=$finished; updatedUtc=[DateTime]::UtcNow.ToString('o')
  }
  $temp=$SessionPath+'.tmp'
  [IO.File]::WriteAllText($temp,($record | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
  if([IO.File]::Exists($SessionPath)){[IO.File]::Replace($temp,$SessionPath,[NullString]::Value)}else{[IO.File]::Move($temp,$SessionPath)}
}
Write-Session $false
$ticks=0
while($true) {
  $game=Get-Process -Id $GameProcessId -ErrorAction SilentlyContinue
  if(-not $game){break}
  try{if($game.StartTime.ToUniversalTime().Ticks -ne $StartTimeUtcTicks){break}}catch{break}
  Start-Sleep -Seconds 1
  $ticks++
  if($ticks % 10 -eq 0){Write-Session $false}
}
Write-Session $true
