[CmdletBinding()]
param(
    [string]$NamePattern = "*"
)

$ErrorActionPreference = "Stop"
$skillRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Join-Path $skillRoot "scripts"
$failures = New-Object System.Collections.Generic.List[string]
$passes = New-Object System.Collections.Generic.List[string]

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-TestCase {
    param(
        [string]$Name,
        [scriptblock]$Body
    )

    if ($Name -notlike $NamePattern) {
        return
    }

    try {
        & $Body
        $passes.Add($Name)
        Write-Host "PASS $Name"
    } catch {
        $failures.Add("$Name`: $($_.Exception.Message)")
        Write-Host "FAIL $Name"
        Write-Host $_.Exception.Message
    }
}

function Invoke-CommandCapture {
    param(
        [string]$ScriptPath,
        [hashtable]$Parameters
    )

    $output = & $ScriptPath @Parameters 2>&1
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = @($output)
    }
}

function New-TestPdf {
    param([string]$Path)

    $encoding = [System.Text.Encoding]::ASCII
    $content1 = "BT /F1 12 Tf 72 200 Td (Page 1) Tj ET"
    $content2 = "BT /F1 12 Tf 72 200 Td (Page 2) Tj ET"
    $objects = @(
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Resources << /Font << /F1 7 0 R >> >> /Contents 5 0 R >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Resources << /Font << /F1 7 0 R >> >> /Contents 6 0 R >>",
        "<< /Length $($encoding.GetByteCount($content1)) >>`nstream`n$content1`nendstream",
        "<< /Length $($encoding.GetByteCount($content2)) >>`nstream`n$content2`nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    )

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append("%PDF-1.4`n")
    $offsets = New-Object System.Collections.Generic.List[int]
    for ($index = 0; $index -lt $objects.Count; $index++) {
        $offsets.Add($encoding.GetByteCount($builder.ToString()))
        [void]$builder.Append("$($index + 1) 0 obj`n$($objects[$index])`nendobj`n")
    }
    $xrefOffset = $encoding.GetByteCount($builder.ToString())
    [void]$builder.Append("xref`n0 $($objects.Count + 1)`n")
    [void]$builder.Append("0000000000 65535 f `n")
    foreach ($offset in $offsets) {
        [void]$builder.Append(('{0:D10} 00000 n ' -f $offset) + "`n")
    }
    [void]$builder.Append("trailer`n<< /Size $($objects.Count + 1) /Root 1 0 R >>`nstartxref`n$xrefOffset`n%%EOF`n")
    [System.IO.File]::WriteAllBytes($Path, $encoding.GetBytes($builder.ToString()))
}

function New-ValidPackage {
    param(
        [string]$Name,
        [string]$PdfPath,
        [switch]$IncludeReview
    )

    $outputRoot = Join-Path $fixtureRoot $Name
    & (Join-Path $scriptRoot "new_transcription_job.ps1") -InputPdf $PdfPath -OutputRoot $outputRoot -SourceMode visual-only | Out-Null
    $manifestDir = Join-Path $outputRoot "_audit\manifests"
    $markdownPath = Join-Path $outputRoot "fixture.md"
    [System.IO.File]::WriteAllText(
        $markdownPath,
        "# Title`n`nBody cites (1).`n`n\[`n\alpha + \beta`n\]`n",
        [System.Text.UTF8Encoding]::new($false)
    )

    $pageAssets = New-Object System.Collections.Generic.List[object]
    for ($page = 1; $page -le 2; $page++) {
        $pagePath = Join-Path $outputRoot ("_audit\pages\page-{0:D4}-300dpi.png" -f $page)
        & magick -size 300x300 xc:white $pagePath
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to create page fixture: $pagePath"
        }
        $pageAssets.Add([pscustomobject][ordered]@{
            SchemaVersion = "2"
            AssetId = ("page-{0:D4}-300dpi" -f $page)
            AssetType = "rendered-page"
            RelatedBlockId = ""
            PageNumber = $page
            Path = [System.IO.Path]::GetRelativePath($outputRoot, $pagePath)
            Sha256 = (Get-FileHash -LiteralPath $pagePath -Algorithm SHA256).Hash.ToLowerInvariant()
            Bytes = (Get-Item -LiteralPath $pagePath).Length
            Width = 300
            Height = 300
            Dpi = 300
            IsAuthoritative = "true"
            SourceMethod = "render"
            DerivedFromCandidateIds = ""
            VisualMatch = "complete"
            FallbackReason = ""
            PlacementRule = "audit-only"
            FirstCitationAnchor = ""
            CaptionAnchor = ""
            TranscriberChecked = "checked"
            Notes = ""
        })
    }
    $pageAssets | Export-Csv -LiteralPath (Join-Path $manifestDir "assets.csv") -NoTypeInformation -Encoding UTF8

    $blocks = @(
        [pscustomobject][ordered]@{
            SchemaVersion="2"; BlockId="b001"; LogicalBlockId="l001"; Sequence="1"; PageAssetId="page-0001-300dpi"; Region="title"; Continuation="single"; BlockType="title"; Section="front-matter"; VisualFirstWords="Title"; VisualLastWords="Title"; MarkdownAnchor="# Title"; Representation="markdown"; DraftFirstWords=""; DraftLastWords=""; CorrectionsMade=""; Numbering="not-applicable"; VisualNumber=""; MarkdownTag=""; FallbackAssetId=""; TranscriberChecked="checked"; Uncertainty="none"; Notes=""
        },
        [pscustomobject][ordered]@{
            SchemaVersion="2"; BlockId="b002"; LogicalBlockId="l002"; Sequence="2"; PageAssetId="page-0001-300dpi"; Region="body"; Continuation="single"; BlockType="paragraph"; Section="body"; VisualFirstWords="Body cites"; VisualLastWords="(1)."; MarkdownAnchor="Body cites (1)."; Representation="markdown"; DraftFirstWords=""; DraftLastWords=""; CorrectionsMade=""; Numbering="not-applicable"; VisualNumber=""; MarkdownTag=""; FallbackAssetId=""; TranscriberChecked="checked"; Uncertainty="none"; Notes=""
        },
        [pscustomobject][ordered]@{
            SchemaVersion="2"; BlockId="b003"; LogicalBlockId="l003"; Sequence="3"; PageAssetId="page-0002-300dpi"; Region="body"; Continuation="single"; BlockType="formula"; Section="body"; VisualFirstWords="alpha"; VisualLastWords="beta"; MarkdownAnchor="\[`n\alpha + \beta`n\]"; Representation="markdown"; DraftFirstWords=""; DraftLastWords=""; CorrectionsMade=""; Numbering="unnumbered"; VisualNumber=""; MarkdownTag=""; FallbackAssetId=""; TranscriberChecked="checked"; Uncertainty="none"; Notes=""
        },
        [pscustomobject][ordered]@{
            SchemaVersion="2"; BlockId="b004"; LogicalBlockId="l004"; Sequence="4"; PageAssetId="page-0002-300dpi"; Region="cutoff"; Continuation="single"; BlockType="reference-cutoff"; Section="references"; VisualFirstWords="References"; VisualLastWords="References"; MarkdownAnchor="Body cites (1)."; Representation="none"; DraftFirstWords=""; DraftLastWords=""; CorrectionsMade=""; Numbering="not-applicable"; VisualNumber=""; MarkdownTag=""; FallbackAssetId=""; TranscriberChecked="checked"; Uncertainty="none"; Notes="excluded after heading"
        }
    )
    $blocks | Export-Csv -LiteralPath (Join-Path $manifestDir "blocks.csv") -NoTypeInformation -Encoding UTF8

    $jobPath = Join-Path $manifestDir "job.csv"
    $job = Import-Csv -LiteralPath $jobPath
    $job.CutoffPage = "2"
    $job.CutoffHeading = "References"
    $job.LastIncludedBlockId = "b003"
    $job.TranscriptionStatus = "transcribed"
    $job.StructuralStatus = "initialized"
    $job.ReviewStatus = "initialized"
    $job.FinalStatus = "initialized"
    $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8

    if ($IncludeReview) {
        $reviews = foreach ($block in $blocks) {
            [pscustomobject][ordered]@{
                SchemaVersion="2"; ReviewId=("review-" + $block.BlockId); ReviewerRunId="fresh-reviewer-1"; ReviewerContext="fresh"; TargetType="block"; TargetId=$block.BlockId; PageAssetId=$block.PageAssetId; Outcome="pass"; Category="coverage"; Expected="matches rendered page"; Actual="matches"; EvidencePath=""; Blocking="false"; Cycle="1"; Resolution="closed"; RecheckOutcome="pass"; Notes=""
            }
        }
        $reviews | Export-Csv -LiteralPath (Join-Path $manifestDir "review_findings.csv") -NoTypeInformation -Encoding UTF8
    }

    [pscustomobject]@{
        OutputRoot = $outputRoot
        MarkdownPath = $markdownPath
        ManifestDir = $manifestDir
    }
}

function Add-RenderedPageVersion {
    param(
        [object]$Package,
        [int]$PageNumber,
        [ValidateSet(300, 400)]
        [int]$Dpi,
        [bool]$IsAuthoritative
    )

    $pagePath = Join-Path $Package.OutputRoot ("_audit\pages\page-{0:D4}-{1}dpi.png" -f $PageNumber, $Dpi)
    & magick -size ("{0}x{0}" -f $Dpi) xc:white $pagePath
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to create rendered-page fixture: $pagePath"
    }
    $assetsPath = Join-Path $Package.ManifestDir "assets.csv"
    $assets = @(Import-Csv -LiteralPath $assetsPath)
    $assets += [pscustomobject][ordered]@{
        SchemaVersion="2"; AssetId=("page-{0:D4}-{1}dpi" -f $PageNumber, $Dpi); AssetType="rendered-page"; RelatedBlockId=""; PageNumber=$PageNumber; Path=[System.IO.Path]::GetRelativePath($Package.OutputRoot,$pagePath); Sha256=(Get-FileHash -LiteralPath $pagePath -Algorithm SHA256).Hash.ToLowerInvariant(); Bytes=(Get-Item -LiteralPath $pagePath).Length; Width=$Dpi; Height=$Dpi; Dpi=$Dpi; IsAuthoritative=$(if ($IsAuthoritative) { "true" } else { "false" }); SourceMethod="render"; DerivedFromCandidateIds=""; VisualMatch="complete"; FallbackReason=""; PlacementRule="audit-only"; FirstCitationAnchor=""; CaptionAnchor=""; TranscriberChecked="checked"; Notes=""
    }
    $assets | Export-Csv -LiteralPath $assetsPath -NoTypeInformation -Encoding UTF8
}

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("visual-pdf-v2-tests-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
$resolvedFixtureRoot = [System.IO.Path]::GetFullPath($fixtureRoot)
$resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
if (-not $resolvedFixtureRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe fixture root: $resolvedFixtureRoot"
}

try {
    $pdfPath = Join-Path $fixtureRoot "fixture.pdf"
    New-TestPdf -Path $pdfPath

    Invoke-TestCase "preflight binds a readable two-page PDF" {
        $outputRoot = Join-Path $fixtureRoot "preflight-output"
        $result = & (Join-Path $scriptRoot "preflight_transcription.ps1") -InputPdf $pdfPath -OutputRoot $outputRoot -SourceMode visual-only
        Assert-True ($result.SchemaVersion -eq "2") "Expected SchemaVersion=2."
        Assert-True ($result.PageCount -eq 2) "Expected a two-page PDF."
        Assert-True ($result.SourcePdfSha256 -match '^[A-Fa-f0-9]{64}$') "Expected a SHA-256 digest."
        Assert-True (-not (Test-Path -LiteralPath $outputRoot)) "Preflight must not create the output directory."
    }

    Invoke-TestCase "preflight rejects an existing output package" {
        $outputRoot = Join-Path $fixtureRoot "existing-output"
        New-Item -ItemType Directory -Path $outputRoot | Out-Null
        $failed = $false
        try {
            & (Join-Path $scriptRoot "preflight_transcription.ps1") -InputPdf $pdfPath -OutputRoot $outputRoot -SourceMode visual-only | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "already exists"
        }
        Assert-True $failed "Expected preflight to reject an existing output package."
    }

    Invoke-TestCase "initializer creates one v2 package and refuses overwrite" {
        $outputRoot = Join-Path $fixtureRoot "job-output"
        $result = & (Join-Path $scriptRoot "new_transcription_job.ps1") -InputPdf $pdfPath -OutputRoot $outputRoot -SourceMode visual-only
        Assert-True ($result.Status -eq "initialized") "Expected initialized status."
        foreach ($relativePath in @(
            "fixture.md",
            "assets\figures",
            "assets\tables",
            "assets\formulas",
            "_audit\pages",
            "_audit\candidates",
            "_audit\drafts",
            "_audit\review\evidence",
            "_audit\manifests\job.csv",
            "_audit\manifests\blocks.csv",
            "_audit\manifests\assets.csv",
            "_audit\manifests\image_candidates.csv",
            "_audit\manifests\review_findings.csv"
        )) {
            Assert-True (Test-Path -LiteralPath (Join-Path $outputRoot $relativePath)) "Missing initialized path: $relativePath"
        }
        $job = Import-Csv -LiteralPath (Join-Path $outputRoot "_audit\manifests\job.csv")
        Assert-True ($job.SchemaVersion -eq "2") "Expected a v2 job manifest."
        Assert-True ($job.SourceMode -eq "visual-only") "Expected visual-only source mode."
        Assert-True ($job.ReferencePolicy -eq "exclude") "Expected references to be excluded by default."

        $failed = $false
        try {
            & (Join-Path $scriptRoot "new_transcription_job.ps1") -InputPdf $pdfPath -OutputRoot $outputRoot -SourceMode visual-only | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "already exists"
        }
        Assert-True $failed "Expected a second initializer run to refuse overwrite."
    }

    Invoke-TestCase "structural validation binds source PDF, pages, blocks, and an unnumbered formula" {
        $package = New-ValidPackage -Name "structural-valid" -PdfPath $pdfPath
        $result = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") `
            -MarkdownPath $package.MarkdownPath `
            -JobManifestPath (Join-Path $package.ManifestDir "job.csv") `
            -BlockManifestPath (Join-Path $package.ManifestDir "blocks.csv") `
            -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") `
            -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") `
            -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") `
            -Phase Structural
        Assert-True ($result.Status -eq "structurally-valid") "Expected structural validation to pass."
    }

    Invoke-TestCase "canonical author and metadata block types pass structural validation" {
        foreach ($blockType in @("author", "metadata")) {
            $package = New-ValidPackage -Name ("canonical-block-" + $blockType) -PdfPath $pdfPath
            $blocksPath = Join-Path $package.ManifestDir "blocks.csv"
            $blocks = @(Import-Csv -LiteralPath $blocksPath)
            $blocks[0].BlockType = $blockType
            $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8

            $result = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural
            Assert-True ($result.Status -eq "structurally-valid") "Expected canonical BlockType '$blockType' to pass."
        }
    }

    Invoke-TestCase "canonical front matter receives fresh review coverage in Final" {
        $package = New-ValidPackage -Name "canonical-front-matter-final" -PdfPath $pdfPath -IncludeReview
        $blocksPath = Join-Path $package.ManifestDir "blocks.csv"
        $blocks = @(Import-Csv -LiteralPath $blocksPath)
        ($blocks | Where-Object BlockId -eq "b001").BlockType = "author"
        ($blocks | Where-Object BlockId -eq "b002").BlockType = "metadata"
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8

        $result = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Final
        Assert-True ($result.Status -eq "verified") "Expected canonical author and metadata blocks to accept fresh full review coverage."
    }

    Invoke-TestCase "retired granular metadata block types are rejected" {
        foreach ($blockType in @("authors", "journal", "year", "volume-issue-pages", "doi")) {
            $package = New-ValidPackage -Name ("retired-block-" + $blockType) -PdfPath $pdfPath
            $blocksPath = Join-Path $package.ManifestDir "blocks.csv"
            $blocks = @(Import-Csv -LiteralPath $blocksPath)
            $blocks[0].BlockType = $blockType
            $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8

            $failed = $false
            try {
                & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
            } catch {
                $failed = $_.Exception.Message -match "invalid BlockType '$([regex]::Escape($blockType))'"
            }
            Assert-True $failed "Expected retired BlockType '$blockType' to fail."
        }
    }

    Invoke-TestCase "structural validation rejects a changed source PDF hash" {
        $package = New-ValidPackage -Name "bad-source-hash" -PdfPath $pdfPath
        $jobPath = Join-Path $package.ManifestDir "job.csv"
        $job = Import-Csv -LiteralPath $jobPath
        $job.SourcePdfSha256 = ("0" * 64)
        $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath (Join-Path $package.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "source PDF hash"
        }
        Assert-True $failed "Expected a changed source PDF hash to fail."
    }

    Invoke-TestCase "structural validation rejects false page counts and rendered-page hashes" {
        $badCount = New-ValidPackage -Name "bad-page-count" -PdfPath $pdfPath
        $jobPath = Join-Path $badCount.ManifestDir "job.csv"
        $job = Import-Csv -LiteralPath $jobPath
        $job.PageCount = "3"
        $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $badCount.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath (Join-Path $badCount.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $badCount.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $badCount.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $badCount.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "PageCount does not match"
        }
        Assert-True $failed "Expected a false recorded page count to fail."

        $badHash = New-ValidPackage -Name "bad-page-hash" -PdfPath $pdfPath
        $assetsPath = Join-Path $badHash.ManifestDir "assets.csv"
        $assets = @(Import-Csv -LiteralPath $assetsPath)
        $assets[0].Sha256 = ("0" * 64)
        $assets | Export-Csv -LiteralPath $assetsPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $badHash.MarkdownPath -JobManifestPath (Join-Path $badHash.ManifestDir "job.csv") -BlockManifestPath (Join-Path $badHash.ManifestDir "blocks.csv") -AssetManifestPath $assetsPath -ImageCandidateManifestPath (Join-Path $badHash.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $badHash.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "Asset 'page-0001-300dpi' hash does not match"
        }
        Assert-True $failed "Expected a false rendered-page hash to fail."
    }

    Invoke-TestCase "source-mode provenance cannot be self-contradictory" {
        $visual = New-ValidPackage -Name "visual-with-draft" -PdfPath $pdfPath
        $jobPath = Join-Path $visual.ManifestDir "job.csv"
        $job = Import-Csv -LiteralPath $jobPath
        $job.DraftRelativePath = "_audit\drafts\forbidden.txt"
        $job.DraftSha256 = ("0" * 64)
        $job.DraftProducer = "embedded-text"
        $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $visual.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath (Join-Path $visual.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $visual.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $visual.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $visual.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "visual-only must not contain draft provenance"
        }
        Assert-True $failed "Expected visual-only mode to reject draft provenance."

        $embedded = New-ValidPackage -Name "embedded-without-draft" -PdfPath $pdfPath
        $jobPath = Join-Path $embedded.ManifestDir "job.csv"
        $job = Import-Csv -LiteralPath $jobPath
        $job.SourceMode = "embedded-text-assisted"
        $job.EmbeddedTextAuthorized = "false"
        $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $embedded.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath (Join-Path $embedded.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $embedded.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $embedded.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $embedded.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "requires authorization"
        }
        Assert-True $failed "Expected embedded-text-assisted mode to require authorization and a draft."

        $ocrClaim = New-ValidPackage -Name "codex-ocr-claim" -PdfPath $pdfPath
        $jobPath = Join-Path $ocrClaim.ManifestDir "job.csv"
        $job = Import-Csv -LiteralPath $jobPath
        $job.CodexInvokedOcr = "true"
        $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $ocrClaim.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath (Join-Path $ocrClaim.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $ocrClaim.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $ocrClaim.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $ocrClaim.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "CodexInvokedOcr must be false"
        }
        Assert-True $failed "Expected CodexInvokedOcr=true to fail in every source mode."
    }

    Invoke-TestCase "block IDs and Markdown anchors must be unique" {
        $package = New-ValidPackage -Name "duplicate-block" -PdfPath $pdfPath
        $blocksPath = Join-Path $package.ManifestDir "blocks.csv"
        $blocks = @(Import-Csv -LiteralPath $blocksPath)
        $blocks[1].BlockId = $blocks[0].BlockId
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "BlockId is empty or duplicated"
        }
        Assert-True $failed "Expected duplicate BlockId values to fail."

        $package = New-ValidPackage -Name "duplicate-anchor" -PdfPath $pdfPath
        $blocksPath = Join-Path $package.ManifestDir "blocks.csv"
        $blocks = @(Import-Csv -LiteralPath $blocksPath)
        $blocks[1].MarkdownAnchor = $blocks[0].MarkdownAnchor
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "MarkdownAnchor is duplicated"
        }
        Assert-True $failed "Expected duplicate represented Markdown anchors to fail."
    }

    Invoke-TestCase "typed formula asset does not require a figure citation anchor" {
        $package = New-ValidPackage -Name "formula-asset" -PdfPath $pdfPath
        $formulaPath = Join-Path $package.OutputRoot "assets\formulas\formula1.png"
        & magick -size 300x150 xc:white $formulaPath
        $markdown = Get-Content -LiteralPath $package.MarkdownPath -Raw
        $markdown = $markdown.Replace("\[`n\alpha + \beta`n\]", "![Formula 1](assets/formulas/formula1.png)")
        [System.IO.File]::WriteAllText($package.MarkdownPath, $markdown, [System.Text.UTF8Encoding]::new($false))
        $assetsPath = Join-Path $package.ManifestDir "assets.csv"
        $assets = @(Import-Csv -LiteralPath $assetsPath)
        $assets += [pscustomobject][ordered]@{
            SchemaVersion="2"; AssetId="formula-001"; AssetType="formula"; RelatedBlockId="b003"; PageNumber="2"; Path=[System.IO.Path]::GetRelativePath($package.OutputRoot,$formulaPath); Sha256=(Get-FileHash -LiteralPath $formulaPath -Algorithm SHA256).Hash.ToLowerInvariant(); Bytes=(Get-Item $formulaPath).Length; Width="300"; Height="150"; Dpi="300"; IsAuthoritative="true"; SourceMethod="page-crop"; DerivedFromCandidateIds=""; VisualMatch="fallback-authoritative"; FallbackReason="LaTeX uncertain"; PlacementRule="formula-location"; FirstCitationAnchor=""; CaptionAnchor=""; TranscriberChecked="checked"; Notes=""
        }
        $assets | Export-Csv -LiteralPath $assetsPath -NoTypeInformation -Encoding UTF8
        $blocksPath = Join-Path $package.ManifestDir "blocks.csv"
        $blocks = @(Import-Csv -LiteralPath $blocksPath)
        $formulaBlock = $blocks | Where-Object BlockId -eq "b003"
        $formulaBlock.Representation = "asset"
        $formulaBlock.FallbackAssetId = "formula-001"
        $formulaBlock.Uncertainty = "structured-fallback"
        $formulaBlock.MarkdownAnchor = "![Formula 1](assets/formulas/formula1.png)"
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8

        $result = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath $assetsPath -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural
        Assert-True ($result.Status -eq "structurally-valid") "Expected a typed formula fallback to pass without FirstCitationAnchor."
    }

    Invoke-TestCase "ordinary text uncertainty returns needs-user-review" {
        $package = New-ValidPackage -Name "uncertain-prose" -PdfPath $pdfPath -IncludeReview
        $blocksPath = Join-Path $package.ManifestDir "blocks.csv"
        $blocks = @(Import-Csv -LiteralPath $blocksPath)
        ($blocks | Where-Object BlockId -eq "b002").Uncertainty = "unresolved"
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8

        $structural = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural
        Assert-True ($structural.Status -eq "needs-user-review") "Expected unresolved prose to block structural completion."

        $final = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Final
        Assert-True ($final.Status -eq "needs-user-review") "Expected unresolved prose to prevent a verified final status."

        $committed = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural -CommitStatus
        $job = Import-Csv -LiteralPath (Join-Path $package.ManifestDir "job.csv")
        Assert-True ($committed.Committed -eq $true -and $job.StructuralStatus -eq "structurally-valid") "Expected unresolved prose to remain structurally valid when committed."
        Assert-True ($job.TranscriptionStatus -eq "needs-user-review" -and $job.FinalStatus -eq "needs-user-review") "Expected Structural commit to record the blocking ordinary-text uncertainty."
    }

    Invoke-TestCase "job lifecycle fields use stage-specific enums" {
        $package = New-ValidPackage -Name "invalid-lifecycle-enum" -PdfPath $pdfPath
        $jobPath = Join-Path $package.ManifestDir "job.csv"
        $validValues = @{
            TranscriptionStatus = "transcribed"
            StructuralStatus = "initialized"
            ReviewStatus = "initialized"
            FinalStatus = "initialized"
        }
        $invalidCases = @(
            @{ Field = "TranscriptionStatus"; Value = "verified" },
            @{ Field = "StructuralStatus"; Value = "reviewing" },
            @{ Field = "ReviewStatus"; Value = "transcribed" },
            @{ Field = "FinalStatus"; Value = "reviewing" }
        )
        foreach ($case in $invalidCases) {
            $job = Import-Csv -LiteralPath $jobPath
            $job.($case.Field) = $case.Value
            $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8
            $failed = $false
            try {
                & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath (Join-Path $package.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
            } catch {
                $failed = $_.Exception.Message -match ("invalid {0} '{1}'" -f $case.Field, $case.Value)
            }
            Assert-True $failed "Expected $($case.Field) to reject the other-stage value '$($case.Value)'."
            $job.($case.Field) = $validValues[$case.Field]
            $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8
        }
    }

    Invoke-TestCase "validator separates read-only status computation from atomic status commit" {
        $package = New-ValidPackage -Name "status-commit" -PdfPath $pdfPath -IncludeReview
        $parameters = @{
            MarkdownPath = $package.MarkdownPath
            JobManifestPath = (Join-Path $package.ManifestDir "job.csv")
            BlockManifestPath = (Join-Path $package.ManifestDir "blocks.csv")
            AssetManifestPath = (Join-Path $package.ManifestDir "assets.csv")
            ImageCandidateManifestPath = (Join-Path $package.ManifestDir "image_candidates.csv")
            ReviewManifestPath = (Join-Path $package.ManifestDir "review_findings.csv")
        }
        $jobPath = $parameters.JobManifestPath
        $beforeReadOnlyHash = (Get-FileHash -LiteralPath $jobPath -Algorithm SHA256).Hash
        $readOnlyStructural = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") @parameters -Phase Structural
        Assert-True ($readOnlyStructural.Committed -eq $false) "Expected a default Structural check to report Committed=false."
        Assert-True ((Get-FileHash -LiteralPath $jobPath -Algorithm SHA256).Hash -eq $beforeReadOnlyHash) "Expected a read-only check not to modify job.csv."

        $committedStructural = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") @parameters -Phase Structural -CommitStatus
        $job = Import-Csv -LiteralPath $jobPath
        Assert-True ($committedStructural.Committed -eq $true) "Expected Structural -CommitStatus to report a commit."
        Assert-True ($job.StructuralStatus -eq "structurally-valid") "Expected StructuralStatus to be committed."
        Assert-True ($job.FinalStatus -eq "initialized") "Expected Structural commit not to invent a final result."

        & (Join-Path $scriptRoot "update_transcription_job_status.ps1") -JobManifestPath $jobPath -Event ReviewStarted | Out-Null

        $readOnlyFinal = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") @parameters -Phase Final
        $job = Import-Csv -LiteralPath $jobPath
        Assert-True ($readOnlyFinal.Status -eq "verified" -and $readOnlyFinal.Committed -eq $false) "Expected read-only Final to compute but not commit verified."
        Assert-True ($job.FinalStatus -eq "initialized") "Expected read-only Final not to change FinalStatus."

        $committedFinal = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") @parameters -Phase Final -CommitStatus
        $job = Import-Csv -LiteralPath $jobPath
        Assert-True ($committedFinal.Committed -eq $true) "Expected Final -CommitStatus to report a commit."
        Assert-True ($job.ReviewStatus -eq "verified" -and $job.FinalStatus -eq "verified") "Expected review and final status to match the verified result."
        $committedHash = (Get-FileHash -LiteralPath $jobPath -Algorithm SHA256).Hash
        $repeatedFinal = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") @parameters -Phase Final -CommitStatus
        Assert-True ($repeatedFinal.Committed -eq $true) "Expected a repeated successful commit to remain valid."
        Assert-True ((Get-FileHash -LiteralPath $jobPath -Algorithm SHA256).Hash -eq $committedHash) "Expected repeated status commit to be byte-idempotent."

        $failed = $false
        try {
            & (Join-Path $scriptRoot "update_transcription_job_status.ps1") -JobManifestPath $jobPath -Event CorrectionRequired | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "terminal"
        }
        Assert-True $failed "Expected verified lifecycle states to reject helper mutations."
    }

    Invoke-TestCase "status commits reject skipped stages and terminal failure" {
        $structuralPackage = New-ValidPackage -Name "skipped-transcription-commit" -PdfPath $pdfPath
        $structuralJobPath = Join-Path $structuralPackage.ManifestDir "job.csv"
        $structuralJob = Import-Csv -LiteralPath $structuralJobPath
        $structuralJob.TranscriptionStatus = "initialized"
        $structuralJob | Export-Csv -LiteralPath $structuralJobPath -NoTypeInformation -Encoding UTF8
        $beforeHash = (Get-FileHash -LiteralPath $structuralJobPath -Algorithm SHA256).Hash
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $structuralPackage.MarkdownPath -JobManifestPath $structuralJobPath -BlockManifestPath (Join-Path $structuralPackage.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $structuralPackage.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $structuralPackage.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $structuralPackage.ManifestDir "review_findings.csv") -Phase Structural -CommitStatus | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "TranscriptionStatus=transcribed"
        }
        Assert-True $failed "Expected Structural commit to require completed transcription."
        Assert-True ((Get-FileHash -LiteralPath $structuralJobPath -Algorithm SHA256).Hash -eq $beforeHash) "Expected a skipped Structural stage not to modify job.csv."

        $finalPackage = New-ValidPackage -Name "skipped-structural-final" -PdfPath $pdfPath -IncludeReview
        $finalJobPath = Join-Path $finalPackage.ManifestDir "job.csv"
        $finalJob = Import-Csv -LiteralPath $finalJobPath
        $finalJob.ReviewStatus = "reviewing"
        $finalJob | Export-Csv -LiteralPath $finalJobPath -NoTypeInformation -Encoding UTF8
        $beforeHash = (Get-FileHash -LiteralPath $finalJobPath -Algorithm SHA256).Hash
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $finalPackage.MarkdownPath -JobManifestPath $finalJobPath -BlockManifestPath (Join-Path $finalPackage.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $finalPackage.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $finalPackage.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $finalPackage.ManifestDir "review_findings.csv") -Phase Final -CommitStatus | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "StructuralStatus=structurally-valid"
        }
        Assert-True $failed "Expected Final commit to require a committed Structural stage."
        Assert-True ((Get-FileHash -LiteralPath $finalJobPath -Algorithm SHA256).Hash -eq $beforeHash) "Expected a skipped Final stage not to modify job.csv."

        $finalJob = Import-Csv -LiteralPath $finalJobPath
        $finalJob.TranscriptionStatus = "failed"
        $finalJob.StructuralStatus = "failed"
        $finalJob.ReviewStatus = "failed"
        $finalJob.FinalStatus = "failed"
        $finalJob | Export-Csv -LiteralPath $finalJobPath -NoTypeInformation -Encoding UTF8
        $beforeHash = (Get-FileHash -LiteralPath $finalJobPath -Algorithm SHA256).Hash
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $finalPackage.MarkdownPath -JobManifestPath $finalJobPath -BlockManifestPath (Join-Path $finalPackage.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $finalPackage.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $finalPackage.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $finalPackage.ManifestDir "review_findings.csv") -Phase Final -CommitStatus | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "terminal failed lifecycle"
        }
        Assert-True $failed "Expected Final commit never to revive terminal failure."
        Assert-True ((Get-FileHash -LiteralPath $finalJobPath -Algorithm SHA256).Hash -eq $beforeHash) "Expected terminal failure to remain byte-identical."
    }

    Invoke-TestCase "failed status commit preserves the original job manifest" {
        $package = New-ValidPackage -Name "failed-status-commit" -PdfPath $pdfPath
        $jobPath = Join-Path $package.ManifestDir "job.csv"
        $job = Import-Csv -LiteralPath $jobPath
        $job.SourcePdfSha256 = ("0" * 64)
        $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8
        $beforeHash = (Get-FileHash -LiteralPath $jobPath -Algorithm SHA256).Hash
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath (Join-Path $package.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural -CommitStatus | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "source PDF hash"
        }
        Assert-True $failed "Expected validation to fail before any status commit."
        Assert-True ((Get-FileHash -LiteralPath $jobPath -Algorithm SHA256).Hash -eq $beforeHash) "Expected failed commit to preserve job.csv byte-for-byte."
    }

    Invoke-TestCase "concurrent manifest changes abort status commit" {
        $package = New-ValidPackage -Name "concurrent-status-input" -PdfPath $pdfPath
        $jobPath = Join-Path $package.ManifestDir "job.csv"
        $reviewsPath = Join-Path $package.ManifestDir "review_findings.csv"
        $beforeHash = (Get-FileHash -LiteralPath $jobPath -Algorithm SHA256).Hash
        $checkerJob = Start-Job -ScriptBlock {
            param($CheckerPath, $MarkdownPath, $JobPath, $BlocksPath, $AssetsPath, $CandidatesPath, $ReviewsPath)
            & $CheckerPath -MarkdownPath $MarkdownPath -JobManifestPath $JobPath -BlockManifestPath $BlocksPath -AssetManifestPath $AssetsPath -ImageCandidateManifestPath $CandidatesPath -ReviewManifestPath $ReviewsPath -Phase Structural -CommitStatus
        } -ArgumentList @(
            (Join-Path $scriptRoot "check_markdown_transcription.ps1"),
            $package.MarkdownPath,
            $jobPath,
            (Join-Path $package.ManifestDir "blocks.csv"),
            (Join-Path $package.ManifestDir "assets.csv"),
            (Join-Path $package.ManifestDir "image_candidates.csv"),
            $reviewsPath
        )
        try {
            $appendCount = 0
            $deadline = [DateTime]::UtcNow.AddSeconds(20)
            while ($checkerJob.State -in @("NotStarted", "Running") -and [DateTime]::UtcNow -lt $deadline) {
                [System.IO.File]::AppendAllText($reviewsPath, [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
                $appendCount++
                Start-Sleep -Milliseconds 2
            }
            Wait-Job -Job $checkerJob -Timeout 5 | Out-Null
            $receiveErrors = @()
            $received = @(Receive-Job -Job $checkerJob -ErrorAction SilentlyContinue -ErrorVariable +receiveErrors)
            $combined = (($received + $receiveErrors) | Out-String)
            Assert-True ($appendCount -gt 1) "Expected the concurrent writer to change the manifest more than once."
            Assert-True ($combined -match "Validation input changed before status commit: Reviews") "Expected a changed review manifest to abort the commit."
            Assert-True ((Get-FileHash -LiteralPath $jobPath -Algorithm SHA256).Hash -eq $beforeHash) "Expected concurrent input change to preserve job.csv."
        } finally {
            Remove-Job -Job $checkerJob -Force -ErrorAction SilentlyContinue
        }
    }

    Invoke-TestCase "atomic replacement failure preserves the original job manifest" {
        $package = New-ValidPackage -Name "locked-status-commit" -PdfPath $pdfPath
        $jobPath = Join-Path $package.ManifestDir "job.csv"
        $beforeHash = (Get-FileHash -LiteralPath $jobPath -Algorithm SHA256).Hash
        $stream = [System.IO.File]::Open($jobPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $failed = $false
        try {
            try {
                & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath (Join-Path $package.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural -CommitStatus | Out-Null
            } catch {
                $failed = $true
            }
        } finally {
            $stream.Dispose()
        }
        Assert-True $failed "Expected a locked destination to reject atomic status replacement."
        Assert-True ((Get-FileHash -LiteralPath $jobPath -Algorithm SHA256).Hash -eq $beforeHash) "Expected atomic replacement failure to preserve job.csv byte-for-byte."
    }

    Invoke-TestCase "lifecycle helper enforces legal forward-only workflow events" {
        $package = New-ValidPackage -Name "lifecycle-events" -PdfPath $pdfPath
        $jobPath = Join-Path $package.ManifestDir "job.csv"
        $helperPath = Join-Path $scriptRoot "update_transcription_job_status.ps1"
        $beforeInvalidHash = (Get-FileHash -LiteralPath $jobPath -Algorithm SHA256).Hash
        $failed = $false
        try {
            & $helperPath -JobManifestPath $jobPath -Event ReviewStarted | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "StructuralStatus=structurally-valid"
        }
        Assert-True $failed "Expected ReviewStarted before structural validation to fail."
        Assert-True ((Get-FileHash -LiteralPath $jobPath -Algorithm SHA256).Hash -eq $beforeInvalidHash) "Expected an illegal event not to modify job.csv."

        $job = Import-Csv -LiteralPath $jobPath
        $job.TranscriptionStatus = "initialized"
        $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8
        & $helperPath -JobManifestPath $jobPath -Event TranscriptionCompleted | Out-Null
        $job = Import-Csv -LiteralPath $jobPath
        Assert-True ($job.TranscriptionStatus -eq "transcribed") "Expected TranscriptionCompleted to advance initialized transcription."

        & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath (Join-Path $package.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural -CommitStatus | Out-Null
        & $helperPath -JobManifestPath $jobPath -Event ReviewerUnavailable | Out-Null
        $job = Import-Csv -LiteralPath $jobPath
        Assert-True ($job.ReviewStatus -eq "review-pending" -and $job.FinalStatus -eq "review-pending") "Expected ReviewerUnavailable to synchronize pending review and final states."
        & $helperPath -JobManifestPath $jobPath -Event ReviewStarted | Out-Null
        $job = Import-Csv -LiteralPath $jobPath
        Assert-True ($job.ReviewStatus -eq "reviewing" -and $job.FinalStatus -eq "initialized") "Expected ReviewStarted to resume a pending review."
        & $helperPath -JobManifestPath $jobPath -Event CorrectionRequired | Out-Null
        $job = Import-Csv -LiteralPath $jobPath
        Assert-True ($job.TranscriptionStatus -eq "needs-correction" -and $job.ReviewStatus -eq "needs-correction") "Expected CorrectionRequired to mark both active stages."
        $beforeInvalidHash = (Get-FileHash -LiteralPath $jobPath -Algorithm SHA256).Hash
        $failed = $false
        try {
            & $helperPath -JobManifestPath $jobPath -Event TranscriptionCompleted | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "CorrectionApplied"
        }
        Assert-True $failed "Expected correction recovery to reject TranscriptionCompleted."
        Assert-True ((Get-FileHash -LiteralPath $jobPath -Algorithm SHA256).Hash -eq $beforeInvalidHash) "Expected a rejected correction event not to split lifecycle fields."
        & $helperPath -JobManifestPath $jobPath -Event CorrectionApplied | Out-Null
        $job = Import-Csv -LiteralPath $jobPath
        Assert-True ($job.TranscriptionStatus -eq "transcribed" -and $job.ReviewStatus -eq "reviewing") "Expected CorrectionApplied to resume review."
        & $helperPath -JobManifestPath $jobPath -Event UserReviewRequired | Out-Null
        $job = Import-Csv -LiteralPath $jobPath
        Assert-True ($job.TranscriptionStatus -eq "needs-user-review" -and $job.ReviewStatus -eq "needs-user-review" -and $job.FinalStatus -eq "needs-user-review") "Expected UserReviewRequired to synchronize all terminal uncertainty states."
        $failed = $false
        try {
            & $helperPath -JobManifestPath $jobPath -Event ReviewStarted | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "terminal"
        }
        Assert-True $failed "Expected workflow events after needs-user-review to be rejected."
    }

    Invoke-TestCase "lifecycle failure events affect only their stage and Final" {
        $cases = @(
            @{ Event = "FailTranscription"; Field = "TranscriptionStatus" },
            @{ Event = "FailStructural"; Field = "StructuralStatus" },
            @{ Event = "FailReview"; Field = "ReviewStatus" },
            @{ Event = "FailFinal"; Field = "FinalStatus" }
        )
        foreach ($case in $cases) {
            $package = New-ValidPackage -Name ("lifecycle-" + $case.Event.ToLowerInvariant()) -PdfPath $pdfPath
            $jobPath = Join-Path $package.ManifestDir "job.csv"
            $before = Import-Csv -LiteralPath $jobPath
            & (Join-Path $scriptRoot "update_transcription_job_status.ps1") -JobManifestPath $jobPath -Event $case.Event | Out-Null
            $after = Import-Csv -LiteralPath $jobPath
            Assert-True ($after.($case.Field) -eq "failed" -and $after.FinalStatus -eq "failed") "Expected $($case.Event) to fail its stage and Final."
            foreach ($field in @("TranscriptionStatus", "StructuralStatus", "ReviewStatus")) {
                if ($field -ne $case.Field) {
                    Assert-True ($after.$field -eq $before.$field) "Expected $($case.Event) to preserve successful or untouched stage '$field'."
                }
            }
        }
    }

    Invoke-TestCase "final validation requires a fresh full-coverage review" {
        $withoutReview = New-ValidPackage -Name "final-missing-review" -PdfPath $pdfPath
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $withoutReview.MarkdownPath -JobManifestPath (Join-Path $withoutReview.ManifestDir "job.csv") -BlockManifestPath (Join-Path $withoutReview.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $withoutReview.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $withoutReview.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $withoutReview.ManifestDir "review_findings.csv") -Phase Final | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "review coverage"
        }
        Assert-True $failed "Expected final validation to reject missing review coverage."

        $withReview = New-ValidPackage -Name "final-valid" -PdfPath $pdfPath -IncludeReview
        $result = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $withReview.MarkdownPath -JobManifestPath (Join-Path $withReview.ManifestDir "job.csv") -BlockManifestPath (Join-Path $withReview.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $withReview.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $withReview.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $withReview.ManifestDir "review_findings.csv") -Phase Final
        Assert-True ($result.Status -eq "verified") "Expected final validation with fresh full coverage to pass."
    }

    Invoke-TestCase "renderer retains deterministic 300 and 400 DPI page versions" {
        $renderDir = Join-Path $fixtureRoot "rendered-pages"
        $pages300 = @(& (Join-Path $scriptRoot "render_pdf_pages.ps1") -InputPdf $pdfPath -OutputDir $renderDir -Dpi 300 -Clean)
        $page400 = @(& (Join-Path $scriptRoot "render_pdf_pages.ps1") -InputPdf $pdfPath -OutputDir $renderDir -Dpi 400 -FirstPage 1 -LastPage 1)
        Assert-True ($pages300.Count -eq 2) "Expected two 300 DPI rendered pages."
        Assert-True ($page400.Count -eq 1) "Expected one 400 DPI rendered page."
        Assert-True ($pages300[0].FullName -match 'page-0001-300dpi\.png$') "Expected a DPI-qualified first page filename."
        Assert-True ($pages300[1].FullName -match 'page-0002-300dpi\.png$') "Expected a DPI-qualified second page filename."
        Assert-True ($page400[0].FullName -match 'page-0001-400dpi\.png$') "Expected a DPI-qualified 400 DPI filename."
        Assert-True ($pages300[0].AssetId -eq "page-0001-300dpi") "Expected AssetId to match the 300 DPI page identity."
        Assert-True ($page400[0].AssetId -eq "page-0001-400dpi") "Expected AssetId to match the 400 DPI page identity."
        Assert-True ($pages300[0].Sha256 -match '^[A-Fa-f0-9]{64}$') "Expected a rendered-page SHA-256 digest."
        Assert-True ((Get-ChildItem -LiteralPath $renderDir -File).Count -eq 3) "Expected both 300 DPI pages and the 400 DPI first page to remain."
    }

    Invoke-TestCase "renderer conflict and range clean leave no raw or unrelated page loss" {
        $renderDir = Join-Path $fixtureRoot "rendered-page-cleaning"
        & (Join-Path $scriptRoot "render_pdf_pages.ps1") -InputPdf $pdfPath -OutputDir $renderDir -Dpi 300 -Clean | Out-Null
        & (Join-Path $scriptRoot "render_pdf_pages.ps1") -InputPdf $pdfPath -OutputDir $renderDir -Dpi 400 -FirstPage 1 -LastPage 2 | Out-Null

        $failed = $false
        try {
            & (Join-Path $scriptRoot "render_pdf_pages.ps1") -InputPdf $pdfPath -OutputDir $renderDir -Dpi 300 | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "Refusing to replace"
        }
        Assert-True $failed "Expected a same-DPI target conflict without -Clean to fail."
        Assert-True (@(Get-ChildItem -LiteralPath $renderDir -File | Where-Object { $_.Name -match '^page-\d+\.png$' }).Count -eq 0) "Expected no raw Poppler pages after a conflict."

        $untouchedPageHash = (Get-FileHash -LiteralPath (Join-Path $renderDir "page-0002-400dpi.png") -Algorithm SHA256).Hash
        Copy-Item -LiteralPath (Join-Path $renderDir "page-0001-400dpi.png") -Destination (Join-Path $renderDir "alternate-0001-400dpi.png")
        & (Join-Path $scriptRoot "render_pdf_pages.ps1") -InputPdf $pdfPath -OutputDir $renderDir -Dpi 400 -FirstPage 1 -LastPage 1 -Clean | Out-Null
        foreach ($name in @("page-0001-300dpi.png", "page-0002-300dpi.png", "page-0001-400dpi.png", "page-0002-400dpi.png")) {
            Assert-True (Test-Path -LiteralPath (Join-Path $renderDir $name)) "Expected range clean to preserve or replace $name."
        }
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $renderDir "page-0002-400dpi.png") -Algorithm SHA256).Hash -eq $untouchedPageHash) "Expected range clean not to replace an unrequested page."
        Assert-True (Test-Path -LiteralPath (Join-Path $renderDir "alternate-0001-400dpi.png")) "Expected range clean not to remove a different prefix."
        Assert-True (@(Get-ChildItem -LiteralPath $renderDir -Directory -Filter ".render-*" -ErrorAction SilentlyContinue).Count -eq 0) "Expected renderer staging directories to be cleaned."

        $stalePagePath = Join-Path $renderDir "page-0003-300dpi.png"
        & magick -size 37x37 xc:blue $stalePagePath
        $stalePageHash = (Get-FileHash -LiteralPath $stalePagePath -Algorithm SHA256).Hash
        $failed = $false
        try {
            & (Join-Path $scriptRoot "render_pdf_pages.ps1") -InputPdf $pdfPath -OutputDir $renderDir -Dpi 300 -FirstPage 1 -LastPage 3 -Clean | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "exceeds source page count"
        }
        Assert-True $failed "Expected a requested range beyond the real PDF page count to fail before promotion."
        Assert-True ((Get-FileHash -LiteralPath $stalePagePath -Algorithm SHA256).Hash -eq $stalePageHash) "Expected an invalid clean range not to touch a stale sentinel."

        $first300 = Join-Path $renderDir "page-0001-300dpi.png"
        $second300 = Join-Path $renderDir "page-0002-300dpi.png"
        & magick -size 41x41 xc:red $first300
        $firstHash = (Get-FileHash -LiteralPath $first300 -Algorithm SHA256).Hash
        $secondHash = (Get-FileHash -LiteralPath $second300 -Algorithm SHA256).Hash
        $stream = [System.IO.File]::Open($second300, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $failed = $false
        try {
            try {
                & (Join-Path $scriptRoot "render_pdf_pages.ps1") -InputPdf $pdfPath -OutputDir $renderDir -Dpi 300 -FirstPage 1 -LastPage 2 -Clean | Out-Null
            } catch {
                $failed = $true
            }
        } finally {
            $stream.Dispose()
        }
        Assert-True $failed "Expected a locked target to abort the clean promotion transaction."
        Assert-True ((Test-Path -LiteralPath $first300) -and (Get-FileHash -LiteralPath $first300 -Algorithm SHA256).Hash -eq $firstHash) "Expected a backup-phase failure to restore the first existing target."
        Assert-True ((Get-FileHash -LiteralPath $second300 -Algorithm SHA256).Hash -eq $secondHash) "Expected a backup-phase failure to preserve the locked target."
        Assert-True (@(Get-ChildItem -LiteralPath $renderDir -Directory -Filter ".render-*" -ErrorAction SilentlyContinue).Count -eq 0) "Expected failed promotion staging to be cleaned after rollback."
    }

    Invoke-TestCase "rendered-page manifests enforce the 300 and 400 DPI authority contract" {
        $valid = New-ValidPackage -Name "valid-multi-dpi" -PdfPath $pdfPath
        Add-RenderedPageVersion -Package $valid -PageNumber 1 -Dpi 400 -IsAuthoritative $true
        $assetsPath = Join-Path $valid.ManifestDir "assets.csv"
        $assets = @(Import-Csv -LiteralPath $assetsPath)
        ($assets | Where-Object AssetId -eq "page-0001-300dpi").IsAuthoritative = "false"
        $assets | Export-Csv -LiteralPath $assetsPath -NoTypeInformation -Encoding UTF8
        $blocksPath = Join-Path $valid.ManifestDir "blocks.csv"
        $blocks = @(Import-Csv -LiteralPath $blocksPath)
        $blocks | Where-Object PageAssetId -eq "page-0001-300dpi" | ForEach-Object { $_.PageAssetId = "page-0001-400dpi" }
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8
        $result = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $valid.MarkdownPath -JobManifestPath (Join-Path $valid.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath $assetsPath -ImageCandidateManifestPath (Join-Path $valid.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $valid.ManifestDir "review_findings.csv") -Phase Structural
        Assert-True ($result.Status -eq "structurally-valid") "Expected a retained 300 DPI baseline and authoritative 400 DPI page to pass."

        $missing300 = New-ValidPackage -Name "missing-300-dpi" -PdfPath $pdfPath
        Add-RenderedPageVersion -Package $missing300 -PageNumber 1 -Dpi 400 -IsAuthoritative $true
        $assetsPath = Join-Path $missing300.ManifestDir "assets.csv"
        $assets = @(Import-Csv -LiteralPath $assetsPath | Where-Object AssetId -ne "page-0001-300dpi")
        $assets | Export-Csv -LiteralPath $assetsPath -NoTypeInformation -Encoding UTF8
        Remove-Item -LiteralPath (Join-Path $missing300.OutputRoot "_audit\pages\page-0001-300dpi.png") -Force
        $blocksPath = Join-Path $missing300.ManifestDir "blocks.csv"
        $blocks = @(Import-Csv -LiteralPath $blocksPath)
        $blocks | Where-Object PageAssetId -eq "page-0001-300dpi" | ForEach-Object { $_.PageAssetId = "page-0001-400dpi" }
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $missing300.MarkdownPath -JobManifestPath (Join-Path $missing300.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath $assetsPath -ImageCandidateManifestPath (Join-Path $missing300.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $missing300.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "exactly one 300 DPI"
        }
        Assert-True $failed "Expected a missing 300 DPI baseline to fail."

        $wrongAuthority = New-ValidPackage -Name "wrong-400-authority" -PdfPath $pdfPath
        Add-RenderedPageVersion -Package $wrongAuthority -PageNumber 1 -Dpi 400 -IsAuthoritative $false
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $wrongAuthority.MarkdownPath -JobManifestPath (Join-Path $wrongAuthority.ManifestDir "job.csv") -BlockManifestPath (Join-Path $wrongAuthority.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $wrongAuthority.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $wrongAuthority.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $wrongAuthority.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "400 DPI version must be authoritative"
        }
        Assert-True $failed "Expected a retained 400 DPI page with 300 DPI authority to fail."

        $duplicateDpi = New-ValidPackage -Name "duplicate-page-dpi" -PdfPath $pdfPath
        $assetsPath = Join-Path $duplicateDpi.ManifestDir "assets.csv"
        $assets = @(Import-Csv -LiteralPath $assetsPath)
        $sourcePage = Join-Path $duplicateDpi.OutputRoot "_audit\pages\page-0001-300dpi.png"
        $duplicatePage = Join-Path $duplicateDpi.OutputRoot "_audit\pages\page-0001-300dpi-copy.png"
        Copy-Item -LiteralPath $sourcePage -Destination $duplicatePage
        $duplicate = ($assets | Where-Object AssetId -eq "page-0001-300dpi" | Select-Object -First 1) | Select-Object *
        $duplicate.AssetId = "page-0001-300dpi-copy"
        $duplicate.Path = "_audit\pages\page-0001-300dpi-copy.png"
        $assets += $duplicate
        $assets | Export-Csv -LiteralPath $assetsPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $duplicateDpi.MarkdownPath -JobManifestPath (Join-Path $duplicateDpi.ManifestDir "job.csv") -BlockManifestPath (Join-Path $duplicateDpi.ManifestDir "blocks.csv") -AssetManifestPath $assetsPath -ImageCandidateManifestPath (Join-Path $duplicateDpi.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $duplicateDpi.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "more than one 300 DPI rendered-page asset"
        }
        Assert-True $failed "Expected duplicate same-page same-DPI assets to fail."

        $malformedIdentity = New-ValidPackage -Name "malformed-page-identity" -PdfPath $pdfPath
        $assetsPath = Join-Path $malformedIdentity.ManifestDir "assets.csv"
        $assets = @(Import-Csv -LiteralPath $assetsPath)
        $wrongPagePath = Join-Path $malformedIdentity.OutputRoot "_audit\pages\wrong.png"
        Copy-Item -LiteralPath (Join-Path $malformedIdentity.OutputRoot "_audit\pages\page-0001-300dpi.png") -Destination $wrongPagePath
        ($assets | Where-Object AssetId -eq "page-0001-300dpi").Path = "_audit\pages\wrong.png"
        $assets | Export-Csv -LiteralPath $assetsPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $malformedIdentity.MarkdownPath -JobManifestPath (Join-Path $malformedIdentity.ManifestDir "job.csv") -BlockManifestPath (Join-Path $malformedIdentity.ManifestDir "blocks.csv") -AssetManifestPath $assetsPath -ImageCandidateManifestPath (Join-Path $malformedIdentity.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $malformedIdentity.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "identity, path, PageNumber, and DPI must match"
        }
        Assert-True $failed "Expected a malformed rendered-page identity or path to fail."

        $nonAuthoritativeBlock = New-ValidPackage -Name "non-authoritative-block-reference" -PdfPath $pdfPath
        Add-RenderedPageVersion -Package $nonAuthoritativeBlock -PageNumber 1 -Dpi 400 -IsAuthoritative $true
        $assetsPath = Join-Path $nonAuthoritativeBlock.ManifestDir "assets.csv"
        $assets = @(Import-Csv -LiteralPath $assetsPath)
        ($assets | Where-Object AssetId -eq "page-0001-300dpi").IsAuthoritative = "false"
        $assets | Export-Csv -LiteralPath $assetsPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $nonAuthoritativeBlock.MarkdownPath -JobManifestPath (Join-Path $nonAuthoritativeBlock.ManifestDir "job.csv") -BlockManifestPath (Join-Path $nonAuthoritativeBlock.ManifestDir "blocks.csv") -AssetManifestPath $assetsPath -ImageCandidateManifestPath (Join-Path $nonAuthoritativeBlock.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $nonAuthoritativeBlock.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "Block 'b001' must reference the authoritative rendered-page asset"
        }
        Assert-True $failed "Expected a block reference to a retained non-authoritative page to fail."

        $nonAuthoritativeReview = New-ValidPackage -Name "non-authoritative-review-reference" -PdfPath $pdfPath -IncludeReview
        Add-RenderedPageVersion -Package $nonAuthoritativeReview -PageNumber 1 -Dpi 400 -IsAuthoritative $true
        $assetsPath = Join-Path $nonAuthoritativeReview.ManifestDir "assets.csv"
        $assets = @(Import-Csv -LiteralPath $assetsPath)
        ($assets | Where-Object AssetId -eq "page-0001-300dpi").IsAuthoritative = "false"
        $assets | Export-Csv -LiteralPath $assetsPath -NoTypeInformation -Encoding UTF8
        $blocksPath = Join-Path $nonAuthoritativeReview.ManifestDir "blocks.csv"
        $blocks = @(Import-Csv -LiteralPath $blocksPath)
        $blocks | Where-Object PageAssetId -eq "page-0001-300dpi" | ForEach-Object { $_.PageAssetId = "page-0001-400dpi" }
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8
        $reviewsPath = Join-Path $nonAuthoritativeReview.ManifestDir "review_findings.csv"
        $reviews = @(Import-Csv -LiteralPath $reviewsPath)
        $reviews | Where-Object PageAssetId -eq "page-0001-300dpi" | ForEach-Object { $_.PageAssetId = "page-0001-400dpi" }
        ($reviews | Where-Object TargetId -eq "b001").PageAssetId = "page-0001-300dpi"
        $reviews | Export-Csv -LiteralPath $reviewsPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $nonAuthoritativeReview.MarkdownPath -JobManifestPath (Join-Path $nonAuthoritativeReview.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath $assetsPath -ImageCandidateManifestPath (Join-Path $nonAuthoritativeReview.ManifestDir "image_candidates.csv") -ReviewManifestPath $reviewsPath -Phase Final | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "Review 'review-b001' must reference the authoritative rendered-page asset"
        }
        Assert-True $failed "Expected a review finding to reference the authoritative page version."
    }

    Invoke-TestCase "typed crop gate accepts a formula fallback decision" {
        $package = New-ValidPackage -Name "typed-crop" -PdfPath $pdfPath
        $inputPage = Join-Path $package.OutputRoot "_audit\pages\page-0001-300dpi.png"
        $outputImage = Join-Path $package.OutputRoot "assets\formulas\formula2.png"
        $assetsPath = Join-Path $package.ManifestDir "assets.csv"
        $assets = @(Import-Csv -LiteralPath $assetsPath)
        $assets += [pscustomobject][ordered]@{
            SchemaVersion="2"; AssetId="formula-002"; AssetType="formula"; RelatedBlockId="b003"; PageNumber="2"; Path="assets\formulas\formula2.png"; Sha256=""; Bytes=""; Width=""; Height=""; Dpi="300"; IsAuthoritative="true"; SourceMethod="page-crop"; DerivedFromCandidateIds=""; VisualMatch="fallback-authoritative"; FallbackReason="LaTeX uncertain"; PlacementRule="formula-location"; FirstCitationAnchor=""; CaptionAnchor=""; TranscriberChecked=""; Notes="pending crop"
        }
        $assets | Export-Csv -LiteralPath $assetsPath -NoTypeInformation -Encoding UTF8
        $result = & (Join-Path $scriptRoot "crop_pdf_region.ps1") -InputImage $inputPage -OutputImage $outputImage -Geometry "100x100+0+0" -MinWidth 100 -MinHeight 100 -AssetManifestPath $assetsPath -AssetId "formula-002" -RequireManifestDecision
        Assert-True ($result.AssetType -eq "formula") "Expected a formula crop result."
        Assert-True ($result.Sha256 -match '^[A-Fa-f0-9]{64}$') "Expected a crop SHA-256 digest."
    }

    Invoke-TestCase "embedded text extraction requires explicit authorization" {
        $draftPath = Join-Path $fixtureRoot "embedded-draft.txt"
        $failed = $false
        try {
            & (Join-Path $scriptRoot "extract_pdf_text_layer.ps1") -InputPdf $pdfPath -OutputPath $draftPath | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "explicit authorization"
        }
        Assert-True $failed "Expected text-layer extraction to require explicit authorization."
        $result = & (Join-Path $scriptRoot "extract_pdf_text_layer.ps1") -InputPdf $pdfPath -OutputPath $draftPath -UserAuthorized
        Assert-True (Test-Path -LiteralPath $draftPath) "Expected an embedded-text draft file."
        Assert-True ($result.Sha256 -match '^[A-Fa-f0-9]{64}$') "Expected a draft SHA-256 digest."
        Assert-True ((Get-Content -LiteralPath $draftPath -Raw) -match "Page 1") "Expected the extracted draft to contain fixture text."
    }

    Invoke-TestCase "user OCR mode archives only a user-provided draft" {
        $ocrPath = Join-Path $fixtureRoot "provided-ocr.txt"
        [System.IO.File]::WriteAllText($ocrPath, "User supplied OCR draft", [System.Text.UTF8Encoding]::new($false))
        $outputRoot = Join-Path $fixtureRoot "user-ocr-job"
        & (Join-Path $scriptRoot "new_transcription_job.ps1") -InputPdf $pdfPath -OutputRoot $outputRoot -SourceMode user-ocr-assisted -UserOcrPath $ocrPath | Out-Null
        $job = Import-Csv -LiteralPath (Join-Path $outputRoot "_audit\manifests\job.csv")
        Assert-True ($job.DraftProducer -eq "user-provided") "Expected user-provided draft provenance."
        Assert-True ($job.CodexInvokedOcr -eq "false") "Expected CodexInvokedOcr=false."
        $archivedDraft = Join-Path $outputRoot $job.DraftRelativePath
        Assert-True (Test-Path -LiteralPath $archivedDraft) "Expected the provided OCR draft to be archived."
        Assert-True ((Get-FileHash $archivedDraft -Algorithm SHA256).Hash.ToLowerInvariant() -eq $job.DraftSha256) "Expected the archived OCR hash to match job.csv."
    }

    Invoke-TestCase "structural validation rejects missing rendered pages and v1 manifests" {
        $missingPage = New-ValidPackage -Name "missing-page" -PdfPath $pdfPath
        Remove-Item -LiteralPath (Join-Path $missingPage.OutputRoot "_audit\pages\page-0002-300dpi.png") -Force
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $missingPage.MarkdownPath -JobManifestPath (Join-Path $missingPage.ManifestDir "job.csv") -BlockManifestPath (Join-Path $missingPage.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $missingPage.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $missingPage.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $missingPage.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "path does not resolve"
        }
        Assert-True $failed "Expected a missing rendered page to fail."

        $v1 = New-ValidPackage -Name "v1-schema" -PdfPath $pdfPath
        $jobPath = Join-Path $v1.ManifestDir "job.csv"
        $job = Import-Csv -LiteralPath $jobPath
        $job.SchemaVersion = "1"
        $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $v1.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath (Join-Path $v1.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $v1.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $v1.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $v1.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "v1 is not accepted"
        }
        Assert-True $failed "Expected v1 schema to be rejected explicitly."
    }

    Invoke-TestCase "numbered formulas require an actual Markdown tag" {
        $package = New-ValidPackage -Name "numbered-formula" -PdfPath $pdfPath
        $blocksPath = Join-Path $package.ManifestDir "blocks.csv"
        $blocks = @(Import-Csv -LiteralPath $blocksPath)
        $formula = $blocks | Where-Object BlockId -eq "b003"
        $formula.Numbering = "numbered"
        $formula.VisualNumber = "1"
        $formula.MarkdownTag = "1"
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "MarkdownTag is absent"
        }
        Assert-True $failed "Expected a missing formula tag to fail."

        $markdown = Get-Content -LiteralPath $package.MarkdownPath -Raw
        $markdown = $markdown -replace '\\alpha \+ \\beta', '\alpha + \beta \tag{1}'
        [System.IO.File]::WriteAllText($package.MarkdownPath, $markdown, [System.Text.UTF8Encoding]::new($false))
        $formula.MarkdownAnchor = "\[`n\alpha + \beta \tag{1}`n\]"
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8
        $result = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural
        Assert-True ($result.Status -eq "structurally-valid") "Expected a numbered formula with a matching tag to pass."
    }

    Invoke-TestCase "reference exclusion rejects the recorded heading in any language and line ending" {
        $headingCases = @(
            [pscustomobject]@{ Recorded = "参考文献"; Rendered = "参考文献"; Label = "Chinese exact" },
            [pscustomobject]@{ Recorded = "Références"; Rendered = "Références"; Label = "French exact" },
            [pscustomobject]@{ Recorded = "Literaturverzeichnis"; Rendered = "Literaturverzeichnis"; Label = "German exact" },
            [pscustomobject]@{ Recorded = "参考 文献"; Rendered = "参考    文献"; Label = "multiple spaces" },
            [pscustomobject]@{ Recorded = "参考 文献"; Rendered = "参考`t文献"; Label = "tab" }
        )
        foreach ($headingCase in $headingCases) {
            foreach ($headingStyle in @("ATX", "Setext")) {
                foreach ($lineEnding in @("LF", "CRLF")) {
                    $package = New-ValidPackage -Name ("reference-heading-" + [guid]::NewGuid().ToString("N")) -PdfPath $pdfPath
                    $headingMarkdown = $(if ($headingStyle -eq "ATX") { "## $($headingCase.Rendered)" } else { "$($headingCase.Rendered)`n---" })
                    $markdown = Get-Content -LiteralPath $package.MarkdownPath -Raw
                    $markdown = $markdown.Replace("Body cites (1).", "Body cites (1).`n`n$headingMarkdown")
                    if ($lineEnding -eq "CRLF") {
                        $markdown = $markdown -replace "`r?`n", "`r`n"
                    }
                    [System.IO.File]::WriteAllText($package.MarkdownPath, $markdown, [System.Text.UTF8Encoding]::new($false))
                    $jobPath = Join-Path $package.ManifestDir "job.csv"
                    $job = Import-Csv -LiteralPath $jobPath
                    $job.CutoffHeading = $headingCase.Recorded
                    $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8
                    $blocksPath = Join-Path $package.ManifestDir "blocks.csv"
                    $blocks = @(Import-Csv -LiteralPath $blocksPath)
                    $cutoff = $blocks | Where-Object BlockType -eq "reference-cutoff"
                    $cutoff.VisualFirstWords = $headingCase.Recorded
                    $cutoff.VisualLastWords = $headingCase.Recorded
                    $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8

                    $failed = $false
                    try {
                        & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
                    } catch {
                        $failed = $_.Exception.Message -match "recorded reference heading"
                    }
                    Assert-True $failed "Expected $($headingCase.Label) recorded heading with $headingStyle and $lineEnding to fail."
                }
            }
        }
    }

    Invoke-TestCase "structural validation rejects semantic Markdown outside block and asset coverage" {
        $package = New-ValidPackage -Name "untracked-interior-markdown" -PdfPath $pdfPath
        $markdown = Get-Content -LiteralPath $package.MarkdownPath -Raw
        $markdown = $markdown.Replace(
            "Body cites (1).",
            "Body cites (1).`n`n[1] Untracked bibliography entry, 2026."
        )
        [System.IO.File]::WriteAllText($package.MarkdownPath, $markdown, [System.Text.UTF8Encoding]::new($false))

        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath (Join-Path $package.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "outside represented block or final asset coverage"
        }
        Assert-True $failed "Expected untracked semantic Markdown before the terminal block anchor to fail."

        $swallowed = New-ValidPackage -Name "untracked-interior-anchor-swallow" -PdfPath $pdfPath
        $markdown = Get-Content -LiteralPath $swallowed.MarkdownPath -Raw
        $markdown = $markdown.Replace(
            "Body cites (1).",
            "Body cites (1).`n`n[1] Untracked bibliography entry, 2026."
        )
        [System.IO.File]::WriteAllText($swallowed.MarkdownPath, $markdown, [System.Text.UTF8Encoding]::new($false))
        $blocksPath = Join-Path $swallowed.ManifestDir "blocks.csv"
        $blocks = @(Import-Csv -LiteralPath $blocksPath)
        ($blocks | Where-Object BlockId -eq "b002").MarkdownAnchor = "Body cites (1).`n`n[1] Untracked bibliography entry, 2026."
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8

        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $swallowed.MarkdownPath -JobManifestPath (Join-Path $swallowed.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $swallowed.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $swallowed.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $swallowed.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "continues past its VisualLastWords boundary"
        }
        Assert-True $failed "Expected an interior block anchor not to absorb undeclared semantic Markdown."
    }

    Invoke-TestCase "reference cutoff must be the final block in Structural and Final" {
        foreach ($phase in @("Structural", "Final")) {
            $package = New-ValidPackage -Name ("post-cutoff-" + $phase.ToLowerInvariant()) -PdfPath $pdfPath -IncludeReview
            [System.IO.File]::AppendAllText($package.MarkdownPath, "`nBibliography entry after cutoff.`n", [System.Text.UTF8Encoding]::new($false))
            $blocksPath = Join-Path $package.ManifestDir "blocks.csv"
            $blocks = @(Import-Csv -LiteralPath $blocksPath)
            $blocks += [pscustomobject][ordered]@{
                SchemaVersion="2"; BlockId="b005"; LogicalBlockId="l005"; Sequence="5"; PageAssetId="page-0002-300dpi"; Region="bibliography"; Continuation="single"; BlockType="paragraph"; Section="references"; VisualFirstWords="Bibliography"; VisualLastWords="cutoff."; MarkdownAnchor="Bibliography entry after cutoff."; Representation="markdown"; DraftFirstWords=""; DraftLastWords=""; CorrectionsMade=""; Numbering="not-applicable"; VisualNumber=""; MarkdownTag=""; FallbackAssetId=""; TranscriberChecked="checked"; Uncertainty="none"; Notes=""
            }
            $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8
            $reviewsPath = Join-Path $package.ManifestDir "review_findings.csv"
            $reviews = @(Import-Csv -LiteralPath $reviewsPath)
            $reviews += [pscustomobject][ordered]@{
                SchemaVersion="2"; ReviewId="review-b005"; ReviewerRunId="fresh-reviewer-1"; ReviewerContext="fresh"; TargetType="block"; TargetId="b005"; PageAssetId="page-0002-300dpi"; Outcome="pass"; Category="coverage"; Expected="matches rendered page"; Actual="matches"; EvidencePath=""; Blocking="false"; Cycle="1"; Resolution="closed"; RecheckOutcome="pass"; Notes=""
            }
            $reviews | Export-Csv -LiteralPath $reviewsPath -NoTypeInformation -Encoding UTF8

            $failed = $false
            try {
                & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath $reviewsPath -Phase $phase | Out-Null
            } catch {
                $failed = $_.Exception.Message -match "reference-cutoff block must be the final block"
            }
            Assert-True $failed "Expected a represented block after cutoff to fail in $phase."
        }
    }

    Invoke-TestCase "reference exclusion rejects untracked Markdown after the terminal anchor" {
        $package = New-ValidPackage -Name "reference-terminal-anchor" -PdfPath $pdfPath
        [System.IO.File]::AppendAllText($package.MarkdownPath, "`nUntracked bibliography entry.`n", [System.Text.UTF8Encoding]::new($false))
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath (Join-Path $package.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "last included MarkdownAnchor must end at the final non-whitespace character"
        }
        Assert-True $failed "Expected trailing untracked Markdown to fail reference exclusion."
    }

    Invoke-TestCase "reference exclusion permits only explicit blank pages before the terminal cutoff" {
        $package = New-ValidPackage -Name "reference-blank-page" -PdfPath $pdfPath
        $blocksPath = Join-Path $package.ManifestDir "blocks.csv"
        $blocks = @(Import-Csv -LiteralPath $blocksPath)
        ($blocks | Where-Object BlockId -eq "b004").Sequence = "5"
        $blocks += [pscustomobject][ordered]@{
            SchemaVersion="2"; BlockId="b005"; LogicalBlockId="l005"; Sequence="4"; PageAssetId="page-0002-300dpi"; Region="full-page"; Continuation="single"; BlockType="blank-page"; Section="references"; VisualFirstWords="blank page"; VisualLastWords="blank page"; MarkdownAnchor=""; Representation="none"; DraftFirstWords=""; DraftLastWords=""; CorrectionsMade=""; Numbering="not-applicable"; VisualNumber=""; MarkdownTag=""; FallbackAssetId=""; TranscriberChecked="checked"; Uncertainty="none"; Notes="explicit blank page"
        }
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8

        $result = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural
        Assert-True ($result.Status -eq "structurally-valid") "Expected an explicit non-represented blank page between content and cutoff to pass."
        Assert-True ((Get-Content -LiteralPath $package.MarkdownPath -Raw) -match [regex]::Escape("Body cites (1).")) "Expected in-text citations to remain under exclude policy."
    }

    Invoke-TestCase "reference exclusion binds LastIncludedBlockId to the final represented block" {
        $package = New-ValidPackage -Name "reference-wrong-last-included" -PdfPath $pdfPath
        $jobPath = Join-Path $package.ManifestDir "job.csv"
        $job = Import-Csv -LiteralPath $jobPath
        $job.LastIncludedBlockId = "b002"
        $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath (Join-Path $package.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "LastIncludedBlockId must identify the final represented block"
        }
        Assert-True $failed "Expected a stale LastIncludedBlockId to fail."
    }

    Invoke-TestCase "reference exclusion rejects represented bibliography scope and anchor swallowing" {
        $represented = New-ValidPackage -Name "reference-represented-before-cutoff" -PdfPath $pdfPath
        [System.IO.File]::AppendAllText($represented.MarkdownPath, "`n1. Bibliography entry.`n", [System.Text.UTF8Encoding]::new($false))
        $blocksPath = Join-Path $represented.ManifestDir "blocks.csv"
        $blocks = @(Import-Csv -LiteralPath $blocksPath)
        ($blocks | Where-Object BlockId -eq "b004").Sequence = "5"
        $blocks += [pscustomobject][ordered]@{
            SchemaVersion="2"; BlockId="b005"; LogicalBlockId="l005"; Sequence="4"; PageAssetId="page-0002-300dpi"; Region="reference-entry"; Continuation="single"; BlockType="paragraph"; Section="references"; VisualFirstWords="1. Bibliography"; VisualLastWords="entry."; MarkdownAnchor="1. Bibliography entry."; Representation="markdown"; DraftFirstWords=""; DraftLastWords=""; CorrectionsMade=""; Numbering="not-applicable"; VisualNumber=""; MarkdownTag=""; FallbackAssetId=""; TranscriberChecked="checked"; Uncertainty="none"; Notes=""
        }
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8
        $jobPath = Join-Path $represented.ManifestDir "job.csv"
        $job = Import-Csv -LiteralPath $jobPath
        $job.LastIncludedBlockId = "b005"
        $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $represented.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $represented.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $represented.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $represented.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "exclude must not contain represented Section=references blocks"
        }
        Assert-True $failed "Expected exclude policy to reject a represented bibliography block even before the cutoff row."

        $swallowed = New-ValidPackage -Name "reference-anchor-swallow" -PdfPath $pdfPath
        [System.IO.File]::AppendAllText($swallowed.MarkdownPath, "`n1. Hidden bibliography entry.`n", [System.Text.UTF8Encoding]::new($false))
        $blocksPath = Join-Path $swallowed.ManifestDir "blocks.csv"
        $blocks = @(Import-Csv -LiteralPath $blocksPath)
        ($blocks | Where-Object BlockId -eq "b003").MarkdownAnchor = "\[`n\alpha + \beta`n\]`n`n1. Hidden bibliography entry."
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $swallowed.MarkdownPath -JobManifestPath (Join-Path $swallowed.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $swallowed.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $swallowed.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $swallowed.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "continues past its VisualLastWords boundary"
        }
        Assert-True $failed "Expected a terminal anchor not to absorb unrecorded bibliography text."
    }

    Invoke-TestCase "reference keep mode requires represented heading and entry coverage" {
        $package = New-ValidPackage -Name "reference-keep-empty" -PdfPath $pdfPath
        $jobPath = Join-Path $package.ManifestDir "job.csv"
        $job = Import-Csv -LiteralPath $jobPath
        $job.ReferencePolicy = "keep"
        $job.CutoffPage = ""
        $job.CutoffHeading = ""
        $job.LastIncludedBlockId = ""
        $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8
        $blocksPath = Join-Path $package.ManifestDir "blocks.csv"
        $blocks = @(Import-Csv -LiteralPath $blocksPath | Where-Object BlockType -ne "reference-cutoff")
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "keep requires represented bibliography heading and entry blocks"
        }
        Assert-True $failed "Expected keep mode not to certify a package with no bibliography coverage."
    }

    Invoke-TestCase "reference keep mode allows ordinary bibliography blocks and rejects cutoff residue" {
        $package = New-ValidPackage -Name "reference-keep" -PdfPath $pdfPath
        [System.IO.File]::AppendAllText($package.MarkdownPath, "`n# References`n`n1. Example entry.`n", [System.Text.UTF8Encoding]::new($false))
        $jobPath = Join-Path $package.ManifestDir "job.csv"
        $job = Import-Csv -LiteralPath $jobPath
        $job.ReferencePolicy = "keep"
        $job.CutoffPage = ""
        $job.CutoffHeading = ""
        $job.LastIncludedBlockId = ""
        $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8
        $blocksPath = Join-Path $package.ManifestDir "blocks.csv"
        $blocks = @(Import-Csv -LiteralPath $blocksPath | Where-Object BlockType -ne "reference-cutoff")
        $blocks += [pscustomobject][ordered]@{
            SchemaVersion="2"; BlockId="b005"; LogicalBlockId="l005"; Sequence="4"; PageAssetId="page-0002-300dpi"; Region="reference-heading"; Continuation="single"; BlockType="heading"; Section="references"; VisualFirstWords="References"; VisualLastWords="References"; MarkdownAnchor="# References"; Representation="markdown"; DraftFirstWords=""; DraftLastWords=""; CorrectionsMade=""; Numbering="not-applicable"; VisualNumber=""; MarkdownTag=""; FallbackAssetId=""; TranscriberChecked="checked"; Uncertainty="none"; Notes=""
        }
        $blocks += [pscustomobject][ordered]@{
            SchemaVersion="2"; BlockId="b006"; LogicalBlockId="l006"; Sequence="5"; PageAssetId="page-0002-300dpi"; Region="reference-entry"; Continuation="single"; BlockType="paragraph"; Section="references"; VisualFirstWords="1. Example"; VisualLastWords="entry."; MarkdownAnchor="1. Example entry."; Representation="markdown"; DraftFirstWords=""; DraftLastWords=""; CorrectionsMade=""; Numbering="not-applicable"; VisualNumber=""; MarkdownTag=""; FallbackAssetId=""; TranscriberChecked="checked"; Uncertainty="none"; Notes=""
        }
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8

        $result = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural
        Assert-True ($result.Status -eq "structurally-valid") "Expected keep mode to accept represented bibliography heading and entries."

        $job = Import-Csv -LiteralPath $jobPath
        $job.CutoffPage = "2"
        $job.CutoffHeading = "References"
        $job.LastIncludedBlockId = "b003"
        $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "keep requires empty cutoff fields"
        }
        Assert-True $failed "Expected keep mode to reject residual cutoff fields."

        $job.CutoffPage = ""
        $job.CutoffHeading = ""
        $job.LastIncludedBlockId = ""
        $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8
        $blocks += [pscustomobject][ordered]@{
            SchemaVersion="2"; BlockId="b007"; LogicalBlockId="l007"; Sequence="6"; PageAssetId="page-0002-300dpi"; Region="cutoff"; Continuation="single"; BlockType="reference-cutoff"; Section="references"; VisualFirstWords="References"; VisualLastWords="References"; MarkdownAnchor=""; Representation="none"; DraftFirstWords=""; DraftLastWords=""; CorrectionsMade=""; Numbering="not-applicable"; VisualNumber=""; MarkdownTag=""; FallbackAssetId=""; TranscriberChecked="checked"; Uncertainty="none"; Notes=""
        }
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath $blocksPath -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "must not contain a reference-cutoff block"
        }
        Assert-True $failed "Expected keep mode to reject a residual reference-cutoff block."
    }

    Invoke-TestCase "direct-export figure requires a chosen candidate and first-citation placement" {
        $package = New-ValidPackage -Name "direct-figure" -PdfPath $pdfPath
        [System.IO.File]::AppendAllText($package.MarkdownPath, "`nAs shown in Fig. 1, the result is clear.`n`n![Figure 1](assets/figures/fig1.png)`n`n**Fig. 1.** Result.`n", [System.Text.UTF8Encoding]::new($false))
        $figurePath = Join-Path $package.OutputRoot "assets\figures\fig1.png"
        $candidatePath = Join-Path $package.OutputRoot "_audit\candidates\candidate-0001.png"
        & magick -size 300x200 xc:white $figurePath
        Copy-Item -LiteralPath $figurePath -Destination $candidatePath

        $blocksPath = Join-Path $package.ManifestDir "blocks.csv"
        $blocks = @(Import-Csv -LiteralPath $blocksPath)
        ($blocks | Where-Object BlockId -eq "b004").Sequence = "6"
        $blocks += [pscustomobject][ordered]@{
            SchemaVersion="2"; BlockId="b005"; LogicalBlockId="l005"; Sequence="4"; PageAssetId="page-0002-300dpi"; Region="body"; Continuation="single"; BlockType="paragraph"; Section="body"; VisualFirstWords="As shown"; VisualLastWords="clear."; MarkdownAnchor="As shown in Fig. 1, the result is clear."; Representation="markdown"; DraftFirstWords=""; DraftLastWords=""; CorrectionsMade=""; Numbering="not-applicable"; VisualNumber=""; MarkdownTag=""; FallbackAssetId=""; TranscriberChecked="checked"; Uncertainty="none"; Notes=""
        }
        $blocks += [pscustomobject][ordered]@{
            SchemaVersion="2"; BlockId="b006"; LogicalBlockId="l006"; Sequence="5"; PageAssetId="page-0002-300dpi"; Region="caption"; Continuation="single"; BlockType="caption"; Section="body"; VisualFirstWords="Fig. 1."; VisualLastWords="Result."; MarkdownAnchor="**Fig. 1.** Result."; Representation="markdown"; DraftFirstWords=""; DraftLastWords=""; CorrectionsMade=""; Numbering="not-applicable"; VisualNumber=""; MarkdownTag=""; FallbackAssetId=""; TranscriberChecked="checked"; Uncertainty="none"; Notes=""
        }
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8
        $jobPath = Join-Path $package.ManifestDir "job.csv"
        $job = Import-Csv -LiteralPath $jobPath
        $job.LastIncludedBlockId = "b006"
        $job | Export-Csv -LiteralPath $jobPath -NoTypeInformation -Encoding UTF8

        $assetsPath = Join-Path $package.ManifestDir "assets.csv"
        $assets = @(Import-Csv -LiteralPath $assetsPath)
        $assets += [pscustomobject][ordered]@{
            SchemaVersion="2"; AssetId="fig-001"; AssetType="figure"; RelatedBlockId="b006"; PageNumber="2"; Path="assets\figures\fig1.png"; Sha256=(Get-FileHash $figurePath -Algorithm SHA256).Hash.ToLowerInvariant(); Bytes=(Get-Item $figurePath).Length; Width="300"; Height="200"; Dpi="300"; IsAuthoritative="true"; SourceMethod="direct-export"; DerivedFromCandidateIds="candidate-0001"; VisualMatch="complete"; FallbackReason=""; PlacementRule="first-citation"; FirstCitationAnchor="As shown in Fig. 1"; CaptionAnchor="**Fig. 1.** Result."; TranscriberChecked="checked"; Notes=""
        }
        $assets | Export-Csv -LiteralPath $assetsPath -NoTypeInformation -Encoding UTF8
        [pscustomobject][ordered]@{
            SchemaVersion="2"; CandidateId="candidate-0001"; PdfObject="1"; PageHint="2"; Path="_audit\candidates\candidate-0001.png"; Sha256=(Get-FileHash $candidatePath -Algorithm SHA256).Hash.ToLowerInvariant(); Bytes=(Get-Item $candidatePath).Length; Width="300"; Height="200"; MatchedAssetId="fig-001"; Decision="chosen"; RejectReason=""; Checked="checked"; Notes=""
        } | Export-Csv -LiteralPath (Join-Path $package.ManifestDir "image_candidates.csv") -NoTypeInformation -Encoding UTF8

        $result = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath $blocksPath -AssetManifestPath $assetsPath -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural
        Assert-True ($result.Status -eq "structurally-valid") "Expected a chosen direct-export figure to pass."

        $markdown = Get-Content -LiteralPath $package.MarkdownPath -Raw
        $markdown = $markdown.Replace(
            "As shown in Fig. 1, the result is clear.`n`n![Figure 1](assets/figures/fig1.png)",
            "![Figure 1](assets/figures/fig1.png)`n`nAs shown in Fig. 1, the result is clear."
        )
        [System.IO.File]::WriteAllText($package.MarkdownPath, $markdown, [System.Text.UTF8Encoding]::new($false))
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath $blocksPath -AssetManifestPath $assetsPath -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "is not placed after its FirstCitationAnchor"
        }
        Assert-True $failed "Expected a figure placed before its first citation to fail."
    }

    Invoke-TestCase "every rejected image candidate requires a reason" {
        $package = New-ValidPackage -Name "candidate-reason" -PdfPath $pdfPath
        $candidatePath = Join-Path $package.OutputRoot "_audit\candidates\candidate-0001.png"
        & magick -size 20x20 xc:white $candidatePath
        [pscustomobject][ordered]@{
            SchemaVersion="2"; CandidateId="candidate-0001"; PdfObject="1"; PageHint="1"; Path="_audit\candidates\candidate-0001.png"; Sha256=(Get-FileHash $candidatePath -Algorithm SHA256).Hash.ToLowerInvariant(); Bytes=(Get-Item $candidatePath).Length; Width="20"; Height="20"; MatchedAssetId=""; Decision="rejected"; RejectReason=""; Checked="checked"; Notes=""
        } | Export-Csv -LiteralPath (Join-Path $package.ManifestDir "image_candidates.csv") -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath (Join-Path $package.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "requires RejectReason"
        }
        Assert-True $failed "Expected a rejected candidate without a reason to fail."
    }

    Invoke-TestCase "final review rejects open blockers and cycles above two" {
        $package = New-ValidPackage -Name "open-review-blocker" -PdfPath $pdfPath -IncludeReview
        $reviewsPath = Join-Path $package.ManifestDir "review_findings.csv"
        $reviews = @(Import-Csv -LiteralPath $reviewsPath)
        $reviews[0].Outcome = "fail"
        $reviews[0].Blocking = "true"
        $reviews[0].Resolution = "open"
        $reviews[0].RecheckOutcome = "pending"
        $reviews | Export-Csv -LiteralPath $reviewsPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath (Join-Path $package.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath $reviewsPath -Phase Final | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "unresolved blocking finding"
        }
        Assert-True $failed "Expected an open blocking review finding to fail."

        $reviews[0].Outcome = "pass"
        $reviews[0].Blocking = "false"
        $reviews[0].Resolution = "closed"
        $reviews[0].RecheckOutcome = "pass"
        $reviews[0].Cycle = "3"
        $reviews | Export-Csv -LiteralPath $reviewsPath -NoTypeInformation -Encoding UTF8
        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath (Join-Path $package.ManifestDir "blocks.csv") -AssetManifestPath (Join-Path $package.ManifestDir "assets.csv") -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath $reviewsPath -Phase Final | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "only 1 or 2 is allowed"
        }
        Assert-True $failed "Expected review Cycle=3 to fail."
    }

    Invoke-TestCase "image extraction reports a v2 no-candidate result" {
        $candidateDir = Join-Path $fixtureRoot "no-image-candidates"
        $result = & (Join-Path $scriptRoot "extract_pdf_images.ps1") -InputPdf $pdfPath -OutputDir $candidateDir -AllowNone
        Assert-True ($result.SchemaVersion -eq "2") "Expected a v2 extraction result."
        Assert-True ($result.Status -eq "NoImagesExported") "Expected the text-only fixture to have no image candidates."
    }

    Invoke-TestCase "final validation reports verified-with-fallback only after asset review" {
        $package = New-ValidPackage -Name "final-fallback" -PdfPath $pdfPath -IncludeReview
        $formulaPath = Join-Path $package.OutputRoot "assets\formulas\formula1.png"
        & magick -size 300x150 xc:white $formulaPath
        $markdown = Get-Content -LiteralPath $package.MarkdownPath -Raw
        $markdown = $markdown.Replace("\[`n\alpha + \beta`n\]", "![Formula 1](assets/formulas/formula1.png)")
        [System.IO.File]::WriteAllText($package.MarkdownPath, $markdown, [System.Text.UTF8Encoding]::new($false))

        $assetsPath = Join-Path $package.ManifestDir "assets.csv"
        $assets = @(Import-Csv -LiteralPath $assetsPath)
        $assets += [pscustomobject][ordered]@{
            SchemaVersion="2"; AssetId="formula-001"; AssetType="formula"; RelatedBlockId="b003"; PageNumber="2"; Path="assets\formulas\formula1.png"; Sha256=(Get-FileHash $formulaPath -Algorithm SHA256).Hash.ToLowerInvariant(); Bytes=(Get-Item $formulaPath).Length; Width="300"; Height="150"; Dpi="300"; IsAuthoritative="true"; SourceMethod="page-crop"; DerivedFromCandidateIds=""; VisualMatch="fallback-authoritative"; FallbackReason="LaTeX uncertain"; PlacementRule="formula-location"; FirstCitationAnchor=""; CaptionAnchor=""; TranscriberChecked="checked"; Notes=""
        }
        $assets | Export-Csv -LiteralPath $assetsPath -NoTypeInformation -Encoding UTF8
        $blocksPath = Join-Path $package.ManifestDir "blocks.csv"
        $blocks = @(Import-Csv -LiteralPath $blocksPath)
        $formulaBlock = $blocks | Where-Object BlockId -eq "b003"
        $formulaBlock.Representation = "asset"
        $formulaBlock.FallbackAssetId = "formula-001"
        $formulaBlock.Uncertainty = "structured-fallback"
        $formulaBlock.MarkdownAnchor = "![Formula 1](assets/formulas/formula1.png)"
        $blocks | Export-Csv -LiteralPath $blocksPath -NoTypeInformation -Encoding UTF8

        $jobPath = Join-Path $package.ManifestDir "job.csv"
        & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath $blocksPath -AssetManifestPath $assetsPath -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Structural -CommitStatus | Out-Null
        & (Join-Path $scriptRoot "update_transcription_job_status.ps1") -JobManifestPath $jobPath -Event ReviewStarted | Out-Null

        $failed = $false
        try {
            & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath (Join-Path $package.ManifestDir "job.csv") -BlockManifestPath $blocksPath -AssetManifestPath $assetsPath -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath (Join-Path $package.ManifestDir "review_findings.csv") -Phase Final | Out-Null
        } catch {
            $failed = $_.Exception.Message -match "review coverage for asset"
        }
        Assert-True $failed "Expected final fallback to require independent asset review."

        $reviewsPath = Join-Path $package.ManifestDir "review_findings.csv"
        $reviews = @(Import-Csv -LiteralPath $reviewsPath)
        $reviews += [pscustomobject][ordered]@{
            SchemaVersion="2"; ReviewId="review-formula-001"; ReviewerRunId="fresh-reviewer-1"; ReviewerContext="fresh"; TargetType="asset"; TargetId="formula-001"; PageAssetId="page-0002-300dpi"; Outcome="pass"; Category="formula"; Expected="faithful fallback"; Actual="matches"; EvidencePath=""; Blocking="false"; Cycle="1"; Resolution="closed"; RecheckOutcome="pass"; Notes=""
        }
        $reviews | Export-Csv -LiteralPath $reviewsPath -NoTypeInformation -Encoding UTF8
        $result = & (Join-Path $scriptRoot "check_markdown_transcription.ps1") -MarkdownPath $package.MarkdownPath -JobManifestPath $jobPath -BlockManifestPath $blocksPath -AssetManifestPath $assetsPath -ImageCandidateManifestPath (Join-Path $package.ManifestDir "image_candidates.csv") -ReviewManifestPath $reviewsPath -Phase Final -CommitStatus
        $job = Import-Csv -LiteralPath $jobPath
        Assert-True ($result.Status -eq "verified-with-fallback" -and $result.Committed -eq $true) "Expected reviewed structured fallback status to commit."
        Assert-True ($job.ReviewStatus -eq "verified-with-fallback" -and $job.FinalStatus -eq "verified-with-fallback") "Expected fallback review and final states to remain synchronized."
    }
} finally {
    if (Test-Path -LiteralPath $resolvedFixtureRoot) {
        Remove-Item -LiteralPath $resolvedFixtureRoot -Recurse -Force
    }
}

Write-Host "Passed: $($passes.Count)"
Write-Host "Failed: $($failures.Count)"
if ($failures.Count -gt 0) {
    Write-Error ($failures -join [Environment]::NewLine)
    exit 1
}

exit 0
