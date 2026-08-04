$ErrorActionPreference = 'Stop'
function Get-Exp129RemainingContainerText([object]$Ids) { (@($Ids) -join "`n").Trim() }
function Test-Exp129Cleanup([object]$Ids,[int]$DownExit=0,[int]$QueryExit=0) {
    if ($DownExit -ne 0) { throw 'CLEANUP_COMPOSE_DOWN_FAILED' }
    if ($QueryExit -ne 0) { throw 'CLEANUP_STATE_QUERY_FAILED' }
    $text = Get-Exp129RemainingContainerText $Ids
    if (-not [string]::IsNullOrWhiteSpace($text)) { throw 'CLEANUP_CONTAINERS_REMAIN' }
    'PASS'
}
if ((Test-Exp129Cleanup @()) -ne 'PASS') { throw 'C1_FAILED' }
if ((Test-Exp129Cleanup $null) -ne 'PASS') { throw 'C2_FAILED' }
$c3=$false;try{Test-Exp129Cleanup @('abc123')}catch{$c3=$_.Exception.Message -eq 'CLEANUP_CONTAINERS_REMAIN'};if(-not$c3){throw 'C3_FAILED'}
$c4=$false;try{Test-Exp129Cleanup @('abc123','def456')}catch{$c4=$_.Exception.Message -eq 'CLEANUP_CONTAINERS_REMAIN'};if(-not$c4){throw 'C4_FAILED'}
$c5=$false;try{Test-Exp129Cleanup @() 1 0}catch{$c5=$_.Exception.Message -eq 'CLEANUP_COMPOSE_DOWN_FAILED'};if(-not$c5){throw 'C5_FAILED'}
$c6=$false;try{Test-Exp129Cleanup @() 0 1}catch{$c6=$_.Exception.Message -eq 'CLEANUP_STATE_QUERY_FAILED'};if(-not$c6){throw 'C6_FAILED'}
Write-Output 'EXP129_CLEANUP_C1_C6_PASS'
