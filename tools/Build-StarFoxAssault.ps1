param(
  [Parameter(Mandatory=$true)][string]$GameImage,
  [switch]$UsePortableToolchain,
  [string]$ProgressFile='', [string]$CancelFile='', [string]$BuildDirectory='',
  [ValidateRange(0,32)][int]$Jobs=0,
  [switch]$Offline, [switch]$DiagnosticBuild
)
$ErrorActionPreference='Stop'
try {
  & (Join-Path $PSScriptRoot 'Build-NativeGame.ps1') @PSBoundParameters
  exit $LASTEXITCODE
} catch {
  Write-Error $_ -ErrorAction Continue
  exit 1
}
