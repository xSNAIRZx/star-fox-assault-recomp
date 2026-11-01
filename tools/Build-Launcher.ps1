$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $PSScriptRoot 'LauncherBootstrap.cs'
$outputPath = Join-Path $projectDir 'Star Fox Assault Recomp.exe'
$iconPath = Join-Path $projectDir 'assets\assault-launcher.ico'
if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) { & (Join-Path $PSScriptRoot 'Build-LauncherIcon.ps1') }
$compilerCandidates = @(
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$compilerPath = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $compilerPath) { throw 'The .NET Framework C# compiler was not found. Install the .NET Framework 4.x developer tools.' }
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Bootstrap source not found: $sourcePath" }

$arguments = @(
  '/nologo',
  '/target:winexe',
  '/platform:anycpu',
  "/out:$outputPath",
  "/win32icon:$iconPath",
  '/reference:System.dll',
  '/reference:System.Windows.Forms.dll',
  $sourcePath
)
& $compilerPath @arguments
if ($LASTEXITCODE -ne 0) { throw "C# compiler exited with code $LASTEXITCODE." }
if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw 'The launcher executable was not produced.' }
Write-Output "Built $outputPath"
