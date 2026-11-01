param(
  [Parameter(Mandatory=$true)][string]$IsoPath,
  [string]$OutputPath = (Join-Path $PSScriptRoot '..\analysis\main.dol')
)
$ErrorActionPreference = 'Stop'
$iso = [IO.Path]::GetFullPath($IsoPath)
$out = [IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $iso -PathType Leaf)) { throw "Input image not found: $iso" }
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $out.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Output must remain inside the project folder.' }
if (Test-Path -LiteralPath $out) { throw "Refusing to overwrite existing output: $out" }
$stream = [IO.File]::Open($iso, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
  if ($stream.Length -lt 0x440) { throw 'Image is too small to contain a GameCube boot header.' }
  $header = [byte[]]::new(0x440)
  [void]$stream.Read($header, 0, $header.Length)
  $gameId = [Text.Encoding]::ASCII.GetString($header, 0, 6)
  if ($gameId -ne 'GF7E01') { throw "Expected Star Fox Assault USA GF7E01, found $gameId." }
  $magic = [BitConverter]::ToUInt32([byte[]]@($header[0x1F],$header[0x1E],$header[0x1D],$header[0x1C]),0)
  if ($magic -ne 0xC2339F3D) { throw 'GameCube disc magic did not match.' }
  $dolOffset = [BitConverter]::ToUInt32([byte[]]@($header[0x423],$header[0x422],$header[0x421],$header[0x420]),0)
  $fstOffset = [BitConverter]::ToUInt32([byte[]]@($header[0x427],$header[0x426],$header[0x425],$header[0x424]),0)
  if ($dolOffset -le 0 -or $dolOffset -ge $fstOffset -or ($dolOffset + 0x100) -gt $stream.Length) { throw 'Boot header contains invalid DOL/FST offsets.' }
  $stream.Position = $dolOffset
  $dolHeader = [byte[]]::new(0x100)
  [void]$stream.Read($dolHeader, 0, $dolHeader.Length)
  $end = 0
  foreach ($base in @(0x00,0x1C)) {
    $count = if ($base -eq 0) { 7 } else { 11 }
    for ($i=0; $i -lt $count; $i++) {
      $offPos = $base + $i*4
      $sizeBase = if ($base -eq 0) { 0x90 } else { 0xAC }
      $off = [BitConverter]::ToUInt32([byte[]]@($dolHeader[$offPos+3],$dolHeader[$offPos+2],$dolHeader[$offPos+1],$dolHeader[$offPos]),0)
      $size = [BitConverter]::ToUInt32([byte[]]@($dolHeader[$sizeBase+$i*4+3],$dolHeader[$sizeBase+$i*4+2],$dolHeader[$sizeBase+$i*4+1],$dolHeader[$sizeBase+$i*4]),0)
      if ($size -gt 0 -and ($off + $size) -gt $end) { $end = $off + $size }
    }
  }
  if ($end -lt 0x100 -or ($dolOffset + $end) -gt $fstOffset) { throw 'DOL section table is invalid or overlaps the filesystem table.' }
  $dol = [byte[]]::new([int]$end)
  $stream.Position = $dolOffset
  $read = 0
  while ($read -lt $dol.Length) {
    $n = $stream.Read($dol, $read, $dol.Length - $read)
    if ($n -le 0) { throw 'Unexpected end of input image while reading DOL.' }
    $read += $n
  }
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($out)) | Out-Null
  [IO.File]::WriteAllBytes($out, $dol)
  $sha = (Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash
  [pscustomobject]@{ GameId=$gameId; DolOffset=('0x{0:X}' -f $dolOffset); DolBytes=$end; Sha256=$sha; Output=$out }
} finally { $stream.Dispose() }
