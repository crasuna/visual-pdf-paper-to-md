[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPdf,

    [string]$OutputDir,

    [string]$Prefix = "image",

    [switch]$ListOnly,

    [switch]$Clean,

    [switch]$AllowNone
)

$ErrorActionPreference = "Stop"

$inputItem = Get-Item -LiteralPath $InputPdf
$pdfimages = (Get-Command pdfimages -ErrorAction Stop).Source

if ($ListOnly) {
    & $pdfimages -list $inputItem.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "pdfimages -list failed with exit code $LASTEXITCODE."
    }
    return
}

if (-not $OutputDir) {
    throw "OutputDir is required unless -ListOnly is used."
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$outputPath = (Resolve-Path -LiteralPath $OutputDir).Path

if ($Clean) {
    Get-ChildItem -LiteralPath $outputPath -Filter "$Prefix-*" -File -ErrorAction SilentlyContinue | Remove-Item -Force
}

$before = @{}
Get-ChildItem -LiteralPath $outputPath -File -ErrorAction SilentlyContinue | ForEach-Object {
    $before[$_.FullName] = $true
}

$outputPrefix = Join-Path $outputPath $Prefix
& $pdfimages -all $inputItem.FullName $outputPrefix
if ($LASTEXITCODE -ne 0) {
    throw "pdfimages export failed with exit code $LASTEXITCODE."
}

$magick = (Get-Command magick -ErrorAction SilentlyContinue).Source
$created = Get-ChildItem -LiteralPath $outputPath -File | Where-Object {
    $_.Name -like "$Prefix-*" -and (-not $before.ContainsKey($_.FullName) -or $Clean)
} | Sort-Object `
    @{ Expression = { if ($_.BaseName -match '(\d+)$') { [int]$Matches[1] } else { [int]::MaxValue } } }, `
    Name

if ($created.Count -eq 0) {
    if ($AllowNone) {
        [pscustomobject]@{
            FullName = $null
            Width = $null
            Height = $null
            Bytes = 0
            Extension = $null
            Status = "NoImagesExported"
        }
        return
    }
    throw "No image files were exported to $outputPath."
}

foreach ($item in $created) {
    $width = $null
    $height = $null
    $status = "OK"

    if ($magick) {
        $dimensions = & $magick identify -format "%w %h" $item.FullName 2>$null
        if ($LASTEXITCODE -eq 0 -and $dimensions) {
            $parts = $dimensions -split '\s+'
            $width = [int]$parts[0]
            $height = [int]$parts[1]
        } else {
            $status = "UnreadableDimensions"
        }
    } else {
        $status = "NoMagick"
    }

    [pscustomobject]@{
        FullName = $item.FullName
        Width = $width
        Height = $height
        Bytes = $item.Length
        Extension = $item.Extension
        Status = $status
    }
}
