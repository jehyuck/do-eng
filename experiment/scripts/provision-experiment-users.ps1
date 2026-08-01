param(
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    [Parameter(Mandatory = $true)]
    [string]$ComposeProject,
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 1000)]
    [int]$UserCount,
    [Parameter(Mandatory = $true)]
    [string]$MetadataPath,
    [Parameter(Mandatory = $true)]
    [string]$TokenPath,
    [string[]]$ComposeFiles,
    [string]$MockBaseUrl = "http://127.0.0.1:9100"
)

$ErrorActionPreference = "Stop"

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ($null -eq $ComposeFiles -or $ComposeFiles.Count -eq 0) {
    $ComposeFiles = @(Join-Path $repositoryRoot "backend\docker-compose.experiment.yaml")
}
$ComposeFiles = @($ComposeFiles | ForEach-Object {
    $_ -split ',' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
})
$composeArguments = @()
foreach ($composeFile in $ComposeFiles) {
    if (-not (Test-Path -LiteralPath $composeFile)) {
        throw "Compose file not found: $composeFile"
    }
    $composeArguments += @("-f", $composeFile)
}

$safeRunId = $RunId -replace "[^A-Za-z0-9_-]", "-"
if ([string]::IsNullOrWhiteSpace($safeRunId)) {
    throw "RunId did not produce a safe experiment-user prefix"
}
$memberPrefix = "experiment-$safeRunId"
$metadataAbsolutePath = [System.IO.Path]::GetFullPath($MetadataPath)
$tokenAbsolutePath = [System.IO.Path]::GetFullPath($TokenPath)
if (Test-Path -LiteralPath $metadataAbsolutePath) {
    throw "MetadataPath already exists: $metadataAbsolutePath"
}
if (Test-Path -LiteralPath $tokenAbsolutePath) {
    throw "TokenPath already exists: $tokenAbsolutePath"
}

function Invoke-DatabaseSql {
    param([Parameter(Mandatory = $true)][string]$Sql)

    $output = & docker compose `
        -p $ComposeProject `
        @composeArguments `
        exec -T mariadb `
        mariadb -N -B `
        -udoeng `
        -pdoeng-experiment-pass `
        doeng `
        -e $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "Experiment-user database operation failed"
    }
    return @($output)
}

$existingCount = @(Invoke-DatabaseSql -Sql (
    "SELECT COUNT(*) FROM member WHERE member_id LIKE '$memberPrefix-%';"
))
if ($existingCount.Count -ne 1 -or [int]$existingCount[0] -ne 0) {
    throw "Experiment user prefix already exists in this database: $memberPrefix"
}

$passwordHash = '$2a$10$2ycck55zXeJz4fhB3gi8s.MuWyuOTojSLQmMHpYrR7yH1PfLd6UAq'
$usersToCreate = for ($index = 1; $index -le $UserCount; $index++) {
    $login = "$memberPrefix-u$index"
    [ordered]@{
        vu = $index
        login = $login
        email = "$login@example.invalid"
        nickname = $login
    }
}

$valueRows = @($usersToCreate | ForEach-Object {
    "(UTC_TIMESTAMP(6), 'ROLE_EXPERIMENT', '$($_.email)', '$($_.login)', '$($_.login)', '$($_.nickname)', '$passwordHash', '000-0000-0000', NULL, NULL)"
})
# docker compose forwards the SQL as a process argument on Windows. A single
# INSERT for large VU cohorts can exceed the Windows command-line limit before
# MariaDB receives it, so keep each otherwise identical multi-row INSERT small.
$insertBatchSize = 25
for ($startIndex = 0; $startIndex -lt $valueRows.Count; $startIndex += $insertBatchSize) {
    $endIndex = [Math]::Min($startIndex + $insertBatchSize - 1, $valueRows.Count - 1)
    $batchRows = @($valueRows[$startIndex..$endIndex])
    $insertSql = @"
INSERT INTO member
    (created_at, authority, email, member_id, name, nickname, password, phone, provider, provider_id)
VALUES
$($batchRows -join ",`n");
"@
    Invoke-DatabaseSql -Sql $insertSql | Out-Null
}

$rows = @(Invoke-DatabaseSql -Sql @"
SELECT id, member_id
FROM member
WHERE member_id LIKE '$memberPrefix-%'
ORDER BY id;
"@)
if ($rows.Count -ne $UserCount) {
    throw "Created member count mismatch: expected $UserCount, found $($rows.Count)"
}

$provisionedUsers = for ($index = 0; $index -lt $rows.Count; $index++) {
    $fields = $rows[$index] -split "`t", 2
    if ($fields.Count -ne 2) {
        throw "Experiment-user database row could not be parsed: $($rows[$index])"
    }
    $expected = $usersToCreate[$index]
    if ($fields[1] -ne $expected.login) {
        throw "Experiment-user order mismatch: expected $($expected.login), found $($fields[1])"
    }
    [ordered]@{
        vu = $expected.vu
        login = $expected.login
        memberId = [long]$fields[0]
    }
}

$registration = Invoke-RestMethod `
    -Method Post `
    -Uri "$MockBaseUrl/__auth/users" `
    -ContentType "application/json" `
    -Body (([ordered]@{
        users = @($provisionedUsers | ForEach-Object {
            [ordered]@{
                login = $_.login
                memberId = $_.memberId
            }
        })
    }) | ConvertTo-Json -Depth 5 -Compress)
if (-not $registration.strictAuth -or $registration.registeredUsers -ne $UserCount) {
    throw "Auth mock registration did not enable the expected strict-user state"
}

$authorizations = [System.Collections.Generic.List[string]]::new()
foreach ($user in $provisionedUsers) {
    $loginResponse = Invoke-RestMethod `
        -Method Post `
        -Uri "$MockBaseUrl/__auth/login" `
        -ContentType "application/json" `
        -Body (([ordered]@{ login = $user.login }) | ConvertTo-Json -Compress)
    if ($loginResponse.memberId -ne $user.memberId -or
        [string]::IsNullOrWhiteSpace($loginResponse.authorization)) {
        throw "Mock login returned an invalid identity for VU $($user.vu)"
    }
    $authorizations.Add([string]$loginResponse.authorization)
}
if (($authorizations | Select-Object -Unique).Count -ne $UserCount) {
    throw "Mock login did not issue distinct tokens"
}

$mockMetrics = Invoke-RestMethod -Uri "$MockBaseUrl/__metrics"
if (-not $mockMetrics.strictAuth -or
    $mockMetrics.authRegisteredUsers -ne $UserCount -or
    $mockMetrics.authIssuedTokens -ne $UserCount -or
    $mockMetrics.authLoginCompleted -ne $UserCount -or
    $mockMetrics.authLoginFailures -ne 0) {
    throw "Auth mock metrics did not match the provisioned users"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $metadataAbsolutePath) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $tokenAbsolutePath) | Out-Null
[ordered]@{
    runId = $RunId
    memberPrefix = $memberPrefix
    userCount = $UserCount
    users = $provisionedUsers
    auth = [ordered]@{
        strictAuth = $mockMetrics.strictAuth
        registeredUsers = $mockMetrics.authRegisteredUsers
        issuedTokens = $mockMetrics.authIssuedTokens
        loginCompleted = $mockMetrics.authLoginCompleted
        loginFailures = $mockMetrics.authLoginFailures
    }
    tokenFile = "private runtime file; deleted by the calling runner"
    completedAt = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath $metadataAbsolutePath

$authorizations | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $tokenAbsolutePath

Get-Content -Raw -LiteralPath $metadataAbsolutePath
