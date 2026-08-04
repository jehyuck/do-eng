param([Parameter(Mandatory)][ValidateSet('BASELINE','REMEDIATION')][string]$Condition,[Parameter(Mandatory)][ValidateSet('001','002','003')][string]$RunIndex,[string]$RunDate='PLAN-DATE',[ValidateSet('PLAN','EXECUTE')][string]$ExecutionMode='PLAN')
$ErrorActionPreference='Stop';$source=Join-Path $PSScriptRoot 'run-experiment-1-25-core.ps1';$generated=Join-Path $PSScriptRoot '.exp126-core.generated.ps1'
if(-not(Test-Path $source)){throw 'EXP125_CORE_TEMPLATE_MISSING'}
$text=Get-Content $source -Raw
$text=$text.Replace('Experiment 1-25','Experiment 1-26').Replace('EXP125','EXP126').Replace('experiment-1-25','experiment-1-26').Replace('doeng-exp125-core','doeng-exp126-core').Replace('collect-diagnostic-pool-until-stop.ps1','collect-experiment-1-26-pool-until-stop.ps1')
[IO.File]::WriteAllText($generated,$text,(New-Object Text.UTF8Encoding($false)))
try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $generated -Condition $Condition -RunIndex $RunIndex -RunDate $RunDate -ExecutionMode $ExecutionMode; if($LASTEXITCODE){exit $LASTEXITCODE} } finally { Remove-Item -LiteralPath $generated -Force -ErrorAction SilentlyContinue }
