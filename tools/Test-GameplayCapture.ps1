# ISO-free orchestration tests using a synthetic console executable, never game code.
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$root=Join-Path $project ('user-data\verification\capture-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$stub=Join-Path $root 'capture stub.exe'
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
public class CaptureStub {
  public static int Main(string[] args) {
    Console.WriteLine("SYNTHETIC TEST PROCESS");
    Console.WriteLine("cwd=" + Directory.GetCurrentDirectory());
    string parent = Directory.GetParent(Directory.GetCurrentDirectory()).FullName;
    foreach (string name in new [] {"stdout.log", "stderr.log"}) {
      using (var live = new FileStream(Path.Combine(parent, name), FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
        Console.WriteLine("live-read=" + name);
      bool blocked = false;
      try { using (var writer = new FileStream(Path.Combine(parent, name), FileMode.Open, FileAccess.Write, FileShare.ReadWrite)) {} }
      catch (IOException) { blocked = true; }
      if (!blocked) return 99;
    }
    foreach (string arg in args) Console.WriteLine("arg=" + Convert.ToBase64String(Encoding.UTF8.GetBytes(arg)));
    foreach (System.Collections.DictionaryEntry item in Environment.GetEnvironmentVariables())
      if (((string)item.Key).StartsWith("GCN_")) Console.Error.WriteLine(item.Key + "=" + item.Value);
    foreach (string arg in args) if (arg.StartsWith("--replay="))
      File.WriteAllText(Path.Combine(arg.Substring(9), "memcard_replay.raw"), "scratch");
    if (args[args.Length-1].EndsWith("slow.iso")) System.Threading.Thread.Sleep(10000);
    return 7;
  }
}
'@ -OutputAssembly $stub -OutputType ConsoleApplication
$image=Join-Path $root ("image with spaces and ' quote-"+[char]0x03A9+'.iso')
[IO.File]::WriteAllText($image,'synthetic, not an image')
$replay=Join-Path $root 'original replay'
[void][IO.Directory]::CreateDirectory($replay)
[IO.File]::WriteAllText((Join-Path $replay 'inputs.txt'),'synthetic recording')
[IO.File]::WriteAllText((Join-Path $replay 'memcard_a.raw'),'original card')
$capture=Join-Path $PSScriptRoot 'Capture-Gameplay.ps1'
function Assert([bool]$condition,[string]$message){if(-not $condition){throw $message}}
$oldInput=$env:GCN_INPUT;$oldVert=$env:GCN_VERTCHECK
try {
  $env:GCN_INPUT='must not leak';$env:GCN_VERTCHECK='must not leak'
  $out=Join-Path $root 'both'
  & $capture -GameImage $image -Executable $stub -OutputRoot $out -ReplayDirectory $replay -Mode Both -DrawFrame 42 -RamFrames @(40,41)
  $session=(Get-ChildItem -LiteralPath $out -Directory).FullName
  $plan=Get-Content -LiteralPath (Join-Path $session 'capture.json') -Raw | ConvertFrom-Json
  $result=Get-Content -LiteralPath (Join-Path $session 'result.json') -Raw | ConvertFrom-Json
  Assert ($result.exit_code -eq 7 -and -not $result.forced_stop) 'Child exit code was lost.'
  $lines=Get-Content -LiteralPath (Join-Path $session 'stdout.log')
  Assert (($lines -contains 'live-read=stdout.log') -and ($lines -contains 'live-read=stderr.log')) 'Capture logs could not be read while the child was running.'
  $decoded=@($lines | Where-Object {$_ -like 'arg=*'} | ForEach-Object {[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_.Substring(4)))})
  Assert ($decoded[-1] -ceq $image) 'Image path quoting changed the argument.'
  Assert ($decoded -contains ('--replay='+ (Join-Path $session 'replay'))) 'Replay argument was split.'
  Assert ($lines -contains ('cwd='+ (Join-Path $session 'run'))) 'Working directory was not isolated.'
  $err=Get-Content -LiteralPath (Join-Path $session 'stderr.log') -Raw
  Assert ($err -match 'GCN_GUARD=800000E4' -and $err -match 'GCN_VERTCHECK=1' -and $err -match 'GCN_DRAWLOG=42' -and $err -match 'GCN_RAM_DUMP_AT=40,41') 'Capture environment was incomplete.'
  Assert ($err -notmatch 'GCN_INPUT=') 'Inherited scripted input leaked.'
  Assert ($env:GCN_INPUT -eq 'must not leak') 'Parent environment was changed.'
  Assert (-not(Test-Path -LiteralPath (Join-Path $replay 'memcard_replay.raw'))) 'Original replay was modified.'
  Assert ((Get-Content -LiteralPath (Join-Path $replay 'memcard_a.raw') -Raw) -eq 'original card') 'Original card changed.'
  Assert (Test-Path -LiteralPath (Join-Path $session 'replay\memcard_replay.raw')) 'Scratch replay was not isolated.'
  $out=Join-Path $root 'thread'
  & $capture -GameImage $image -Executable $stub -OutputRoot $out -Mode Thread -MemoryCard (Join-Path $replay 'memcard_a.raw') -InputScript '100:START:10,200:A:10' -LogHostKeys
  $session=(Get-ChildItem -LiteralPath $out -Directory).FullName
  Assert ((Get-Content -LiteralPath (Join-Path $session 'run\saves\memcard_a.raw') -Raw) -eq 'original card') 'Starting card was not copied.'
  Assert ((Get-Content -LiteralPath (Join-Path $session 'stderr.log') -Raw) -notmatch 'GCN_VERTCHECK=') 'Boss environment leaked into thread capture.'
  $explicit=Get-Content -LiteralPath (Join-Path $session 'stderr.log') -Raw
  Assert ($explicit -match 'GCN_INPUT=100:START:10,200:A:10' -and $explicit -match 'GCN_LOG_HOST_KEYS=1') 'Explicit input diagnostics were not applied.'
  $planOnly=Join-Path $root 'must not exist'
  $json=& $capture -GameImage (Join-Path $root 'missing.iso') -Executable (Join-Path $root 'missing.exe') -OutputRoot $planOnly -Mode Boss -PlanOnly
  Assert (-not(Test-Path -LiteralPath $planOnly)) 'PlanOnly wrote files.'
  $p=$json | ConvertFrom-Json
  Assert ($p.environment.GCN_VERTCHECK -eq '1' -and -not $p.environment.GCN_GUARD) 'Boss plan had wrong environment.'
  $hiddenPlan=(& $capture -GameImage $image -Mode Boss -Hidden -PlanOnly) | ConvertFrom-Json
  Assert ($hiddenPlan.arguments -contains '--hidden' -and $hiddenPlan.arguments -contains '--script-only' -and $hiddenPlan.environment.SDL_AUDIODRIVER -eq 'dummy') 'Hidden replay does not isolate live input and audio.'
  foreach($bad in @(@{DrawFrame=0},@{Mode='Thread';DrawFrame=2},@{ReplayDirectory=$replay;MemoryCard=$image},@{ReplayDirectory=$replay;InputScript='100:A:10'})){
    $rejected=$false;try {& $capture -GameImage $image -PlanOnly @bad | Out-Null}catch{$rejected=$true}
    Assert $rejected 'Invalid option combination was accepted.'
  }
  $rejected=$false;try {& $capture -GameImage $image -Executable (Join-Path $root 'missing.exe') -OutputRoot $planOnly}catch{$rejected=$true}
  Assert ($rejected -and -not(Test-Path -LiteralPath $planOnly)) 'Missing executable created a partial capture.'
  $incomplete=Join-Path $root 'missing card replay';[void][IO.Directory]::CreateDirectory($incomplete)
  [IO.File]::WriteAllText((Join-Path $incomplete 'inputs.txt'),'synthetic')
  $rejected=$false;try {& $capture -GameImage $image -Executable $stub -ReplayDirectory $incomplete -OutputRoot $planOnly}catch{$rejected=$true}
  Assert ($rejected -and -not(Test-Path -LiteralPath $planOnly)) 'Replay without starting card was accepted.'
  $slow=Join-Path $root 'slow.iso';[IO.File]::WriteAllText($slow,'synthetic')
  $out=Join-Path $root 'timeout'
  & $capture -GameImage $slow -Executable $stub -OutputRoot $out -StopAfterSeconds 1
  $session=(Get-ChildItem -LiteralPath $out -Directory).FullName
  $r=Get-Content -LiteralPath (Join-Path $session 'result.json') -Raw | ConvertFrom-Json
  Assert $r.forced_stop 'Bounded run did not report forced termination.'
  Write-Host 'PASS: synthetic capture, quoting, environment, modes, replay/card isolation, validation, plan-only and timeout checks.'
} finally {$env:GCN_INPUT=$oldInput;$env:GCN_VERTCHECK=$oldVert}
