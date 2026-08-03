$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$closure = Join-Path $root 'backend\experiments\results\experiment-1-19\closure'
$runId = 'RUN-20260803-EXP119-BASELINE-001'
$roots = @(
    'backend\experiments\results\experiment-1-19\core\RUN-20260803-EXP119-BASELINE-001',
    'experiment\results\RUN-20260803-EXP119-BASELINE-001'
)
New-Item -ItemType Directory -Force -Path $closure | Out-Null
$files = foreach ($relativeRoot in $roots) {
    $absoluteRoot = (Resolve-Path (Join-Path $root $relativeRoot)).Path
    Get-ChildItem -LiteralPath $absoluteRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
        [ordered]@{ root=$relativeRoot.Replace('\','/'); relativePath=$_.FullName.Substring($absoluteRoot.Length + 1).Replace('\','/'); sizeBytes=$_.Length; sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower() }
    }
}
[ordered]@{ experiment='Experiment 1-19'; runId=$runId; outcomeInspected=$false; inventoryMethod='path, size and SHA-256 only'; generatedAt=(Get-Date).ToUniversalTime().ToString('o'); files=@($files) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $closure 'raw-artifact-inventory.json') -Encoding UTF8
[ordered]@{ experiment='Experiment 1-19'; runId=$runId; classification='MEASUREMENT_EXECUTED_ARTIFACT_INCOMPLETE'; warmupStarted=$true; coreStarted=$true; k6Started=$true; requiredArtifactMissing='pool/pool-metrics.jsonl'; eligibleForAggregate=$false; rerunAllowedUnderExperiment119=$false; remainingExperiment119RunsAllowed=$false; policyDecision='NOT_RUN'; finalExperimentState='INVALID'; rawOutcomeInspectedDuringClosure=$false } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $closure 'measurement-disposition.json') -Encoding UTF8
