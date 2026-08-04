. (Join-Path $PSScriptRoot 'experiment-1-22-container-stop.ps1')
function Invoke-Exp123ContainerStop { param([Parameter(Mandatory)][hashtable]$Parameters); Invoke-Exp122ContainerStop @Parameters }
