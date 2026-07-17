Set-StrictMode -Version Latest

function Get-FileSha256Lower {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-AtomicCsvRow {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Row,

        [string]$ExpectedExistingSha256
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $parentPath = [System.IO.Path]::GetDirectoryName($fullPath)
    if (-not (Test-Path -LiteralPath $parentPath -PathType Container)) {
        throw "CSV parent directory does not exist: $parentPath"
    }
    $tempPath = Join-Path $parentPath ("." + [System.IO.Path]::GetFileName($fullPath) + "." + [guid]::NewGuid().ToString("N") + ".tmp")
    $backupPath = Join-Path $parentPath ("." + [System.IO.Path]::GetFileName($fullPath) + "." + [guid]::NewGuid().ToString("N") + ".replace-backup")
    $replaceCompleted = $false
    try {
        @($Row) | Export-Csv -LiteralPath $tempPath -NoTypeInformation -Encoding UTF8
        if (Test-Path -LiteralPath $fullPath) {
            $existingSha256 = Get-FileSha256Lower -Path $fullPath
            if ($ExpectedExistingSha256 -and $existingSha256 -ne $ExpectedExistingSha256.Trim().ToLowerInvariant()) {
                throw "CSV changed before atomic replacement: $fullPath"
            }
            if ((Get-FileSha256Lower -Path $tempPath) -eq $existingSha256) {
                return
            }
            [System.IO.File]::Replace($tempPath, $fullPath, $backupPath)
            $replaceCompleted = $true
        } else {
            [System.IO.File]::Move($tempPath, $fullPath)
        }
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
        }
        if ($replaceCompleted -and (Test-Path -LiteralPath $backupPath)) {
            Remove-Item -LiteralPath $backupPath -Force
        }
    }
}

function Write-AtomicCsvHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$Fields
    )

    $prototype = [ordered]@{}
    foreach ($field in $Fields) {
        $prototype[$field] = ""
    }
    $header = ([pscustomobject]$prototype | ConvertTo-Csv -NoTypeInformation)[0]
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $parentPath = [System.IO.Path]::GetDirectoryName($fullPath)
    if (-not (Test-Path -LiteralPath $parentPath -PathType Container)) {
        throw "CSV parent directory does not exist: $parentPath"
    }
    $tempPath = Join-Path $parentPath ("." + [System.IO.Path]::GetFileName($fullPath) + "." + [guid]::NewGuid().ToString("N") + ".tmp")
    $backupPath = Join-Path $parentPath ("." + [System.IO.Path]::GetFileName($fullPath) + "." + [guid]::NewGuid().ToString("N") + ".replace-backup")
    $replaceCompleted = $false
    try {
        [System.IO.File]::WriteAllText($tempPath, $header + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $fullPath) {
            [System.IO.File]::Replace($tempPath, $fullPath, $backupPath)
            $replaceCompleted = $true
        } else {
            [System.IO.File]::Move($tempPath, $fullPath)
        }
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
        }
        if ($replaceCompleted -and (Test-Path -LiteralPath $backupPath)) {
            Remove-Item -LiteralPath $backupPath -Force
        }
    }
}
