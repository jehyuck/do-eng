param(
    [Parameter(Mandatory = $true)][string]$ManagementUrl,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [int]$DurationSeconds = 140,
    [int]$IntervalMilliseconds = 1000
)

$ErrorActionPreference = "Stop"
$parent = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$end = (Get-Date).ToUniversalTime().AddSeconds($DurationSeconds)
$failures = 0
while ((Get-Date).ToUniversalTime() -lt $end) {
    $captured = (Get-Date).ToUniversalTime().ToString("o")
    try {
        $snapshot = Invoke-RestMethod -Uri ($ManagementUrl.TrimEnd('/') + "/actuator/doengadmission") -TimeoutSec 5
        [ordered]@{ timestamp = $captured; snapshot = $snapshot; failure = $null } |
            ConvertTo-Json -Depth 8 | Add-Content -Encoding UTF8 -LiteralPath $OutputPath
    } catch {
        $failures++
        [ordered]@{ timestamp = $captured; snapshot = $null; failure = $_.Exception.Message } |
            ConvertTo-Json -Depth 8 | Add-Content -Encoding UTF8 -LiteralPath $OutputPath
    }
    Start-Sleep -Milliseconds $IntervalMilliseconds
}
[ordered]@{ durationSeconds = $DurationSeconds; intervalMilliseconds = $IntervalMilliseconds; failures = $failures } |
    ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath ($OutputPath + ".summary.json")
