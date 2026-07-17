[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPdf,

    [Parameter(Mandatory = $true)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $true)]
    [ValidateSet("visual-only", "embedded-text-assisted", "user-ocr-assisted")]
    [string]$SourceMode,

    [string]$UserOcrPath,

    [switch]$AllowEmbeddedTextExtraction,

    [ValidateSet("exclude", "keep")]
    [string]$ReferencePolicy = "exclude",

    [ValidateSet("pdf-only", "authorized-official-check")]
    [string]$ExternalMetadataPolicy = "pdf-only"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "transcription_manifest_common.ps1")

$preflightParameters = @{
    InputPdf = $InputPdf
    OutputRoot = $OutputRoot
    SourceMode = $SourceMode
    ReferencePolicy = $ReferencePolicy
    ExternalMetadataPolicy = $ExternalMetadataPolicy
}
if ($UserOcrPath) {
    $preflightParameters.UserOcrPath = $UserOcrPath
}
if ($AllowEmbeddedTextExtraction) {
    $preflightParameters.AllowEmbeddedTextExtraction = $true
}

$preflight = & (Join-Path $PSScriptRoot "preflight_transcription.ps1") @preflightParameters
$outputPath = $preflight.OutputRoot
$outputParent = Split-Path -Parent $outputPath
if (-not (Test-Path -LiteralPath $outputParent)) {
    throw "Output parent directory does not exist: $outputParent"
}

$createdOutput = $false
try {
    New-Item -ItemType Directory -Path $outputPath | Out-Null
    $createdOutput = $true
    foreach ($relativeDir in @(
        "assets\figures",
        "assets\tables",
        "assets\formulas",
        "_audit\pages",
        "_audit\candidates",
        "_audit\drafts",
        "_audit\manifests",
        "_audit\review\evidence"
    )) {
        New-Item -ItemType Directory -Path (Join-Path $outputPath $relativeDir) | Out-Null
    }

    $sourceItem = Get-Item -LiteralPath $preflight.SourcePdf
    $markdownName = $sourceItem.BaseName + ".md"
    $markdownPath = Join-Path $outputPath $markdownName
    [System.IO.File]::WriteAllText($markdownPath, "", [System.Text.UTF8Encoding]::new($false))

    $draftRelativePath = ""
    $draftSha256 = ""
    $draftProducer = ""
    if ($SourceMode -eq "user-ocr-assisted") {
        $ocrItem = Get-Item -LiteralPath $preflight.UserOcrPath
        $draftName = "user-ocr" + $ocrItem.Extension
        $draftPath = Join-Path $outputPath ("_audit\drafts\" + $draftName)
        Copy-Item -LiteralPath $ocrItem.FullName -Destination $draftPath
        $draftRelativePath = [System.IO.Path]::GetRelativePath($outputPath, $draftPath)
        $draftSha256 = (Get-FileHash -LiteralPath $draftPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $draftProducer = "user-provided"
    }

    $manifestDir = Join-Path $outputPath "_audit\manifests"
    $jobFields = @(
        "SchemaVersion", "JobId", "SourcePdfRelativePath", "SourcePdfSha256", "SourcePdfBytes", "PageCount",
        "SourceMode", "DraftRelativePath", "DraftSha256", "DraftProducer", "DraftToolPath", "DraftToolVersion",
        "DraftToolParameters", "CodexInvokedOcr", "EmbeddedTextAuthorized",
        "ReferencePolicy", "CutoffPage", "CutoffHeading", "LastIncludedBlockId", "ExternalMetadataPolicy",
        "MarkdownRelativePath", "CreatedUtc", "PdftoppmPath", "PdftoppmVersion", "PdfinfoPath", "PdfinfoVersion",
        "PdfimagesPath", "PdfimagesVersion", "MagickPath", "MagickVersion", "PdftotextPath", "PdftotextVersion",
        "TranscriptionStatus", "StructuralStatus", "ReviewStatus", "FinalStatus"
    )
    $jobRow = [pscustomobject][ordered]@{
        SchemaVersion = "2"
        JobId = [guid]::NewGuid().ToString("D")
        SourcePdfRelativePath = [System.IO.Path]::GetRelativePath($outputPath, $sourceItem.FullName)
        SourcePdfSha256 = $preflight.SourcePdfSha256
        SourcePdfBytes = $preflight.SourcePdfBytes
        PageCount = $preflight.PageCount
        SourceMode = $SourceMode
        DraftRelativePath = $draftRelativePath
        DraftSha256 = $draftSha256
        DraftProducer = $draftProducer
        DraftToolPath = ""
        DraftToolVersion = ""
        DraftToolParameters = ""
        CodexInvokedOcr = "false"
        EmbeddedTextAuthorized = ([bool]$preflight.EmbeddedTextAuthorized).ToString().ToLowerInvariant()
        ReferencePolicy = $ReferencePolicy
        CutoffPage = ""
        CutoffHeading = ""
        LastIncludedBlockId = ""
        ExternalMetadataPolicy = $ExternalMetadataPolicy
        MarkdownRelativePath = $markdownName
        CreatedUtc = [DateTime]::UtcNow.ToString("o")
        PdftoppmPath = $preflight.PdftoppmPath
        PdftoppmVersion = $preflight.PdftoppmVersion
        PdfinfoPath = $preflight.PdfinfoPath
        PdfinfoVersion = $preflight.PdfinfoVersion
        PdfimagesPath = $preflight.PdfimagesPath
        PdfimagesVersion = $preflight.PdfimagesVersion
        MagickPath = $preflight.MagickPath
        MagickVersion = $preflight.MagickVersion
        PdftotextPath = $preflight.PdftotextPath
        PdftotextVersion = $preflight.PdftotextVersion
        TranscriptionStatus = "initialized"
        StructuralStatus = "initialized"
        ReviewStatus = "initialized"
        FinalStatus = "initialized"
    }
    Write-AtomicCsvRow -Path (Join-Path $manifestDir "job.csv") -Row $jobRow

    Write-AtomicCsvHeader -Path (Join-Path $manifestDir "blocks.csv") -Fields @(
        "SchemaVersion", "BlockId", "LogicalBlockId", "Sequence", "PageAssetId", "Region", "Continuation", "BlockType",
        "Section", "VisualFirstWords", "VisualLastWords", "MarkdownAnchor", "Representation", "DraftFirstWords",
        "DraftLastWords", "CorrectionsMade", "Numbering", "VisualNumber", "MarkdownTag", "FallbackAssetId",
        "TranscriberChecked", "Uncertainty", "Notes"
    )
    Write-AtomicCsvHeader -Path (Join-Path $manifestDir "assets.csv") -Fields @(
        "SchemaVersion", "AssetId", "AssetType", "RelatedBlockId", "PageNumber", "Path", "Sha256", "Bytes", "Width",
        "Height", "Dpi", "IsAuthoritative", "SourceMethod", "DerivedFromCandidateIds", "VisualMatch", "FallbackReason",
        "PlacementRule", "FirstCitationAnchor", "CaptionAnchor", "TranscriberChecked", "Notes"
    )
    Write-AtomicCsvHeader -Path (Join-Path $manifestDir "image_candidates.csv") -Fields @(
        "SchemaVersion", "CandidateId", "PdfObject", "PageHint", "Path", "Sha256", "Bytes", "Width", "Height",
        "MatchedAssetId", "Decision", "RejectReason", "Checked", "Notes"
    )
    Write-AtomicCsvHeader -Path (Join-Path $manifestDir "review_findings.csv") -Fields @(
        "SchemaVersion", "ReviewId", "ReviewerRunId", "ReviewerContext", "TargetType", "TargetId", "PageAssetId",
        "Outcome", "Category", "Expected", "Actual", "EvidencePath", "Blocking", "Cycle", "Resolution", "RecheckOutcome", "Notes"
    )

    [pscustomobject][ordered]@{
        SchemaVersion = "2"
        JobId = $jobRow.JobId
        OutputRoot = $outputPath
        Markdown = $markdownPath
        ManifestDirectory = $manifestDir
        Status = "initialized"
    }
} catch {
    if ($createdOutput -and (Test-Path -LiteralPath $outputPath)) {
        $resolvedCreated = [System.IO.Path]::GetFullPath($outputPath)
        $resolvedParent = [System.IO.Path]::GetFullPath($outputParent)
        if (-not $resolvedCreated.StartsWith($resolvedParent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Initializer failed and refused unsafe cleanup for: $resolvedCreated. Original error: $($_.Exception.Message)"
        }
        Remove-Item -LiteralPath $resolvedCreated -Recurse -Force
    }
    throw
}
