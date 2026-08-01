param(
    [string]$BaselineDirectory,
    [string]$ExpectedCommit = "8e856468b36dcb1d7297afc05461af01d6dd6424"
)

$ErrorActionPreference = "Stop"

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$workspaceRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot ".experiment-work")
)
$gitRepositoryArguments = @(
    "-c",
    "safe.directory=$($repositoryRoot.Replace('\', '/'))",
    "-C",
    $repositoryRoot
)

function Get-PathRelativeTo {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    $basePrefix = [System.IO.Path]::GetFullPath($BasePath).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    $targetFullPath = [System.IO.Path]::GetFullPath($TargetPath)
    if (-not $targetFullPath.StartsWith(
            $basePrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw "TargetPath must be inside BasePath: $targetFullPath"
    }

    return $targetFullPath.Substring($basePrefix.Length)
}

if ([string]::IsNullOrWhiteSpace($BaselineDirectory)) {
    $BaselineDirectory = Join-Path $workspaceRoot "baseline-source-$($ExpectedCommit.Substring(0, 7))"
}

$resolvedBaseline = [System.IO.Path]::GetFullPath($BaselineDirectory)
Get-PathRelativeTo $workspaceRoot $resolvedBaseline | Out-Null
$baselineRelative = (
    Get-PathRelativeTo $repositoryRoot $resolvedBaseline
).Replace("\", "/")
$manifestPath = Join-Path $resolvedBaseline "baseline-source-manifest.json"
$executionManifestPath = Join-Path $resolvedBaseline "baseline-execution-manifest.json"
$patchPath = Join-Path $repositoryRoot "experiment\patches\baseline-external-urls.patch"

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Baseline source manifest not found: $manifestPath"
}
if (Test-Path -LiteralPath $executionManifestPath) {
    throw "Baseline overlay already applied: $executionManifestPath"
}

$sourceManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($sourceManifest.sourceCommit -ne $ExpectedCommit) {
    throw "Unexpected baseline commit: $($sourceManifest.sourceCommit)"
}

& git @gitRepositoryArguments apply `
    --check `
    --whitespace=nowarn `
    "--directory=$baselineRelative" `
    $patchPath
if ($LASTEXITCODE -ne 0) {
    throw "Baseline overlay does not apply cleanly"
}

& git @gitRepositoryArguments apply `
    --whitespace=nowarn `
    "--directory=$baselineRelative" `
    $patchPath
if ($LASTEXITCODE -ne 0) {
    throw "Failed to apply baseline overlay"
}

$modifiedRelativePaths = @(
    "src\main\java\com\example\doenggameflux\component\TokenComponent.java",
    "src\main\java\com\example\doenggameflux\contoller\AiGameController.java"
)
$modifiedFiles = foreach ($relativePath in $modifiedRelativePaths) {
    $absolutePath = Join-Path $resolvedBaseline $relativePath
    [ordered]@{
        path = $relativePath
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $absolutePath).Hash.ToLower()
        bytes = (Get-Item -LiteralPath $absolutePath).Length
    }
}

[ordered]@{
    sourceCommit = $sourceManifest.sourceCommit
    sourceTree = $sourceManifest.sourceTree
    sourceManifestSha256 = (
        Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath
    ).Hash.ToLower()
    overlay = [ordered]@{
        path = Get-PathRelativeTo $repositoryRoot $patchPath
        sha256 = (
            Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath
        ).Hash.ToLower()
    }
    appliedAt = (Get-Date).ToUniversalTime().ToString("o")
    modifiedFiles = $modifiedFiles
} | ConvertTo-Json -Depth 6 |
    Set-Content -Encoding UTF8 -LiteralPath $executionManifestPath

Write-Output $executionManifestPath
