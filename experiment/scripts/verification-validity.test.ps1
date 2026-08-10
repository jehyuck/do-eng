. (Join-Path $PSScriptRoot "resolve-verification-validity.ps1")

function New-Assertions([bool]$ExecutionPassed, [bool]$ApplicationPassed) {
    $assertions = [ordered]@{}
    foreach ($name in @(
        "preRunMockIdle", "loadStopAndDrainArtifactsPresent", "userCountMatchesVu",
        "loginCompletedBeforeMeasurement", "strictAuthEnabled", "distinctAuthorizations",
        "accountingContract", "observabilityArtifactsPresent"
    )) { $assertions[$name] = $ExecutionPassed }
    foreach ($name in @(
        "oneTrueResponsePerVu", "oneProgressAndPicturePerVu", "oneStoredObjectPerVu",
        "pictureKeysMatchStorage", "reconnectRamp", "storedObjectsMatchFixture"
    )) { $assertions[$name] = $ApplicationPassed }
    return [pscustomobject]$assertions
}

$caseA = Get-VerificationValidity (New-Assertions $true $true)
if ($caseA.executionValidity -ne "VALID" -or -not $caseA.applicationOutcomePassed) { throw "Case A classification failed" }

$caseB = Get-VerificationValidity (New-Assertions $true $false)
if ($caseB.executionValidity -ne "VALID" -or $caseB.applicationOutcomePassed) { throw "Case B classification failed" }

$caseC = Get-VerificationValidity (New-Assertions $false $true)
if ($caseC.executionValidity -ne "INVALID" -or -not $caseC.applicationOutcomePassed) { throw "Case C classification failed" }

"verification validity separation test passed"
