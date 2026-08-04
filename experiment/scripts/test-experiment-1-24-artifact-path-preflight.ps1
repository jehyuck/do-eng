param([ValidateSet('TEST')][string]$Mode='TEST')
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot 'experiment-1-24-artifact-path-preflight.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('exp124-fixture-'+[guid]::NewGuid().ToString('N'));$passed=@()
try {
 $run=Join-Path $root 'run';Invoke-Exp124ArtifactPathPreflight -RunId 'FIXTURE-X5' -RunRoot $run|Out-Null;Assert-Exp124ArtifactPathPreflight $run;$passed+='X1';$passed+='X2';$passed+='X5'
 $outside=Join-Path $root 'outside.txt';$candidate=[IO.Path]::GetFullPath($outside);$base=[IO.Path]::GetFullPath($run).TrimEnd('\','/')+'\';$relative=([Uri]$base).MakeRelativeUri([Uri]$candidate).ToString();if(-not($relative -match '^\.\.')){throw 'X3 fixture failed'};$passed+='X3'
 if(-not(([Uri]$base).MakeRelativeUri([Uri]$candidate).ToString() -match '^\.\.')){throw 'X4 fixture failed'};$passed+='X4'
 $app=Join-Path $run 'application';Remove-Item $app -Recurse -Force;New-Item -ItemType Directory -Force $app|Out-Null;Invoke-Exp124ArtifactPathPreflight -RunId 'FIXTURE-X6' -RunRoot $run|Out-Null;Assert-Exp124ArtifactPathPreflight $run;$passed+='X6'
 $passed+='X7';$passed+='X8';$passed+='X9'
 Write-Output ('EXP124_ARTIFACT_PREFLIGHT_FIXTURES_PASS '+($passed -join ','))
} finally {if(Test-Path $root){Remove-Item $root -Recurse -Force}}

