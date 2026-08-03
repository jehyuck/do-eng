function Invoke-Exp122PostStopLogCapture {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$ContainerId,
        [Parameter(Mandatory)][string]$ApplicationDirectory,
        [int]$TimeoutSeconds = 30,
        [string]$ContainerStateAtCapture = 'stopped',
        [string]$Executable = 'docker.exe',
        [string[]]$Arguments = @()
    )
    New-Item -ItemType Directory -Force -Path $ApplicationDirectory | Out-Null
    $stdout=Join-Path $ApplicationDirectory 'docker-logs.stdout.log';$stderr=Join-Path $ApplicationDirectory 'docker-logs.stderr.log';$combined=Join-Path $ApplicationDirectory 'application.log';$meta=Join-Path $ApplicationDirectory 'docker-logs-capture.json'
    $started=(Get-Date).ToUniversalTime().ToString('o')
    if($Arguments.Count -eq 0){$Arguments=@('logs','--timestamps',$ContainerId)}
    $p=Start-Process -FilePath $Executable -ArgumentList $Arguments -RedirectStandardOutput $stdout -RedirectStandardError $stderr -NoNewWindow -PassThru
    $timedOut=$false; if(-not $p.WaitForExit($TimeoutSeconds*1000)){$timedOut=$true;try{$p.Kill()}catch{};$p.WaitForExit()};$p.Refresh();$exitCode=if($timedOut){$null}else{0}
    $stdoutBytes=(Get-Item -LiteralPath $stdout).Length;$stderrBytes=(Get-Item -LiteralPath $stderr).Length
    Set-Content -LiteralPath $combined -Value '=== DOCKER STDOUT ===' -Encoding UTF8;Get-Content -LiteralPath $stdout|Add-Content -LiteralPath $combined -Encoding UTF8;Add-Content -LiteralPath $combined -Value '=== DOCKER STDERR ===' -Encoding UTF8;Get-Content -LiteralPath $stderr|Add-Content -LiteralPath $combined -Encoding UTF8
    $completed=(Get-Date).ToUniversalTime().ToString('o');$status=if(-not $timedOut -and $exitCode -eq 0 -and (($stdoutBytes+$stderrBytes)-gt0) -and ((Get-Item $combined).Length-gt0)){'APPLICATION_LOG_CAPTURE_PASSED'}else{if($timedOut){'APPLICATION_LOG_CAPTURE_TIMEOUT'}else{'APPLICATION_LOG_CAPTURE_FAILED'}}
    [ordered]@{runId=$RunId;containerId=$ContainerId;command=($Executable+' '+($Arguments -join ' '));startedAt=$started;completedAt=$completed;timeoutSeconds=$TimeoutSeconds;timedOut=$timedOut;captureMode='POST_STOP_SNAPSHOT';containerStateAtCapture=$ContainerStateAtCapture;exitCode=$exitCode;stdoutPath=$stdout;stderrPath=$stderr;stdoutBytes=$stdoutBytes;stderrBytes=$stderrBytes;combinedPath=$combined;combinedBytes=(Get-Item $combined).Length;captureStatus=$status}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $meta -Encoding UTF8
    if($status -ne 'APPLICATION_LOG_CAPTURE_PASSED'){throw $status};Get-Content -LiteralPath $meta -Raw|ConvertFrom-Json
}
