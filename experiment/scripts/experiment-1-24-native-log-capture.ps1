. (Join-Path $PSScriptRoot 'experiment-1-22-native-log-capture.ps1')
function Invoke-Exp124PostStopLogCapture {
 param([Parameter(Mandatory)][hashtable]$Parameters)
 $app=[string]$Parameters.ApplicationDirectory;if([string]::IsNullOrWhiteSpace($app)){throw 'APPLICATION_LOG_CAPTURE_DIRECTORY_INVALID'}
 New-Item -ItemType Directory -Force -Path $app|Out-Null;if(-not(Test-Path -LiteralPath $app -PathType Container)){throw 'APPLICATION_LOG_CAPTURE_DIRECTORY_UNAVAILABLE'}
 $value=Invoke-Exp122PostStopLogCapture @Parameters
 $meta=Join-Path $app 'docker-logs-capture.json';if(Test-Path -LiteralPath $meta){$tmp=$meta+'.tmp';Get-Content -LiteralPath $meta -Raw|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $meta -Force}
 $value
}
