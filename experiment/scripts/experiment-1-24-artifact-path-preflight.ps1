function Get-Exp124RelativePath { param([string]$Base,[string]$Candidate); ([Uri]$Base).MakeRelativeUri([Uri]$Candidate).ToString() }
function Initialize-Exp124ArtifactDirectories {
 param([Parameter(Mandatory)][string]$RunRoot)
 $dirs=@('application','pool','database','container','mock','drain','provenance')
 New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
 foreach($name in $dirs){ New-Item -ItemType Directory -Force -Path (Join-Path $RunRoot $name) | Out-Null }
}
function Test-Exp124ArtifactDirectoryWriteability {
 param([Parameter(Mandatory)][string]$RunRoot)
 $root=[IO.Path]::GetFullPath($RunRoot).TrimEnd('\','/')+'\'
 $dirs=@('application','pool','database','container','mock','drain','provenance')
 $rows=@()
 foreach($name in $dirs){
  $path=[IO.Path]::GetFullPath((Join-Path $RunRoot $name))
  $relative=Get-Exp124RelativePath $root ($path+'\')
  $contained= -not [IO.Path]::IsPathRooted($relative) -and $relative -ne '..' -and -not $relative.StartsWith('..\') -and -not $relative.StartsWith('../')
  $existedBefore=Test-Path -LiteralPath $path -PathType Container;$tmp=Join-Path $path ('.exp124-write-probe-'+[guid]::NewGuid().ToString('N')+'.tmp')
  $created=$false;$write=$false;$deleted=$false
  try { if(-not(Test-Path -LiteralPath $path -PathType Container)){throw 'DIRECTORY_MISSING'}; Set-Content -LiteralPath $tmp -Value 'EXP124_WRITE_PROBE' -Encoding UTF8; $created=$true; $write=((Get-Content -LiteralPath $tmp -Raw).Trim() -eq 'EXP124_WRITE_PROBE'); Remove-Item -LiteralPath $tmp -Force; $deleted=$true } catch { if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue} }
  $rows+=[ordered]@{name=$name;path=$path;canonicalPath=$path;directoryExistedBefore=$existedBefore;directoryExistsAfterInitialization=(Test-Path -LiteralPath $path -PathType Container);created=(-not $existedBefore);pathContained=$contained;writeProbeCreated=$created;writeProbeContentVerified=$write;writeProbePassed=$write;deleteProbePassed=$deleted;probeFileAbsentAfterDelete=(-not(Test-Path -LiteralPath $tmp))}
 }
 $rows
}
function Invoke-Exp124ArtifactPathPreflight {
 param([Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$RunRoot)
 $started=(Get-Date).ToUniversalTime().ToString('o');$rows=@();$failureType=$null;$failedDirectory=$null
 try { Initialize-Exp124ArtifactDirectories $RunRoot; $rows=@(Test-Exp124ArtifactDirectoryWriteability $RunRoot); if($rows.Count -ne 7){throw 'ARTIFACT_PATH_PREFLIGHT_DIRECTORY_COUNT_INVALID'};if(@($rows|Where-Object{$_.directoryExistsAfterInitialization -ne $true -or $_.pathContained -ne $true -or $_.writeProbeCreated -ne $true -or $_.writeProbeContentVerified -ne $true -or $_.deleteProbePassed -ne $true -or $_.probeFileAbsentAfterDelete -ne $true}).Count -gt 0){throw 'ARTIFACT_PATH_PREFLIGHT_PROBE_FAILED'} }
 catch { $failureType=$_.Exception.Message }
 $passed=[string]::IsNullOrWhiteSpace($failureType);$artifact=[ordered]@{runId=$RunId;startedAt=$started;completedAt=(Get-Date).ToUniversalTime().ToString('o');requiredDirectories=$rows;failedDirectory=$failedDirectory;preflightStatus=if($passed){'ARTIFACT_PATH_PREFLIGHT_PASSED'}else{'ARTIFACT_PATH_PREFLIGHT_FAILED'};failureType=if($passed){$null}else{$failureType}}
 $path=Join-Path $RunRoot 'provenance/artifact-path-preflight.json';try{if(Test-Path (Split-Path $path)){ $tmp=$path+'.tmp';[IO.File]::WriteAllText($tmp,($artifact|ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)));Move-Item -LiteralPath $tmp -Destination $path -Force }}catch{}
 if(-not $passed){throw $failureType};$artifact
}
function Assert-Exp124ArtifactPathPreflight {
 param([Parameter(Mandatory)][string]$RunRoot)
 $p=Join-Path $RunRoot 'provenance/artifact-path-preflight.json';if(-not(Test-Path -LiteralPath $p)){throw 'PREFLIGHT_ARTIFACT_MISSING'};$o=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json;$r=Join-Path $RunRoot 'run-config.json';if((Test-Path -LiteralPath $r) -and ((Get-Content $r -Raw|ConvertFrom-Json).runId -ne $o.runId)){throw 'PREFLIGHT_RUN_ID_MISMATCH'};if($o.preflightStatus -ne 'ARTIFACT_PATH_PREFLIGHT_PASSED'){throw 'PREFLIGHT_STATUS_INVALID'};if(@($o.requiredDirectories).Count -ne 7 -or @($o.requiredDirectories|Where-Object{$_.pathContained -ne $true -or $_.directoryExistsAfterInitialization -ne $true -or $_.writeProbeCreated -ne $true -or $_.writeProbeContentVerified -ne $true -or $_.deleteProbePassed -ne $true -or $_.probeFileAbsentAfterDelete -ne $true}).Count -ne 0){throw 'PREFLIGHT_DIRECTORY_CONTRACT_FAILED'}
}
















