function Get-Exp128LoadStopContract {
    param(
        [Parameter(Mandatory)][int]$DrainObservationSeconds,
        [Parameter(Mandatory)]$LoadStopMockMetrics,
        [Parameter(Mandatory)]$MockDrain,
        [Parameter(Mandatory)][object[]]$MockDrainSamples,
        [Parameter(Mandatory)][bool]$DrainJsonlPresent,
        [Parameter(Mandatory)][bool]$DrainSummaryPresent
    )

    $loadStopArtifactPresent = $null -ne $LoadStopMockMetrics
    $loadStopSnapshotObserved = $loadStopArtifactPresent -and
        $LoadStopMockMetrics.ok -eq $true -and
        $null -ne $LoadStopMockMetrics.metrics -and
        [string]::IsNullOrWhiteSpace([string]$LoadStopMockMetrics.error)
    $loadStopSnapshotTimeoutRecorded = $loadStopArtifactPresent -and
        $LoadStopMockMetrics.ok -eq $false -and
        [string]$LoadStopMockMetrics.error -eq 'timeout'

    $drainSampleCountValid = $DrainSummaryPresent -and
        $null -ne $MockDrain -and
        [int]$MockDrain.sampleCount -eq ($DrainObservationSeconds + 1) -and
        $MockDrain.configuredSeconds -eq $DrainObservationSeconds -and
        $MockDrainSamples.Count -eq ($DrainObservationSeconds + 1)
    $drainSequenceValid = $false
    if ($MockDrainSamples.Count -gt 0) {
        $first = $MockDrainSamples[0]
        $rest = @($MockDrainSamples | Select-Object -Skip 1)
        $drainSequenceValid = $first.phase -eq 'load-stop' -and
            [int]$first.elapsedMs -eq 0 -and
            $rest.Count -eq $DrainObservationSeconds -and
            (@($rest | Where-Object { $_.phase -ne 'drain' -or [int]$_.sample -lt 1 -or [int]$_.sample -gt $DrainObservationSeconds }).Count -eq 0) -and
            (@($rest | ForEach-Object { [int]$_.sample } | Sort-Object -Unique) -join ',' -eq ((1..$DrainObservationSeconds) -join ','))
    }
    $elapsedValues = @($MockDrainSamples | ForEach-Object { [int]$_.elapsedMs })
    $elapsedValid = $true
    for ($i = 0; $i -lt $elapsedValues.Count; $i++) {
        if ($elapsedValues[$i] -lt 0 -or ($i -gt 0 -and $elapsedValues[$i] -lt $elapsedValues[$i - 1])) {
            $elapsedValid = $false
            break
        }
    }
    $drainTimestampsValid = $true
    $previous = [DateTimeOffset]::MinValue
    foreach ($sample in $MockDrainSamples) {
        $parsed = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$sample.capturedAt, [ref]$parsed) -or $parsed -lt $previous) {
            $drainTimestampsValid = $false
            break
        }
        $previous = $parsed
    }
    $drainObservationsValid = (@($MockDrainSamples | Select-Object -Skip 1 | Where-Object {
        $_.ok -ne $true -or $null -eq $_.metrics
    }).Count -eq 0)
    $summaryIdentityValid = $DrainSummaryPresent -and $MockDrainSamples.Count -gt 0 -and
        $MockDrain.initial.phase -eq $MockDrainSamples[0].phase -and
        $MockDrain.initial.capturedAt -eq $MockDrainSamples[0].capturedAt -and
        $MockDrain.terminal.capturedAt -eq $MockDrainSamples[-1].capturedAt -and
        [int]$MockDrain.sampleCount -eq $MockDrainSamples.Count -and
        [int]$MockDrain.configuredSeconds -eq $DrainObservationSeconds

    $loadStopObservationValid = $loadStopSnapshotObserved -or $loadStopSnapshotTimeoutRecorded
    [ordered]@{
        loadStopArtifactPresent = $loadStopArtifactPresent
        loadStopSnapshotObserved = $loadStopSnapshotObserved
        loadStopSnapshotTimeoutRecorded = $loadStopSnapshotTimeoutRecorded
        drainJsonlPresent = $DrainJsonlPresent
        drainSummaryPresent = $DrainSummaryPresent
        drainSampleCountValid = $drainSampleCountValid
        drainSequenceValid = $drainSequenceValid
        drainElapsedValid = $elapsedValid
        drainTimestampsValid = $drainTimestampsValid
        drainObservationsValid = $drainObservationsValid
        drainSummaryIdentityValid = $summaryIdentityValid
        loadStopObservationValid = $loadStopObservationValid
        drainArtifactsPresent = $DrainObservationSeconds -eq 0 -or (
            $loadStopObservationValid -and $DrainJsonlPresent -and $DrainSummaryPresent -and
            $drainSampleCountValid -and $drainSequenceValid -and $drainTimestampsValid -and
            $elapsedValid -and $drainObservationsValid -and $summaryIdentityValid
        )
    }
}
