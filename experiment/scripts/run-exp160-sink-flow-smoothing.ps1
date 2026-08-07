param(
    [Parameter(Mandatory=$true)][ValidateSet('Plan','Smoke','Execute')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$RunId,
    [string]$ExpectedCommit='2313b10a14c850a8992dfbc5d567f4b9a2b02244'
)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$template=Join-Path $repo 'experiment\scripts\run-exp155-flow-control-cell.ps1'
$temp=Join-Path (Join-Path $repo 'experiment\scripts') ('.doeng-exp160-run-'+$RunId.ToLowerInvariant()+'.ps1')
$source=Get-Content $template -Raw -Encoding UTF8
$source=$source.Replace('ValidateSet("CONTROL","GATE","SINK")','ValidateSet("SINK")')
$source=$source.Replace('experiment-1-55','experiment-1-60').Replace('Exp155','Exp160').Replace('EXP155_EXECUTE_PASS','EXP160_EXECUTE_PASS').Replace('doeng-exp155-','doeng-exp160-')
$source=$source.Replace('experiment-1-55-{0}.override.yml','experiment-1-60-sink.override.yml')
$source=[regex]::Replace($source,'(?ms)\$ports = switch \(\$Cell\) \{.*?\r?\n\}', '$ports = @{app=18560;management=19560;mock=18660;db=18760}',1)
$source=$source.Replace('durationMs=30000;drainSeconds=30','durationMs=30000;drainSeconds=15').Replace('$env:DRAIN_OBSERVATION_SECONDS="30"','$env:DRAIN_OBSERVATION_SECONDS="15"')
$source=$source.Replace('aiPool="400/640"','aiPool="600/960"').Replace('admission=$admissionMode; sink=$sinkMode','admission=$admissionMode; sink=$sinkMode; sinkTokenConcurrency=100; sinkAiConcurrency=400; sinkStorageConcurrency=100; sinkTokenQueue=300; sinkAiQueue=1200; sinkStorageQueue=300')
$source=$source.Replace('$collector = $null','$collector = $null'+[Environment]::NewLine+'$dispatcherCollector = $null')
$extra=@'
function Start-DispatcherCollector {
    $out=Join-Path $runDir "dispatcher-metrics.jsonl"; $m=$managementUrl; $script:dispatcherCollector=Start-Job -ScriptBlock {
        param($out,$m)
        $end=(Get-Date).AddSeconds(95)
        while((Get-Date)-lt $end){
            $ts=[DateTime]::UtcNow.ToString("o")
            foreach($d in @("token","ai","storage")){
                try {
                    $q=(Invoke-RestMethod "$m/actuator/metrics/doeng.dispatcher.queue.depth`?tag=dispatcher:$d" -TimeoutSec 3)
                    $a=(Invoke-RestMethod "$m/actuator/metrics/doeng.dispatcher.active`?tag=dispatcher:$d" -TimeoutSec 3)
                    $w=(Invoke-RestMethod "$m/actuator/metrics/doeng.dispatcher.queue.wait`?tag=dispatcher:$d" -TimeoutSec 3)
                    (@{timestamp=$ts;dispatcher=$d;queueDepth=$q.measurements[0].value;active=$a.measurements[0].value;queueWaitCount=$w.measurements[0].count;queueWaitMaxMs=$w.measurements[0].max}|ConvertTo-Json -Compress)|Add-Content $out -Encoding UTF8
                } catch { (@{timestamp=$ts;dispatcher=$d;error=$_.Exception.Message}|ConvertTo-Json -Compress)|Add-Content $out -Encoding UTF8 }
            }
            Start-Sleep 1
        }
    } -ArgumentList $out,$m
}
function Save-DispatcherSnapshot {
    $result=[ordered]@{capturedAt=(Get-Date).ToUniversalTime().ToString("o");dispatchers=[ordered]@{}}
    foreach($d in @("token","ai","storage")){
        $entry=[ordered]@{}
        foreach($metric in @("queue.depth","active","events","queue.wait","deadline")){
            try{$entry[$metric]=(Invoke-RestMethod "$managementUrl/actuator/metrics/doeng.dispatcher.$metric`?tag=dispatcher:$d" -TimeoutSec 5)}catch{$entry[$metric]=[ordered]@{status="NOT_AVAILABLE";error=$_.Exception.Message}}
        }
        $result.dispatchers[$d]=$entry
    }
    Save-Json (Join-Path $runDir "dispatcher-final.json") $result
}
'@
$idx=$source.LastIndexOf('Assert-Inputs')
if($idx -ge 0){$source=$source.Insert($idx,[Environment]::NewLine+$extra+[Environment]::NewLine)}else{throw 'ASSERT_INPUTS_MARKER_NOT_FOUND'}
$source=$source.Replace('Start-Collector; Start-Sleep 5; Run-Load; Save-Snapshots','if($Mode -eq "Smoke"){Save-Json (Join-Path $runDir "smoke.json") ([ordered]@{status="PASS";health="UP"})}else{Start-Collector; Start-DispatcherCollector; Start-Sleep 5; Run-Load; Save-Snapshots; Save-DispatcherSnapshot}')
$source=$source.Replace('Wait-Job $collector -Timeout 100 | Out-Null; Receive-Job $collector -ErrorAction SilentlyContinue | Out-Null; Remove-Job $collector -Force','if($collector){Wait-Job $collector -Timeout 100 | Out-Null; Receive-Job $collector -ErrorAction SilentlyContinue | Out-Null; Remove-Job $collector -Force}; if($dispatcherCollector){Wait-Job $dispatcherCollector -Timeout 100 | Out-Null; Receive-Job $dispatcherCollector -ErrorAction SilentlyContinue | Out-Null; Remove-Job $dispatcherCollector -Force}')
$source=$source.Replace('    Validate-Run','    if($Mode -ne "Smoke"){Validate-Run}')
$source=$source.Replace('if ($collector) { Remove-Job $collector -Force -ErrorAction SilentlyContinue }','if ($collector) { Remove-Job $collector -Force -ErrorAction SilentlyContinue }; if ($dispatcherCollector) { Remove-Job $dispatcherCollector -Force -ErrorAction SilentlyContinue }')
Set-Content $temp $source -Encoding UTF8
try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $temp -Cell SINK -Mode $Mode -RunId $RunId -ExpectedCommit $ExpectedCommit; exit $LASTEXITCODE }
finally { Remove-Item $temp -Force -ErrorAction SilentlyContinue }
