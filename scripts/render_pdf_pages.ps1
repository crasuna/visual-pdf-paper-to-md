[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPdf,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [int]$Dpi = 300,

    [int]$FirstPage = 0,

    [int]$LastPage = 0,

    [string]$Prefix = "page",

    [switch]$Clean
)

$ErrorActionPreference = "Stop"

if ($Dpi -lt 72 -or $Dpi -gt 600) {
    throw "Dpi must be between 72 and 600."
}
if ($FirstPage -lt 0 -or $LastPage -lt 0 -or ($FirstPage -gt 0 -and $LastPage -gt 0 -and $LastPage -lt $FirstPage)) {
    throw "FirstPage and LastPage must describe a valid positive page range."
}
if (-not $Prefix -or [System.IO.Path]::GetFileName($Prefix) -ne $Prefix -or $Prefix.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
    throw "Prefix must be a non-empty file-name component."
}

$inputItem = Get-Item -LiteralPath $InputPdf
if ($inputItem.Extension -ne ".pdf") {
    throw "InputPdf must be a PDF file."
}
$pdftoppmCommand = Get-Command pdftoppm.exe -ErrorAction SilentlyContinue
if (-not $pdftoppmCommand) {
    $pdftoppmCommand = Get-Command pdftoppm -ErrorAction Stop
}
$pdfinfoCommand = Get-Command pdfinfo.exe -ErrorAction SilentlyContinue
if (-not $pdfinfoCommand) {
    $pdfinfoCommand = Get-Command pdfinfo -ErrorAction Stop
}
$magick = (Get-Command magick -ErrorAction Stop).Source
$pdftoppmVersionOutput = @(& $pdftoppmCommand.Source -v 2>&1)
if ($LASTEXITCODE -ne 0 -or $pdftoppmVersionOutput.Count -eq 0) {
    throw "Unable to determine pdftoppm version."
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$outputPath = (Resolve-Path -LiteralPath $OutputDir).Path
$stagingPath = Join-Path $outputPath (".render-" + [guid]::NewGuid().ToString("N"))
$resolvedStagingPath = $null
$tempPdf = $null
$promotedTargets = New-Object System.Collections.Generic.List[string]
$backups = New-Object System.Collections.Generic.List[object]
$results = New-Object System.Collections.Generic.List[object]
$toolMessages = @()

try {
    New-Item -ItemType Directory -Path $stagingPath | Out-Null
    $resolvedStagingPath = (Resolve-Path -LiteralPath $stagingPath).Path
    if ([System.IO.Path]::GetDirectoryName($resolvedStagingPath) -ne $outputPath) {
        throw "Unsafe renderer staging path: $resolvedStagingPath"
    }

    $renderInput = $inputItem.FullName
    if ($renderInput -match '[^\x00-\x7F]') {
        $tempPdf = Join-Path ([System.IO.Path]::GetTempPath()) ("visual-pdf-render-" + [guid]::NewGuid().ToString("N") + ".pdf")
        Copy-Item -LiteralPath $inputItem.FullName -Destination $tempPdf
        $renderInput = $tempPdf
    }

    $pdfinfoOutput = @(& $pdfinfoCommand.Source $renderInput 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "pdfinfo failed while validating the requested render range."
    }
    $sourcePageCount = 0
    foreach ($line in $pdfinfoOutput) {
        if ([string]$line -match '^Pages:\s+(\d+)') {
            $sourcePageCount = [int]$Matches[1]
            break
        }
    }
    if ($sourcePageCount -lt 1) {
        throw "Unable to determine the source PDF page count before rendering."
    }
    $requestedFirstPage = $(if ($FirstPage -gt 0) { $FirstPage } else { 1 })
    $requestedLastPage = $(if ($LastPage -gt 0) { $LastPage } else { $sourcePageCount })
    if ($requestedFirstPage -gt $sourcePageCount -or $requestedLastPage -gt $sourcePageCount) {
        throw "Requested render range $requestedFirstPage-$requestedLastPage exceeds source page count $sourcePageCount."
    }

    $stagingPrefix = Join-Path $resolvedStagingPath $Prefix
    $arguments = @("-r", $Dpi, "-png")
    if ($FirstPage -gt 0) {
        $arguments += @("-f", $FirstPage)
    }
    if ($LastPage -gt 0) {
        $arguments += @("-l", $LastPage)
    }
    $arguments += @($renderInput, $stagingPrefix)

    $toolMessages = @(& $pdftoppmCommand.Source @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "pdftoppm failed with exit code $LASTEXITCODE."
    }

    $rawPages = @(
        Get-ChildItem -LiteralPath $resolvedStagingPath -Filter "$Prefix-*.png" -File |
            Where-Object { $_.BaseName -match '(\d+)$' } |
            Sort-Object { [int]([regex]::Match($_.BaseName, '(\d+)$').Groups[1].Value) }
    )
    if ($rawPages.Count -eq 0) {
        throw "No rendered PNG pages were created in the staging directory."
    }

    $preparedPages = New-Object System.Collections.Generic.List[object]
    foreach ($item in $rawPages) {
        $pageNumber = [int]([regex]::Match($item.BaseName, '(\d+)$').Groups[1].Value)
        $canonicalName = ("{0}-{1:D4}-{2}dpi.png" -f $Prefix, $pageNumber, $Dpi)
        $stagedCanonicalPath = Join-Path $resolvedStagingPath $canonicalName
        if ($item.FullName -ne $stagedCanonicalPath) {
            Move-Item -LiteralPath $item.FullName -Destination $stagedCanonicalPath
        }
        $stagedItem = Get-Item -LiteralPath $stagedCanonicalPath
        $dimensions = & $magick identify -format "%w %h" $stagedItem.FullName 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $dimensions) {
            throw "Unable to inspect rendered page dimensions: $($stagedItem.FullName)"
        }
        $dimensionParts = $dimensions -split '\s+'
        $preparedPages.Add([pscustomobject][ordered]@{
            PageNumber = $pageNumber
            StagedPath = $stagedItem.FullName
            FinalPath = Join-Path $outputPath $canonicalName
            Sha256 = (Get-FileHash -LiteralPath $stagedItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            Bytes = $stagedItem.Length
            Width = [int]$dimensionParts[0]
            Height = [int]$dimensionParts[1]
        })
    }

    $actualPageNumbers = @($preparedPages | ForEach-Object { [int]$_.PageNumber })
    $expectedPageNumbers = @($requestedFirstPage..$requestedLastPage)
    $pageSetDifference = @(Compare-Object -ReferenceObject $expectedPageNumbers -DifferenceObject $actualPageNumbers)
    if ($actualPageNumbers.Count -ne $expectedPageNumbers.Count -or $pageSetDifference.Count -gt 0) {
        throw "Rendered page set does not match the complete requested range $requestedFirstPage-$requestedLastPage."
    }

    if (-not $Clean) {
        $conflict = $preparedPages | Where-Object { Test-Path -LiteralPath $_.FinalPath } | Select-Object -First 1
        if ($conflict) {
            throw "Refusing to replace an existing rendered page: $($conflict.FinalPath)"
        }
    }

    $backupPath = Join-Path $resolvedStagingPath "backup"
    try {
        if ($Clean) {
            New-Item -ItemType Directory -Path $backupPath | Out-Null
            foreach ($prepared in $preparedPages) {
                if (Test-Path -LiteralPath $prepared.FinalPath) {
                    $backupFile = Join-Path $backupPath ([System.IO.Path]::GetFileName($prepared.FinalPath))
                    Move-Item -LiteralPath $prepared.FinalPath -Destination $backupFile
                    $backups.Add([pscustomobject]@{ FinalPath = $prepared.FinalPath; BackupPath = $backupFile })
                }
            }
        }

        foreach ($prepared in $preparedPages) {
            Move-Item -LiteralPath $prepared.StagedPath -Destination $prepared.FinalPath
            $promotedTargets.Add($prepared.FinalPath)
        }

        foreach ($prepared in $preparedPages) {
            $results.Add([pscustomobject][ordered]@{
                SchemaVersion = "2"
                AssetId = ("page-{0:D4}-{1}dpi" -f $prepared.PageNumber, $Dpi)
                AssetType = "rendered-page"
                PageNumber = $prepared.PageNumber
                FullName = $prepared.FinalPath
                Sha256 = $prepared.Sha256
                Bytes = $prepared.Bytes
                Width = $prepared.Width
                Height = $prepared.Height
                Dpi = $Dpi
                SourcePageCount = $sourcePageCount
                SourceMethod = "render"
                ToolPath = $pdftoppmCommand.Source
                ToolVersion = ([string]$pdftoppmVersionOutput[0]).Trim()
                ToolMessages = ($toolMessages -join [Environment]::NewLine)
                Status = "OK"
            })
        }
    } catch {
        foreach ($promotedPath in $promotedTargets) {
            if (Test-Path -LiteralPath $promotedPath) {
                Remove-Item -LiteralPath $promotedPath -Force
            }
        }
        foreach ($backup in $backups) {
            if (Test-Path -LiteralPath $backup.BackupPath) {
                Move-Item -LiteralPath $backup.BackupPath -Destination $backup.FinalPath
            }
        }
        throw
    }
} finally {
    if ($tempPdf -and (Test-Path -LiteralPath $tempPdf)) {
        Remove-Item -LiteralPath $tempPdf -Force
    }
    if (Test-Path -LiteralPath $stagingPath) {
        $currentStagingPath = [System.IO.Path]::GetFullPath($stagingPath)
        $currentStagingParent = [System.IO.Path]::GetDirectoryName($currentStagingPath)
        if ($currentStagingParent -ne $outputPath) {
            throw "Refusing to clean an unsafe renderer staging path: $currentStagingPath"
        }
        Remove-Item -LiteralPath $currentStagingPath -Recurse -Force
    }
}

$results.ToArray()
