param(
  [Parameter(Mandatory=$true)][string]$GameImage,
  [switch]$UsePortableToolchain,
  [string]$ProgressFile='', [string]$CancelFile='', [string]$BuildDirectory='',
  [ValidateRange(1,32)][int]$Jobs=([Math]::Min(8,[Math]::Max(1,[Environment]::ProcessorCount-2))),
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
