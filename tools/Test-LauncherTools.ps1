# Static audit of the launcher's runtime dependencies.
# Every project path the launcher opens must exist, and the package and update scripts must
# ship it: named in their required-file lists or covered by a source tree they copy. Run it
# after adding a tool, so a missing file fails here instead of on the user's machine.
param([string]$ProjectRoot = '')

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)

function Read-ProjectText([string]$relative) {
  $path = Join-Path $ProjectRoot $relative
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file is missing from the repository: $relative" }
  return [IO.File]::ReadAllText($path)
}

function Get-RequiredEntries([string]$text,[string]$variable) {
  $start = $text.IndexOf($variable)
  if ($start -lt 0) { throw "Could not find $variable in the packaging script." }
  $end = $text.IndexOf([string][char]10 + '  )', $start)
  if ($end -lt 0) { $end = $text.IndexOf([string][char]10 + ')', $start) }
  if ($end -lt 0) { throw "Could not find the end of $variable." }
  $block = $text.Substring($start, $end - $start)
  return @([regex]::Matches($block, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
}

$launcher = Read-ProjectText 'Launch-StarFoxAssault.ps1'
$package = Read-ProjectText 'tools/Package-Prototype.ps1'
$update = Read-ProjectText 'tools/Install-PrototypeUpdate.ps1'

# Copied wholesale by the package, so anything under them ships.
$shippedTrees = @('tools','runtime','recomp','assets','decomp/config/GF7E01','third_party_licenses')
# Added one file at a time, or produced by packaging itself.
$shippedFiles = @('Launch-StarFoxAssault.ps1','Start-StarFoxAssault.cmd','Star Fox Assault Recomp.exe',
  'CMakeLists.txt','LICENSE','THIRD_PARTY_NOTICES.md','CREDITS.md','RELEASE-NOTES.md','portable.txt',
  'README-PROTOTYPE.txt','VALIDATION.md','release.json','SHA256SUMS.txt')
# The launcher creates these itself.
$runtimePaths = @('build-desktop','user-data')

$failures = 0
$checked = 0

foreach ($match in [regex]::Matches($launcher, 'Join-Path\s+\$script:projectDir\s+''([^'']+)''')) {
  $relative = $match.Groups[1].Value.Replace('\','/')
  $top = ($relative -split '/')[0]
  if ($runtimePaths -contains $top) { continue }
  $checked++
  if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $relative))) {
    Write-Output "MISSING: the launcher opens $relative, which is not in the repository"
    $failures++
    continue
  }
  if ($shippedFiles -contains $relative) { continue }
  $covered = $false
  foreach ($tree in $shippedTrees) {
    if ($relative -eq $tree -or $relative.StartsWith($tree + '/')) { $covered = $true; break }
  }
  if (-not $covered) {
    Write-Output "NOT PACKAGED: $relative exists, but no packaging rule ships it"
    $failures++
  }
}

$lists = @(
  @{ Text = $package; Variable = '$required'; Label = 'the package script' },
  @{ Text = $update; Variable = '$requiredFiles'; Label = 'the update installer' }
)
$requiredByList = @{}
# Shipped files that are build outputs, not tracked in Git: the source they are built from
# must be in the repository instead.
$builtFrom = @{ 'Star Fox Assault Recomp.exe' = 'tools/LauncherBootstrap.cs' }
foreach ($list in $lists) {
  $entries = Get-RequiredEntries $list.Text $list.Variable
  if (-not $entries.Count) { throw "No required-file entries were found in $($list.Label)." }
  $requiredByList[$list.Label] = $entries
  foreach ($entry in $entries) {
    $relative = $entry.Replace('\','/')
    if ($relative -eq 'tools/Package-Prototype.ps1') { continue }  # need not ship itself
    if ($builtFrom.ContainsKey($relative)) { $relative = $builtFrom[$relative] }
    $checked++
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $relative))) {
      Write-Output "MISSING: $($list.Label) requires $relative, which is not in the repository"
      $failures++
    }
  }
}

# The launcher's own dependencies must be required by both lists, not merely present.
$launcherNeeds = @('tools/Install-PrototypeUpdate.ps1','tools/Track-Session.ps1','tools/LauncherCore.ps1',
  'tools/portable-toolchain.json','runtime/recomp/rel.py','runtime/recomp/dol.py')
foreach ($needed in $launcherNeeds) {
  foreach ($list in $lists) {
    if (-not ($requiredByList[$list.Label] -contains $needed)) {
      Write-Output "NOT GUARDED: $($list.Label) does not require $needed"
      $failures++
    }
  }
}

Write-Output ("launcher tool audit: {0} paths checked, {1} problems" -f $checked,$failures)
if ($failures) { exit 1 }
Write-Output 'PASS every launcher tool is present and shipped'
