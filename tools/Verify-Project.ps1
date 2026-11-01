param(
  [Parameter(Mandatory=$true)][string]$OriginalImage,
  [string]$ExpectedImageSha256 = ''
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$checks = New-Object 'System.Collections.Generic.List[object]'
function Add-Check([string]$name, [bool]$passed, [string]$evidence) {
  $checks.Add([pscustomobject]@{ name=$name; passed=$passed; evidence=$evidence })
}

# Read the supplied image directly. No extraction, conversion or write access is used here.
if (Test-Path -LiteralPath $OriginalImage -PathType Leaf) {
  $originalHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $OriginalImage).Hash
  $matchesExpected = [string]::IsNullOrWhiteSpace($ExpectedImageSha256) -or ($originalHash -eq $ExpectedImageSha256.Trim())
  $description = if ([string]::IsNullOrWhiteSpace($ExpectedImageSha256)) { 'Readable user-supplied image; no baseline hash requested' } else { "Expected hash match; SHA256=$originalHash" }
  Add-Check 'Supplied image read-only hash check' $matchesExpected $description
} else { Add-Check 'Supplied image read-only hash check' $false "Missing: $OriginalImage" }

$scriptFiles=@('Launch-StarFoxAssault.ps1') + @(Get-ChildItem -LiteralPath (Join-Path $project 'tools') -Filter '*.ps1' -File | ForEach-Object { 'tools\'+$_.Name })
foreach ($relative in $scriptFiles) {
  $tokens=$null; $errors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $project $relative),[ref]$tokens,[ref]$errors)
  Add-Check "PowerShell syntax: $relative" ($errors.Count -eq 0) (($errors | ForEach-Object Message) -join '; ')
}

$native = Join-Path $project 'build-desktop\Release\assault.exe'
if (Test-Path -LiteralPath $native -PathType Leaf) {
  $artifact=Get-Item -LiteralPath $native
  Add-Check 'Native executable exists' $true ("{0} bytes; SHA256={1}" -f $artifact.Length,(Get-FileHash -Algorithm SHA256 -LiteralPath $native).Hash)
} else { Add-Check 'Native executable exists' $false $native }

$bootstrap = Join-Path $project 'Star Fox Assault Recomp.exe'
if (Test-Path -LiteralPath $bootstrap -PathType Leaf) {
  Add-Check 'Windows launcher executable exists' $true ("SHA256={0}" -f (Get-FileHash -Algorithm SHA256 -LiteralPath $bootstrap).Hash)
} else { Add-Check 'Windows launcher executable exists' $false $bootstrap }

$config=Get-Content -LiteralPath (Join-Path $project 'CMakeLists.txt') -Raw
$moduleList=[regex]::Match($config,'(?s)set\(ASSAULT_REL_MODULES\s+([^)]*)\)')
$modules=@($moduleList.Groups[1].Value.Trim() -split '\s+' | Where-Object { $_ })
$expectedModules=@('md0','md1','md2','m0','m009','m1','m10','m2','m3','m4','m5','m6','m7','m8','m9','mb01a','mb01b','mb02','mb05','mb10a','mbg0','mbg1','mbg2')
$difference=@(Compare-Object $expectedModules $modules)
Add-Check 'All 23 standalone RELs configured' (($modules.Count -eq 23) -and ($difference.Count -eq 0)) ($modules -join ', ')
$missingMetadata=@()
foreach($module in $expectedModules) {
  foreach($leaf in @('symbols.txt','splits.txt')) {
    $relative="decomp\config\GF7E01\$module\$leaf"
    if(-not(Test-Path -LiteralPath (Join-Path $project $relative) -PathType Leaf)) { $missingMetadata+=$relative }
  }
}
Add-Check 'Source REL analysis metadata present' ($missingMetadata.Count -eq 0) ("46 metadata files expected; missing: {0}" -f ($missingMetadata -join ', '))
foreach ($relative in @('assets\assault-launcher-background.png','assets\assault-arwing-hangar.png','assets\assault-arwing-hangar.prompt.txt','assets\assault-launcher.ico','runtime\LICENSE','THIRD_PARTY_NOTICES.md')) {
  Add-Check "Required file: $relative" (Test-Path -LiteralPath (Join-Path $project $relative) -PathType Leaf) $relative
}
$fontHashes=@{
  'font_western.bin'='4AD991BE2B0AA305F09B90A79FC50F57833B30B008890B5EF1336CC3D9D0BAE0'
  'font_japanese.bin'='38F9F59D505BC4E2D86B0196706195F33AD72B7FE9D029CF263072CDE19D044F'
}
foreach($name in $fontHashes.Keys) {
  $font=Join-Path $project ('assets\fonts\'+$name)
  $hash=if(Test-Path -LiteralPath $font -PathType Leaf){(Get-FileHash -Algorithm SHA256 -LiteralPath $font).Hash}else{'missing'}
  Add-Check "Licensed system font: $name" ($hash -eq $fontHashes[$name]) $hash
}
Add-Check 'System font license present' (Test-Path -LiteralPath (Join-Path $project 'assets\fonts\font-licenses.txt') -PathType Leaf) 'Apache-2.0 attribution and license retained'

$report = [pscustomobject]@{
  checkedAt=(Get-Date).ToUniversalTime().ToString('o')
  scope='Original-image preservation, launcher syntax, and local artifact presence. Does not establish gameplay or feature compatibility.'
  passed=(@($checks | Where-Object { -not $_.passed }).Count -eq 0)
  checks=@($checks.ToArray())
}
$reportDir=Join-Path $project 'user-data\verification'
[void][IO.Directory]::CreateDirectory($reportDir)
$reportPath=Join-Path $reportDir 'project-verification.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$checks | Format-Table name,passed,evidence -Wrap
Write-Host "Report: $reportPath"
if (-not $report.passed) { exit 1 }
