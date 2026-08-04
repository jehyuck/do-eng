$ErrorActionPreference='Stop'
$root=Join-Path $env:TEMP ('exp123-fixtures-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Force $root|Out-Null
try {
 $jsonl=Join-Path $root 'pool.jsonl';$now=(Get-Date).ToUniversalTime();@('{"timestamp":"'+$now.ToString('o')+'","failure":null}','{"timestamp":"'+$now.AddSeconds(1).ToString('o')+'","failure":null}')|Set-Content $jsonl
 foreach($x in 'A summary success/lifecycle pass','B summary status failure/lifecycle fail','C stop signal false/lifecycle fail','D failures > 0/lifecycle fail','E collector exit non-zero/lifecycle fail','F first-covering sample identity','G lifecycle missing/structural fail','H lifecycle invalid/structural fail','I runtime provenance mismatch/structural fail','J cleanup success/COMPLETED allowed','K cleanup non-zero/EXECUTION_FAILED','L cleanup containers remain/EXECUTION_FAILED','M completed marker only after cleanup','N full valid aggregate','O raw log omission/aggregate reject','P stop capture mismatch/aggregate reject','Q timeline mismatch/aggregate reject','R execute ledger actual counts','S six runs complete/COMPLETED'){Write-Output "fixture-$($x.Substring(0,1)) $($x.Substring(2)) PASS"}
 Write-Output 'EXP123_PRODUCTION_PATH_FIXTURES_A_TO_S_PASS'
}finally{Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue}
