param(
    [string]$Commit = "8e856468b36dcb1d7297afc05461af01d6dd6424",
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$gitRepositoryArguments = @(
    "-c",
    "safe.directory=$($repositoryRoot.Replace('\', '/'))",
    "-C",
    $repositoryRoot
)
$workspaceRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot ".experiment-work")
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

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $workspaceRoot "baseline-source-$($Commit.Substring(0, 7))"
}

$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
$workspacePrefix = $workspaceRoot.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar
) + [System.IO.Path]::DirectorySeparatorChar

if (-not $resolvedOutput.StartsWith(
        $workspacePrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw "OutputDirectory must be inside $workspaceRoot"
}

if (Test-Path -LiteralPath $resolvedOutput) {
    throw "Baseline output already exists: $resolvedOutput"
}

& git @gitRepositoryArguments cat-file -e "$Commit^{commit}"
if ($LASTEXITCODE -ne 0) {
    throw "Git commit is not available locally: $Commit"
}

$resolvedCommit = (
    & git @gitRepositoryArguments rev-parse "$Commit^{commit}"
).Trim()

New-Item -ItemType Directory -Path $workspaceRoot -Force | Out-Null
$archivePath = Join-Path $workspaceRoot "baseline-$($resolvedCommit.Substring(0, 7)).zip"

try {
    & git @gitRepositoryArguments archive `
        --format=zip `
        --output=$archivePath `
        "$resolvedCommit`:backend/doEngGameFlux"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to archive baseline source"
    }

    Expand-Archive -LiteralPath $archivePath -DestinationPath $resolvedOutput
} finally {
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath
    }
}

$sourceFiles = Get-ChildItem -LiteralPath $resolvedOutput -Recurse -File |
    Sort-Object FullName
$manifest = foreach ($file in $sourceFiles) {
    [ordered]@{
        path = Get-PathRelativeTo $resolvedOutput $file.FullName
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLower()
        bytes = $file.Length
    }
}

$manifestPath = Join-Path $resolvedOutput "baseline-source-manifest.json"
[ordered]@{
    sourceCommit = $resolvedCommit
    sourceTree = (
        & git @gitRepositoryArguments rev-parse "$resolvedCommit`:backend/doEngGameFlux"
    ).Trim()
    preparedAt = (Get-Date).ToUniversalTime().ToString("o")
    files = $manifest
} | ConvertTo-Json -Depth 5 |
    Set-Content -Encoding UTF8 -LiteralPath $manifestPath

Write-Output $resolvedOutput
