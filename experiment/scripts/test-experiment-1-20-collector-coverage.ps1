$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'experiment-1-20-collector-coverage.ps1')
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("exp120-coverage-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
function Write-Fixture([string]$Name, [string[]]$Lines) {
    $dir = Join-Path $root $Name; New-Item -ItemType Directory -Path $dir | Out-Null
    $jsonl = Join-Path $dir 'pool-metrics.jsonl'; $Lines | Set-Content -LiteralPath $jsonl -Encoding UTF8
    @{ failures = 0 } | ConvertTo-Json | Set-Content -LiteralPath ($jsonl + '.summary.json') -Encoding UTF8
    $jsonl
}
function Invoke-Fixture([string]$Name, [string[]]$Lines, [string]$Expected) {
    $jsonl = Write-Fixture $Name $Lines
    $coverage = New-Exp120CollectorCoverage -RunId $Name -JsonlPath $jsonl -SummaryPath ($jsonl + '.summary.json') -CollectorDurationSeconds 150 -IntervalMilliseconds 1000 -CollectorProcessStartedAt '2026-08-03T00:00:00.0000000Z' -CoreInvocationStartedAt '2026-08-03T00:00:02.0000000Z' -CoreInvocationCompletedAt '2026-08-03T00:00:04.0000000Z' -CollectorProcessCompletedAt '2026-08-03T00:00:06.0000000Z'
    if ($Expected -eq 'COLLECTOR_COVERAGE_PASSED') { if ($coverage.coverageStatus -ne $Expected) { throw "$Name expected pass" } }
    elseif ($coverage.failureType -ne $Expected) { throw "$Name expected $Expected, got $($coverage.failureType)" }
    [ordered]@{ fixture = $Name; result = if ($Expected -eq 'COLLECTOR_COVERAGE_PASSED') { $coverage.coverageStatus } else { $coverage.failureType } }
}
try {
    $valid = @('{"timestamp":"2026-08-03T00:00:01.0000000Z","failure":null}','{"timestamp":"2026-08-03T00:00:03.0000000Z","failure":null}','{"timestamp":"2026-08-03T00:00:05.0000000Z","failure":null}')
    $results = @(
        Invoke-Fixture 'PASS' $valid 'COLLECTOR_COVERAGE_PASSED'
        Invoke-Fixture 'LATE' @('{"timestamp":"2026-08-03T00:00:03.0000000Z","failure":null}','{"timestamp":"2026-08-03T00:00:05.0000000Z","failure":null}') 'COLLECTOR_STARTED_LATE'
        Invoke-Fixture 'EARLY' @('{"timestamp":"2026-08-03T00:00:01.0000000Z","failure":null}','{"timestamp":"2026-08-03T00:00:03.0000000Z","failure":null}') 'COLLECTOR_ENDED_EARLY'
        Invoke-Fixture 'MALFORMED' @('{"timestamp":"2026-08-03T00:00:01.0000000Z","failure":null}','not-json','{"timestamp":"2026-08-03T00:00:05.0000000Z","failure":null}') 'COLLECTOR_INVALID_JSONL'
    )
    $results | ConvertTo-Json -Depth 4
} finally { Remove-Item -LiteralPath $root -Recurse -Force }
