param(
    [Parameter(Mandatory=$true)][ValidateSet('Smoke','Execute')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$RunId,
    [string]$ExpectedCommit='188b0d32308771596993c893e4369871dc84d806'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$base=Get-Content (Join-Path $repo 'experiment\scripts\run-exp162-sink-serialization.ps1') -Raw -Encoding UTF8
$temp=Join-Path $PSScriptRoot ('.doeng-exp163-run-'+$RunId.ToLowerInvariant()+'.ps1')
$base=$base.Replace("[string]$ExpectedCommit='0ea99dbc8f6775ade817b4e12856dcc9556456c7'", "[string]$ExpectedCommit='$ExpectedCommit'")
$base=$base.Replace('experiment-1-62','experiment-1-63').Replace('Exp162','Exp163').Replace('EXP162','EXP163')
$base=$base.Replace('SINK-C400-Q3-SERIALIZED-R1','SINK-C400-Q6-EDGE-R1').Replace('SINK-C400-Q3-SERIALIZED-R2','SINK-C400-Q6-EDGE-R1')
$base=$base.Replace('Set-Content $temp $base -Encoding UTF8', '$base=$base.Replace(''sinkTokenQueue=300; sinkAiQueue=1200; sinkStorageQueue=300'', ''sinkTokenQueue=600; sinkAiQueue=1200; sinkStorageQueue=600''); Set-Content $temp $base -Encoding UTF8')
Set-Content $temp $base -Encoding UTF8
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $temp -Mode $Mode -RunId $RunId -ExpectedCommit $ExpectedCommit
    exit $LASTEXITCODE
}
finally { Remove-Item $temp -Force -ErrorAction SilentlyContinue }
