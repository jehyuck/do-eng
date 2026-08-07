param(
  [Parameter(Mandatory=$true)][ValidateSet('C600-100','C600-200','C600-150')][string]$Cell,
  [Parameter(Mandatory=$true)][ValidateSet('Plan','Smoke','Execute')][string]$Mode,
  [Parameter(Mandatory=$true)][string]$RunId,
  [string]$ExpectedCommit=''
)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$template=Join-Path $repo 'experiment\scripts\run-exp157-flow-balance.ps1'
$temp=Join-Path (Join-Path $repo 'experiment\scripts') (".doeng-exp158-run-"+$RunId.ToLowerInvariant()+'.ps1')
$source=Get-Content $template -Raw -Encoding UTF8
$source=$source.Replace("ValidateSet('Q600','Q700-B150','Q700-U100','Q700-B200')","ValidateSet('C600-100','C600-200','C600-150')")
$source=$source.Replace("experiment-1-57","experiment-1-58").Replace("Exp157","Exp158").Replace("EXP157_EXECUTE_PASS","EXP158_EXECUTE_PASS").Replace("doeng-exp157-","doeng-exp158-")
$source=$source.Replace('$ports=@{app=18510;management=19510;mock=18610;db=18710}','$ports=@{app=18520;management=19520;mock=18620;db=18720}')
$newCellConfig=@'
function CellConfig{switch($Cell){'C600-100' {return @{token=100;ai=600;storage=100}} 'C600-200' {return @{token=200;ai=600;storage=200}} 'C600-150' {return @{token=150;ai=600;storage=150}}}}
'@
$source=[regex]::Replace($source,'function CellConfig\{(?s:.*?)\}\}\}\}', $newCellConfig, 1)
$source=$source.Replace('$end=(Get-Date).AddSeconds(35)','$end=(Get-Date).AddSeconds(55)').Replace('$env:DURATION_MS=''15000''','$env:DURATION_MS=''30000''').Replace('$env:DRAIN_OBSERVATION_SECONDS=''10''','$env:DRAIN_OBSERVATION_SECONDS=''15''').Replace('durationMs=15000;drainSeconds=10','durationMs=30000;drainSeconds=15')
Set-Content $temp $source -Encoding UTF8
try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $temp -Cell $Cell -Mode $Mode -RunId $RunId -ExpectedCommit $ExpectedCommit; exit $LASTEXITCODE }
finally { Remove-Item $temp -Force -ErrorAction SilentlyContinue }
