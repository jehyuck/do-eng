param(
    [Parameter(Mandatory = $true)][string]$ManagementUrl,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [int]$DurationSeconds = 1,
    [int]$IntervalMilliseconds = 1000
)

$ErrorActionPreference = "Stop"
if ($DurationSeconds -le 0 -or $IntervalMilliseconds -le 0) {
    throw "DurationSeconds and IntervalMilliseconds must be positive"
}

$parent = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$deadline = (Get-Date).AddSeconds($DurationSeconds)
$failures = 0
while ((Get-Date) -lt $deadline) {
    $capturedAt = (Get-Date).ToUniversalTime().ToString("o")
    try {
        $snapshot = Invoke-RestMethod -Uri ($ManagementUrl.TrimEnd('/') + "/actuator/doengdiagnosticpool") -TimeoutSec 5
        [ordered]@{
            timestamp = $capturedAt
            provider = $snapshot.provider
            metrics = $snapshot.metrics
            failure = $null
        } | ConvertTo-Json -Depth 8 -Compress | Add-Content -Encoding UTF8 -LiteralPath $OutputPath
    } catch {
        $failures++
        [ordered]@{
            timestamp = $capturedAt
            provider = "doeng-external"
            metrics = @()
            failure = $_.Exception.Message
        } | ConvertTo-Json -Depth 8 -Compress | Add-Content -Encoding UTF8 -LiteralPath $OutputPath
    }
    Start-Sleep -Milliseconds $IntervalMilliseconds
}
[ordered]@{ durationSeconds = $DurationSeconds; intervalMilliseconds = $IntervalMilliseconds; failures = $failures } |
    ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -LiteralPath ($OutputPath + ".summary.json")
