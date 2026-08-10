function Get-ComparisonSourceStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,
        [string[]]$ComparisonSourcePaths = @(
            "backend/doEngGameFlux/Dockerfile.experiment",
            "backend/doEngGameFlux/build.gradle",
            "backend/doEngGameFlux/settings.gradle",
            "backend/doEngGameFlux/gradlew",
            "backend/doEngGameFlux/gradlew.bat",
            "backend/doEngGameFlux/gradle",
            "backend/doEngGameFlux/src/main",
            "backend/doEngGameMvc/Dockerfile.experiment",
            "backend/doEngGameMvc/build.gradle",
            "backend/doEngGameMvc/settings.gradle",
            "backend/doEngGameMvc/src/main",
            "backend/experiment-mock/Dockerfile",
            "backend/experiment-mock/server.js",
            "backend/docker-compose.experiment.yaml",
            "experiment/compose/experiment-1-37-runtime.override.yml",
            "experiment/load/mission-load.js",
            "experiment/config/experiment-variable-contract.json",
            "experiment/config/resolve-experiment-config.ps1",
            "experiment/scripts/run-comparison.ps1",
            "experiment/scripts/comparison-source-gate.ps1",
            "experiment/scripts/run-isolated-vu-success-smoke.ps1",
            "experiment/scripts/resolve-verification-validity.ps1",
            "experiment/scripts/provision-experiment-users.ps1",
            "image/arc.jpg"
        )
    )

    $dirtyPaths = @()
    Push-Location $RepositoryRoot
    try {
        foreach ($path in $ComparisonSourcePaths) {
            $statusLines = @(git status --short --untracked-files=all -- $path)
            if ($LASTEXITCODE -ne 0) { throw "Git status failed for comparison source path: $path" }
            $dirtyPaths += @($statusLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    } finally {
        Pop-Location
    }

    [ordered]@{
        clean = $dirtyPaths.Count -eq 0
        paths = $ComparisonSourcePaths
        dirtyPaths = $dirtyPaths
    }
}
