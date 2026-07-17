[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPdf,

    [string]$OutputDir,

    [string]$Prefix = "candidate",

    [switch]$ListOnly,

    [switch]$Clean,

    [switch]$AllowNone
)

$ErrorActionPreference = "Stop"

$inputItem = Get-Item -LiteralPath $InputPdf
if ($inputItem.PSIsContainer -or $inputItem.Extension -ne ".pdf") {
    throw "InputPdf must be a readable .pdf file: $InputPdf"
}
if ($Prefix -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw "Prefix may contain only letters, digits, dots, underscores, and hyphens."
}

$pdfimagesCommand = Get-Command pdfimages.exe -ErrorAction SilentlyContinue
if (-not $pdfimagesCommand) {
    $pdfimagesCommand = Get-Command pdfimages -ErrorAction Stop
}
$versionOutput = @(& $pdfimagesCommand.Source -v 2>&1)
if ($LASTEXITCODE -ne 0 -or $versionOutput.Count -eq 0) {
    throw "Unable to determine pdfimages version."
}

$pdfInput = $inputItem.FullName
$tempPdf = $null
if ($pdfInput -match '[^\x00-\x7F]') {
    $tempPdf = Join-Path ([System.IO.Path]::GetTempPath()) ("visual-pdf-images-" + [guid]::NewGuid().ToString("N") + ".pdf")
    Copy-Item -LiteralPath $inputItem.FullName -Destination $tempPdf
    $pdfInput = $tempPdf
}

try {
    if ($ListOnly) {
        $toolMessages = @(& $pdfimagesCommand.Source -list $pdfInput 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "pdfimages -list failed with exit code $LASTEXITCODE."
        }
        [pscustomobject][ordered]@{
            SchemaVersion = "2"
            Status = "Listed"
            SourcePdf = $inputItem.FullName
            ToolPath = $pdfimagesCommand.Source
            ToolVersion = ([string]$versionOutput[0]).Trim()
            ToolMessages = ($toolMessages -join [Environment]::NewLine)
        }
        return
    }

    if (-not $OutputDir) {
        throw "OutputDir is required unless -ListOnly is used."
    }

    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $outputPath = (Resolve-Path -LiteralPath $OutputDir).Path
    if ($Clean) {
        Get-ChildItem -LiteralPath $outputPath -Filter "$Prefix-*" -File -ErrorAction SilentlyContinue |
            Remove-Item -Force
    }

    $before = @{}
    Get-ChildItem -LiteralPath $outputPath -File -ErrorAction SilentlyContinue | ForEach-Object {
        $before[$_.FullName] = $true
    }

    $outputPrefix = Join-Path $outputPath $Prefix
    $toolMessages = @(& $pdfimagesCommand.Source -all $pdfInput $outputPrefix 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "pdfimages export failed with exit code $LASTEXITCODE."
    }

    $created = @(Get-ChildItem -LiteralPath $outputPath -File | Where-Object {
        $_.Name -like "$Prefix-*" -and (-not $before.ContainsKey($_.FullName) -or $Clean)
    } | Sort-Object `
        @{ Expression = { if ($_.BaseName -match '(\d+)$') { [int]$Matches[1] } else { [int]::MaxValue } } }, `
        Name)

    if ($created.Count -eq 0) {
        if (-not $AllowNone) {
            throw "No image files were exported to $outputPath."
        }
        [pscustomobject][ordered]@{
            SchemaVersion = "2"
            CandidateId = ""
            FullName = ""
            Sha256 = ""
            Bytes = 0
            Width = 0
            Height = 0
            Extension = ""
            ToolPath = $pdfimagesCommand.Source
            ToolVersion = ([string]$versionOutput[0]).Trim()
            ToolMessages = ($toolMessages -join [Environment]::NewLine)
            Status = "NoImagesExported"
        }
        return
    }

    $magick = (Get-Command magick -ErrorAction Stop).Source
    for ($index = 0; $index -lt $created.Count; $index++) {
        $item = $created[$index]
        $dimensions = & $magick identify -format "%w %h" $item.FullName 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $dimensions) {
            throw "Unable to inspect exported candidate dimensions: $($item.FullName)"
        }
        $parts = $dimensions -split '\s+'
        [pscustomobject][ordered]@{
            SchemaVersion = "2"
            CandidateId = ("candidate-{0:D4}" -f ($index + 1))
            FullName = $item.FullName
            Sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            Bytes = $item.Length
            Width = [int]$parts[0]
            Height = [int]$parts[1]
            Extension = $item.Extension.ToLowerInvariant()
            ToolPath = $pdfimagesCommand.Source
            ToolVersion = ([string]$versionOutput[0]).Trim()
            ToolMessages = ($toolMessages -join [Environment]::NewLine)
            Status = "Exported"
        }
    }
} finally {
    if ($tempPdf -and (Test-Path -LiteralPath $tempPdf)) {
        Remove-Item -LiteralPath $tempPdf -Force
    }
}
