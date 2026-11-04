# ISO-free tests of the bounded smoke runner; never launch the real game.
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$root=Join-Path $project ('user-data\verification\native-check-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$stub=Join-Path $root ("synthetic smoke with ' quote-"+[char]0x03A9+'.exe')
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
public class NativeCheckStub {
  [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
  public static int Main(string[] args) {
    Console.WriteLine("SYNTHETIC TEST PROCESS");
    Console.WriteLine("visible-console=" + IsWindowVisible(GetConsoleWindow()));
    Console.WriteLine("cwd=" + Directory.GetCurrentDirectory());
    string image = null;
    foreach (string arg in args) {
      Console.WriteLine("arg=" + Convert.ToBase64String(Encoding.UTF8.GetBytes(arg)));
      if (arg.EndsWith(".iso")) image=arg;
      if (arg.StartsWith("--dump-dir=")) {
        File.WriteAllText(Path.Combine(arg.Substring(11), "frame_00100.png"), "synthetic, not PNG");
        File.WriteAllText(Path.Combine(arg.Substring(11), "output_00100.png"), "synthetic, not PNG");
      }
    }
    foreach (System.Collections.DictionaryEntry entry in Environment.GetEnvironmentVariables())
      if (((string)entry.Key).StartsWith("GCN_") || (string)entry.Key == "SDL_AUDIODRIVER")
        Console.Error.WriteLine(entry.Key + "=" + entry.Value);
    // Exceed ordinary pipe buffers on both channels: the runner must drain concurrently.
    Console.WriteLine(new string('x', 262144));
    Console.Error.WriteLine(new string('y', 262144));
    if (File.Exists("saves/memcard_a.raw")) File.WriteAllText("saves/memcard_a.raw", "changed isolated card");
    Console.Out.Flush(); Console.Error.Flush();
    if (image == null) return 99;
    if (image.Contains("after-limit")) System.Threading.Thread.Sleep(1600);
    if (image.Contains("bounded")) System.Threading.Thread.Sleep(20000);
    return image.Contains("exit-zero") ? 0 : 7;
  }
}
'@ -OutputAssembly $stub -OutputType ConsoleApplication
$runner=Join-Path $PSScriptRoot 'Run-NativeCheck.ps1'
$shell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
function Assert([bool]$condition,[string]$message){if(-not $condition){throw $message}}
function Quote-Argument([string]$value){'"'+([regex]::Replace([regex]::Replace($value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1'))+'"'}
function Invoke-Case([string]$name,[string[]]$extra) {
  $image=Join-Path $root ("$name with spaces and ' quote-"+[char]0x03A9+'.iso')
  [IO.File]::WriteAllText($image,'synthetic, not a game image')
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=$shell;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
  $psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
  $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  $argsList=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$runner,'-GameImage',$image,'-NativeExecutable',$stub,'-Seconds','1','-Scale','1.25','-InputScript','100:A:5,200:START:10')+$extra
  $psi.Arguments=($argsList | ForEach-Object {Quote-Argument $_}) -join ' '
  $proc=New-Object Diagnostics.Process;$proc.StartInfo=$psi
  $timer=[Diagnostics.Stopwatch]::StartNew()
  try {
    Assert ($proc.Start()) 'Could not start test runner.'
    $outTask=$proc.StandardOutput.ReadToEndAsync();$errTask=$proc.StandardError.ReadToEndAsync()
    if(-not $proc.WaitForExit(15000)){$proc.Kill();$proc.WaitForExit();throw 'Smoke runner exceeded its test watchdog.'}
    $output=$outTask.GetAwaiter().GetResult();$errors=$errTask.GetAwaiter().GetResult()
    [IO.File]::WriteAllText((Join-Path $root ($name+'.out')),$output)
    [IO.File]::WriteAllText((Join-Path $root ($name+'.err')),$errors)
    $reportPath=@($output -split '\r?\n' | Where-Object {$_ -like 'Run artifacts: *'} | ForEach-Object {$_.Substring(15)})
    $report=if($reportPath.Count -eq 1){Get-Content -LiteralPath (Join-Path $reportPath[0] 'result.json') -Raw | ConvertFrom-Json}else{$null}
    return [pscustomobject]@{name=$name;exitCode=$proc.ExitCode;elapsed=$timer.Elapsed.TotalSeconds;report=$report;image=$image;errors=$errors}
  } finally {$proc.Dispose()}
}
$old=@{}
foreach($name in @('GCN_SMOKE_TEST_SENTINEL','GCN_TIMESCALE','GCN_INPUT','GCN_MODS_DIR','GCN_DUMP_OUTPUT','SDL_AUDIODRIVER')){
  $old[$name]=[Environment]::GetEnvironmentVariable($name,'Process')
}
try {
  $env:GCN_SMOKE_TEST_SENTINEL='must not reach child'
  $env:GCN_TIMESCALE='37';$env:GCN_INPUT='parent scripted input';$env:GCN_MODS_DIR='parent mods';$env:GCN_DUMP_OUTPUT='parent dump';$env:SDL_AUDIODRIVER='parent driver'
  $seed=Join-Path $root 'original card.raw';[IO.File]::WriteAllBytes($seed,[byte[]]::new(524288))
  $seedHash=(Get-FileHash -LiteralPath $seed).Hash
  $cases=@()
  $cases+=Invoke-Case 'exit-seven' @()
  $cases+=Invoke-Case 'exit-zero' @()
  foreach($case in $cases){
    Assert ($case.exitCode -eq 1 -and $null -ne $case.report -and -not $case.report.survivedUntilTimeLimit) "Early exit was falsely accepted: $($case.name)"
    Assert (-not $case.report.forcedTermination) 'Early child was reported forcibly stopped.'
  }
  Assert ($cases[0].report.exitCode -eq 7) 'Nonzero child exit code was lost.'
  Assert ($cases[1].report.exitCode -eq 0) 'Zero child exit code was lost.'
  $lateFailure=Invoke-Case 'after-limit-seven' @()
  Assert ($lateFailure.exitCode -eq 1 -and $lateFailure.report.exitCode -eq 7 -and $lateFailure.report.survivedUntilTimeLimit -and -not $lateFailure.report.forcedTermination) 'Nonzero exit during shutdown grace was falsely accepted.'
  $cases+=$lateFailure
  $bounded=Invoke-Case 'bounded' @('-SeedMemoryCard',$seed,'-CaptureOutput')
  $cases+=$bounded
  Assert ($bounded.exitCode -eq 0 -and $bounded.report.survivedUntilTimeLimit -and $bounded.report.forcedTermination) 'Bounded child was not terminated/reported correctly.'
  Assert ($null -ne $bounded.report.exitCode -and $bounded.report.exitCode -ne 0) 'Forced-stop exit code was lost.'
  Assert ($bounded.elapsed -ge 1 -and $bounded.elapsed -lt 12) 'Bounded run exceeded its deadline and grace interval.'
  Assert ($bounded.report.seedCardSha256 -eq $seedHash -and (Get-FileHash -LiteralPath $seed).Hash -eq $seedHash) 'Original starting card was changed.'
  foreach($case in $cases){
    $r=$case.report;$lines=Get-Content -LiteralPath (Join-Path $r.runDirectory 'run.out')
    $argsSeen=@($lines | Where-Object {$_ -like 'arg=*'} | ForEach-Object {[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_.Substring(4)))})
    Assert ($argsSeen -contains $case.image) 'Image path quoting changed an argument.'
    Assert ($argsSeen -contains ('--dump-dir='+(Join-Path $r.runDirectory 'frames'))) 'Frame output path quoting changed an argument.'
    Assert ($argsSeen -contains '--scale=1.25' -and $argsSeen -contains '--hidden' -and $argsSeen -contains '--script-only') 'Hidden smoke options were lost.'
    Assert ($lines -contains 'visible-console=False') 'Hidden synthetic child displayed a console.'
    Assert ($lines -contains ('cwd='+$r.runDirectory)) 'Child working directory was not isolated.'
    Assert ($r.capturedFrames -eq 1 -and $r.capturedOutputFrames -eq 1) 'Frame artifact counts were lost.'
    $err=Get-Content -LiteralPath (Join-Path $r.runDirectory 'run.err') -Raw
    Assert ($err -match 'GCN_TIMESCALE=1' -and $err -match 'GCN_INPUT=100:A:5,200:START:10' -and $err -match 'SDL_AUDIODRIVER=dummy') 'Controlled child environment was not applied.'
    Assert ($err -notmatch 'GCN_SMOKE_TEST_SENTINEL|GCN_MODS_DIR=|parent driver|parent scripted input|parent mods') 'Inherited environment leaked into the smoke process.'
  }
  Assert ($env:GCN_SMOKE_TEST_SENTINEL -eq 'must not reach child' -and $env:GCN_TIMESCALE -eq '37' -and $env:GCN_INPUT -eq 'parent scripted input' -and $env:SDL_AUDIODRIVER -eq 'parent driver') 'Parent environment was changed.'
  $invalid=Invoke-Case 'fast-visible-invalid' @('-Fast','-ShowWindow')
  Assert ($invalid.exitCode -ne 0 -and $null -eq $invalid.report) 'Visible accelerated run was accepted.'
  $summary=[ordered]@{scope='Synthetic host-process tests only; no game image or gameplay';passed=$true;cases=@($cases | ForEach-Object {[ordered]@{name=$_.name;runnerExit=$_.exitCode;childExit=$_.report.exitCode;survived=$_.report.survivedUntilTimeLimit;forced=$_.report.forcedTermination;elapsedSeconds=[Math]::Round($_.elapsed,2)}})}
  $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $root 'results.json') -Encoding UTF8
  Write-Host 'PASS: smoke exit codes, early-exit rejection, bounded stop, hidden mode, pipe draining, quoting, environment and save isolation.'
  Write-Host "Synthetic evidence: $root"
} finally {
  foreach($name in $old.Keys){[Environment]::SetEnvironmentVariable($name,$old[$name],'Process')}
}
