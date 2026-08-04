. (Join-Path $PSScriptRoot 'experiment-1-22-container-stop.ps1')
function Invoke-Exp125ContainerStop {
 param([Parameter(Mandatory)][hashtable]$Parameters)
 $metadata=[string]$Parameters.MetadataPath;if([string]::IsNullOrWhiteSpace($metadata)){throw 'CONTAINER_STOP_METADATA_PARENT_INVALID'}
 $dir=Split-Path -Parent $metadata;if([string]::IsNullOrWhiteSpace($dir)){throw 'CONTAINER_STOP_METADATA_PARENT_INVALID'}
 New-Item -ItemType Directory -Force -Path $dir|Out-Null;if(-not(Test-Path -LiteralPath $dir -PathType Container)){throw 'CONTAINER_STOP_METADATA_PARENT_UNAVAILABLE'}
 $tmp=$metadata+'.tmp';$p=@{};foreach($k in $Parameters.Keys){$p[$k]=$Parameters[$k]};$p.MetadataPath=$tmp
 try {$value=Invoke-Exp122ContainerStop @p;if(Test-Path -LiteralPath $tmp){$obj=Get-Content $tmp -Raw|ConvertFrom-Json;[IO.File]::WriteAllText($tmp,($obj|ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)));Move-Item -LiteralPath $tmp -Destination $metadata -Force};return $value}
 catch {if(Test-Path -LiteralPath $tmp){Move-Item -LiteralPath $tmp -Destination $metadata -Force};throw}
}




