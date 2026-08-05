param([Parameter(Mandatory=$true)][string]$RunId,[Parameter(Mandatory=$true)][ValidateSet(400,1000)][int]$PoolMaxConnections,[string]$RunDate=(Get-Date -Format yyyyMMdd),[string]$Condition,[switch]$Core)
if([string]::IsNullOrWhiteSpace($Condition)){ $Condition = "POOL$PoolMaxConnections" }
& (Join-Path $PSScriptRoot 'run-exp131-pool-identity-recovery.ps1') -RunId $RunId -RunDate $RunDate -PoolMaxConnections $PoolMaxConnections -ExperimentId '1-33' -Condition $Condition -Core:$Core
exit $LASTEXITCODE
