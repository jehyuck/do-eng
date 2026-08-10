function Get-VerificationValidity {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Assertions
    )

    $executionNames = @(
        "preRunMockIdle",
        "loadStopAndDrainArtifactsPresent",
        "userCountMatchesVu",
        "loginCompletedBeforeMeasurement",
        "strictAuthEnabled",
        "distinctAuthorizations",
        "accountingContract",
        "observabilityArtifactsPresent"
    )
    $applicationOutcomeNames = @(
        "oneTrueResponsePerVu",
        "oneProgressAndPicturePerVu",
        "oneStoredObjectPerVu",
        "pictureKeysMatchStorage",
        "reconnectRamp",
        "storedObjectsMatchFixture"
    )

    $executionAssertions = [ordered]@{}
    foreach ($name in $executionNames) {
        $executionAssertions[$name] = [bool]($Assertions.$name -eq $true)
    }
    $applicationOutcomeAssertions = [ordered]@{}
    foreach ($name in $applicationOutcomeNames) {
        $applicationOutcomeAssertions[$name] = [bool]($Assertions.$name -eq $true)
    }

    [ordered]@{
        executionAssertions = $executionAssertions
        executionValidity = if (@($executionAssertions.Values -contains $false)) { "INVALID" } else { "VALID" }
        applicationOutcomeAssertions = $applicationOutcomeAssertions
        applicationOutcomePassed = -not (@($applicationOutcomeAssertions.Values -contains $false))
    }
}
