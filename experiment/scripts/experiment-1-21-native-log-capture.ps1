function Invoke-Exp121NativeLogCapture {
    param([Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$ContainerId,[Parameter(Mandatory)][string]$ApplicationDirectory)
    New-Item -ItemType Directory -Force -Path $ApplicationDirectory | Out-Null
    $stdout=Join-Path $ApplicationDirectory 'docker-logs.stdout.log'; $stderr=Join-Path $ApplicationDirectory 'docker-logs.stderr.log'; $combined=Join-Path $ApplicationDirectory 'application.log'; $meta=Join-Path $ApplicationDirectory 'docker-logs-capture.json'
    $started=(Get-Date).ToUniversalTime().ToString('o')
    $psi=[System.Diagnostics.ProcessStartInfo]::new();$psi.FileName='docker.exe';$psi.Arguments="logs --timestamps $ContainerId";$psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.CreateNoWindow=$true
    $p=[System.Diagnostics.Process]::new();$p.StartInfo=$psi;$null=$p.Start();$out=$p.StandardOutput.ReadToEnd();$err=$p.StandardError.ReadToEnd();$p.WaitForExit();[System.IO.File]::WriteAllText($stdout,$out);[System.IO.File]::WriteAllText($stderr,$err)
    [System.IO.File]::WriteAllText($combined,"=== DOCKER STDOUT ===`r`n$out`r`n=== DOCKER STDERR ===`r`n$err")
    $completed=(Get-Date).ToUniversalTime().ToString('o');$status=if($p.ExitCode-eq0 -and (($out.Length+$err.Length)-gt0) -and ((Get-Item $combined).Length-gt0)){'APPLICATION_LOG_CAPTURE_PASSED'}else{'APPLICATION_LOG_CAPTURE_FAILED'}
    [ordered]@{runId=$RunId;containerId=$ContainerId;command="docker logs --timestamps $ContainerId";startedAt=$started;completedAt=$completed;exitCode=$p.ExitCode;stdoutPath=$stdout;stderrPath=$stderr;stdoutBytes=$out.Length;stderrBytes=$err.Length;combinedPath=$combined;combinedBytes=(Get-Item $combined).Length;captureStatus=$status}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $meta -Encoding UTF8
    if($status-ne'APPLICATION_LOG_CAPTURE_PASSED'){throw "Application log capture failed with exit code $($p.ExitCode)"};Get-Content -LiteralPath $meta -Raw|ConvertFrom-Json
}
