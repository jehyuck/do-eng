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
  $tmp=Join-Path $path ('.exp124-write-probe-'+[guid]::NewGuid().ToString('N')+'.tmp')
  $created=$false;$write=$false;$deleted=$false
  try { if(-not(Test-Path -LiteralPath $path -PathType Container)){throw 'DIRECTORY_MISSING'}; Set-Content -LiteralPath $tmp -Value 'EXP124_WRITE_PROBE' -Encoding UTF8; $created=$true; $write=((Get-Content -LiteralPath $tmp -Raw).Trim() -eq 'EXP124_WRITE_PROBE'); Remove-Item -LiteralPath $tmp -Force; $deleted=$true } catch { if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue} }
  $rows+=[ordered]@{name=$name;path=$path;canonicalPath=$path;created=$true;pathContained=$contained;writeProbePassed=$write;deleteProbePassed=$deleted}
 }
 $rows
}
function Invoke-Exp124ArtifactPathPreflight {
 param([Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$RunRoot)
 $started=(Get-Date).ToUniversalTime().ToString('o'); Initialize-Exp124ArtifactDirectories $RunRoot; $rows=@(Test-Exp124ArtifactDirectoryWriteability $RunRoot); $passed=($rows.Count -eq 7 -and ($rows|Where-Object{-not $_.pathContained -or -not $_.writeProbePassed -or -not $_.deleteProbePassed}).Count -eq 0)
 $artifact=[ordered]@{runId=$RunId;startedAt=$started;completedAt=(Get-Date).ToUniversalTime().ToString('o');requiredDirectories=$rows;preflightStatus=if($passed){'ARTIFACT_PATH_PREFLIGHT_PASSED'}else{'ARTIFACT_PATH_PREFLIGHT_FAILED'};failureType=if($passed){$null}else{'ARTIFACT_PATH_PREFLIGHT_FAILED'}}
 $path=Join-Path $RunRoot 'provenance/artifact-path-preflight.json';$tmp=$path+'.tmp';$artifact|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $path -Force
 if(-not $passed){throw 'ARTIFACT_PATH_PREFLIGHT_FAILED'}; $artifact
}
function Assert-Exp124ArtifactPathPreflight {
 param([Parameter(Mandatory)][string]$RunRoot)
 $p=Join-Path $RunRoot 'provenance/artifact-path-preflight.json';if(-not(Test-Path -LiteralPath $p)){throw 'PREFLIGHT_ARTIFACT_MISSING'};$o=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json;if($o.preflightStatus -ne 'ARTIFACT_PATH_PREFLIGHT_PASSED'){throw 'PREFLIGHT_STATUS_INVALID'};if(@($o.requiredDirectories).Count -ne 7 -or @($o.requiredDirectories|Where-Object{-not $_.pathContained -or -not $_.writeProbePassed -or -not $_.deleteProbePassed}).Count -ne 0){throw 'PREFLIGHT_DIRECTORY_CONTRACT_FAILED'}
}


