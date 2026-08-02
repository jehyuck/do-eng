param(
    [Parameter(Mandatory = $true)][ValidateSet("Start", "Stop", "Verify")][string]$Action,
    [Parameter(Mandatory = $true)][string]$CaptureRoot,
    [Parameter(Mandatory = $true)][string]$ComposeProject,
    [Parameter(Mandatory = $true)][string[]]$ComposeFiles
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$capturePath = if ([System.IO.Path]::IsPathRooted($CaptureRoot)) {
    [System.IO.Path]::GetFullPath($CaptureRoot)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $root $CaptureRoot))
}
$applicationPath = Join-Path $capturePath "application"
$mockPath = Join-Path $capturePath "mock"
$composeArgs = @()
foreach ($file in $ComposeFiles) { $composeArgs += @("-f", $file) }
$previousCaptureRoot = $env:EXP112_CAPTURE_ROOT
$env:EXP112_CAPTURE_ROOT = $capturePath.Replace("\", "/")

try {
    if ($Action -eq "Start") {
        New-Item -ItemType Directory -Force -Path $applicationPath,$mockPath | Out-Null
        docker compose -p $ComposeProject @composeArgs up -d --force-recreate capture-application capture-mock | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "capture sidecar start failed" }
        Start-Sleep -Seconds 2
        foreach ($service in @("capture-application", "capture-mock")) {
            $containerOutput = docker compose -p $ComposeProject @composeArgs ps -q $service
            $container = if ($null -eq $containerOutput) { "" } else { $containerOutput.ToString().Trim() }
            if ([string]::IsNullOrWhiteSpace($container)) { throw "capture container missing: $service" }
            $running = (docker inspect -f "{{.State.Running}}" $container).Trim()
            if ($running -ne "true") { throw "capture container is not running: $service" }
        }
    } elseif ($Action -eq "Stop") {
        docker compose -p $ComposeProject @composeArgs stop -t 10 capture-application capture-mock | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "capture sidecar stop failed" }
        foreach ($entry in @(
            @{ Directory = $applicationPath; Pcap = "application-control.pcap"; Text = "application-control.txt" },
            @{ Directory = $mockPath; Pcap = "mock-control.pcap"; Text = "mock-control.txt" }
        )) {
            $mount = "$($entry.Directory.Replace('\', '/')):/capture"
            $previousErrorPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            $output = docker run --rm -v $mount nicolaka/netshoot:v0.13 `
                tcpdump -nn -tt -S -r "/capture/$($entry.Pcap)" 2>&1
            $decodeExitCode = $LASTEXITCODE
            $ErrorActionPreference = $previousErrorPreference
            if ($decodeExitCode -ne 0) { throw "pcap decode failed: $($entry.Pcap)" }
            $output | ForEach-Object { $_.ToString() } |
                Out-File -LiteralPath (Join-Path $entry.Directory $entry.Text) -Encoding UTF8
        }
    } else {
        foreach ($file in @(
            (Join-Path $applicationPath "application-control.pcap"),
            (Join-Path $applicationPath "application-control.txt"),
            (Join-Path $mockPath "mock-control.pcap"),
            (Join-Path $mockPath "mock-control.txt")
        )) {
            if (-not (Test-Path -LiteralPath $file)) { throw "capture artifact missing: $file" }
            if ((Get-Item -LiteralPath $file).Length -eq 0) { throw "capture artifact empty: $file" }
        }
    }
} finally {
    if ($null -eq $previousCaptureRoot) { Remove-Item Env:EXP112_CAPTURE_ROOT -ErrorAction SilentlyContinue }
    else { $env:EXP112_CAPTURE_ROOT = $previousCaptureRoot }
}
