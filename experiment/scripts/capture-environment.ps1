param(
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    [string]$OutputDirectory,
    [string]$NodeCommand = "node",
    [string]$JavaCommand = "java"
)

$ErrorActionPreference = "Stop"

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
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

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repositoryRoot "experiment\results\$RunId"
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)

$resultsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "experiment\results")
)
$resultsPrefix = $resultsRoot.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar
) + [System.IO.Path]::DirectorySeparatorChar

if (-not $resolvedOutput.StartsWith(
        $resultsPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw "OutputDirectory must be inside $resultsRoot"
}

New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null

function Invoke-CapturedCommand {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    try {
        $output = & $Command @Arguments 2>&1
        if ($LASTEXITCODE -ne 0) {
            return [ordered]@{
                command = $Command
                available = $false
                output = ($output | Out-String).Trim()
            }
        }
        return [ordered]@{
            command = $Command
            available = $true
            output = ($output | Out-String).Trim()
        }
    } catch {
        return [ordered]@{
            command = $Command
            available = $false
            output = $_.Exception.Message
        }
    }
}

$sourceRoots = @(
    ".experiment-work\baseline-source-8e85646",
    "backend\doEngGameFlux",
    "backend\doEngGameMvc",
    "backend\experiment-mock",
    "backend\docker-compose.experiment.yaml",
    "experiment\load",
    "experiment\scripts"
)

$sourceFiles = foreach ($sourceRoot in $sourceRoots) {
    $absoluteRoot = Join-Path $repositoryRoot $sourceRoot
    if (-not (Test-Path -LiteralPath $absoluteRoot)) {
        continue
    }

    $item = Get-Item -LiteralPath $absoluteRoot
    if ($item.PSIsContainer) {
        Get-ChildItem -LiteralPath $absoluteRoot -Recurse -File |
            Where-Object {
                $_.FullName -notmatch '[\\/](build|\.gradle)[\\/]'
            }
    } else {
        $item
    }
}

$fileHashes = foreach ($file in ($sourceFiles | Sort-Object FullName -Unique)) {
    [ordered]@{
        path = Get-PathRelativeTo $repositoryRoot $file.FullName
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLower()
        bytes = $file.Length
    }
}

$aggregateText = ($fileHashes | ForEach-Object {
        "$($_.path)|$($_.sha256)|$($_.bytes)"
    }) -join "`n"
$aggregateBytes = [System.Text.Encoding]::UTF8.GetBytes($aggregateText)
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $aggregateHash = [System.BitConverter]::ToString(
        $sha256.ComputeHash($aggregateBytes)
    ).Replace("-", "").ToLower()
} finally {
    $sha256.Dispose()
}

$computerSystem = Get-CimInstance Win32_ComputerSystem
$processor = Get-CimInstance Win32_Processor | Select-Object -First 1
$operatingSystem = Get-CimInstance Win32_OperatingSystem

$environment = [ordered]@{
    runId = $RunId
    capturedAt = (Get-Date).ToUniversalTime().ToString("o")
    git = [ordered]@{
        head = (
            & git @gitRepositoryArguments rev-parse HEAD
        ).Trim()
        branch = (
            & git @gitRepositoryArguments branch --show-current
        ).Trim()
        status = (
            & git @gitRepositoryArguments status --short
        )
    }
    source = [ordered]@{
        aggregateSha256 = $aggregateHash
        files = $fileHashes
    }
    host = [ordered]@{
        os = $operatingSystem.Caption
        osVersion = $operatingSystem.Version
        cpu = $processor.Name
        logicalProcessors = $computerSystem.NumberOfLogicalProcessors
        totalMemoryBytes = [long]$computerSystem.TotalPhysicalMemory
    }
    tools = [ordered]@{
        docker = Invoke-CapturedCommand "docker" @("version", "--format", "{{json .}}")
        java = Invoke-CapturedCommand $JavaCommand @("-version")
        node = Invoke-CapturedCommand $NodeCommand @("--version")
        git = Invoke-CapturedCommand "git" @("--version")
    }
}

$environmentPath = Join-Path $resolvedOutput "environment.json"
$environment | ConvertTo-Json -Depth 8 |
    Set-Content -Encoding UTF8 -LiteralPath $environmentPath

Write-Output $environmentPath
