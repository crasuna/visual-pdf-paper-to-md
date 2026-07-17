[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MarkdownPath,

    [Parameter(Mandatory = $true)]
    [string]$JobManifestPath,

    [Parameter(Mandatory = $true)]
    [string]$BlockManifestPath,

    [Parameter(Mandatory = $true)]
    [string]$AssetManifestPath,

    [Parameter(Mandatory = $true)]
    [string]$ImageCandidateManifestPath,

    [Parameter(Mandatory = $true)]
    [string]$ReviewManifestPath,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Structural", "Final")]
    [string]$Phase,

    [switch]$CommitStatus
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "transcription_manifest_common.ps1")
$errors = New-Object System.Collections.Generic.List[string]

$inputPaths = [ordered]@{
    Markdown = $MarkdownPath
    Job = $JobManifestPath
    Blocks = $BlockManifestPath
    Assets = $AssetManifestPath
    ImageCandidates = $ImageCandidateManifestPath
    Reviews = $ReviewManifestPath
}
$initialInputHashes = [ordered]@{}
foreach ($inputName in $inputPaths.Keys) {
    $initialInputHashes[$inputName] = Get-FileSha256Lower -Path $inputPaths[$inputName]
}

function Test-CheckedValue {
    param([string]$Value)

    if (-not $Value) {
        return $false
    }
    return @("1", "true", "yes", "checked", "reviewed", "done", "ok") -contains $Value.Trim().ToLowerInvariant()
}

function Test-FalseValue {
    param([string]$Value)

    if (-not $Value) {
        return $false
    }
    return @("0", "false", "no") -contains $Value.Trim().ToLowerInvariant()
}

function Test-AnchorEndsAtVisualBoundary {
    param(
        [string]$Anchor,
        [string]$VisualLastWords,
        [string]$Representation
    )

    if ($Representation -eq "asset") {
        return $Anchor -match '^\s*!\[[^\]]*\]\(\s*(?:<[^>]+>|[^\s\)]+)\s*\)\s*$'
    }
    if ($Representation -notin @("markdown", "html") -or -not $VisualLastWords) {
        return $false
    }
    $lastIndex = $Anchor.LastIndexOf($VisualLastWords, [System.StringComparison]::Ordinal)
    if ($lastIndex -lt 0) {
        return $false
    }
    $tail = $Anchor.Substring($lastIndex + $VisualLastWords.Length)
    $allowedTail = '^(?s)(?:\s+|[*_~`>#|]+|\\[\)\]]|\\tag\{[^}\r\n]+\}|\\end\{[A-Za-z*]+\}|</?[A-Za-z][^>]*>|\]\([^\)\r\n]+\)|[\]\)])*$'
    return $tail -match $allowedTail
}

function Get-CsvRows {
    param(
        [string]$Path,
        [string[]]$RequiredFields,
        [switch]$AllowEmpty
    )

    $item = Get-Item -LiteralPath $Path
    if ($item.Extension.ToLowerInvariant() -ne ".csv") {
        throw "v2 manifests must be CSV files: $Path"
    }
    $headerLine = Get-Content -LiteralPath $item.FullName -TotalCount 1
    if (-not $headerLine) {
        throw "CSV manifest has no header: $Path"
    }
    $headers = @($headerLine -split ',' | ForEach-Object { $_.Trim().Trim('"') })
    $missing = @($RequiredFields | Where-Object { $_ -notin $headers })
    if ($missing.Count -gt 0) {
        throw "CSV manifest is missing required v2 fields: $($missing -join ', '): $Path"
    }
    $rows = @(Import-Csv -LiteralPath $item.FullName)
    if (-not $AllowEmpty -and $rows.Count -eq 0) {
        throw "CSV manifest has no data rows: $Path"
    }
    return $rows
}

function Resolve-PackagePath {
    param(
        [string]$PackageRoot,
        [string]$RelativePath,
        [switch]$AllowOutsidePackage
    )

    if (-not $RelativePath) {
        return $null
    }
    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "Manifest paths must be relative: $RelativePath"
    }
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $PackageRoot $RelativePath))
    if (-not $AllowOutsidePackage) {
        $root = [System.IO.Path]::GetFullPath($PackageRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $resolved.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Manifest path escapes the package root: $RelativePath"
        }
    }
    return $resolved
}

function Get-PdfPageCount {
    param(
        [string]$PdfPath,
        [string]$PdfinfoPath
    )

    $commandPath = $PdfinfoPath
    if (-not $commandPath -or -not (Test-Path -LiteralPath $commandPath)) {
        $command = Get-Command pdfinfo.exe -ErrorAction SilentlyContinue
        if (-not $command) {
            $command = Get-Command pdfinfo -ErrorAction Stop
        }
        $commandPath = $command.Source
    }

    $infoInput = $PdfPath
    $tempPdf = $null
    if ($infoInput -match '[^\x00-\x7F]') {
        $tempPdf = Join-Path ([System.IO.Path]::GetTempPath()) ("visual-pdf-validator-" + [guid]::NewGuid().ToString("N") + ".pdf")
        Copy-Item -LiteralPath $PdfPath -Destination $tempPdf
        $infoInput = $tempPdf
    }
    try {
        $output = & $commandPath $infoInput 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "pdfinfo failed while validating the source PDF: $($output -join ' ')"
        }
    } finally {
        if ($tempPdf -and (Test-Path -LiteralPath $tempPdf)) {
            Remove-Item -LiteralPath $tempPdf -Force
        }
    }
    foreach ($line in $output) {
        if ([string]$line -match '^Pages:\s+(\d+)') {
            return [int]$Matches[1]
        }
    }
    throw "Unable to determine source PDF page count."
}

function Get-ImageDimensions {
    param(
        [string]$ImagePath,
        [string]$MagickPath
    )

    $commandPath = $MagickPath
    if (-not $commandPath -or -not (Test-Path -LiteralPath $commandPath)) {
        $commandPath = (Get-Command magick -ErrorAction Stop).Source
    }
    $dimensions = & $commandPath identify -format "%w %h" $ImagePath 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $dimensions) {
        throw "Unable to read image dimensions: $ImagePath"
    }
    $parts = $dimensions -split '\s+'
    return [pscustomobject]@{ Width = [int]$parts[0]; Height = [int]$parts[1] }
}

$jobFields = @(
    "SchemaVersion", "JobId", "SourcePdfRelativePath", "SourcePdfSha256", "SourcePdfBytes", "PageCount", "SourceMode",
    "DraftRelativePath", "DraftSha256", "DraftProducer", "DraftToolPath", "DraftToolVersion", "DraftToolParameters",
    "CodexInvokedOcr", "EmbeddedTextAuthorized", "ReferencePolicy",
    "CutoffPage", "CutoffHeading", "LastIncludedBlockId", "ExternalMetadataPolicy", "MarkdownRelativePath", "CreatedUtc",
    "PdftoppmPath", "PdftoppmVersion", "PdfinfoPath", "PdfinfoVersion", "PdfimagesPath", "PdfimagesVersion",
    "MagickPath", "MagickVersion", "PdftotextPath", "PdftotextVersion", "TranscriptionStatus", "StructuralStatus",
    "ReviewStatus", "FinalStatus"
)
$blockFields = @(
    "SchemaVersion", "BlockId", "LogicalBlockId", "Sequence", "PageAssetId", "Region", "Continuation", "BlockType", "Section",
    "VisualFirstWords", "VisualLastWords", "MarkdownAnchor", "Representation", "DraftFirstWords", "DraftLastWords", "CorrectionsMade",
    "Numbering", "VisualNumber", "MarkdownTag", "FallbackAssetId", "TranscriberChecked", "Uncertainty", "Notes"
)
$assetFields = @(
    "SchemaVersion", "AssetId", "AssetType", "RelatedBlockId", "PageNumber", "Path", "Sha256", "Bytes", "Width", "Height", "Dpi",
    "IsAuthoritative", "SourceMethod", "DerivedFromCandidateIds", "VisualMatch", "FallbackReason", "PlacementRule", "FirstCitationAnchor",
    "CaptionAnchor", "TranscriberChecked", "Notes"
)
$candidateFields = @(
    "SchemaVersion", "CandidateId", "PdfObject", "PageHint", "Path", "Sha256", "Bytes", "Width", "Height", "MatchedAssetId",
    "Decision", "RejectReason", "Checked", "Notes"
)
$reviewFields = @(
    "SchemaVersion", "ReviewId", "ReviewerRunId", "ReviewerContext", "TargetType", "TargetId", "PageAssetId", "Outcome", "Category",
    "Expected", "Actual", "EvidencePath", "Blocking", "Cycle", "Resolution", "RecheckOutcome", "Notes"
)

$jobs = @(Get-CsvRows -Path $JobManifestPath -RequiredFields $jobFields)
if ($jobs.Count -ne 1) {
    throw "job.csv must contain exactly one row."
}
$job = $jobs[0]
$blocks = @(Get-CsvRows -Path $BlockManifestPath -RequiredFields $blockFields)
$assets = @(Get-CsvRows -Path $AssetManifestPath -RequiredFields $assetFields)
$candidates = @(Get-CsvRows -Path $ImageCandidateManifestPath -RequiredFields $candidateFields -AllowEmpty)
$reviews = @(Get-CsvRows -Path $ReviewManifestPath -RequiredFields $reviewFields -AllowEmpty)

foreach ($collection in @($jobs, $blocks, $assets, $candidates, $reviews)) {
    foreach ($row in $collection) {
        if ([string]$row.SchemaVersion -ne "2") {
            $errors.Add("Unsupported manifest schema '$($row.SchemaVersion)'; v2 is required and v1 is not accepted.")
        }
    }
}

$jobManifestItem = Get-Item -LiteralPath $JobManifestPath
$manifestDir = Split-Path -Parent $jobManifestItem.FullName
$auditDir = Split-Path -Parent $manifestDir
$packageRoot = Split-Path -Parent $auditDir
$markdownItem = Get-Item -LiteralPath $MarkdownPath
$markdownFullName = [System.IO.Path]::GetFullPath($markdownItem.FullName)
$text = Get-Content -LiteralPath $markdownFullName -Raw

$recordedMarkdown = Resolve-PackagePath -PackageRoot $packageRoot -RelativePath ([string]$job.MarkdownRelativePath)
if ($recordedMarkdown -ne $markdownFullName) {
    $errors.Add("MarkdownPath does not match job.csv MarkdownRelativePath.")
}

$sourcePdf = Resolve-PackagePath -PackageRoot $packageRoot -RelativePath ([string]$job.SourcePdfRelativePath) -AllowOutsidePackage
if (-not $sourcePdf -or -not (Test-Path -LiteralPath $sourcePdf)) {
    $errors.Add("Source PDF does not resolve from job.csv: $($job.SourcePdfRelativePath)")
} else {
    $sourceItem = Get-Item -LiteralPath $sourcePdf
    $actualHash = (Get-FileHash -LiteralPath $sourceItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne ([string]$job.SourcePdfSha256).Trim().ToLowerInvariant()) {
        $errors.Add("Recorded source PDF hash does not match the source file.")
    }
    if ([int64]$job.SourcePdfBytes -ne $sourceItem.Length) {
        $errors.Add("Recorded source PDF byte size does not match the source file.")
    }
    try {
        $actualPageCount = Get-PdfPageCount -PdfPath $sourceItem.FullName -PdfinfoPath ([string]$job.PdfinfoPath)
        if ([int]$job.PageCount -ne $actualPageCount) {
            $errors.Add("Recorded PageCount does not match the source PDF page count.")
        }
    } catch {
        $errors.Add($_.Exception.Message)
    }
}

$sourceModes = @("visual-only", "embedded-text-assisted", "user-ocr-assisted")
$sourceMode = ([string]$job.SourceMode).Trim()
if ($sourceModes -notcontains $sourceMode) {
    $errors.Add("Invalid SourceMode '$sourceMode'.")
}
if (-not (Test-FalseValue -Value ([string]$job.CodexInvokedOcr))) {
    $errors.Add("CodexInvokedOcr must be false for every v2 source mode.")
}
foreach ($field in @("PdftoppmPath", "PdftoppmVersion", "PdfinfoPath", "PdfinfoVersion", "PdfimagesPath", "PdfimagesVersion", "MagickPath", "MagickVersion")) {
    if (-not ([string]$job.$field).Trim()) {
        $errors.Add("job.csv requires a recorded $field value.")
    }
}
$allowedJobStates = [ordered]@{
    TranscriptionStatus = @("initialized", "transcribed", "needs-correction", "needs-user-review", "failed")
    StructuralStatus = @("initialized", "structurally-valid", "failed")
    ReviewStatus = @("initialized", "review-pending", "reviewing", "needs-correction", "needs-user-review", "verified", "verified-with-fallback", "failed")
    FinalStatus = @("initialized", "review-pending", "needs-user-review", "verified", "verified-with-fallback", "failed")
}
foreach ($field in $allowedJobStates.Keys) {
    if ($allowedJobStates[$field] -notcontains ([string]$job.$field)) {
        $errors.Add("job.csv has invalid $field '$($job.$field)'.")
    }
}
if ($sourceMode -eq "visual-only") {
    if ($job.DraftRelativePath -or $job.DraftSha256 -or $job.DraftProducer -or $job.DraftToolPath -or $job.DraftToolVersion -or $job.DraftToolParameters -or -not (Test-FalseValue -Value ([string]$job.EmbeddedTextAuthorized))) {
        $errors.Add("visual-only must not contain draft provenance or embedded-text authorization.")
    }
}
if ($sourceMode -eq "embedded-text-assisted") {
    if (-not (Test-CheckedValue -Value ([string]$job.EmbeddedTextAuthorized)) -or -not $job.DraftRelativePath -or -not $job.DraftSha256 -or -not $job.DraftToolPath -or -not $job.DraftToolVersion -or -not $job.DraftToolParameters -or -not $job.PdftotextPath -or -not $job.PdftotextVersion) {
        $errors.Add("embedded-text-assisted requires authorization, a hashed draft artifact, and complete extraction-tool provenance.")
    }
}
if ($sourceMode -eq "user-ocr-assisted") {
    if (-not $job.DraftRelativePath -or -not $job.DraftSha256 -or $job.DraftProducer -ne "user-provided" -or $job.DraftToolPath -or $job.DraftToolVersion -or $job.DraftToolParameters) {
        $errors.Add("user-ocr-assisted requires a hashed user-provided draft artifact.")
    }
}
if ($sourceMode -in @("embedded-text-assisted", "user-ocr-assisted") -and $job.DraftRelativePath) {
    try {
        $draftPath = Resolve-PackagePath -PackageRoot $packageRoot -RelativePath ([string]$job.DraftRelativePath)
        if (-not (Test-Path -LiteralPath $draftPath)) {
            $errors.Add("Draft artifact does not exist: $($job.DraftRelativePath)")
        } else {
            $draftHash = (Get-FileHash -LiteralPath $draftPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($draftHash -ne ([string]$job.DraftSha256).Trim().ToLowerInvariant()) {
                $errors.Add("Draft artifact hash does not match job.csv.")
            }
        }
    } catch {
        $errors.Add($_.Exception.Message)
    }
}

$unresolvedPattern = '(?im)\b(TODO|FIXME|TBD|UNCERTAIN)\b|\[uncertain\]|\?\?\?'
if ($text -match $unresolvedPattern) {
    $errors.Add("Markdown contains unresolved text markers.")
}

$allowedBlockTypes = @(
    "title", "author", "affiliation", "metadata", "abstract-label", "heading",
    "paragraph", "footnote", "caption", "table", "formula", "acknowledgement", "appendix", "declaration",
    "copyright-license", "reference-cutoff", "blank-page"
)
$allowedContinuations = @("single", "start", "middle", "end")
$allowedRepresentations = @("markdown", "html", "asset", "none")
$blockIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$sequenceSet = New-Object 'System.Collections.Generic.HashSet[int]'
$markdownAnchorSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$blockById = @{}
$hasUnresolvedContent = $false
$blockCoverageRanges = New-Object System.Collections.Generic.List[object]
foreach ($block in $blocks) {
    $blockId = ([string]$block.BlockId).Trim()
    if (-not $blockId -or -not $blockIds.Add($blockId)) {
        $errors.Add("BlockId is empty or duplicated: '$blockId'.")
    } else {
        $blockById[$blockId] = $block
    }
    if (-not ([string]$block.LogicalBlockId).Trim()) {
        $errors.Add("Block '$blockId' has an empty LogicalBlockId.")
    }
    $sequence = 0
    if (-not [int]::TryParse(([string]$block.Sequence), [ref]$sequence) -or $sequence -lt 1 -or -not $sequenceSet.Add($sequence)) {
        $errors.Add("Block '$blockId' has an invalid or duplicated Sequence.")
    }
    if ($allowedBlockTypes -notcontains ([string]$block.BlockType)) {
        $errors.Add("Block '$blockId' has invalid BlockType '$($block.BlockType)'.")
    }
    if ($allowedContinuations -notcontains ([string]$block.Continuation)) {
        $errors.Add("Block '$blockId' has invalid Continuation '$($block.Continuation)'.")
    }
    if ($allowedRepresentations -notcontains ([string]$block.Representation)) {
        $errors.Add("Block '$blockId' has invalid Representation '$($block.Representation)'.")
    }
    if (-not ([string]$block.Region).Trim() -or -not ([string]$block.VisualFirstWords).Trim() -or -not ([string]$block.VisualLastWords).Trim()) {
        $errors.Add("Block '$blockId' lacks visual region or first/last-word anchors.")
    }
    if (-not (Test-CheckedValue -Value ([string]$block.TranscriberChecked))) {
        $errors.Add("Block '$blockId' is not transcriber-checked.")
    }
    $uncertainty = ([string]$block.Uncertainty).Trim()
    if (@("none", "resolved", "structured-fallback", "unresolved") -notcontains $uncertainty) {
        $errors.Add("Block '$blockId' has invalid uncertainty '$uncertainty'.")
    } elseif ($uncertainty -eq "unresolved") {
        $hasUnresolvedContent = $true
    }
    if ($uncertainty -eq "structured-fallback" -and $block.BlockType -notin @("formula", "table")) {
        $errors.Add("Only formula or table blocks may use structured-fallback.")
    }

    $anchor = ([string]$block.MarkdownAnchor).Trim()
    if ($block.Representation -ne "none") {
        if (-not $anchor) {
            $errors.Add("Block '$blockId' has an empty MarkdownAnchor.")
        } else {
            $anchorMatches = [regex]::Matches($text, [regex]::Escape($anchor))
            if ($anchorMatches.Count -ne 1) {
                $errors.Add("Block '$blockId' MarkdownAnchor must appear exactly once; found $($anchorMatches.Count).")
            } else {
                $blockCoverageRanges.Add([pscustomobject]@{
                    Source = "block '$blockId'"
                    Sequence = $sequence
                    Start = $anchorMatches[0].Index
                    End = $anchorMatches[0].Index + $anchorMatches[0].Length
                })
            }
            if (-not $markdownAnchorSet.Add($anchor)) {
                $errors.Add("MarkdownAnchor is duplicated across represented blocks: $anchor")
            }
            if (-not (Test-AnchorEndsAtVisualBoundary -Anchor $anchor -VisualLastWords ([string]$block.VisualLastWords) -Representation ([string]$block.Representation))) {
                $errors.Add("Block '$blockId' MarkdownAnchor continues past its VisualLastWords boundary or is not a valid asset representation.")
            }
        }
    }

    if ($sourceMode -eq "visual-only" -and ($block.DraftFirstWords -or $block.DraftLastWords -or $block.CorrectionsMade)) {
        $errors.Add("visual-only block '$blockId' must not contain draft provenance.")
    }
    if ($sourceMode -in @("embedded-text-assisted", "user-ocr-assisted") -and $block.Representation -ne "none") {
        if (-not $block.DraftFirstWords -or -not $block.DraftLastWords -or -not $block.CorrectionsMade) {
            $errors.Add("Draft-assisted block '$blockId' lacks draft anchors or CorrectionsMade.")
        }
    }

    if ($block.BlockType -eq "formula") {
        if ($block.Numbering -notin @("numbered", "unnumbered")) {
            $errors.Add("Formula block '$blockId' must use Numbering=numbered or unnumbered.")
        } elseif ($block.Numbering -eq "numbered") {
            if (-not $block.VisualNumber -or -not $block.MarkdownTag) {
                $errors.Add("Numbered formula block '$blockId' requires VisualNumber and MarkdownTag.")
            } elseif ($text -notmatch ('\\tag\{' + [regex]::Escape(([string]$block.MarkdownTag).Trim()) + '\}')) {
                $errors.Add("Numbered formula block '$blockId' MarkdownTag is absent from Markdown.")
            }
        } elseif ($block.VisualNumber -or $block.MarkdownTag) {
            $errors.Add("Unnumbered formula block '$blockId' must not contain VisualNumber or MarkdownTag.")
        }
        if ($block.Representation -eq "asset" -and (-not $block.FallbackAssetId -or $uncertainty -ne "structured-fallback")) {
            $errors.Add("Formula asset block '$blockId' requires FallbackAssetId and structured-fallback uncertainty.")
        }
    } elseif ($block.Numbering -ne "not-applicable" -or $block.VisualNumber -or $block.MarkdownTag) {
        $errors.Add("Non-formula block '$blockId' must use Numbering=not-applicable without formula fields.")
    }
    if ($block.BlockType -eq "table" -and $block.Representation -eq "asset" -and (-not $block.FallbackAssetId -or $uncertainty -ne "structured-fallback")) {
        $errors.Add("Table asset block '$blockId' requires FallbackAssetId and structured-fallback uncertainty.")
    }
}

if ($sequenceSet.Count -eq $blocks.Count) {
    for ($expected = 1; $expected -le $blocks.Count; $expected++) {
        if (-not $sequenceSet.Contains($expected)) {
            $errors.Add("Block Sequence values must be contiguous from 1 through $($blocks.Count).")
            break
        }
    }
}

$assetIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$assetById = @{}
$authoritativePages = @{}
$renderedPagesByNumber = @{}
$renderedPageDpiKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$finalAssets = New-Object System.Collections.Generic.List[object]
$assetCoverageRanges = New-Object System.Collections.Generic.List[object]
$allowedAssetTypes = @("rendered-page", "figure", "table", "formula", "review-evidence")
$imageLinks = [regex]::Matches($text, '!\[[^\]]*\]\(\s*(?<target><[^>]+>|[^\s\)]+)\s*\)')
foreach ($asset in $assets) {
    $assetId = ([string]$asset.AssetId).Trim()
    if (-not $assetId -or -not $assetIds.Add($assetId)) {
        $errors.Add("AssetId is empty or duplicated: '$assetId'.")
    } else {
        $assetById[$assetId] = $asset
    }
    $assetType = ([string]$asset.AssetType).Trim()
    if ($allowedAssetTypes -notcontains $assetType) {
        $errors.Add("Asset '$assetId' has invalid AssetType '$assetType'.")
    }
    $assetPath = $null
    try {
        $assetPath = Resolve-PackagePath -PackageRoot $packageRoot -RelativePath ([string]$asset.Path)
    } catch {
        $errors.Add($_.Exception.Message)
    }
    if (-not $assetPath -or -not (Test-Path -LiteralPath $assetPath)) {
        $errors.Add("Asset '$assetId' path does not resolve: $($asset.Path)")
        continue
    }
    $item = Get-Item -LiteralPath $assetPath
    $actualHash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne ([string]$asset.Sha256).Trim().ToLowerInvariant()) {
        $errors.Add("Asset '$assetId' hash does not match.")
    }
    if ([int64]$asset.Bytes -ne $item.Length) {
        $errors.Add("Asset '$assetId' byte size does not match.")
    }
    try {
        $dimensions = Get-ImageDimensions -ImagePath $item.FullName -MagickPath ([string]$job.MagickPath)
        if ([int]$asset.Width -ne $dimensions.Width -or [int]$asset.Height -ne $dimensions.Height) {
            $errors.Add("Asset '$assetId' dimensions do not match.")
        }
    } catch {
        $errors.Add($_.Exception.Message)
    }
    if (-not (Test-CheckedValue -Value ([string]$asset.TranscriberChecked))) {
        $errors.Add("Asset '$assetId' is not transcriber-checked.")
    }

    if ($assetType -eq "rendered-page") {
        $pageNumber = 0
        $validPageNumber = [int]::TryParse(([string]$asset.PageNumber), [ref]$pageNumber) -and $pageNumber -ge 1 -and $pageNumber -le [int]$job.PageCount
        if (-not $validPageNumber) {
            $errors.Add("Rendered page asset '$assetId' has invalid PageNumber.")
        }
        if ($asset.SourceMethod -ne "render" -or $asset.PlacementRule -ne "audit-only" -or $asset.VisualMatch -ne "complete") {
            $errors.Add("Rendered page asset '$assetId' has invalid source, placement, or visual-match values.")
        }
        $dpi = 0
        $validDpi = [int]::TryParse(([string]$asset.Dpi), [ref]$dpi) -and $dpi -in @(300, 400)
        if (-not $validDpi) {
            $errors.Add("Rendered page asset '$assetId' must use DPI 300 or 400.")
        }
        if ($validPageNumber -and $validDpi) {
            $expectedPageIdentity = ("page-{0:D4}-{1}dpi" -f $pageNumber, $dpi)
            $expectedPageFileName = "$expectedPageIdentity.png"
            $normalizedPagePath = ([string]$asset.Path) -replace '\\', '/'
            if ($assetId -cne $expectedPageIdentity -or [System.IO.Path]::GetFileName($normalizedPagePath) -cne $expectedPageFileName -or $normalizedPagePath -cne "_audit/pages/$expectedPageFileName") {
                $errors.Add("Rendered page asset '$assetId' identity, path, PageNumber, and DPI must match '$expectedPageIdentity'.")
            }
            $dpiKey = "$pageNumber|$dpi"
            if (-not $renderedPageDpiKeys.Add($dpiKey)) {
                $errors.Add("Page $pageNumber has more than one $dpi DPI rendered-page asset.")
            }
            if (-not $renderedPagesByNumber.ContainsKey($pageNumber)) {
                $renderedPagesByNumber[$pageNumber] = New-Object System.Collections.Generic.List[object]
            }
            $renderedPagesByNumber[$pageNumber].Add($asset)
        }
        $isAuthoritative = Test-CheckedValue -Value ([string]$asset.IsAuthoritative)
        $isExplicitlyNonAuthoritative = Test-FalseValue -Value ([string]$asset.IsAuthoritative)
        if (-not $isAuthoritative -and -not $isExplicitlyNonAuthoritative) {
            $errors.Add("Rendered page asset '$assetId' must record IsAuthoritative as true or false.")
        }
        if ($isAuthoritative -and $validPageNumber) {
            if ($authoritativePages.ContainsKey($pageNumber)) {
                $errors.Add("Page $pageNumber has more than one authoritative rendered-page asset.")
            } else {
                $authoritativePages[$pageNumber] = $assetId
            }
        }
    } elseif ($assetType -in @("figure", "table", "formula")) {
        $finalAssets.Add($asset)
        if (-not $asset.RelatedBlockId -or -not $blockById.ContainsKey([string]$asset.RelatedBlockId)) {
            $errors.Add("Final asset '$assetId' does not reference a valid block.")
        } else {
            $relatedBlockType = [string]$blockById[[string]$asset.RelatedBlockId].BlockType
            $expectedBlockType = $(if ($assetType -eq "figure") { "caption" } else { $assetType })
            if ($relatedBlockType -ne $expectedBlockType) {
                $errors.Add("Final asset '$assetId' type does not match its related block type; expected '$expectedBlockType'.")
            }
        }
        if ($asset.SourceMethod -notin @("direct-export", "page-crop")) {
            $errors.Add("Final asset '$assetId' has invalid SourceMethod '$($asset.SourceMethod)'.")
        }
        if ($asset.SourceMethod -eq "page-crop" -and -not $asset.FallbackReason) {
            $errors.Add("Cropped asset '$assetId' requires FallbackReason.")
        }
        if ($asset.VisualMatch -notin @("complete", "fallback-authoritative")) {
            $errors.Add("Final asset '$assetId' must be complete or fallback-authoritative.")
        }
        $normalizedAssetPath = ([string]$asset.Path) -replace '\\', '/'
        $matchingLinks = @($imageLinks | Where-Object { $_.Groups['target'].Value.Trim('<','>') -eq $normalizedAssetPath })
        $matchingLink = $matchingLinks | Select-Object -First 1
        if ($matchingLinks.Count -ne 1) {
            $errors.Add("Final asset '$assetId' must be linked exactly once from Markdown; found $($matchingLinks.Count).")
        } else {
            $assetCoverageRanges.Add([pscustomobject]@{
                Source = "asset '$assetId'"
                Start = $matchingLink.Index
                End = $matchingLink.Index + $matchingLink.Length
            })
        }
        if ($assetType -eq "figure") {
            if ([System.IO.Path]::GetFileName($asset.Path) -notmatch '(?i)^fig\d+\.[a-z0-9]+$') {
                $errors.Add("Figure asset '$assetId' must use figN.ext naming.")
            }
            if ($asset.PlacementRule -ne "first-citation" -or -not $asset.FirstCitationAnchor) {
                $errors.Add("Figure asset '$assetId' requires first-citation placement and an anchor.")
            } elseif ($matchingLink) {
                $anchorIndex = $text.IndexOf(([string]$asset.FirstCitationAnchor), [System.StringComparison]::Ordinal)
                if ($anchorIndex -lt 0 -or $matchingLink.Index -le $anchorIndex) {
                    $errors.Add("Figure asset '$assetId' is not placed after its FirstCitationAnchor.")
                }
            }
        } elseif ($asset.FirstCitationAnchor) {
            $errors.Add("Non-figure asset '$assetId' must not use FirstCitationAnchor.")
        }
    }
}

$orderedBlockCoverage = @($blockCoverageRanges | Sort-Object Sequence)
$previousBlockStart = -1
$previousBlockEnd = -1
foreach ($range in $orderedBlockCoverage) {
    if ($previousBlockStart -ge 0 -and $range.Start -le $previousBlockStart) {
        $errors.Add("Represented block MarkdownAnchor order does not follow blocks.csv Sequence at $($range.Source).")
        break
    }
    if ($previousBlockEnd -ge 0 -and $range.Start -lt $previousBlockEnd) {
        $errors.Add("Represented block MarkdownAnchor spans overlap at $($range.Source).")
        break
    }
    $previousBlockStart = $range.Start
    $previousBlockEnd = $range.End
}

$allCoverageRanges = @(
    @($blockCoverageRanges.ToArray()) + @($assetCoverageRanges.ToArray()) |
        Sort-Object Start, End
)
$coverageCursor = 0
foreach ($range in $allCoverageRanges) {
    if ($range.Start -gt $coverageCursor) {
        $gap = $text.Substring($coverageCursor, $range.Start - $coverageCursor)
        if ($gap -match '\S') {
            $errors.Add("Markdown contains semantic content outside represented block or final asset coverage.")
            break
        }
    }
    if ($range.End -gt $coverageCursor) {
        $coverageCursor = $range.End
    }
}
if ($coverageCursor -lt $text.Length) {
    $tail = $text.Substring($coverageCursor)
    if ($tail -match '\S') {
        $errors.Add("Markdown contains semantic content outside represented block or final asset coverage.")
    }
}

for ($page = 1; $page -le [int]$job.PageCount; $page++) {
    $pageVersions = @($(if ($renderedPagesByNumber.ContainsKey($page)) { $renderedPagesByNumber[$page].ToArray() } else { @() }))
    $versions300 = @($pageVersions | Where-Object { [int]$_.Dpi -eq 300 })
    $versions400 = @($pageVersions | Where-Object { [int]$_.Dpi -eq 400 })
    if ($versions300.Count -ne 1) {
        $errors.Add("Page $page requires exactly one 300 DPI rendered-page asset.")
    }
    if ($versions400.Count -gt 1) {
        $errors.Add("Page $page may contain at most one 400 DPI rendered-page asset.")
    }
    if ($versions400.Count -eq 1) {
        if (-not (Test-CheckedValue -Value ([string]$versions400[0].IsAuthoritative)) -or ($versions300.Count -eq 1 -and -not (Test-FalseValue -Value ([string]$versions300[0].IsAuthoritative)))) {
            $errors.Add("When page $page has a 400 DPI version, the 400 DPI version must be authoritative and the retained 300 DPI version must be non-authoritative.")
        }
    } elseif ($versions300.Count -eq 1 -and -not (Test-CheckedValue -Value ([string]$versions300[0].IsAuthoritative))) {
        $errors.Add("When page $page has no 400 DPI version, its 300 DPI version must be authoritative.")
    }
    if (-not $authoritativePages.ContainsKey($page)) {
        $errors.Add("Page $page has no authoritative rendered-page asset.")
        continue
    }
    $pageAssetId = $authoritativePages[$page]
    if (-not ($blocks | Where-Object { $_.PageAssetId -eq $pageAssetId })) {
        $errors.Add("Authoritative page asset '$pageAssetId' has no block coverage row.")
    }
}
foreach ($block in $blocks) {
    if (-not $assetById.ContainsKey([string]$block.PageAssetId) -or $assetById[[string]$block.PageAssetId].AssetType -ne "rendered-page") {
        $errors.Add("Block '$($block.BlockId)' does not reference a rendered-page asset.")
    } else {
        $blockPageNumber = [int]$assetById[[string]$block.PageAssetId].PageNumber
        if (-not $authoritativePages.ContainsKey($blockPageNumber) -or $authoritativePages[$blockPageNumber] -ne [string]$block.PageAssetId) {
            $errors.Add("Block '$($block.BlockId)' must reference the authoritative rendered-page asset for page $blockPageNumber.")
        }
    }
    if ($block.FallbackAssetId) {
        if (-not $assetById.ContainsKey([string]$block.FallbackAssetId)) {
            $errors.Add("Block '$($block.BlockId)' references a missing FallbackAssetId.")
        } elseif ($assetById[[string]$block.FallbackAssetId].RelatedBlockId -ne $block.BlockId) {
            $errors.Add("Block '$($block.BlockId)' fallback asset is linked to a different block.")
        }
    }
}

$candidateIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$candidateById = @{}
foreach ($candidate in $candidates) {
    $candidateId = ([string]$candidate.CandidateId).Trim()
    if (-not $candidateId -or -not $candidateIds.Add($candidateId)) {
        $errors.Add("CandidateId is empty or duplicated: '$candidateId'.")
    } else {
        $candidateById[$candidateId] = $candidate
    }
    if ($candidate.Decision -notin @("chosen", "rejected", "unmatched")) {
        $errors.Add("Candidate '$candidateId' has invalid Decision '$($candidate.Decision)'.")
    }
    if ($candidate.Decision -eq "rejected" -and -not $candidate.RejectReason) {
        $errors.Add("Rejected candidate '$candidateId' requires RejectReason.")
    }
    if (-not (Test-CheckedValue -Value ([string]$candidate.Checked))) {
        $errors.Add("Candidate '$candidateId' is not checked.")
    }
    try {
        $candidatePath = Resolve-PackagePath -PackageRoot $packageRoot -RelativePath ([string]$candidate.Path)
        if (-not (Test-Path -LiteralPath $candidatePath)) {
            $errors.Add("Candidate '$candidateId' path does not resolve.")
        } else {
            $candidateItem = Get-Item -LiteralPath $candidatePath
            $candidateHash = (Get-FileHash -LiteralPath $candidateItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($candidateHash -ne ([string]$candidate.Sha256).Trim().ToLowerInvariant()) {
                $errors.Add("Candidate '$candidateId' hash does not match.")
            }
            if ([int64]$candidate.Bytes -ne $candidateItem.Length) {
                $errors.Add("Candidate '$candidateId' byte size does not match.")
            }
            try {
                $candidateDimensions = Get-ImageDimensions -ImagePath $candidateItem.FullName -MagickPath ([string]$job.MagickPath)
                if ([int]$candidate.Width -ne $candidateDimensions.Width -or [int]$candidate.Height -ne $candidateDimensions.Height) {
                    $errors.Add("Candidate '$candidateId' dimensions do not match.")
                }
            } catch {
                $errors.Add($_.Exception.Message)
            }
        }
    } catch {
        $errors.Add($_.Exception.Message)
    }
}
foreach ($asset in $finalAssets) {
    if ($asset.SourceMethod -eq "direct-export") {
        $derivedIds = @(([string]$asset.DerivedFromCandidateIds) -split '[;,]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($derivedIds.Count -eq 0) {
            $errors.Add("Direct-export asset '$($asset.AssetId)' requires DerivedFromCandidateIds.")
        }
        foreach ($candidateId in $derivedIds) {
            if (-not $candidateById.ContainsKey($candidateId) -or $candidateById[$candidateId].Decision -ne "chosen" -or $candidateById[$candidateId].MatchedAssetId -ne $asset.AssetId) {
                $errors.Add("Direct-export asset '$($asset.AssetId)' is not backed by a chosen matching candidate '$candidateId'.")
            }
        }
    }
}

$referencePolicy = ([string]$job.ReferencePolicy).Trim()
if ($referencePolicy -notin @("exclude", "keep")) {
    $errors.Add("Invalid ReferencePolicy '$referencePolicy'.")
} elseif ($referencePolicy -eq "exclude") {
    $representedReferenceBlocks = @(
        $blocks | Where-Object {
            ([string]$_.Section).Trim().ToLowerInvariant() -eq "references" -and
            $_.Representation -ne "none"
        }
    )
    if ($representedReferenceBlocks.Count -gt 0) {
        $errors.Add("ReferencePolicy=exclude must not contain represented Section=references blocks.")
    }
    $cutoffPage = 0
    if (-not [int]::TryParse(([string]$job.CutoffPage), [ref]$cutoffPage) -or $cutoffPage -lt 1 -or $cutoffPage -gt [int]$job.PageCount) {
        $errors.Add("ReferencePolicy=exclude requires a valid CutoffPage.")
    }
    if (-not $job.CutoffHeading -or -not $job.LastIncludedBlockId -or -not $blockById.ContainsKey([string]$job.LastIncludedBlockId)) {
        $errors.Add("ReferencePolicy=exclude requires CutoffHeading and a valid LastIncludedBlockId.")
    }
    $cutoffBlocks = @($blocks | Where-Object { $_.BlockType -eq "reference-cutoff" })
    if ($cutoffBlocks.Count -ne 1) {
        $errors.Add("ReferencePolicy=exclude requires exactly one reference-cutoff block.")
    } else {
        $cutoffBlock = $cutoffBlocks[0]
        $cutoffSequence = [int]$cutoffBlock.Sequence
        if ($cutoffSequence -ne $blocks.Count) {
            $errors.Add("The reference-cutoff block must be the final block in blocks.csv.")
        }
        if ($cutoffBlock.Representation -ne "none") {
            $errors.Add("The reference-cutoff block must use Representation=none.")
        }

        $normalizedCutoffHeading = (([string]$job.CutoffHeading).Trim() -replace '\s+', ' ')
        $normalizedFirstWords = (([string]$cutoffBlock.VisualFirstWords).Trim() -replace '\s+', ' ')
        $normalizedLastWords = (([string]$cutoffBlock.VisualLastWords).Trim() -replace '\s+', ' ')
        if ($normalizedFirstWords -cne $normalizedCutoffHeading -or $normalizedLastWords -cne $normalizedCutoffHeading) {
            $errors.Add("The reference-cutoff visual anchors must equal job.csv CutoffHeading.")
        }

        if (-not $assetById.ContainsKey([string]$cutoffBlock.PageAssetId)) {
            $errors.Add("Reference cutoff block does not reference a rendered-page asset.")
        } else {
            $cutoffPageAsset = $assetById[[string]$cutoffBlock.PageAssetId]
            if ([int]$cutoffPageAsset.PageNumber -ne $cutoffPage) {
                $errors.Add("Reference cutoff block page does not match job.csv CutoffPage.")
            }
        }

        $representedBeforeCutoff = @(
            $blocks |
                Where-Object { [int]$_.Sequence -lt $cutoffSequence -and $_.Representation -ne "none" } |
                Sort-Object { [int]$_.Sequence }
        )
        if ($representedBeforeCutoff.Count -eq 0) {
            $errors.Add("ReferencePolicy=exclude requires at least one represented block before the cutoff.")
        } else {
            $lastRepresented = $representedBeforeCutoff[-1]
            if ([string]$job.LastIncludedBlockId -ne [string]$lastRepresented.BlockId) {
                $errors.Add("LastIncludedBlockId must identify the final represented block before the reference cutoff.")
            }
            $interveningBlocks = @(
                $blocks | Where-Object {
                    [int]$_.Sequence -gt [int]$lastRepresented.Sequence -and
                    [int]$_.Sequence -lt $cutoffSequence
                }
            )
            foreach ($interveningBlock in $interveningBlocks) {
                if ($interveningBlock.BlockType -ne "blank-page" -or $interveningBlock.Representation -ne "none") {
                    $errors.Add("Only explicit blank-page blocks may appear between LastIncludedBlockId and the reference cutoff.")
                    break
                }
            }

            $terminalAnchor = ([string]$lastRepresented.MarkdownAnchor).TrimEnd()
            if (-not $terminalAnchor -or -not $text.TrimEnd().EndsWith($terminalAnchor, [System.StringComparison]::Ordinal)) {
                $errors.Add("The last included MarkdownAnchor must end at the final non-whitespace character in Markdown.")
            } elseif (-not (Test-AnchorEndsAtVisualBoundary -Anchor $terminalAnchor -VisualLastWords ([string]$lastRepresented.VisualLastWords) -Representation ([string]$lastRepresented.Representation))) {
                $errors.Add("The last included MarkdownAnchor continues past its VisualLastWords boundary.")
            }
        }

        if ($normalizedCutoffHeading) {
            $recordedHeadingTokens = @($normalizedCutoffHeading -split '\s+' | Where-Object { $_ })
            $recordedHeadingBodyPattern = (@($recordedHeadingTokens | ForEach-Object { [regex]::Escape($_) }) -join '[^\S\r\n]+')
            $recordedHeadingPattern = '(?im)^[\t ]{0,3}#{1,6}[\t ]+' + $recordedHeadingBodyPattern + '[\t ]*#*[\t ]*\r?$'
            $recordedSetextPattern = '(?im)^[\t ]*' + $recordedHeadingBodyPattern + '[\t ]*\r?\n[\t ]*(?:=+|-+)[\t ]*\r?$'
            if ($text -match $recordedHeadingPattern -or $text -match $recordedSetextPattern) {
                $errors.Add("Markdown contains the recorded reference heading under exclude policy.")
            }
        }
    }
    if ($text -match '(?im)^\s*#{1,6}\s+(references|bibliography)\b' -or $text -match '(?im)^\s*(references|bibliography)\s*\r?\n\s*(?:=+|-+)\s*$') {
        $errors.Add("Markdown contains a References/Bibliography heading under exclude policy.")
    }
} else {
    if ($job.CutoffPage -or $job.CutoffHeading -or $job.LastIncludedBlockId) {
        $errors.Add("ReferencePolicy=keep requires empty cutoff fields in job.csv.")
    }
    if (@($blocks | Where-Object { $_.BlockType -eq "reference-cutoff" }).Count -gt 0) {
        $errors.Add("ReferencePolicy=keep must not contain a reference-cutoff block.")
    }
    $keptReferenceBlocks = @(
        $blocks | Where-Object {
            ([string]$_.Section).Trim().ToLowerInvariant() -eq "references" -and
            $_.Representation -ne "none"
        }
    )
    $keptReferenceHeadings = @($keptReferenceBlocks | Where-Object { $_.BlockType -eq "heading" })
    $keptReferenceEntries = @($keptReferenceBlocks | Where-Object { $_.BlockType -ne "heading" })
    if ($keptReferenceHeadings.Count -eq 0 -or $keptReferenceEntries.Count -eq 0) {
        $errors.Add("ReferencePolicy=keep requires represented bibliography heading and entry blocks with Section=references.")
    }
}

if ($Phase -eq "Final") {
    $reviewedTargets = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $reviewIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($review in $reviews) {
        if (-not $review.ReviewId -or -not $reviewIds.Add([string]$review.ReviewId)) {
            $errors.Add("ReviewId is empty or duplicated: '$($review.ReviewId)'.")
        }
        if ($review.ReviewerContext -ne "fresh" -or -not $review.ReviewerRunId) {
            $errors.Add("Review '$($review.ReviewId)' is not attributed to a fresh reviewer context.")
        }
        if ($review.TargetType -notin @("block", "asset")) {
            $errors.Add("Review '$($review.ReviewId)' has invalid TargetType '$($review.TargetType)'.")
        } elseif ($review.TargetType -eq "block" -and -not $blockById.ContainsKey([string]$review.TargetId)) {
            $errors.Add("Review '$($review.ReviewId)' targets an unknown block '$($review.TargetId)'.")
        } elseif ($review.TargetType -eq "asset" -and (-not $assetById.ContainsKey([string]$review.TargetId) -or $assetById[[string]$review.TargetId].AssetType -notin @("figure", "table", "formula"))) {
            $errors.Add("Review '$($review.ReviewId)' targets an unknown or non-final asset '$($review.TargetId)'.")
        }
        if (-not $assetById.ContainsKey([string]$review.PageAssetId) -or $assetById[[string]$review.PageAssetId].AssetType -ne "rendered-page") {
            $errors.Add("Review '$($review.ReviewId)' does not reference a rendered page asset.")
        } else {
            $reviewPageNumber = [int]$assetById[[string]$review.PageAssetId].PageNumber
            if (-not $authoritativePages.ContainsKey($reviewPageNumber) -or $authoritativePages[$reviewPageNumber] -ne [string]$review.PageAssetId) {
                $errors.Add("Review '$($review.ReviewId)' must reference the authoritative rendered-page asset for page $reviewPageNumber.")
            }
            if ($review.TargetType -eq "block" -and $blockById.ContainsKey([string]$review.TargetId) -and $blockById[[string]$review.TargetId].PageAssetId -ne $review.PageAssetId) {
                $errors.Add("Review '$($review.ReviewId)' page does not match its target block.")
            } elseif ($review.TargetType -eq "asset" -and $assetById.ContainsKey([string]$review.TargetId)) {
                $reviewedAssetPage = [int]$assetById[[string]$review.TargetId].PageNumber
                if ($reviewedAssetPage -ne $reviewPageNumber) {
                    $errors.Add("Review '$($review.ReviewId)' page does not match its target asset.")
                }
            }
        }
        if ($review.Outcome -notin @("pass", "fail")) {
            $errors.Add("Review '$($review.ReviewId)' has invalid Outcome '$($review.Outcome)'.")
        }
        if ($review.Resolution -notin @("open", "closed") -or $review.RecheckOutcome -notin @("pass", "fail", "pending")) {
            $errors.Add("Review '$($review.ReviewId)' has invalid resolution or recheck state.")
        }
        if (-not (Test-FalseValue -Value ([string]$review.Blocking) -or (Test-CheckedValue -Value ([string]$review.Blocking)))) {
            $errors.Add("Review '$($review.ReviewId)' must record Blocking as true or false.")
        }
        if ($review.EvidencePath) {
            try {
                $evidencePath = Resolve-PackagePath -PackageRoot $packageRoot -RelativePath ([string]$review.EvidencePath)
                if (-not (Test-Path -LiteralPath $evidencePath)) {
                    $errors.Add("Review '$($review.ReviewId)' evidence path does not resolve.")
                }
            } catch {
                $errors.Add($_.Exception.Message)
            }
        }
        $cycle = 0
        if (-not [int]::TryParse(([string]$review.Cycle), [ref]$cycle) -or $cycle -lt 1 -or $cycle -gt 2) {
            $errors.Add("Review '$($review.ReviewId)' has invalid Cycle; only 1 or 2 is allowed.")
        }
        $targetKey = "$($review.TargetType)|$($review.TargetId)"
        if ($review.Outcome -eq "pass" -and $review.Resolution -eq "closed" -and $review.RecheckOutcome -eq "pass" -and (Test-FalseValue -Value ([string]$review.Blocking))) {
            [void]$reviewedTargets.Add($targetKey)
        }
        if ($review.Outcome -eq "fail" -and (Test-CheckedValue -Value ([string]$review.Blocking)) -and ($review.Resolution -ne "closed" -or $review.RecheckOutcome -ne "pass")) {
            $errors.Add("Review '$($review.ReviewId)' has an unresolved blocking finding.")
        }
    }
    foreach ($block in $blocks) {
        if (-not $reviewedTargets.Contains("block|$($block.BlockId)")) {
            $errors.Add("Missing fresh review coverage for block '$($block.BlockId)'.")
        }
    }
    foreach ($asset in $finalAssets) {
        if (-not $reviewedTargets.Contains("asset|$($asset.AssetId)")) {
            $errors.Add("Missing fresh review coverage for asset '$($asset.AssetId)'.")
        }
    }
}

if ($errors.Count -gt 0) {
    throw ($errors -join [Environment]::NewLine)
}

$hasFallback = @($blocks | Where-Object { $_.Uncertainty -eq "structured-fallback" }).Count -gt 0
$status = if ($hasUnresolvedContent) {
    "needs-user-review"
} elseif ($Phase -eq "Structural") {
    "structurally-valid"
} elseif ($hasFallback) {
    "verified-with-fallback"
} else {
    "verified"
}

$committed = $false
if ($CommitStatus) {
    foreach ($inputName in $inputPaths.Keys) {
        $currentHash = Get-FileSha256Lower -Path $inputPaths[$inputName]
        if ($currentHash -ne $initialInputHashes[$inputName]) {
            throw "Validation input changed before status commit: $inputName"
        }
    }

    $hasFailedLifecycle = @($job.TranscriptionStatus, $job.StructuralStatus, $job.ReviewStatus, $job.FinalStatus) -contains "failed"
    if ($hasFailedLifecycle) {
        throw "Status commit cannot modify a terminal failed lifecycle."
    }

    if ($Phase -eq "Structural") {
        if ([string]$job.TranscriptionStatus -ne "transcribed") {
            throw "Structural status commit requires TranscriptionStatus=transcribed."
        }
        if ([string]$job.StructuralStatus -notin @("initialized", "structurally-valid")) {
            throw "Structural status commit requires StructuralStatus=initialized or structurally-valid."
        }
        if ([string]$job.ReviewStatus -ne "initialized" -or [string]$job.FinalStatus -ne "initialized") {
            throw "Structural status commit requires ReviewStatus=initialized and FinalStatus=initialized."
        }
        $job.StructuralStatus = "structurally-valid"
        if ($status -eq "needs-user-review") {
            $job.TranscriptionStatus = "needs-user-review"
            $job.FinalStatus = "needs-user-review"
        }
    } else {
        if ([string]$job.StructuralStatus -ne "structurally-valid") {
            throw "Final status commit requires StructuralStatus=structurally-valid."
        }
        $isRepeatedFinalCommit = (
            [string]$job.TranscriptionStatus -eq $(if ($status -eq "needs-user-review") { "needs-user-review" } else { "transcribed" }) -and
            [string]$job.ReviewStatus -eq $status -and
            [string]$job.FinalStatus -eq $status
        )
        $isFirstFinalCommit = (
            [string]$job.TranscriptionStatus -eq "transcribed" -and
            [string]$job.ReviewStatus -eq "reviewing" -and
            [string]$job.FinalStatus -eq "initialized"
        )
        if (-not $isFirstFinalCommit -and -not $isRepeatedFinalCommit) {
            throw "Final status commit requires TranscriptionStatus=transcribed, ReviewStatus=reviewing, and FinalStatus=initialized, or an identical previously committed final state."
        }
        if ($status -eq "needs-user-review") {
            $job.TranscriptionStatus = "needs-user-review"
            $job.ReviewStatus = "needs-user-review"
            $job.FinalStatus = "needs-user-review"
        } else {
            $job.ReviewStatus = $status
            $job.FinalStatus = $status
        }
    }

    Write-AtomicCsvRow -Path $JobManifestPath -Row $job -ExpectedExistingSha256 $initialInputHashes.Job
    $committed = $true
}

[pscustomobject][ordered]@{
    SchemaVersion = "2"
    Phase = $Phase
    Status = $status
    Committed = $committed
    TranscriptionStatus = [string]$job.TranscriptionStatus
    StructuralStatus = [string]$job.StructuralStatus
    ReviewStatus = [string]$job.ReviewStatus
    FinalStatus = [string]$job.FinalStatus
    SourcePdf = $sourcePdf
    Markdown = $markdownFullName
    PageCount = [int]$job.PageCount
    BlockCount = $blocks.Count
    AssetCount = $assets.Count
    CandidateCount = $candidates.Count
    ReviewCount = $reviews.Count
    ReferencePolicy = $referencePolicy
    SourceMode = $sourceMode
}
