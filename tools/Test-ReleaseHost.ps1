[CmdletBinding()]
param([switch]$Offline)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
function Invoke-Checked([string]$program,[string[]]$arguments) {
  & $program @arguments
  if($LASTEXITCODE -ne 0){throw "$program failed with exit code $LASTEXITCODE"}
}
# Run each script in its own process: some scripts use exit, and native failure
# must never be masked by a later successful command or an empty CTest run.
$shell=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
$scripts=@('Test-LauncherTools.ps1','Test-BuildCacheSignature.ps1','Test-GameplayCapture.ps1','Test-NativeCheck.ps1')
foreach($file in @((Join-Path $project 'Launch-StarFoxAssault.ps1'))+@(Get-ChildItem $PSScriptRoot -Filter '*.ps1' -File | ForEach-Object FullName)){
  $tokens=$null; $errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
  if($errors.Count){throw "PowerShell syntax errors in ${file}: $errors"}
}
foreach($script in $scripts){Invoke-Checked $shell @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot $script))}
$toolArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Ensure-PortableToolchain.ps1'))
if($Offline){$toolArgs+='-Offline'}
Invoke-Checked $shell $toolArgs
$root=Join-Path $project 'user-data/build-tools'
$manifest=Get-Content (Join-Path $PSScriptRoot 'portable-toolchain.json') -Raw | ConvertFrom-Json
$paths=@{}
foreach($tool in $manifest.tools){
  $folder=Join-Path $root ($tool.id+'-'+$tool.version)
  if($tool.archive_root){$folder=Join-Path $folder $tool.archive_root}
  $paths[$tool.id]=(Join-Path $folder $tool.executable).Replace('\','/')
}
$bin=(Split-Path -Parent $paths['llvm-mingw']).Replace('\','/')
Invoke-Checked $paths.python @("$project/runtime/tests/ppc_integer_test.py",'--cc',"$bin/x86_64-w64-mingw32-clang.exe",'--work',"$project/user-data/verification/ppc-integer")
Invoke-Checked $paths.python @("$project/runtime/tests/ppc_fp_compare_test.py",'--cc',"$bin/x86_64-w64-mingw32-clang.exe",'--work',"$project/user-data/verification/ppc-fp-compare")
Invoke-Checked $paths.python @("$project/runtime/tests/ppc_paired_sum_test.py",'--cc',"$bin/x86_64-w64-mingw32-clang.exe",'--work',"$project/user-data/verification/ppc-paired-sum")
Invoke-Checked $paths.python @("$project/runtime/tests/ppc_non_ieee_test.py",'--cc',"$bin/x86_64-w64-mingw32-clang.exe",'--work',"$project/user-data/verification/ppc-non-ieee")
Invoke-Checked $paths.python @("$project/runtime/tests/context_restore_test.py",'--cc',"$bin/x86_64-w64-mingw32-clang.exe",'--work',"$project/user-data/verification/context-restore")
$build=(Join-Path $project 'user-data/verification/release-host-tests').Replace('\','/')
Invoke-Checked $paths.cmake @('--fresh','-S',"$project/runtime/tests",'-B',$build,'-G','Ninja','-DCMAKE_BUILD_TYPE=Release',"-DCMAKE_MAKE_PROGRAM=$($paths.ninja)","-DCMAKE_C_COMPILER=$bin/x86_64-w64-mingw32-clang.exe", "-DCMAKE_CXX_COMPILER=$bin/x86_64-w64-mingw32-clang++.exe", "-DCMAKE_RC_COMPILER=$bin/llvm-windres.exe")
Invoke-Checked $paths.cmake @('--build',$build,'--parallel','4')
$ctest=Join-Path (Split-Path -Parent $paths.cmake) 'ctest.exe'
Invoke-Checked $ctest @('--test-dir',$build,'--output-on-failure','--no-tests=error')
$hostBuild=(Join-Path $project 'user-data/verification/release-host-tool').Replace('\','/')
Invoke-Checked $paths.cmake @('-S',"$project/runtime/tools/native",'-B',$hostBuild,'-G','Ninja','-DCMAKE_BUILD_TYPE=Release',"-DCMAKE_MAKE_PROGRAM=$($paths.ninja)","-DCMAKE_CXX_COMPILER=$bin/x86_64-w64-mingw32-clang++.exe")
Invoke-Checked $paths.cmake @('--build',$hostBuild,'--parallel','4')
Invoke-Checked $shell @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Build-Launcher.ps1'))
Invoke-Checked $shell @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Package-Prototype.ps1'),'-HostToolPath',"$hostBuild/assault-image-tool.exe",'-ReleaseVersion','0.2.0-host-check')
Invoke-Checked $shell @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Test-PrototypeUpdate.ps1'))
Write-Host 'PASS: host checks and Windows builds. Gameplay and release approval remain separate gates.'
