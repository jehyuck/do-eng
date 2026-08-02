param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = "Stop"
$rows = @(Get-Content -Encoding UTF8 -LiteralPath $InputPath | ForEach-Object {
    if ($_.Trim()) { $_ | ConvertFrom-Json }
})
$samples = @{}
$providerValues = @{}

foreach ($row in $rows) {
    if ($null -eq $row.snapshot -or $null -eq $row.snapshot.metrics) { continue }
    $timestamp = if ($row.snapshot.capturedAtEpochMs) {
        [string]$row.snapshot.capturedAtEpochMs
    } else {
        [string]$row.timestamp
    }
    if (-not $samples.ContainsKey($timestamp)) { $samples[$timestamp] = @{} }
    foreach ($metric in @($row.snapshot.metrics)) {
        $provider = $metric.tags.name
        if ([string]::IsNullOrWhiteSpace($provider)) { $provider = "NOT_AVAILABLE" }
        if (-not $providerValues.ContainsKey($provider)) { $providerValues[$provider] = @{} }
        $name = [string]$metric.name
        $shortName = $name -replace '^reactor\.netty\.connection\.provider\.', ''
        if ($shortName -notmatch '^(active|pending|total|idle|max)\.connections$' -and
            $shortName -notmatch '^max\.pending\.connections$') { continue }
        $key = "$provider|$shortName"
        $value = if ($null -eq $metric.value) { $null } else { [double]$metric.value }
        if (-not $samples[$timestamp].ContainsKey($key)) { $samples[$timestamp][$key] = $value }
        if ($null -ne $value) {
            if (-not $providerValues[$provider].ContainsKey($shortName)) { $providerValues[$provider][$shortName] = @() }
            $providerValues[$provider][$shortName] += $value
        }
    }
}

$providerSummary = foreach ($provider in ($providerValues.Keys | Sort-Object)) {
    $values = $providerValues[$provider]
    $entry = [ordered]@{ provider = $provider }
    foreach ($name in @(
            "active.connections", "pending.connections", "total.connections", "idle.connections",
            "max.connections", "max.pending.connections")) {
        $series = @($values[$name] | Where-Object { $null -ne $_ })
        $entry[($name -replace '\.', '_') + "_max"] = if ($series.Count) {
            ($series | Measure-Object -Maximum).Maximum
        } else { "NOT_AVAILABLE" }
    }
    $entry.poolAcquirePendingLimitExceptionCount = "NOT_AVAILABLE"
    $entry.prematureCloseExceptionCount = "NOT_AVAILABLE"
    [pscustomobject]$entry
}

$totalActive = @()
$totalPending = @()
foreach ($timestamp in $samples.Keys) {
    $active = 0.0
    $pending = 0.0
    foreach ($key in $samples[$timestamp].Keys) {
        $value = $samples[$timestamp][$key]
        if ($null -eq $value) { continue }
        if ($key -like "*|active.connections") { $active += $value }
        if ($key -like "*|pending.connections") { $pending += $value }
    }
    $totalActive += $active
    $totalPending += $pending
}

[ordered]@{
    sampleCount = $rows.Count
    providerSummary = @($providerSummary)
    sameTimestampTotalActiveMax = if ($totalActive.Count) { ($totalActive | Measure-Object -Maximum).Maximum } else { "NOT_AVAILABLE" }
    sameTimestampTotalPendingMax = if ($totalPending.Count) { ($totalPending | Measure-Object -Maximum).Maximum } else { "NOT_AVAILABLE" }
    poolAcquirePendingLimitExceptionCount = "NOT_AVAILABLE"
    prematureCloseExceptionCount = "NOT_AVAILABLE"
} | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $OutputPath
