function Get-FileSetFingerprint([string]$Root, [string[]]$RelativePaths) {
  $rootFull = [IO.Path]::GetFullPath($Root)
  $records = foreach ($relative in ($RelativePaths | Sort-Object -Unique)) {
    $path = Join-Path $rootFull $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Build signature input is missing: $relative" }
    $relative.Replace('\','/') + ' ' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  }
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($records -join "`n"))))).Replace('-','') }
  finally { $sha.Dispose() }
}

function Get-ImageContentFingerprint([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'The selected game image was not found.' }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
