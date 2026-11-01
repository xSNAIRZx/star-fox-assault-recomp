$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Build-CacheSignature.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('assault-cache-signature-' + [guid]::NewGuid().ToString('N'))
$tools = Join-Path $root 'tools'
[IO.Directory]::CreateDirectory($tools) | Out-Null
try {
  $image = Join-Path $root 'game.iso'
  [IO.File]::WriteAllBytes($image,[byte[]](1,2,3,4,5,6,7,8))
  $fixedTime = [DateTime]::UtcNow.AddDays(-3)
  [IO.File]::SetLastWriteTimeUtc($image,$fixedTime)
  $firstImageHash = Get-ImageContentFingerprint $image
  $firstInfo = Get-Item -LiteralPath $image

  [IO.File]::WriteAllBytes($image,[byte[]](1,2,3,4,5,6,7,9))
  [IO.File]::SetLastWriteTimeUtc($image,$fixedTime)
  $secondImageHash = Get-ImageContentFingerprint $image
  $secondInfo = Get-Item -LiteralPath $image
  if ($firstInfo.Length -ne $secondInfo.Length -or $firstInfo.LastWriteTimeUtc.Ticks -ne $secondInfo.LastWriteTimeUtc.Ticks -or $firstImageHash -eq $secondImageHash) {
    throw 'Image content changes with identical size and timestamp were not distinguished.'
  }

  $workerNames = @('Build-NativeGame.ps1','Build-StarFoxAssault.ps1','Ensure-PortableToolchain.ps1')
  foreach ($name in $workerNames) { [IO.File]::WriteAllText((Join-Path $tools $name),'Option=ON') }
  $workerPaths = @($workerNames | ForEach-Object { 'tools/' + $_ })
  $workerBefore = Get-FileSetFingerprint $root $workerPaths
  [IO.File]::WriteAllText((Join-Path $tools 'Build-NativeGame.ps1'),'Option=OF')
  $workerAfter = Get-FileSetFingerprint $root $workerPaths
  if ($workerBefore -eq $workerAfter) { throw 'A build-worker flag change did not invalidate the source fingerprint.' }

  [pscustomobject]@{
    result = 'passed'
    same_image_size = ($firstInfo.Length -eq $secondInfo.Length)
    restored_image_timestamp = ($firstInfo.LastWriteTimeUtc.Ticks -eq $secondInfo.LastWriteTimeUtc.Ticks)
    image_checksum_changed = ($firstImageHash -ne $secondImageHash)
    build_worker_fingerprint_changed = ($workerBefore -ne $workerAfter)
  } | ConvertTo-Json
} finally {
  $cleanupRoot=[IO.Path]::GetFullPath($root)
  $tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
  if(-not $cleanupRoot.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $cleanupRoot) -notmatch '^assault-cache-signature-[0-9a-f]{32}$'){throw 'Unsafe temporary fixture cleanup path.'}
  if (Test-Path -LiteralPath $cleanupRoot) { Remove-Item -LiteralPath $cleanupRoot -Recurse -Force }
}
