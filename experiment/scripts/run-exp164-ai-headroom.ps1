param(
    [Parameter(Mandatory=$true)][ValidateSet('Smoke','Execute')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$RunId,
    [string]$ExpectedCommit='aa28b7f481543ed99386a431bfa29fd797d15a22'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$base=Get-Content (Join-Path $PSScriptRoot 'run-exp162-sink-serialization.ps1') -Raw -Encoding UTF8
$temp=Join-Path $PSScriptRoot ('.doeng-exp164-run-'+$RunId.ToLowerInvariant()+'.ps1')
$appImage='doeng-exp162-sink-serialized-flux-corrected:latest'
$base=$base.Replace("[string]$ExpectedCommit='0ea99dbc8f6775ade817b4e12856dcc9556456c7'", "[string]$ExpectedCommit='$ExpectedCommit'")
$base=$base.Replace('experiment-1-62','experiment-1-64').Replace('Exp162','Exp164').Replace('EXP162_EXECUTE_PASS','EXP164_EXECUTE_PASS').Replace('doeng-exp162-','doeng-exp164-')
$base=$base.Replace('doeng-exp164-sink-serialized-flux-corrected:latest',$appImage)
$base=$base.Replace('Set-Content $temp $base -Encoding UTF8', '$base=$base.Replace(''sinkAiConcurrency=400'', ''sinkAiConcurrency=500''); $base=$base.Replace(''DOENG_DISPATCHER_AI_CONCURRENCY: "400"'', ''DOENG_DISPATCHER_AI_CONCURRENCY: "500"''); Set-Content $temp $base -Encoding UTF8')
$base=$base.Replace('experiment-1-62-sink.override.yml','experiment-1-64-sink.override.yml')
Set-Content $temp $base -Encoding UTF8
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $temp -Mode $Mode -RunId $RunId -ExpectedCommit $ExpectedCommit
    exit $LASTEXITCODE
}
finally { Remove-Item $temp -Force -ErrorAction SilentlyContinue }
