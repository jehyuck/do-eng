function Invoke-Exp121NativeLogCapture {
    param([Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$ContainerId,[Parameter(Mandatory)][string]$ApplicationDirectory)
    New-Item -ItemType Directory -Force -Path $ApplicationDirectory | Out-Null
    $stdout=Join-Path $ApplicationDirectory 'docker-logs.stdout.log'; $stderr=Join-Path $ApplicationDirectory 'docker-logs.stderr.log'; $combined=Join-Path $ApplicationDirectory 'application.log'; $meta=Join-Path $ApplicationDirectory 'docker-logs-capture.json'
    $started=(Get-Date).ToUniversalTime().ToString('o')
    $psi=[System.Diagnostics.ProcessStartInfo]::new();$psi.FileName='docker.exe';$psi.Arguments="logs --timestamps $ContainerId";$psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.CreateNoWindow=$true
    $p=Start-Process -FilePath 'docker.exe' -ArgumentList @('logs','--timestamps',$ContainerId) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -NoNewWindow -Wait -PassThru
    $stdoutBytes=(Get-Item -LiteralPath $stdout).Length;$stderrBytes=(Get-Item -LiteralPath $stderr).Length
    Set-Content -LiteralPath $combined -Value '=== DOCKER STDOUT ===' -Encoding UTF8;Get-Content -LiteralPath $stdout|Add-Content -LiteralPath $combined -Encoding UTF8;Add-Content -LiteralPath $combined -Value '=== DOCKER STDERR ===' -Encoding UTF8;Get-Content -LiteralPath $stderr|Add-Content -LiteralPath $combined -Encoding UTF8
    $completed=(Get-Date).ToUniversalTime().ToString('o');$status=if($p.ExitCode-eq0 -and (($stdoutBytes+$stderrBytes)-gt0) -and ((Get-Item $combined).Length-gt0)){'APPLICATION_LOG_CAPTURE_PASSED'}else{'APPLICATION_LOG_CAPTURE_FAILED'}
    [ordered]@{runId=$RunId;containerId=$ContainerId;command="docker logs --timestamps $ContainerId";startedAt=$started;completedAt=$completed;exitCode=$p.ExitCode;stdoutPath=$stdout;stderrPath=$stderr;stdoutBytes=$stdoutBytes;stderrBytes=$stderrBytes;combinedPath=$combined;combinedBytes=(Get-Item $combined).Length;captureStatus=$status}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $meta -Encoding UTF8
    if($status-ne'APPLICATION_LOG_CAPTURE_PASSED'){throw "Application log capture failed with exit code $($p.ExitCode)"};Get-Content -LiteralPath $meta -Raw|ConvertFrom-Json
}
