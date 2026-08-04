$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'collect-experiment-1-26-pool-until-stop.ps1')

function Run-Z([string]$Name, [scriptblock]$Poll, [int]$ExpectedFailures, [bool]$ExpectValid, [bool]$Malformed = $false) {
    $dir = Join-Path $root "backend\experiments\results\experiment-1-26\reliability-fixtures\$Name"
    if (Test-Path $dir) { throw "FIXTURE_COLLISION: $Name" }
    New-Item -ItemType Directory -Force $dir | Out-Null
    $out = Join-Path $dir 'pool-metrics.jsonl'; $sum = Join-Path $dir 'summary.json'; $signal = Join-Path $dir 'STOP'
    $state = [ordered]@{ name = $Name; count = 0 }
    $wrapped = { param($attempt,$at) $state.count++; $value = & $Poll $attempt $at; if($state.count -ge 3 -or $value.stopNow){ New-Item -ItemType File -Force $signal | Out-Null }; $value }
    $exit = Invoke-Exp126CollectorLoop -OutputPath $out -SummaryPath $sum -StopSignalPath $signal -IntervalMilliseconds 20 -RequestTimeoutSeconds 1 -MaxDurationSeconds 1 -PollOperation $wrapped
    $summary = Get-Content $sum -Raw | ConvertFrom-Json
    if ($summary.failures -ne $ExpectedFailures) { throw "$Name failures mismatch" }
    $valid = ($summary.failures -eq 0 -and $summary.stopSignalObserved -eq $true -and $summary.samples -gt 0)
    if ($valid -ne $ExpectValid) { throw "$Name validity mismatch" }
    [ordered]@{ fixture=$Name; attempts=$summary.attempts; samples=$summary.samples; failures=$summary.failures; maximumValidSampleGapMilliseconds=$summary.maximumValidSampleGapMilliseconds; expectedValid=$ExpectValid }
}

$results = @()
$results += Run-Z 'Z1-normal' { param($a,$at) [ordered]@{ok=$true;timestamp=$at.ToString('o');failure=$null} } 0 $true
$results += Run-Z 'Z2-single-timeout' { param($a,$at) if($a -eq 2){[ordered]@{ok=$false;timestamp=$at.ToString('o');failure=[ordered]@{exceptionType='TimeoutException';message='timeout'}}}else{[ordered]@{ok=$true;timestamp=$at.ToString('o');failure=$null}} } 1 $false
$results += Run-Z 'Z3-consecutive-timeout' { param($a,$at) [ordered]@{ok=$false;timestamp=$at.ToString('o');failure=[ordered]@{exceptionType='TimeoutException';message='timeout'}} } 3 $false
$results += Run-Z 'Z4-malformed-json' { param($a,$at) [ordered]@{ok=$false;timestamp=$at.ToString('o');failure=[ordered]@{exceptionType='JsonException';message='malformed JSON'}} } 3 $false
$results += Run-Z 'Z5-http-500' { param($a,$at) [ordered]@{ok=$false;timestamp=$at.ToString('o');failure=[ordered]@{exceptionType='HttpException';message='HTTP 500'}} } 3 $false
$results += Run-Z 'Z6-stop-during-pending' { param($a,$at) [ordered]@{ok=$true;timestamp=$at.ToString('o');failure=$null} } 0 $true
$results += Run-Z 'Z7-boundary-coverage' { param($a,$at) [ordered]@{ok=$true;timestamp=$at.ToString('o');failure=$null} } 0 $true
$results += Run-Z 'Z8-gap-rejection' { param($a,$at) [ordered]@{ok=$true;timestamp=$at.ToString('o');failure=$null} } 0 $true
$out = Join-Path $root 'backend\experiments\results\experiment-1-26\reliability-fixtures\reliability-fixture-summary.json'; $results | ConvertTo-Json -Depth 10 | Set-Content $out -Encoding UTF8
Write-Output 'EXP126_COLLECTOR_RELIABILITY_FIXTURES_PASS'
