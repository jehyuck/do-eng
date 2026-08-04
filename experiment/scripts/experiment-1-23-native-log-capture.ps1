. (Join-Path $PSScriptRoot 'experiment-1-22-native-log-capture.ps1')
function Invoke-Exp123PostStopLogCapture { param([Parameter(Mandatory)][hashtable]$Parameters); Invoke-Exp122PostStopLogCapture @Parameters }
