. (Join-Path $PSScriptRoot "comparison-source-gate.ps1")

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$status = Get-ComparisonSourceStatus -RepositoryRoot $repositoryRoot
if (-not $status.clean) { throw "Comparison source is unexpectedly dirty: $($status.dirtyPaths -join '; ')" }
if ($status.paths.Count -lt 10) { throw "Comparison source path set is incomplete" }

$temporaryRepository = Join-Path ([IO.Path]::GetTempPath()) "doeng-comparison-gate-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temporaryRepository -Force | Out-Null
try {
    & git -C $temporaryRepository init --quiet
    Set-Content -LiteralPath (Join-Path $temporaryRepository "tracked-input.txt") -Value "uncommitted"
    $dirtyStatus = Get-ComparisonSourceStatus -RepositoryRoot $temporaryRepository -ComparisonSourcePaths @("tracked-input.txt")
    if ($dirtyStatus.clean -or @($dirtyStatus.dirtyPaths).Count -eq 0) { throw "Dirty comparison source was not rejected" }
} finally {
    Remove-Item -LiteralPath $temporaryRepository -Recurse -Force -ErrorAction SilentlyContinue
}
"comparison source dirty gate test passed"
