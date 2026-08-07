param(
    [Parameter(Mandatory=$true)][ValidateSet('Smoke','Execute')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$RunId,
    [string]$ExpectedCommit='2a0f35e2ee9e22330e315154e6f270db0dcbfad9'
)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$source=Get-Content (Join-Path $PSScriptRoot 'run-exp155-flow-control-cell.ps1') -Raw -Encoding UTF8
$temp=Join-Path $PSScriptRoot ('.doeng-exp165-run-'+$RunId.ToLowerInvariant()+'.ps1')
$appImage='doeng-exp162-sink-serialized-flux-corrected:latest'; $mockImage='doeng-exp153-b3-recovery-experiment-mock:latest'
$source=$source.Replace('[ValidateSet("CONTROL","GATE","SINK")]', '[ValidateSet("SINK")]')
$source=$source.Replace('[string]$ExpectedCommit = ""', "[string]`$ExpectedCommit = '$ExpectedCommit'")
$source=$source.Replace('cf5b36ad38928d55eab131d1328dc85ccff0ad3b',$ExpectedCommit)
$source=$source.Replace('experiment-1-55','experiment-1-65').Replace('Exp155','Exp165').Replace('EXP155_EXECUTE_PASS','EXP165_EXECUTE_PASS').Replace('doeng-exp155-','doeng-exp165-')
$source=$source.Replace('experiment-1-65-{0}.override.yml','experiment-1-65-finite-batch.override.yml')
$source=$source.Replace('doeng-exp153-b3-recovery-flux-corrected:latest',$appImage).Replace('doeng-exp153-b3-recovery-experiment-mock:latest',$mockImage)
$source=$source.Replace('durationMs=30000;drainSeconds=30','durationMs=1000;drainSeconds=60').Replace('$env:DRAIN_OBSERVATION_SECONDS="30"','$env:DRAIN_OBSERVATION_SECONDS="60"')
$source=$source.Replace('activeMissions=200; intervalMs=1000; durationMs=30000; clientTimeoutMs=15000; aiDelayMs=2000; storageDelayMs=100','activeMissions=300; intervalMs=1000; durationMs=1000; clientTimeoutMs=60000; aiDelayMs=2000; storageDelayMs=100')
$source=$source.Replace('aiPool="400/640"','aiPool="600/960"')
$source=$source.Replace('admission=$admissionMode; sink=$sinkMode','admission=$admissionMode; sink=$sinkMode; sinkTokenConcurrency=100; sinkAiConcurrency=400; sinkStorageConcurrency=100; sinkTokenQueue=300; sinkAiQueue=1200; sinkStorageQueue=300')
$source=$source.Replace('$env:ACTIVE_MISSIONS="200"','$env:ACTIVE_MISSIONS="300"').Replace('$env:INITIAL_ACTIVE_USERS="200"','$env:INITIAL_ACTIVE_USERS="300"').Replace('$env:ACTIVATION_STEP_USERS="200"','$env:ACTIVATION_STEP_USERS="300"').Replace('$env:DURATION_MS="30000"','$env:DURATION_MS="1000"').Replace('$env:REQUEST_TIMEOUT_MS="15000"','$env:REQUEST_TIMEOUT_MS="60000"')
$source=$source.Replace('$collector = $null','$collector = $null'+[Environment]::NewLine+'$dispatcherCollector = $null')
$extra=@'
function Start-DispatcherCollector {
    $out=Join-Path $runDir "dispatcher-metrics.jsonl"; $m=$managementUrl; $script:dispatcherCollector=Start-Job -ScriptBlock {
        param($out,$m); $end=(Get-Date).AddSeconds(70)
        while((Get-Date)-lt $end){$ts=[DateTime]::UtcNow.ToString("o"); foreach($d in @("token","ai","storage")){try{$q=Invoke-RestMethod "$m/actuator/metrics/doeng.dispatcher.queue.depth`?tag=dispatcher:$d" -TimeoutSec 3;$a=Invoke-RestMethod "$m/actuator/metrics/doeng.dispatcher.active`?tag=dispatcher:$d" -TimeoutSec 3;(@{timestamp=$ts;dispatcher=$d;queueDepth=$q.measurements[0].value;active=$a.measurements[0].value}|ConvertTo-Json -Compress)|Add-Content $out -Encoding UTF8}catch{(@{timestamp=$ts;dispatcher=$d;error=$_.Exception.Message}|ConvertTo-Json -Compress)|Add-Content $out -Encoding UTF8}};Start-Sleep 1}
    } -ArgumentList $out,$m
}
'@
$idx=$source.LastIndexOf('Assert-Inputs'); if($idx -lt 0){throw 'ASSERT_INPUTS_MARKER_NOT_FOUND'}; $source=$source.Insert($idx,$extra+[Environment]::NewLine)
$source=$source.Replace('Start-Collector; Start-Sleep 5; Run-Load; Save-Snapshots','if($Mode -eq "Smoke"){Save-Json (Join-Path $runDir "smoke.json") ([ordered]@{status="PASS";health="UP"})}else{Start-Collector; Start-DispatcherCollector; Start-Sleep 5; Run-Load; Save-Snapshots}')
$source=$source.Replace('Wait-Job $collector -Timeout 100 | Out-Null; Receive-Job $collector -ErrorAction SilentlyContinue | Out-Null; Remove-Job $collector -Force','if($collector){Wait-Job $collector -Timeout 100 | Out-Null; Receive-Job $collector -ErrorAction SilentlyContinue | Out-Null; Remove-Job $collector -Force}; if($dispatcherCollector){Wait-Job $dispatcherCollector -Timeout 100 | Out-Null; Receive-Job $dispatcherCollector -ErrorAction SilentlyContinue | Out-Null; Remove-Job $dispatcherCollector -Force}')
$source=$source.Replace('if ($collector) { Remove-Job $collector -Force -ErrorAction SilentlyContinue }','if ($collector) { Remove-Job $collector -Force -ErrorAction SilentlyContinue }; if ($dispatcherCollector) { Remove-Job $dispatcherCollector -Force -ErrorAction SilentlyContinue }')
$source=$source.Replace('    Validate-Run','    if($Mode -eq "Execute"){Validate-Run}')
Set-Content $temp $source -Encoding UTF8
try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $temp -Cell SINK -Mode $Mode -RunId $RunId -ExpectedCommit $ExpectedCommit; exit $LASTEXITCODE }
finally { Remove-Item $temp -Force -ErrorAction SilentlyContinue }
