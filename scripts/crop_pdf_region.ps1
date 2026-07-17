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

    [string]$AssetManifestPath,

    [string]$AssetId,

    [switch]$RequireManifestDecision,

    [switch]$OpenAfterCrop
)

$ErrorActionPreference = "Stop"

if ($Geometry -notmatch '^\d+x\d+\+\d+\+\d+$') {
    throw "Geometry must use WIDTHxHEIGHT+X+Y, for example 1200x700+300+450."
}
if ($MinWidth -lt 1 -or $MinHeight -lt 1) {
    throw "MinWidth and MinHeight must be positive integers."
}

$manifestRow = $null
if ($RequireManifestDecision -or $AssetManifestPath -or $AssetId) {
    if (-not $AssetManifestPath -or -not $AssetId) {
        throw "AssetManifestPath and AssetId are required when enforcing a v2 crop decision."
    }
    $manifestItem = Get-Item -LiteralPath $AssetManifestPath
    if ($manifestItem.Extension -ne ".csv") {
        throw "v2 asset manifests must be CSV files."
    }
    $rows = @(Import-Csv -LiteralPath $manifestItem.FullName)
    $matches = @($rows | Where-Object { $_.SchemaVersion -eq "2" -and $_.AssetId -eq $AssetId })
    if ($matches.Count -ne 1) {
        throw "Expected exactly one v2 asset manifest row for AssetId '$AssetId'."
    }
    $manifestRow = $matches[0]
    if ($manifestRow.AssetType -notin @("figure", "table", "formula")) {
        throw "Asset '$AssetId' has non-croppable AssetType '$($manifestRow.AssetType)'."
    }
    if ($manifestRow.SourceMethod -ne "page-crop" -or -not $manifestRow.FallbackReason) {
        throw "Asset '$AssetId' must record SourceMethod=page-crop and a FallbackReason before cropping."
    }
    $manifestDir = Split-Path -Parent $manifestItem.FullName
    $auditDir = Split-Path -Parent $manifestDir
    $packageRoot = Split-Path -Parent $auditDir
    if ([System.IO.Path]::IsPathRooted($manifestRow.Path)) {
        throw "Asset manifest paths must be relative."
    }
    $recordedOutput = [System.IO.Path]::GetFullPath((Join-Path $packageRoot $manifestRow.Path))
    if ($recordedOutput -ne [System.IO.Path]::GetFullPath($OutputImage)) {
        throw "OutputImage does not match the path recorded for AssetId '$AssetId'."
    }
}

$inputItem = Get-Item -LiteralPath $InputImage
$outputParent = Split-Path -Parent $OutputImage
if ($outputParent -and -not (Test-Path -LiteralPath $outputParent)) {
    New-Item -ItemType Directory -Path $outputParent | Out-Null
}
if (Test-Path -LiteralPath $OutputImage) {
    throw "Refusing to overwrite an existing crop: $OutputImage"
}

$magick = (Get-Command magick -ErrorAction Stop).Source
$magickVersionOutput = @(& $magick -version 2>&1)
if ($LASTEXITCODE -ne 0 -or $magickVersionOutput.Count -eq 0) {
    throw "Unable to determine ImageMagick version."
}
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

[pscustomobject][ordered]@{
    SchemaVersion = "2"
    AssetId = $(if ($manifestRow) { $manifestRow.AssetId } else { "" })
    AssetType = $(if ($manifestRow) { $manifestRow.AssetType } else { "" })
    FullName = $outputItem.FullName
    Sha256 = (Get-FileHash -LiteralPath $outputItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    Width = $width
    Height = $height
    Bytes = $outputItem.Length
    Geometry = $Geometry
    ToolPath = $magick
    ToolVersion = ([string]$magickVersionOutput[0]).Trim()
    Status = "OK"
}
