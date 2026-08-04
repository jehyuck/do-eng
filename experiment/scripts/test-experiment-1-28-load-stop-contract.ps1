$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'experiment-1-28-load-stop-contract.ps1')

function New-ContractCase {
    param([bool]$SnapshotObserved = $true, [bool]$BadDrain = $false, [bool]$Missing = $false, [bool]$Incomplete = $false)
    $seconds = 30
    $base = [DateTimeOffset]::Parse('2026-08-04T00:00:00Z')
    $samples = [System.Collections.Generic.List[object]]::new()
    $snapshot = if ($SnapshotObserved) {
        [pscustomobject]@{ ok = $true; metrics = [pscustomobject]@{ aiInFlight = 5; storageInFlight = 1 }; error = $null }
    } else {
        [pscustomobject]@{ ok = $false; metrics = $null; error = 'timeout' }
    }
    $samples.Add([pscustomobject]@{ phase = 'load-stop'; sample = 0; elapsedMs = 0; capturedAt = $base.ToString('o'); ok = $snapshot.ok; metrics = $snapshot.metrics; error = $snapshot.error })
    for ($i = 1; $i -le $seconds; $i++) {
        $ok = -not ($BadDrain -and $i -eq 7)
        $samples.Add([pscustomobject]@{ phase = 'drain'; sample = $i; elapsedMs = $i * 1000; capturedAt = $base.AddSeconds($i).ToString('o'); ok = $ok; metrics = if ($ok) { [pscustomobject]@{ aiInFlight = [Math]::Max(0, 5 - $i); storageInFlight = 0 } } else { $null }; error = if ($ok) { $null } else { 'timeout' } })
    }
    $summary = [pscustomobject]@{
        sampleCount = $seconds + 1; configuredSeconds = $seconds
        initial = [pscustomobject]@{ phase = 'load-stop'; capturedAt = $samples[0].capturedAt }
        terminal = [pscustomobject]@{ capturedAt = $samples[-1].capturedAt }
        drainCompleted = -not $Incomplete; remainingBacklog = if ($Incomplete) { 3 } else { 0 }
    }
    $result = Get-Exp128LoadStopContract -DrainObservationSeconds $seconds -LoadStopMockMetrics $snapshot -MockDrain $summary -MockDrainSamples @($samples) -DrainJsonlPresent (-not $Missing) -DrainSummaryPresent (-not $Missing)
    return $result
}

$d1 = New-ContractCase
if (-not $d1.drainArtifactsPresent -or -not $d1.loadStopSnapshotObserved -or -not $d1.drainElapsedValid) { throw 'D1 failed' }
$d2 = New-ContractCase -SnapshotObserved:$false
if (-not $d2.drainArtifactsPresent -or -not $d2.loadStopSnapshotTimeoutRecorded -or $d2.loadStopSnapshotObserved) { throw 'D2 failed' }
$d3 = New-ContractCase -SnapshotObserved:$false -BadDrain:$true
if ($d3.drainArtifactsPresent -or $d3.drainObservationsValid) { throw 'D3 failed' }
$d4 = New-ContractCase -Missing:$true
if ($d4.drainArtifactsPresent) { throw 'D4 failed' }
$d5 = New-ContractCase -Incomplete:$true
if (-not $d5.drainArtifactsPresent -or -not $d5.loadStopSnapshotObserved) { throw 'D5 failed' }
Write-Output 'EXP128_LOAD_STOP_CONTRACT_D1_D5_PASS'
