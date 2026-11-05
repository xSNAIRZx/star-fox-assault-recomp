param(
  [string]$ToolRoot='',
  [string]$ProgressFile='',
  [string]$CancelFile='',
  [switch]$Offline
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if(-not [Environment]::Is64BitOperatingSystem){throw 'A 64-bit Windows PC is required.'}
$project=Split-Path -Parent $PSScriptRoot
if(-not $ToolRoot){$ToolRoot=Join-Path $project 'user-data\build-tools'}
$ToolRoot=[IO.Path]::GetFullPath($ToolRoot)
[void][IO.Directory]::CreateDirectory($ToolRoot)
$rootPrefix=$ToolRoot.TrimEnd('\')+'\'
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'portable-toolchain.json') -Raw | ConvertFrom-Json
if($manifest.schema_version -ne 1){throw 'Unsupported portable toolchain manifest.'}
function Test-Cancel {
  if($CancelFile -and (Test-Path -LiteralPath $CancelFile)){throw [OperationCanceledException]::new('Build cancelled.')}
}
function Write-ToolStatus([string]$message,[switch]$Quiet){
  if(-not $Quiet){Write-Host $message}
  if($ProgressFile){
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent ([IO.Path]::GetFullPath($ProgressFile))))
    $status=[ordered]@{schema_version=1;state='running';phase='Preparing build tools';message=$message;percent=$null;executable=$null}
    [IO.File]::WriteAllText($ProgressFile,($status | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  }
}
function Format-DownloadSize([long]$bytes){([double]$bytes/1MB).ToString('0.0',[Globalization.CultureInfo]::InvariantCulture)}
# Streams the download so the launcher can show megabytes received and cancel between chunks.
function Save-ToolDownload([Uri]$uri,[string]$destination,[string]$label){
  $request=[Net.HttpWebRequest]::Create($uri)
  $request.Timeout=30000;$request.ReadWriteTimeout=60000;$request.AllowAutoRedirect=$true;$request.UserAgent='PeregrineForge-Toolchain'
  $response=$request.GetResponse()
  try {
    $total=[long]$response.ContentLength
    $body=$response.GetResponseStream()
    $output=[IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
      $buffer=New-Object byte[] 262144
      $received=[long]0;$lastReport=[DateTime]::MinValue
      while(($read=$body.Read($buffer,0,$buffer.Length)) -gt 0){
        $output.Write($buffer,0,$read);$received+=$read
        $now=[DateTime]::UtcNow
        if(($now-$lastReport).TotalMilliseconds -ge 500){
          Test-Cancel
          $sizeText=if($total -gt 0){'{0} of {1} MB' -f (Format-DownloadSize $received),(Format-DownloadSize $total)}else{'{0} MB' -f (Format-DownloadSize $received)}
          Write-ToolStatus ("Downloading {0}: {1}" -f $label,$sizeText) -Quiet
          $lastReport=$now
        }
      }
      if($total -gt 0 -and $received -ne $total){throw "The $label download ended early ($received of $total bytes)."}
      Write-Host ("Downloaded {0} ({1} MB)" -f $label,(Format-DownloadSize $received))
    } finally {$output.Dispose();$body.Dispose()}
  } finally {$response.Dispose()}
}
function Test-Inside([string]$path){
  $full=[IO.Path]::GetFullPath($path)
  if(-not $full.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)){throw "Tool path escaped cache: $full"}
  return $full
}
function Expand-CheckedZip([string]$archive,[string]$destination){
  $destination=Test-Inside $destination
  $prefix=$destination.TrimEnd('\')+'\'
  $zip=[IO.Compression.ZipFile]::OpenRead($archive)
  try {
    $total=[long]0
    foreach($entry in $zip.Entries){
      $relative=$entry.FullName.Replace('/','\')
      if([IO.Path]::IsPathRooted($relative) -or $relative.Contains(':')){throw 'Unsafe path in tool archive.'}
      $resolved=[IO.Path]::GetFullPath((Join-Path $destination $relative))
      if(-not $resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Tool archive traversal rejected.'}
      if((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000){throw 'Symbolic link in tool archive rejected.'}
      $total+=$entry.Length
      if($total -gt 6GB){throw 'Tool archive exceeds the supported extracted size.'}
    }
  } finally {$zip.Dispose()}
  [IO.Compression.ZipFile]::ExtractToDirectory($archive,$destination)
}
function Install-Tool($tool){
  Test-Cancel
  if($tool.id -notmatch '^[a-z][a-z0-9-]+$' -or $tool.version -notmatch '^[a-zA-Z0-9._-]+$' -or $tool.sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid portable tool entry.'}
  $uri=[Uri]$tool.url
  if($uri.Scheme -ne 'https' -or $uri.Host -notin @('github.com','www.python.org')){throw 'Tool downloads must use the pinned official HTTPS hosts.'}
  $folder=Test-Inside (Join-Path $ToolRoot ($tool.id+'-'+$tool.version))
  $relative=if($tool.archive_root){Join-Path ([string]$tool.archive_root) ([string]$tool.executable)}else{[string]$tool.executable}
  $exe=[IO.Path]::GetFullPath((Join-Path $folder $relative))
  if(-not $exe.StartsWith($folder+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid tool executable path.'}
  $stamp=Join-Path $folder '.ready.json'
  if((Test-Path -LiteralPath $stamp) -and (Test-Path -LiteralPath $exe)){
    try {
      $record=Get-Content -LiteralPath $stamp -Raw | ConvertFrom-Json
      if($record.archive_sha256 -eq $tool.sha256 -and $record.executable_sha256 -eq (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash){
        Write-ToolStatus ("Using cached {0} {1}" -f $tool.id,$tool.version)
        return [pscustomobject]@{root=$folder;executable=$exe}
      }
    } catch {}
  }
  $downloadDir=Test-Inside (Join-Path $ToolRoot 'downloads')
  [void][IO.Directory]::CreateDirectory($downloadDir)
  $archive=Join-Path $downloadDir ($tool.id+'-'+$tool.version+'.zip')
  if(Test-Path -LiteralPath $archive){
    if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $tool.sha256){
      Move-Item -LiteralPath $archive -Destination ($archive+'.invalid-'+[guid]::NewGuid().ToString('N'))
    }
  }
  if(-not(Test-Path -LiteralPath $archive)){
    if($Offline){throw "Missing cached $($tool.id). The first build needs internet access."}
    Write-ToolStatus ("Downloading {0} {1} from its official release..." -f $tool.id,$tool.version)
    $partial=$archive+'.partial-'+[guid]::NewGuid().ToString('N')
    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    try {
      Save-ToolDownload $uri $partial ("{0} {1}" -f $tool.id,$tool.version)
      Test-Cancel
      if((Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $tool.sha256){throw "SHA-256 verification failed for $($tool.id)."}
      Move-Item -LiteralPath $partial -Destination $archive
    } finally {
      if(Test-Path -LiteralPath $partial){Remove-Item -LiteralPath $partial -Force}
    }
  }
  Test-Cancel
  Write-ToolStatus ("Unpacking verified {0} {1}..." -f $tool.id,$tool.version)
  $stage=Test-Inside (Join-Path $ToolRoot ('.stage-'+$tool.id+'-'+[guid]::NewGuid().ToString('N')))
  try {
    Expand-CheckedZip $archive $stage
    Test-Cancel
    $stageExe=[IO.Path]::GetFullPath((Join-Path $stage $relative))
    if(-not(Test-Path -LiteralPath $stageExe -PathType Leaf)){throw "The $($tool.id) archive is missing its expected executable."}
    [ordered]@{id=$tool.id;version=$tool.version;archive_sha256=$tool.sha256;executable_sha256=(Get-FileHash -LiteralPath $stageExe -Algorithm SHA256).Hash} |
      ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage '.ready.json') -Encoding UTF8
    if(Test-Path -LiteralPath $folder){Move-Item -LiteralPath $folder -Destination ($folder+'.previous-'+[guid]::NewGuid().ToString('N'))}
    Move-Item -LiteralPath $stage -Destination $folder
  } finally {
    $safeStage=Test-Inside $stage
    if((Split-Path -Leaf $safeStage) -notmatch '^\.stage-[a-z0-9-]+$'){throw 'Unsafe extraction cleanup path.'}
    if(Test-Path -LiteralPath $safeStage){Remove-Item -LiteralPath $safeStage -Recurse -Force}
  }
  return [pscustomobject]@{root=$folder;executable=$exe}
}
$lock=$null
try {
  try {$lock=[IO.File]::Open((Join-Path $ToolRoot '.setup.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
  catch {throw 'Build tools are already being prepared by another launcher. Wait for that operation to finish.'}
  $installed=@{}
  foreach($tool in $manifest.tools){$installed[[string]$tool.id]=Install-Tool $tool}
  $compilerDir=Split-Path -Parent $installed['llvm-mingw'].executable
  [pscustomobject]@{
    root=$ToolRoot
    cmake=$installed['cmake'].executable
    ninja=$installed['ninja'].executable
    python=$installed['python'].executable
    cc=$installed['llvm-mingw'].executable
    cxx=(Join-Path $compilerDir 'x86_64-w64-mingw32-clang++.exe')
    rc=(Join-Path $compilerDir 'x86_64-w64-mingw32-windres.exe')
    compilerDirectory=$compilerDir
  }
} finally {if($lock){$lock.Dispose()}}
