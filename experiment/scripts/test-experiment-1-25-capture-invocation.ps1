$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'experiment-1-25-native-log-capture.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('exp125-capture-'+[guid]::NewGuid().ToString('N'));$app=Join-Path $root 'application';New-Item -ItemType Directory -Force $app|Out-Null;$name='exp125-capture-fixture-'+[guid]::NewGuid().ToString('N')
$container=$null
try {
 $container=(& docker run -d --name $name alpine sh -c 'echo fixture-output; echo fixture-error 1>&2').Trim();if($LASTEXITCODE){throw 'CAPTURE_FIXTURE_CONTAINER_START_FAILED'};Start-Sleep -Seconds 1;& docker stop $name|Out-Null
 $captureParameters=@{RunId='FIXTURE-Y1';ContainerId=$container;ApplicationDirectory=$app;TimeoutSeconds=30;ContainerStateAtCapture='exited'};$cap=Invoke-Exp125PostStopLogCapture @captureParameters
 if($cap.captureStatus -ne 'APPLICATION_LOG_CAPTURE_PASSED' -or -not(Test-Path (Join-Path $app 'docker-logs-capture.json')) -or (Test-Path (Join-Path $app 'docker-logs-capture.json.tmp'))){throw 'Y1_CAPTURE_SPLAT_FAILED'};$passed=@('Y1','Y6')
 $checks=@(
  [pscustomobject]@{name='Y2';invoke={ Invoke-Exp125PostStopLogCapture @{RunId='x';ContainerId=$container;ApplicationDirectory=$app} }},
  [pscustomobject]@{name='Y3';invoke={ Invoke-Exp125PostStopLogCapture @{ContainerId=$container;ApplicationDirectory=$app} }},
  [pscustomobject]@{name='Y4';invoke={ Invoke-Exp125PostStopLogCapture @{RunId='x';ApplicationDirectory=$app} }},
  [pscustomobject]@{name='Y5';invoke={ Invoke-Exp125PostStopLogCapture @{RunId='x';ContainerId=$container} }}
 )
 foreach($check in $checks){$failed=$false;try{& $check.invoke|Out-Null}catch{$failed=$true};if(-not$failed){throw "$($check.name)_MISSING_PARAMETER_NOT_REJECTED"};$passed+=$check.name}
 Write-Output ('EXP125_CAPTURE_INVOCATION_FIXTURES_PASS '+($passed -join ','))
} finally {if($container){& docker rm -f $name|Out-Null};if(Test-Path $root){Remove-Item $root -Recurse -Force}}

