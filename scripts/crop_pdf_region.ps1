[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputImage,

    [Parameter(Mandatory = $true)]
    [string]$OutputImage,

    [Parameter(Mandatory = $true)]
    [string]$Geometry,

    [int]$MinWidth = 1,

    [int]$MinHeight = 1,

    [switch]$OpenAfterCrop
)

$ErrorActionPreference = "Stop"

if ($Geometry -notmatch '^\d+x\d+\+\d+\+\d+$') {
    throw "Geometry must use ImageMagick crop format WIDTHxHEIGHT+X+Y, for example 1200x700+300+450."
}

if ($MinWidth -lt 1 -or $MinHeight -lt 1) {
    throw "MinWidth and MinHeight must be positive integers."
}

$inputItem = Get-Item -LiteralPath $InputImage
$outputParent = Split-Path -Parent $OutputImage
if ($outputParent) {
    New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
}

$magick = (Get-Command magick -ErrorAction Stop).Source
& $magick $inputItem.FullName -crop $Geometry +repage $OutputImage
if ($LASTEXITCODE -ne 0) {
    throw "ImageMagick crop failed with exit code $LASTEXITCODE."
}

$outputItem = Get-Item -LiteralPath $OutputImage
$dimensions = & $magick identify -format "%w %h" $outputItem.FullName
if ($LASTEXITCODE -ne 0 -or -not $dimensions) {
    throw "Unable to read output image dimensions."
}

$parts = $dimensions -split '\s+'
$width = [int]$parts[0]
$height = [int]$parts[1]

if ($width -lt $MinWidth -or $height -lt $MinHeight) {
    throw "Cropped image is smaller than requested minimum: ${width}x${height}, minimum ${MinWidth}x${MinHeight}."
}

if ($OpenAfterCrop) {
    Start-Process -FilePath $outputItem.FullName
}

[pscustomobject]@{
    FullName = $outputItem.FullName
    Width = $width
    Height = $height
    Bytes = $outputItem.Length
    Geometry = $Geometry
}
