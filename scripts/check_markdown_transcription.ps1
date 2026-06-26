[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MarkdownPath,

    [string]$AssetManifestPath,

    [switch]$RequireAssetManifest,

    [string]$ChecklistPath,

    [string]$FormulaManifestPath,

    [string]$BlockManifestPath,

    [string]$MetadataManifestPath,

    [string]$ReferenceCutoffManifestPath,

    [string]$ImageCandidateManifestPath,

    [string]$TextLayerDraftManifestPath,

    [switch]$StrictFullPaper,

    [switch]$TextLayerAssisted,

    [ValidateSet("Exclude", "Keep")]
    [string]$ReferencePolicy = "Exclude"
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

function Test-UncertaintyValue {
    param([string]$Value)

    if (-not $Value) {
        return $false
    }

    $normalized = $Value.Trim().ToLowerInvariant()
    return @("0", "false", "no", "none", "n", "resolved", "clear") -notcontains $normalized
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

function Get-ManifestRows {
    param(
        [string]$Path,
        [string[]]$RequiredFields
    )

    $manifestItem = Get-Item -LiteralPath $Path
    $extension = $manifestItem.Extension.ToLowerInvariant()

    if ($extension -eq ".csv") {
        $rows = @(Import-Csv -LiteralPath $manifestItem.FullName)
        if ($rows.Count -gt 0) {
            $headers = @($rows[0].PSObject.Properties.Name)
            $missing = @($RequiredFields | Where-Object { $_ -notin $headers })
            if ($missing.Count -gt 0) {
                throw "Manifest is missing required fields: $($missing -join ', ')"
            }
        }
        return $rows
    }

    if ($extension -ne ".md" -and $extension -ne ".markdown") {
        throw "Manifest must be .csv or .md: $Path"
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
        throw "Unable to find manifest table header with required fields: $($RequiredFields -join ', ')"
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

function Split-ListValues {
    param([string]$Value)

    if (-not $Value) {
        return @()
    }

    return @($Value -split '\s*[;,]\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Add-PathKeys {
    param(
        [System.Collections.Generic.HashSet[string]]$Set,
        [string]$Value,
        [string]$ManifestDir,
        [string]$MarkdownDir
    )

    foreach ($part in (Split-ListValues -Value $Value)) {
        $candidate = $part.Trim().Trim([char[]]@("<", ">", '"', "'"))
        if (-not $candidate) {
            continue
        }

        [void]$Set.Add(($candidate -replace '/', '\'))
        [void]$Set.Add([System.IO.Path]::GetFileName($candidate))
        $expanded = [Environment]::ExpandEnvironmentVariables($candidate)
        if ([System.IO.Path]::IsPathRooted($expanded)) {
            [void]$Set.Add([System.IO.Path]::GetFullPath($expanded))
        } else {
            [void]$Set.Add([System.IO.Path]::GetFullPath((Join-Path $ManifestDir $expanded)))
            [void]$Set.Add([System.IO.Path]::GetFullPath((Join-Path $MarkdownDir $expanded)))
        }
    }
}

function Test-PathCandidateExists {
    param(
        [string]$Value,
        [string]$ManifestDir,
        [string]$MarkdownDir
    )

    if (-not $Value) {
        return $false
    }

    $clean = $Value.Trim().Trim([char[]]@("<", ">", '"', "'"))
    if (-not $clean) {
        return $false
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($clean)
    if ([System.IO.Path]::IsPathRooted($expanded)) {
        return (Test-Path -LiteralPath $expanded)
    }

    return (
        (Test-Path -LiteralPath (Join-Path $ManifestDir $expanded)) -or
        (Test-Path -LiteralPath (Join-Path $MarkdownDir $expanded))
    )
}

function Test-AnyPathKeyInSet {
    param(
        [System.Collections.Generic.HashSet[string]]$Set,
        [string]$Value,
        [string]$ManifestDir,
        [string]$MarkdownDir
    )

    $keys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    Add-PathKeys -Set $keys -Value $Value -ManifestDir $ManifestDir -MarkdownDir $MarkdownDir
    foreach ($key in $keys) {
        if ($Set.Contains($key)) {
            return $true
        }
    }
    return $false
}

function Test-MarkdownAnchorExists {
    param(
        [string]$Anchor,
        [string]$MarkdownText
    )

    if (-not $Anchor) {
        return $false
    }

    $trimmed = $Anchor.Trim()
    if (-not $trimmed) {
        return $false
    }

    return $MarkdownText.Contains($trimmed)
}

function New-BlockLinkKey {
    param(
        [string]$Page,
        [string]$BlockType,
        [string]$MarkdownAnchor
    )

    return (([string]$Page).Trim() + "|" + ([string]$BlockType).Trim() + "|" + ([string]$MarkdownAnchor).Trim()).ToLowerInvariant()
}

$markdownItem = Get-Item -LiteralPath $MarkdownPath
$markdownDir = Split-Path -Parent $markdownItem.FullName
$text = Get-Content -LiteralPath $markdownItem.FullName -Raw
$lines = $text -split "`r?`n"
$errors = New-Object System.Collections.Generic.List[string]

$unresolvedTerms = @("TO" + "DO", "FIX" + "ME", "TB" + "D", "UNC" + "ERTAIN")
$termPattern = ($unresolvedTerms | ForEach-Object { [regex]::Escape($_) }) -join '|'
$unresolvedPattern = "(?im)\b($termPattern)\b|\[uncertain\]|\?\?\?"
$unresolvedMatches = [regex]::Matches($text, $unresolvedPattern)
if ($unresolvedMatches.Count -gt 0) {
    $samples = $unresolvedMatches | Select-Object -First 5 | ForEach-Object { $_.Value }
    $errors.Add("Markdown contains unresolved markers: $($samples -join ', ')")
}

if ($ReferencePolicy -eq "Exclude") {
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
}

$imagePattern = '!\[(?<alt>[^\]]*)\]\(\s*(?<target><[^>]+>|"[^"]+"|''[^'']+''|[^\s\)]+)(?:\s+["''][^)]*["''])?\s*\)'
$imageMatches = [regex]::Matches($text, $imagePattern)
$missingImages = New-Object System.Collections.Generic.List[string]
$imageReports = New-Object System.Collections.Generic.List[object]
$localImageReports = New-Object System.Collections.Generic.List[object]
$figureImageReports = New-Object System.Collections.Generic.List[object]
$magick = (Get-Command magick -ErrorAction SilentlyContinue).Source
foreach ($match in $imageMatches) {
    $alt = $match.Groups["alt"].Value.Trim()
    $target = $match.Groups["target"].Value.Trim()
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
    $leaf = [System.IO.Path]::GetFileName($target)
    $figureNumber = $null
    if ($alt -match '(?i)\bfig(?:ure)?\.?\s*(\d+)\b') {
        $figureNumber = $Matches[1]
    } elseif ($leaf -match '(?i)^fig(\d+)\.') {
        $figureNumber = $Matches[1]
    }

    $imageInfo = [pscustomobject]@{
        Alt = $alt
        Target = $target
        FullName = $assetFullName
        Leaf = $leaf
        FigureNumber = $figureNumber
    }
    $localImageReports.Add($imageInfo)
    if ($figureNumber -or $alt -match '(?i)\bfig(?:ure)?\b' -or $leaf -match '(?i)^fig') {
        $figureImageReports.Add($imageInfo)
    }

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

if ($StrictFullPaper) {
    foreach ($figureImage in $figureImageReports) {
        if ($figureImage.Leaf -notmatch '(?i)^fig\d+\.[a-z0-9]+$') {
            $errors.Add("StrictFullPaper requires figure asset names to use figN.ext: $($figureImage.Target)")
        }
        if ($figureImage.FigureNumber) {
            $captionPattern = "(?m)^\s*\*\*Fig\. $([regex]::Escape($figureImage.FigureNumber))\.\*\*"
            if ($text -notmatch $captionPattern) {
                $errors.Add("StrictFullPaper requires editable caption text beginning with **Fig. $($figureImage.FigureNumber).**")
            }
        }
    }
}

$formulaReports = New-Object System.Collections.Generic.List[object]
$markdownTagSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($match in [regex]::Matches($text, '\\tag\{([^}]+)\}')) {
    [void]$markdownTagSet.Add($match.Groups[1].Value)
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

$checklistRows = @()
if ($ChecklistPath) {
    $checklistRequiredFields = @(
        "Page",
        "Rendered image",
        "Reading order blocks",
        "Body paragraphs checked",
        "Formulas checked",
        "Figures/tables checked",
        "Uncertainties",
        "Done"
    )
    $checklistRows = @(Get-ManifestRows -Path $ChecklistPath -RequiredFields $checklistRequiredFields)
    if ($checklistRows.Count -eq 0) {
        $errors.Add("Checklist contains no page rows.")
    }

    foreach ($row in $checklistRows) {
        $page = ([string]$row.Page).Trim()
        if (-not $page) {
            $errors.Add("Checklist row has an empty Page value.")
            continue
        }
        if (-not (Test-DoneValue -Value ([string]$row.'Body paragraphs checked'))) {
            $errors.Add("Checklist page '$page' has unchecked Body paragraphs checked.")
        }
        if (-not (Test-DoneValue -Value ([string]$row.'Formulas checked'))) {
            $errors.Add("Checklist page '$page' has unchecked Formulas checked.")
        }
        if (-not (Test-DoneValue -Value ([string]$row.'Figures/tables checked'))) {
            $errors.Add("Checklist page '$page' has unchecked Figures/tables checked.")
        }
        if (-not (Test-DoneValue -Value ([string]$row.Done))) {
            $errors.Add("Checklist page '$page' is not marked Done.")
        }
    }
}

if ($StrictFullPaper) {
    if (-not $ChecklistPath) {
        $errors.Add("StrictFullPaper requires ChecklistPath.")
    }
    if (-not $BlockManifestPath) {
        $errors.Add("StrictFullPaper requires BlockManifestPath.")
    }
    if (-not $MetadataManifestPath) {
        $errors.Add("StrictFullPaper requires MetadataManifestPath.")
    }
    if (-not $ReferenceCutoffManifestPath) {
        $errors.Add("StrictFullPaper requires ReferenceCutoffManifestPath.")
    }
    if ($localImageReports.Count -gt 0 -and -not $AssetManifestPath) {
        $errors.Add("StrictFullPaper requires AssetManifestPath when Markdown contains local image links.")
    }
    if ($localImageReports.Count -gt 0 -and -not $ImageCandidateManifestPath) {
        $errors.Add("StrictFullPaper requires ImageCandidateManifestPath when Markdown contains local image links.")
    }
}

if ($TextLayerAssisted -and -not $TextLayerDraftManifestPath) {
    $errors.Add("TextLayerAssisted requires TextLayerDraftManifestPath.")
}

$blockRows = @()
$blockLinkKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
if ($BlockManifestPath) {
    $blockRequiredFields = @(
        "Page",
        "ColumnOrRegion",
        "BlockType",
        "Section",
        "FirstWords",
        "LastWords",
        "MarkdownAnchor",
        "Checked",
        "Notes"
    )
    $blockRows = @(Get-ManifestRows -Path $BlockManifestPath -RequiredFields $blockRequiredFields)
    if ($blockRows.Count -eq 0) {
        $errors.Add("Block coverage manifest contains no rows.")
    }
    foreach ($row in $blockRows) {
        $blockType = ([string]$row.BlockType).Trim()
        $page = ([string]$row.Page).Trim()
        if (-not $page) {
            $errors.Add("Block coverage row has an empty Page value.")
        }
        if (-not $blockType) {
            $errors.Add("Block coverage row has an empty BlockType value.")
        }
        if (-not ([string]$row.FirstWords).Trim()) {
            $errors.Add("Block coverage row for '$blockType' has empty FirstWords.")
        }
        if (-not ([string]$row.LastWords).Trim()) {
            $errors.Add("Block coverage row for '$blockType' has empty LastWords.")
        }
        $markdownAnchor = ([string]$row.MarkdownAnchor).Trim()
        if (-not $markdownAnchor) {
            $errors.Add("Block coverage row for '$blockType' has empty MarkdownAnchor.")
        } elseif (-not (Test-MarkdownAnchorExists -Anchor $markdownAnchor -MarkdownText $text)) {
            $errors.Add("Block coverage MarkdownAnchor for '$blockType' is not present in Markdown: $markdownAnchor")
        }
        if (-not (Test-DoneValue -Value ([string]$row.Checked))) {
            $errors.Add("Block coverage row for '$blockType' is not checked.")
        }
        if ($page -and $blockType -and $markdownAnchor) {
            [void]$blockLinkKeys.Add((New-BlockLinkKey -Page $page -BlockType $blockType -MarkdownAnchor $markdownAnchor))
        }
    }
}

if ($StrictFullPaper -and $blockRows.Count -gt 0) {
    $formulaBlocks = @($blockRows | Where-Object { ([string]$_.BlockType) -match '(?i)formula|equation' })
    if (($formulaBlocks.Count -gt 0 -or $markdownTagSet.Count -gt 0) -and -not $FormulaManifestPath) {
        $errors.Add("StrictFullPaper requires FormulaManifestPath when formulas are present in the block manifest or Markdown.")
    }
}

$metadataRows = @()
if ($MetadataManifestPath) {
    $metadataRequiredFields = @(
        "Field",
        "SourcePage",
        "VisualValue",
        "MarkdownValue",
        "Checked",
        "Notes"
    )
    $metadataRows = @(Get-ManifestRows -Path $MetadataManifestPath -RequiredFields $metadataRequiredFields)
    $expectedMetadata = @("Title", "Authors", "Journal", "Year", "VolumeIssuePages", "DOI")
    $metadataFields = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $metadataRows) {
        $field = ([string]$row.Field).Trim()
        if ($field) {
            [void]$metadataFields.Add($field)
        }
        if (-not $field) {
            $errors.Add("Metadata manifest row has an empty Field value.")
        }
        if (-not ([string]$row.SourcePage).Trim()) {
            $errors.Add("Metadata manifest row for '$field' has empty SourcePage.")
        }
        if (-not ([string]$row.VisualValue).Trim()) {
            $errors.Add("Metadata manifest row for '$field' has empty VisualValue.")
        }
        if (-not ([string]$row.MarkdownValue).Trim()) {
            $errors.Add("Metadata manifest row for '$field' has empty MarkdownValue.")
        }
        if (-not (Test-DoneValue -Value ([string]$row.Checked))) {
            $errors.Add("Metadata manifest row for '$field' is not checked.")
        }
    }
    foreach ($field in $expectedMetadata) {
        if (-not $metadataFields.Contains($field)) {
            $errors.Add("Metadata manifest is missing required field row: $field")
        }
    }
}

$referenceCutoffRows = @()
if ($ReferenceCutoffManifestPath) {
    $referenceRequiredFields = @(
        "ReferencePolicy",
        "CutoffPage",
        "CutoffHeading",
        "LastIncludedBlock",
        "ExcludedAfterHeading",
        "Checked",
        "Notes"
    )
    $referenceCutoffRows = @(Get-ManifestRows -Path $ReferenceCutoffManifestPath -RequiredFields $referenceRequiredFields)
    if ($referenceCutoffRows.Count -eq 0) {
        $errors.Add("Reference cutoff manifest contains no rows.")
    }
    foreach ($row in $referenceCutoffRows) {
        $policy = ([string]$row.ReferencePolicy).Trim()
        if ($policy -ne $ReferencePolicy) {
            $errors.Add("Reference cutoff policy '$policy' does not match ReferencePolicy '$ReferencePolicy'.")
        }
        if (-not (Test-DoneValue -Value ([string]$row.Checked))) {
            $errors.Add("Reference cutoff manifest row is not checked.")
        }
        if ($ReferencePolicy -eq "Exclude") {
            if (-not ([string]$row.CutoffPage).Trim()) {
                $errors.Add("Reference cutoff manifest requires CutoffPage for Exclude policy.")
            }
            if (-not ([string]$row.CutoffHeading).Trim()) {
                $errors.Add("Reference cutoff manifest requires CutoffHeading for Exclude policy.")
            }
            if (-not ([string]$row.LastIncludedBlock).Trim()) {
                $errors.Add("Reference cutoff manifest requires LastIncludedBlock for Exclude policy.")
            }
            if (-not (Test-DoneValue -Value ([string]$row.ExcludedAfterHeading))) {
                $errors.Add("Reference cutoff manifest requires ExcludedAfterHeading to be checked for Exclude policy.")
            }
        }
    }
}

$textLayerDraftRows = @()
if ($TextLayerDraftManifestPath) {
    $textLayerRequiredFields = @(
        "Page",
        "ColumnOrRegion",
        "BlockType",
        "Section",
        "TextLayerTool",
        "DraftSource",
        "DraftFirstWords",
        "DraftLastWords",
        "VisualFirstWords",
        "VisualLastWords",
        "MarkdownAnchor",
        "CorrectionsMade",
        "VisualChecked",
        "Notes"
    )
    $textLayerDraftRows = @(Get-ManifestRows -Path $TextLayerDraftManifestPath -RequiredFields $textLayerRequiredFields)
    if ($textLayerDraftRows.Count -eq 0) {
        $errors.Add("Text layer draft manifest contains no rows.")
    }
    foreach ($row in $textLayerDraftRows) {
        $blockType = ([string]$row.BlockType).Trim()
        $page = ([string]$row.Page).Trim()
        if (-not $page) {
            $errors.Add("Text layer draft row has an empty Page value.")
        }
        if (-not $blockType) {
            $errors.Add("Text layer draft row has an empty BlockType value.")
        }
        if (-not ([string]$row.TextLayerTool).Trim()) {
            $errors.Add("Text layer draft row for '$blockType' has empty TextLayerTool.")
        }
        if (-not ([string]$row.DraftSource).Trim()) {
            $errors.Add("Text layer draft row for '$blockType' has empty DraftSource.")
        }
        if (-not ([string]$row.DraftFirstWords).Trim()) {
            $errors.Add("Text layer draft row for '$blockType' has empty DraftFirstWords.")
        }
        if (-not ([string]$row.DraftLastWords).Trim()) {
            $errors.Add("Text layer draft row for '$blockType' has empty DraftLastWords.")
        }
        if (-not ([string]$row.VisualFirstWords).Trim()) {
            $errors.Add("Text layer draft row for '$blockType' has empty VisualFirstWords.")
        }
        if (-not ([string]$row.VisualLastWords).Trim()) {
            $errors.Add("Text layer draft row for '$blockType' has empty VisualLastWords.")
        }
        $markdownAnchor = ([string]$row.MarkdownAnchor).Trim()
        if (-not $markdownAnchor) {
            $errors.Add("Text layer draft row for '$blockType' has empty MarkdownAnchor.")
        } elseif (-not (Test-MarkdownAnchorExists -Anchor $markdownAnchor -MarkdownText $text)) {
            $errors.Add("Text layer draft MarkdownAnchor for '$blockType' is not present in Markdown: $markdownAnchor")
        }
        if (-not ([string]$row.CorrectionsMade).Trim()) {
            $errors.Add("Text layer draft row for '$blockType' has empty CorrectionsMade. Use 'none' only after visual verification finds no corrections.")
        }
        if (-not (Test-DoneValue -Value ([string]$row.VisualChecked))) {
            $errors.Add("Text layer draft row for '$blockType' is not visually checked.")
        }
        if ($TextLayerAssisted -and $page -and $blockType -and $markdownAnchor) {
            $linkKey = New-BlockLinkKey -Page $page -BlockType $blockType -MarkdownAnchor $markdownAnchor
            if (-not $blockLinkKeys.Contains($linkKey)) {
                $errors.Add("Text layer draft row for '$blockType' does not match a block coverage row by Page + BlockType + MarkdownAnchor.")
            }
        }
    }
}

$candidateRows = @()
$chosenCandidateKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
if ($ImageCandidateManifestPath) {
    $candidateManifestItem = Get-Item -LiteralPath $ImageCandidateManifestPath
    $candidateManifestDir = Split-Path -Parent $candidateManifestItem.FullName
    $candidateRequiredFields = @(
        "Candidate",
        "Width",
        "Height",
        "PageHint",
        "MatchedFigure",
        "Decision",
        "RejectReason",
        "Checked",
        "Notes"
    )
    $candidateRows = @(Get-ManifestRows -Path $candidateManifestItem.FullName -RequiredFields $candidateRequiredFields)
    $allowedCandidateDecisions = @("chosen", "rejected", "unmatched")
    foreach ($row in $candidateRows) {
        $candidate = ([string]$row.Candidate).Trim()
        $decision = ([string]$row.Decision).Trim().ToLowerInvariant()
        $matchedFigure = ([string]$row.MatchedFigure).Trim()
        if (-not $candidate -and $localImageReports.Count -gt 0) {
            $errors.Add("Image candidate manifest row has an empty Candidate value.")
        }
        if ($candidate -and $allowedCandidateDecisions -notcontains $decision) {
            $errors.Add("Image candidate '$candidate' has invalid Decision '$decision'. Use chosen, rejected, or unmatched.")
        }
        if ($decision -eq "chosen") {
            if (-not $matchedFigure) {
                $errors.Add("Image candidate '$candidate' is chosen but has empty MatchedFigure.")
            }
            Add-PathKeys -Set $chosenCandidateKeys -Value $candidate -ManifestDir $candidateManifestDir -MarkdownDir $markdownDir
        }
        if ($decision -eq "rejected" -and -not ([string]$row.RejectReason).Trim()) {
            $errors.Add("Image candidate '$candidate' is rejected but has no RejectReason.")
        }
        if ($candidate -and -not (Test-DoneValue -Value ([string]$row.Checked))) {
            $errors.Add("Image candidate '$candidate' is not checked.")
        }
    }
}

$manifestRows = @()
if (($RequireAssetManifest -or $StrictFullPaper) -and $localImageReports.Count -gt 0 -and -not $AssetManifestPath) {
    $errors.Add("AssetManifestPath is required because asset manifest validation is enabled and Markdown contains local image links.")
}

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
    if ($StrictFullPaper) {
        $requiredFields += @("FirstCitationAnchor", "PlacementBasis", "PlacementChecked")
    }
    $manifestRows = @(Get-ManifestRows -Path $manifestItem.FullName -RequiredFields $requiredFields)
    if ($manifestRows.Count -eq 0) {
        $errors.Add("Asset manifest contains no asset decision rows.")
    }

    $chosenKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $allowedMethods = @("direct-export", "crop-fallback")
    $allowedVisualMatches = @("complete", "incomplete", "not-matched")
    foreach ($row in $manifestRows) {
        $figure = [string]$row.Figure
        $method = ([string]$row.Method).Trim()
        $exportCandidates = ([string]$row.ExportCandidates).Trim()
        $chosenAsset = ([string]$row.ChosenAsset).Trim()
        $visualMatch = ([string]$row.VisualMatch).Trim().ToLowerInvariant()
        $fallbackReason = ([string]$row.FallbackReason).Trim()
        $done = ([string]$row.Done).Trim()

        if (-not $figure.Trim()) {
            $errors.Add("Asset manifest row has an empty Figure value.")
        }
        if ($allowedMethods -notcontains $method) {
            $errors.Add("Asset manifest row for '$figure' has invalid Method '$method'. Use direct-export or crop-fallback.")
        }
        if ($allowedVisualMatches -notcontains $visualMatch) {
            $errors.Add("Asset manifest row for '$figure' has invalid VisualMatch '$visualMatch'. Use complete, incomplete, or not-matched.")
        }
        if (-not $chosenAsset) {
            $errors.Add("Asset manifest row for '$figure' has an empty ChosenAsset.")
        }
        if (-not $visualMatch) {
            $errors.Add("Asset manifest row for '$figure' has an empty VisualMatch.")
        }
        if ($method -eq "direct-export") {
            if (-not $exportCandidates) {
                $errors.Add("Asset manifest row for '$figure' uses direct-export without ExportCandidates.")
            }
            if ($visualMatch -ne "complete") {
                $errors.Add("Asset manifest row for '$figure' uses direct-export but VisualMatch is not complete.")
            }
            if ($StrictFullPaper -and $ImageCandidateManifestPath) {
                $hasChosenCandidate = $false
                foreach ($candidate in (Split-ListValues -Value $exportCandidates)) {
                    if (Test-AnyPathKeyInSet -Set $chosenCandidateKeys -Value $candidate -ManifestDir $manifestDir -MarkdownDir $markdownDir) {
                        $hasChosenCandidate = $true
                        break
                    }
                }
                if (-not $hasChosenCandidate) {
                    $errors.Add("Asset manifest row for '$figure' uses direct-export but no ExportCandidates entry is marked chosen in the image candidate manifest.")
                }
            }
        }
        if ($method -eq "crop-fallback" -and -not $fallbackReason) {
            $errors.Add("Asset manifest row for '$figure' uses crop-fallback without FallbackReason.")
        }
        if (-not (Test-DoneValue -Value $done)) {
            $errors.Add("Asset manifest row for '$figure' is not marked Done.")
        }
        if ($StrictFullPaper) {
            if (-not ([string]$row.FirstCitationAnchor).Trim()) {
                $errors.Add("Asset manifest row for '$figure' has empty FirstCitationAnchor.")
            }
            if (([string]$row.PlacementBasis).Trim() -ne "first-citation") {
                $errors.Add("Asset manifest row for '$figure' must use PlacementBasis=first-citation.")
            }
            if (-not (Test-DoneValue -Value ([string]$row.PlacementChecked))) {
                $errors.Add("Asset manifest row for '$figure' has unchecked PlacementChecked.")
            }
        }

        Add-PathKeys -Set $chosenKeys -Value $chosenAsset -ManifestDir $manifestDir -MarkdownDir $markdownDir
    }

    foreach ($image in $localImageReports) {
        $targetKey = $image.Target -replace '/', '\'
        $fullKey = [System.IO.Path]::GetFullPath($image.FullName)
        $leafKey = [System.IO.Path]::GetFileName($image.Target)
        if (-not $chosenKeys.Contains($targetKey) -and -not $chosenKeys.Contains($fullKey) -and -not $chosenKeys.Contains($leafKey)) {
            $errors.Add("Markdown image link is not recorded as a ChosenAsset in the asset manifest: $($image.Target)")
        }
    }
}

$formulaManifestRows = @()
if ($FormulaManifestPath) {
    $formulaManifestItem = Get-Item -LiteralPath $FormulaManifestPath
    $formulaManifestDir = Split-Path -Parent $formulaManifestItem.FullName
    $formulaRequiredFields = @(
        "Formula",
        "SourcePage",
        "SourceBlock",
        "VisualNumber",
        "MarkdownTag",
        "MarkdownAnchor",
        "ScreenshotAsset",
        "DiscoveryChecked",
        "TranscriptionChecked",
        "Uncertainty",
        "ReviewerNotes",
        "Done"
    )
    $formulaManifestRows = @(Get-ManifestRows -Path $formulaManifestItem.FullName -RequiredFields $formulaRequiredFields)
    if ($formulaManifestRows.Count -eq 0) {
        $errors.Add("Formula manifest contains no formula rows.")
    }

    $manifestTagSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $formulaManifestRows) {
        $formula = ([string]$row.Formula).Trim()
        $sourcePage = ([string]$row.SourcePage).Trim()
        $sourceBlock = ([string]$row.SourceBlock).Trim()
        $visualNumber = ([string]$row.VisualNumber).Trim()
        $tag = ([string]$row.MarkdownTag).Trim()
        $markdownAnchor = ([string]$row.MarkdownAnchor).Trim()
        $screenshotAsset = ([string]$row.ScreenshotAsset).Trim()
        $uncertainty = ([string]$row.Uncertainty).Trim()
        $done = ([string]$row.Done).Trim()

        if (-not $formula) {
            $errors.Add("Formula manifest row has an empty Formula value.")
        }
        if (-not $sourcePage) {
            $errors.Add("Formula manifest row for '$formula' has an empty SourcePage.")
        }
        if (-not $sourceBlock) {
            $errors.Add("Formula manifest row for '$formula' has an empty SourceBlock.")
        }
        if (-not $visualNumber) {
            $errors.Add("Formula manifest row for '$formula' has an empty VisualNumber.")
        }
        if (-not $markdownAnchor) {
            $errors.Add("Formula manifest row for '$formula' has an empty MarkdownAnchor.")
        } elseif (-not (Test-MarkdownAnchorExists -Anchor $markdownAnchor -MarkdownText $text)) {
            $errors.Add("Formula manifest MarkdownAnchor for '$formula' is not present in Markdown: $markdownAnchor")
        }
        if (-not (Test-DoneValue -Value ([string]$row.DiscoveryChecked))) {
            $errors.Add("Formula manifest row for '$formula' has unchecked DiscoveryChecked.")
        }
        if (-not (Test-DoneValue -Value ([string]$row.TranscriptionChecked))) {
            $errors.Add("Formula manifest row for '$formula' has unchecked TranscriptionChecked.")
        }
        if (-not $tag) {
            $errors.Add("Formula manifest row for '$formula' has an empty MarkdownTag.")
        } else {
            [void]$manifestTagSet.Add($tag)
            if (-not $markdownTagSet.Contains($tag)) {
                $errors.Add("Formula manifest tag '$tag' is not present as a Markdown \tag{...}.")
            }
        }
        if (Test-UncertaintyValue -Value $uncertainty) {
            if (-not $screenshotAsset) {
                $errors.Add("Formula manifest row for '$formula' has uncertainty but no ScreenshotAsset.")
            } elseif (-not (Test-PathCandidateExists -Value $screenshotAsset -ManifestDir $formulaManifestDir -MarkdownDir $markdownDir)) {
                $errors.Add("Formula manifest ScreenshotAsset does not resolve: $screenshotAsset")
            }
        }
        if (-not (Test-DoneValue -Value $done)) {
            $errors.Add("Formula manifest row for '$formula' is not marked Done.")
        }
    }

    foreach ($tag in $markdownTagSet) {
        if (-not $manifestTagSet.Contains($tag)) {
            $errors.Add("Markdown formula tag '$tag' is not recorded in the formula manifest.")
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Error ($errors -join [Environment]::NewLine)
    exit 1
}

[pscustomobject]@{
    Markdown = $markdownItem.FullName
    StrictFullPaper = [bool]$StrictFullPaper
    AssetManifest = $(if ($AssetManifestPath) { (Get-Item -LiteralPath $AssetManifestPath).FullName } else { $null })
    Checklist = $(if ($ChecklistPath) { (Get-Item -LiteralPath $ChecklistPath).FullName } else { $null })
    BlockManifest = $(if ($BlockManifestPath) { (Get-Item -LiteralPath $BlockManifestPath).FullName } else { $null })
    MetadataManifest = $(if ($MetadataManifestPath) { (Get-Item -LiteralPath $MetadataManifestPath).FullName } else { $null })
    ReferenceCutoffManifest = $(if ($ReferenceCutoffManifestPath) { (Get-Item -LiteralPath $ReferenceCutoffManifestPath).FullName } else { $null })
    ImageCandidateManifest = $(if ($ImageCandidateManifestPath) { (Get-Item -LiteralPath $ImageCandidateManifestPath).FullName } else { $null })
    TextLayerAssisted = [bool]$TextLayerAssisted
    TextLayerDraftManifest = $(if ($TextLayerDraftManifestPath) { (Get-Item -LiteralPath $TextLayerDraftManifestPath).FullName } else { $null })
    FormulaManifest = $(if ($FormulaManifestPath) { (Get-Item -LiteralPath $FormulaManifestPath).FullName } else { $null })
    ImageLinks = $imageMatches.Count
    ManifestRows = $manifestRows.Count
    CandidateRows = $candidateRows.Count
    ChecklistRows = $checklistRows.Count
    BlockRows = $blockRows.Count
    MetadataRows = $metadataRows.Count
    ReferenceCutoffRows = $referenceCutoffRows.Count
    TextLayerDraftRows = $textLayerDraftRows.Count
    FormulaManifestRows = $formulaManifestRows.Count
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
