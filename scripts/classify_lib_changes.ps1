param(
    [Parameter(Mandatory = $true)][string]$Base,
    [Parameter(Mandatory = $true)][string]$Target
)

$ErrorActionPreference = 'Stop'

function Test-LibraryExists([string]$Ref, [string]$Library) {
    $rows = @(& git ls-tree -d --name-only $Ref -- $Library 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Git tree lookup failed: $($rows -join ' ')"
    }
    if ($rows.Count -gt 1 -or ($rows.Count -eq 1 -and $rows[0] -ne $Library)) {
        throw "Unexpected Git tree output for $Library"
    }
    return $rows.Count -eq 1
}

try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git is unavailable'
    }

    foreach ($ref in @($Base, $Target)) {
        $ErrorActionPreference = 'Continue'
        & git cat-file -e "$ref^{commit}" 2>$null | Out-Null
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -ne 0) {
            throw "Invalid commit ref: $ref"
        }
    }

    $rows = @(& git -c core.quotePath=false diff --no-renames --name-status $Base $Target -- Libs/ .pkgmeta .pkgmeta-lock.json 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Git diff failed: $($rows -join ' ')"
    }

    $libraries = @{}
    $metadata = @()
    foreach ($row in $rows) {
        if ($row -notmatch '^([AMD])\t(.+)$') {
            throw "Unexpected Git diff output: $row"
        }
        $status = $Matches[1]
        $path = $Matches[2]
        if ($path -eq '.pkgmeta' -or $path -eq '.pkgmeta-lock.json') {
            $metadata += [ordered]@{ path = $path; status = $status }
            continue
        }
        if ($path -notmatch '^Libs/(.+)$') {
            throw "Unexpected library path: $path"
        }
        $parts = $Matches[1] -split '/', 2
        $library = if ($parts.Count -eq 1) { 'Libs' } else { "Libs/$($parts[0])" }
        if (-not $libraries.ContainsKey($library)) {
            $libraries[$library] = @{ files = 0; statuses = @() }
        }
        $libraries[$library].files++
        $libraries[$library].statuses += $status
    }

    $changes = @(
        foreach ($library in ($libraries.Keys | Sort-Object)) {
            $entry = $libraries[$library]
            $status = 'M'
            $uniqueStatuses = @($entry.statuses | Select-Object -Unique)
            if ($uniqueStatuses.Count -eq 1 -and $uniqueStatuses[0] -eq 'A' -and
                -not (Test-LibraryExists $Base $library)) {
                $status = 'A'
            } elseif ($uniqueStatuses.Count -eq 1 -and $uniqueStatuses[0] -eq 'D' -and
                -not (Test-LibraryExists $Target $library)) {
                $status = 'D'
            }
            [ordered]@{ library = $library; status = $status; files = $entry.files }
        }
    )
    [ordered]@{ changes = $changes; metadata = @($metadata | Sort-Object path) } |
        ConvertTo-Json -Compress -Depth 5
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
