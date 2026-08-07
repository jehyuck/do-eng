param(
    [Parameter(Mandatory=$true)][ValidateSet('Smoke','Execute')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$RunId,
    [string]$ExpectedCommit='0ea99dbc8f6775ade817b4e12856dcc9556456c7'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$base=Get-Content (Join-Path $repo 'experiment\scripts\run-exp160-sink-flow-smoothing.ps1') -Raw -Encoding UTF8
$temp=Join-Path $PSScriptRoot ('.doeng-exp162-run-'+$RunId.ToLowerInvariant()+'.ps1')
$appImage='doeng-exp162-sink-serialized-flux-corrected:latest'
$base=$base.Replace("[string]$ExpectedCommit='2313b10a14c850a8992dfbc5d567f4b9a2b02244'", "[string]$ExpectedCommit='$ExpectedCommit'")
$base=$base.Replace('cf5b36ad38928d55eab131d1328dc85ccff0ad3b',$ExpectedCommit)
$base=$base.Replace('experiment-1-60','experiment-1-62').Replace('Exp160','Exp162').Replace('EXP160_EXECUTE_PASS','EXP162_EXECUTE_PASS').Replace('doeng-exp160-','doeng-exp162-')
$base=$base.Replace('Set-Content $temp $source -Encoding UTF8', '$source=$source.Replace(''cf5b36ad38928d55eab131d1328dc85ccff0ad3b'', '''+$ExpectedCommit+'''); $source=$source.Replace(''doeng-exp153-b3-recovery-flux-corrected:latest'', '''+$appImage+'''); Set-Content $temp $source -Encoding UTF8')
Set-Content $temp $base -Encoding UTF8
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $temp -Mode $Mode -RunId $RunId -ExpectedCommit $ExpectedCommit
    exit $LASTEXITCODE
}
finally {
    Remove-Item $temp -Force -ErrorAction SilentlyContinue
}
