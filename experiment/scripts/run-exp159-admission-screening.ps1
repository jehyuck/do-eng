param(
  [Parameter(Mandatory=$true)][ValidateSet('G600','G400','G800')][string]$Cell,
  [Parameter(Mandatory=$true)][ValidateSet('Plan','Smoke','Execute')][string]$Mode,
  [Parameter(Mandatory=$true)][string]$RunId,
  [string]$ExpectedCommit=''
)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$template=Join-Path $repo 'experiment\scripts\run-exp157-flow-balance.ps1'
$temp=Join-Path (Join-Path $repo 'experiment\scripts') ('.doeng-exp159-run-'+$RunId.ToLowerInvariant()+'.ps1')
$source=Get-Content $template -Raw -Encoding UTF8
$source=$source.Replace("ValidateSet('Q600','Q700-B150','Q700-U100','Q700-B200')","ValidateSet('G600','G400','G800')")
$source=$source.Replace("experiment-1-57","experiment-1-59").Replace("Exp157","Exp159").Replace("EXP157_EXECUTE_PASS","EXP159_EXECUTE_PASS").Replace("doeng-exp157-","doeng-exp159-")
$source=$source.Replace('$ports=@{app=18510;management=19510;mock=18610;db=18710}','$ports=@{app=18530;management=19530;mock=18630;db=18730}')
$newCellConfig=@'
function CellConfig{switch($Cell){'G600' {return @{gate=600;token=100;ai=600;storage=100}} 'G400' {return @{gate=400;token=100;ai=600;storage=100}} 'G800' {return @{gate=800;token=100;ai=600;storage=100}}}}
'@
$source=[regex]::Replace($source,'function CellConfig\{(?s:.*?)\}\}\}\}', $newCellConfig, 1)
$source=$source.Replace('$end=(Get-Date).AddSeconds(35)','$end=(Get-Date).AddSeconds(55)')
$source=$source.Replace('$env:DURATION_MS=''15000''','$env:DURATION_MS=''30000''').Replace('$env:DRAIN_OBSERVATION_SECONDS=''10''','$env:DRAIN_OBSERVATION_SECONDS=''15''').Replace('durationMs=15000;drainSeconds=10','durationMs=30000;drainSeconds=15')
$source=$source.Replace("admission='OFF';sink='OFF'","admission='ENFORCE';sink='OFF'")
$source=$source.Replace("DOENG_AI_ADMISSION_ENABLED: 'false'","DOENG_AI_ADMISSION_ENABLED: 'true'").Replace("DOENG_ADMISSION_MODE: 'OFF'","DOENG_ADMISSION_MODE: 'ENFORCE'").Replace("DOENG_AI_ADMISSION_MAX_CONCURRENT: '400'","DOENG_AI_ADMISSION_MAX_CONCURRENT: '`$(`$cfg.gate)'")
Set-Content $temp $source -Encoding UTF8
try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $temp -Cell $Cell -Mode $Mode -RunId $RunId -ExpectedCommit $ExpectedCommit; exit $LASTEXITCODE }
finally { Remove-Item $temp -Force -ErrorAction SilentlyContinue }
