[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MarkdownPath,

    [string]$AssetManifestPath
)

$ErrorActionPreference = "Stop"

function Test-DoneValue {
    param([string]$Value)

    if (-not $Value) {
        return $false
    }

    $normalized = $Value.Trim().ToLowerInvariant()
    return @("1", "true", "yes", "y", "x", "[x]", "done", "ok", "reviewed", "checked") -contains $normalized
}

function Split-MarkdownTableRow {
    param([string]$Line)

    $trimmed = $Line.Trim()
    if (-not $trimmed.StartsWith("|") -or -not $trimmed.EndsWith("|")) {
        return $null
    }

    $inner = $trimmed.Trim([char[]]@("|"))
    return @($inner -split "\|" | ForEach-Object { $_.Trim() })
}

function Get-AssetManifestRows {
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

function Add-PathKeys {
    param(
        [System.Collections.Generic.HashSet[string]]$Set,
        [string]$Value,
        [string]$ManifestDir,
        [string]$MarkdownDir
    )

    if (-not $Value) {
        return
    }

    $clean = $Value.Trim().Trim([char[]]@("<", ">", '"', "'"))
    if (-not $clean) {
        return
    }

    $parts = $clean -split '\s*;\s*'
    foreach ($part in $parts) {
        $candidate = $part.Trim().Trim([char[]]@("<", ">", '"', "'"))
        if (-not $candidate) {
            continue
        }

        [void]$Set.Add(($candidate -replace '/', '\'))
        $expanded = [Environment]::ExpandEnvironmentVariables($candidate)
        if ([System.IO.Path]::IsPathRooted($expanded)) {
            [void]$Set.Add([System.IO.Path]::GetFullPath($expanded))
        } else {
            [void]$Set.Add([System.IO.Path]::GetFullPath((Join-Path $ManifestDir $expanded)))
            [void]$Set.Add([System.IO.Path]::GetFullPath((Join-Path $MarkdownDir $expanded)))
        }
    }
}

$markdownItem = Get-Item -LiteralPath $MarkdownPath
$markdownDir = Split-Path -Parent $markdownItem.FullName
$text = Get-Content -LiteralPath $markdownItem.FullName -Raw
$lines = $text -split "`r?`n"
$errors = New-Object System.Collections.Generic.List[string]

$unresolvedTerms = @("TO" + "DO", "FIX" + "ME", "TBD", "UNCERTAIN")
$termPattern = ($unresolvedTerms | ForEach-Object { [regex]::Escape($_) }) -join '|'
$unresolvedPattern = "(?im)\b($termPattern)\b|\[uncertain\]|\?\?\?"
$unresolvedMatches = [regex]::Matches($text, $unresolvedPattern)
if ($unresolvedMatches.Count -gt 0) {
    $samples = $unresolvedMatches | Select-Object -First 5 | ForEach-Object { $_.Value }
    $errors.Add("Markdown contains unresolved markers: $($samples -join ', ')")
}

if ($text -match '(?im)^\s*#{1,6}\s+(references|bibliography)\b') {
    $errors.Add("Markdown contains a References/Bibliography heading.")
}

$bibliographyLike = @()
foreach ($line in $lines) {
    if ($line -match '^\s*\d+\.\s+.{20,}(19|20)\d{2}\b' -or
        $line -match '^\s*\d+\.\s+.{20,}\b(J|Journal|Radiology|Magn Reson|Science|Proceedings|Press)\b') {
        $bibliographyLike += $line
    }
}
if ($bibliographyLike.Count -ge 3) {
    $errors.Add("Markdown appears to contain numbered bibliography entries.")
}

$imageMatches = [regex]::Matches($text, '!\[[^\]]*\]\(([^)]+)\)')
$missingImages = New-Object System.Collections.Generic.List[string]
$imageReports = New-Object System.Collections.Generic.List[object]
$localImageReports = New-Object System.Collections.Generic.List[object]
$magick = (Get-Command magick -ErrorAction SilentlyContinue).Source
foreach ($match in $imageMatches) {
    $target = $match.Groups[1].Value.Trim()
    $target = $target.Trim([char[]]@('<', '>', '"', "'"))
    if ($target -match '^(https?|data):') {
        $imageReports.Add([pscustomobject]@{
            Target = $target
            Width = $null
            Height = $null
            Bytes = $null
            Status = "RemoteOrData"
        })
        continue
    }
    if ([System.IO.Path]::IsPathRooted($target)) {
        $assetPath = $target
    } else {
        $assetPath = Join-Path $markdownDir $target
    }
    $assetFullName = [System.IO.Path]::GetFullPath($assetPath)
    $localImageReports.Add([pscustomobject]@{
        Target = $target
        FullName = $assetFullName
    })

    if (-not (Test-Path -LiteralPath $assetPath)) {
        $missingImages.Add($target)
        $imageReports.Add([pscustomobject]@{
            Target = $target
            Width = $null
            Height = $null
            Bytes = $null
            Status = "Missing"
        })
        continue
    }

    $assetItem = Get-Item -LiteralPath $assetPath
    if ($assetItem.Length -eq 0) {
        $errors.Add("Image asset is 0 bytes: $target")
    }

    $width = $null
    $height = $null
    $status = "OK"
    if ($magick) {
        $dimensions = & $magick identify -format "%w %h" $assetItem.FullName 2>$null
        if ($LASTEXITCODE -eq 0 -and $dimensions) {
            $parts = $dimensions -split '\s+'
            $width = [int]$parts[0]
            $height = [int]$parts[1]
            if ($width -lt 200 -or $height -lt 120) {
                $status = "TooSmall"
                $errors.Add("Image asset is suspiciously small: $target (${width}x${height}).")
            }
        } else {
            $status = "UnreadableDimensions"
            $errors.Add("Unable to read image dimensions: $target")
        }
    } else {
        $status = "NoMagick"
    }

    $imageReports.Add([pscustomobject]@{
        Target = $target
        Width = $width
        Height = $height
        Bytes = $assetItem.Length
        Status = $status
    })
}
if ($missingImages.Count -gt 0) {
    $errors.Add("Missing local image assets: $($missingImages -join ', ')")
}

$formulaReports = New-Object System.Collections.Generic.List[object]
foreach ($match in [regex]::Matches($text, '\\tag\{([^}]+)\}')) {
    $formulaReports.Add([pscustomobject]@{
        Kind = "EquationTag"
        Value = $match.Groups[1].Value
        Index = $match.Index
    })
}
foreach ($match in [regex]::Matches($text, 'Eq\.?\s*\[[^\]]+\]')) {
    $formulaReports.Add([pscustomobject]@{
        Kind = "EquationReference"
        Value = $match.Value
        Index = $match.Index
    })
}
foreach ($match in [regex]::Matches($text, '\[(A\d+)\]')) {
    $formulaReports.Add([pscustomobject]@{
        Kind = "AppendixEquationReference"
        Value = $match.Groups[1].Value
        Index = $match.Index
    })
}

$manifestRows = @()
if ($AssetManifestPath) {
    $manifestItem = Get-Item -LiteralPath $AssetManifestPath
    $manifestDir = Split-Path -Parent $manifestItem.FullName
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
    $manifestRows = @(Get-AssetManifestRows -Path $manifestItem.FullName -RequiredFields $requiredFields)
    if ($manifestRows.Count -eq 0) {
        $errors.Add("Asset manifest contains no asset decision rows.")
    }

    $chosenKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $allowedMethods = @("direct-export", "crop-fallback")
    foreach ($row in $manifestRows) {
        foreach ($field in $requiredFields) {
            if (-not ($row.PSObject.Properties.Name -contains $field)) {
                $errors.Add("Asset manifest row is missing required field: $field")
            }
        }

        $figure = [string]$row.Figure
        $method = ([string]$row.Method).Trim()
        $chosenAsset = ([string]$row.ChosenAsset).Trim()
        $visualMatch = ([string]$row.VisualMatch).Trim()
        $fallbackReason = ([string]$row.FallbackReason).Trim()
        $done = ([string]$row.Done).Trim()

        if (-not $figure.Trim()) {
            $errors.Add("Asset manifest row has an empty Figure value.")
        }
        if ($allowedMethods -notcontains $method) {
            $errors.Add("Asset manifest row for '$figure' has invalid Method '$method'. Use direct-export or crop-fallback.")
        }
        if (-not $chosenAsset) {
            $errors.Add("Asset manifest row for '$figure' has an empty ChosenAsset.")
        }
        if (-not $visualMatch) {
            $errors.Add("Asset manifest row for '$figure' has an empty VisualMatch.")
        }
        if ($method -eq "crop-fallback" -and -not $fallbackReason) {
            $errors.Add("Asset manifest row for '$figure' uses crop-fallback without FallbackReason.")
        }
        if (-not (Test-DoneValue -Value $done)) {
            $errors.Add("Asset manifest row for '$figure' is not marked Done.")
        }

        Add-PathKeys -Set $chosenKeys -Value $chosenAsset -ManifestDir $manifestDir -MarkdownDir $markdownDir
    }

    foreach ($image in $localImageReports) {
        $targetKey = $image.Target -replace '/', '\'
        $fullKey = [System.IO.Path]::GetFullPath($image.FullName)
        if (-not $chosenKeys.Contains($targetKey) -and -not $chosenKeys.Contains($fullKey)) {
            $errors.Add("Markdown image link is not recorded as a ChosenAsset in the asset manifest: $($image.Target)")
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Error ($errors -join [Environment]::NewLine)
    exit 1
}

[pscustomobject]@{
    Markdown = $markdownItem.FullName
    AssetManifest = $(if ($AssetManifestPath) { (Get-Item -LiteralPath $AssetManifestPath).FullName } else { $null })
    ImageLinks = $imageMatches.Count
    ManifestRows = $manifestRows.Count
    FormulaMentions = $formulaReports.Count
    Lines = $lines.Count
    Status = "OK"
}

if ($imageReports.Count -gt 0) {
    $imageReports
}

if ($formulaReports.Count -gt 0) {
    $formulaReports | Sort-Object Index
}
