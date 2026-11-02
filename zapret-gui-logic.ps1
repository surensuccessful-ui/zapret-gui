# Pure helpers for ZAPRET GUI. No windows, services, or network.
# build-exe.ps1 inlines this file into the compiled EXE so an update
# stays a single ZapretGUI.exe for people who already installed it.

function Compare-ZapretVersion {
    param([string]$A, [string]$B)
    $na = ($A -replace '[^0-9.].*$', '')
    $nb = ($B -replace '[^0-9.].*$', '')
    try { return ([version]$na).CompareTo([version]$nb) } catch { return [string]::CompareOrdinal($A, $B) }
}

function Select-GuiUpdateAsset {
    param([string[]]$Names)
    foreach ($name in $Names) {
        if ($name -eq 'ZapretGUI.exe') { return $name }
    }
    foreach ($name in $Names) {
        if ($name -match '^ZapretGUI-.*\.exe$') { return $name }
    }
    return $null
}

function Get-GuiUpdateHashFromSums {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $fallback = ''
    foreach ($line in ($Text -split "`n")) {
        $line = $line.TrimEnd("`r").Trim()
        if ($line -match '^([0-9a-fA-F]{64})\s+ZapretGUI\.exe\s*$') {
            return $Matches[1].ToLowerInvariant()
        }
        if (-not $fallback -and $line -match '^([0-9a-fA-F]{64})\s+ZapretGUI-.*\.exe\s*$') {
            $fallback = $Matches[1].ToLowerInvariant()
        }
    }
    return $fallback
}

function Select-BestStrategy {
    param($Scores)
    $best = $null
    $bestOk = 0
    if (-not $Scores) { return $null }
    foreach ($row in $Scores) {
        $ok = 0
        $name = ''
        if ($row -is [System.Collections.IDictionary]) {
            $ok = [int]$row['Ok']
            $name = [string]$row['Name']
        } else {
            $ok = [int]$row.Ok
            $name = [string]$row.Name
        }
        if ($ok -gt $bestOk -and -not [string]::IsNullOrWhiteSpace($name)) {
            $bestOk = $ok
            $best = $name
        }
    }
    if ($bestOk -le 0) { return $null }
    return $best
}

function ConvertTo-HostName {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    $value = $Raw.Trim()
    $value = $value -replace '^\^', ''
    $value = $value -replace '^[a-zA-Z][a-zA-Z0-9+.-]*://', ''
    $value = $value -replace '^[^@/]+@', ''
    $value = ($value -split '[/?#]', 2)[0]
    $value = $value.Trim().TrimEnd('.')
    if ($value -match '^\[.+' ) { return $null }
    if ($value -match '^([^:]+):\d+$') { $value = $Matches[1] }
    $value = $value.Trim().ToLowerInvariant()
    if ($value.StartsWith('www.')) { $value = $value.Substring(4) }
    if ($value -match '^\d{1,3}(\.\d{1,3}){3}$') { return $null }
    try {
        $idn = New-Object System.Globalization.IdnMapping
        $value = $idn.GetAscii($value)
    } catch { return $null }
    if ($value -notmatch '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$') {
        return $null
    }
    return $value
}
