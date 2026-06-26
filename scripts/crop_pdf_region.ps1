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

    [string]$Figure,

    [switch]$RequireManifestDecision,

    [switch]$OpenAfterCrop
)

$ErrorActionPreference = "Stop"

function Split-MarkdownTableRow {
    param([string]$Line)

    $trimmed = $Line.Trim()
    if (-not $trimmed.StartsWith("|") -or -not $trimmed.EndsWith("|")) {
        return $null
    }

    $inner = $trimmed.Trim([char[]]@("|"))
    return @($inner -split "\|" | ForEach-Object { $_.Trim() })
}

function Get-ManifestRows {
    param(
        [string]$Path,
        [string[]]$RequiredFields
    )

    $manifestItem = Get-Item -LiteralPath $Path
    $extension = $manifestItem.Extension.ToLowerInvariant()

    if ($extension -eq ".csv") {
        return @(Import-Csv -LiteralPath $manifestItem.FullName)
    }

    if ($extension -ne ".md" -and $extension -ne ".markdown") {
        throw "Asset manifest must be .csv or .md: $Path"
    }

    $manifestLines = Get-Content -LiteralPath $manifestItem.FullName
    $headerIndex = -1
    $headers = $null
    for ($i = 0; $i -lt $manifestLines.Count; $i++) {
        $cells = Split-MarkdownTableRow -Line $manifestLines[$i]
        if (-not $cells) {
            continue
        }

        $missing = @($RequiredFields | Where-Object { $_ -notin $cells })
        if ($missing.Count -eq 0) {
            $headerIndex = $i
            $headers = $cells
            break
        }
    }

    if ($headerIndex -lt 0) {
        throw "Unable to find asset manifest table header."
    }

    $rows = New-Object System.Collections.Generic.List[object]
    for ($i = $headerIndex + 1; $i -lt $manifestLines.Count; $i++) {
        $cells = Split-MarkdownTableRow -Line $manifestLines[$i]
        if (-not $cells) {
            continue
        }
        $isSeparator = $true
        foreach ($cell in $cells) {
            if ($cell -notmatch '^:?-{3,}:?$') {
                $isSeparator = $false
                break
            }
        }
        if ($isSeparator) {
            continue
        }

        $row = [ordered]@{}
        for ($j = 0; $j -lt $headers.Count; $j++) {
            $value = ""
            if ($j -lt $cells.Count) {
                $value = $cells[$j]
            }
            $row[$headers[$j]] = $value
        }
        $rows.Add([pscustomobject]$row)
    }

    return $rows.ToArray()
}

if ($Geometry -notmatch '^\d+x\d+\+\d+\+\d+$') {
    throw "Geometry must use ImageMagick crop format WIDTHxHEIGHT+X+Y, for example 1200x700+300+450."
}

if ($MinWidth -lt 1 -or $MinHeight -lt 1) {
    throw "MinWidth and MinHeight must be positive integers."
}

if ($RequireManifestDecision -or $AssetManifestPath -or $Figure) {
    if (-not $AssetManifestPath -or -not $Figure) {
        throw "AssetManifestPath and Figure are required when enforcing a crop fallback manifest decision."
    }

    $requiredFields = @(
        "Figure",
        "RenderedPage",
        "ExportCandidates",
        "ChosenAsset",
        "Method",
        "VisualMatch",
        "FallbackReason",
        "ReviewerNotes",
        "Done"
    )
    $manifestRows = @(Get-ManifestRows -Path $AssetManifestPath -RequiredFields $requiredFields)
    $matchingRows = @($manifestRows | Where-Object { ([string]$_.Figure).Trim() -eq $Figure })
    if ($matchingRows.Count -eq 0) {
        throw "No asset manifest row found for figure: $Figure"
    }
    if ($matchingRows.Count -gt 1) {
        throw "Multiple asset manifest rows found for figure: $Figure"
    }

    $row = $matchingRows[0]
    $method = ([string]$row.Method).Trim()
    $fallbackReason = ([string]$row.FallbackReason).Trim()
    if ($method -ne "crop-fallback") {
        throw "Figure '$Figure' is not recorded as crop-fallback in the asset manifest."
    }
    if (-not $fallbackReason) {
        throw "Figure '$Figure' is crop-fallback but has no FallbackReason in the asset manifest."
    }
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
