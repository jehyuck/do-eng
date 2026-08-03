$script:Exp119RequiredArtifacts = @(
    "run-config.json", "client-results.json", "client-progress.jsonl",
    "pool/pool-metrics.jsonl", "application/application.log",
    "database/database-metrics.jsonl", "container/container-stats.jsonl",
    "mock/load-stop-mock-metrics.json", "drain/mock-drain-summary.json",
    "verification-summary.json", "provenance/runtime-provenance.json",
    "execution-summary.json"
)

function Get-Exp119RequiredArtifacts { return @($script:Exp119RequiredArtifacts) }

function Copy-Exp119LegacyArtifacts([string]$LegacyRunRoot, [string]$RunRoot) {
    if (-not (Test-Path -LiteralPath $LegacyRunRoot)) { throw "Legacy run artifact root missing: $LegacyRunRoot" }
    $mapping = @(
        @{ Source = "run-config.json"; Destination = "run-config.json" },
        @{ Source = "client-results.json"; Destination = "client-results.json" },
        @{ Source = "client-progress.jsonl"; Destination = "client-progress.jsonl" },
        @{ Source = "pool-metrics.jsonl"; Destination = "pool/pool-metrics.jsonl" },
        @{ Source = "application.log"; Destination = "application/application.log" },
        @{ Source = "database-metrics.jsonl"; Destination = "database/database-metrics.jsonl" },
        @{ Source = "container-stats.jsonl"; Destination = "container/container-stats.jsonl" },
        @{ Source = "load-stop-mock-metrics.json"; Destination = "mock/load-stop-mock-metrics.json" },
        @{ Source = "mock-drain-summary.json"; Destination = "drain/mock-drain-summary.json" },
        @{ Source = "verification-summary.json"; Destination = "verification-summary.json" }
    )
    foreach ($entry in $mapping) {
        $source = Join-Path $LegacyRunRoot $entry.Source
        if (-not (Test-Path -LiteralPath $source)) { throw "Legacy required artifact missing: $source" }
        $destination = Join-Path $RunRoot $entry.Destination
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
    }
    $legacyProvenance = Join-Path $LegacyRunRoot "experiment-1-13-provenance.json"
    if (Test-Path -LiteralPath $legacyProvenance) {
        $destination = Join-Path $RunRoot "provenance/legacy/experiment-1-13-provenance.json"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $legacyProvenance -Destination $destination -ErrorAction Stop
    }
}

function Test-Exp119Json([string]$Path) {
    try { $null = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json; return $true }
    catch { return $false }
}

function Assert-Exp119RequiredArtifactCompleteness([string]$RunRoot) {
    $missing = @()
    foreach ($relative in $script:Exp119RequiredArtifacts) {
        $path = Join-Path $RunRoot $relative
        if (-not (Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -le 0) { $missing += $relative }
    }
    if ($missing.Count -gt 0) { throw "Required artifact missing or empty: $($missing -join ', ')" }
    foreach ($relative in @("run-config.json", "client-results.json", "mock/load-stop-mock-metrics.json", "drain/mock-drain-summary.json", "verification-summary.json", "provenance/runtime-provenance.json", "execution-summary.json")) {
        if (-not (Test-Exp119Json (Join-Path $RunRoot $relative))) { throw "Required JSON artifact is invalid: $relative" }
    }
    $poolLines = @(Get-Content -LiteralPath (Join-Path $RunRoot "pool/pool-metrics.jsonl") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($poolLines.Count -eq 0 -or -not (Test-Exp119JsonLine $poolLines[0])) { throw "Pool metrics JSONL has no valid line" }
    foreach ($directory in @("database", "container", "provenance")) {
        if ((Get-ChildItem -LiteralPath (Join-Path $RunRoot $directory) -File -Recurse | Where-Object { $_.Length -gt 0 }).Count -eq 0) { throw "Required collector directory has no output: $directory" }
    }
}

function Test-Exp119JsonLine([string]$Line) {
    try { $null = $Line | ConvertFrom-Json; return $true }
    catch { return $false }
}

function Set-Exp119TerminalState([string]$RunRoot, [ValidateSet("COMPLETED", "EXECUTION_FAILED")][string]$State) {
    foreach ($marker in @("RUNNING", "COMPLETED", "EXECUTION_FAILED")) {
        $path = Join-Path $RunRoot $marker
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    New-Item -ItemType File -Path (Join-Path $RunRoot $State) | Out-Null
}
