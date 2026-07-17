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

function Get-ToolVersion {
    param([string]$Path, [string]$Name)

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = if ($Name -eq "magick") {
            @(& $Path -version 2>&1)
        } else {
            @(& $Path -v 2>&1)
        }
        $versionExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($versionExitCode -ne 0 -or $output.Count -eq 0) {
        throw "Unable to determine version for required dependency '$Name'."
    }
    ([string]$output[0]).Trim()
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 or later is required. Detected: $($PSVersionTable.PSVersion)"
}

$inputItem = Get-Item -LiteralPath $InputPdf
if ($inputItem.PSIsContainer -or $inputItem.Extension -ne ".pdf") {
    throw "InputPdf must be a readable .pdf file: $InputPdf"
}

$resolvedOutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $resolvedOutputRoot) {
    throw "Output package already exists; overwrite is forbidden: $resolvedOutputRoot"
}

switch ($SourceMode) {
    "visual-only" {
        if ($UserOcrPath -or $AllowEmbeddedTextExtraction) {
            throw "visual-only cannot use a text-layer authorization or user OCR draft."
        }
    }
    "embedded-text-assisted" {
        if (-not $AllowEmbeddedTextExtraction) {
            throw "embedded-text-assisted requires -AllowEmbeddedTextExtraction."
        }
        if ($UserOcrPath) {
            throw "embedded-text-assisted cannot use UserOcrPath."
        }
    }
    "user-ocr-assisted" {
        if (-not $UserOcrPath) {
            throw "user-ocr-assisted requires a user-provided -UserOcrPath."
        }
        if ($AllowEmbeddedTextExtraction) {
            throw "user-ocr-assisted cannot also authorize embedded text extraction."
        }
        $ocrItem = Get-Item -LiteralPath $UserOcrPath
        if ($ocrItem.PSIsContainer) {
            throw "UserOcrPath must be a file: $UserOcrPath"
        }
    }
}

$requiredCommands = @("pdftoppm", "pdfinfo", "pdfimages", "magick")
if ($SourceMode -eq "embedded-text-assisted") {
    $requiredCommands += "pdftotext"
}
$commands = [ordered]@{}
$versions = [ordered]@{}
foreach ($name in $requiredCommands) {
    $command = $null
    if ($name -in @("pdftoppm", "pdfinfo", "pdfimages", "pdftotext")) {
        $command = Get-Command "$name.exe" -ErrorAction SilentlyContinue
    }
    if (-not $command) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
    }
    if (-not $command) {
        throw "Missing required dependency '$name'. Install Poppler for pdftoppm/pdfinfo/pdfimages or ImageMagick for magick, then rerun preflight."
    }
    $commands[$name] = $command.Source
    $versions[$name] = Get-ToolVersion -Path $command.Source -Name $name
}

$infoInput = $inputItem.FullName
$tempPdf = $null
if ($infoInput -match '[^\x00-\x7F]') {
    $tempPdf = Join-Path ([System.IO.Path]::GetTempPath()) ("visual-pdf-preflight-" + [guid]::NewGuid().ToString("N") + ".pdf")
    Copy-Item -LiteralPath $inputItem.FullName -Destination $tempPdf
    $infoInput = $tempPdf
}

try {
    $pdfInfoOutput = & $commands.pdfinfo $infoInput 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "pdfinfo failed for '$($inputItem.FullName)': $($pdfInfoOutput -join ' ')"
    }
} finally {
    if ($tempPdf -and (Test-Path -LiteralPath $tempPdf)) {
        Remove-Item -LiteralPath $tempPdf -Force
    }
}

$pageCount = $null
foreach ($line in $pdfInfoOutput) {
    if ([string]$line -match '^Pages:\s+(\d+)') {
        $pageCount = [int]$Matches[1]
        break
    }
}
if (-not $pageCount) {
    throw "Unable to determine PDF page count from pdfinfo output."
}

$sourceHash = (Get-FileHash -LiteralPath $inputItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$ocrHash = ""
$ocrFullName = ""
if ($SourceMode -eq "user-ocr-assisted") {
    $ocrItem = Get-Item -LiteralPath $UserOcrPath
    $ocrFullName = $ocrItem.FullName
    $ocrHash = (Get-FileHash -LiteralPath $ocrItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}

[pscustomobject][ordered]@{
    SchemaVersion = "2"
    SourcePdf = $inputItem.FullName
    SourcePdfSha256 = $sourceHash
    SourcePdfBytes = $inputItem.Length
    PageCount = $pageCount
    OutputRoot = $resolvedOutputRoot
    SourceMode = $SourceMode
    UserOcrPath = $ocrFullName
    UserOcrSha256 = $ocrHash
    CodexInvokedOcr = $false
    EmbeddedTextAuthorized = [bool]$AllowEmbeddedTextExtraction
    ReferencePolicy = $ReferencePolicy
    ExternalMetadataPolicy = $ExternalMetadataPolicy
    EstimatedArchiveBytes = [int64]($pageCount * 20MB)
    PdftoppmPath = $commands.pdftoppm
    PdftoppmVersion = $versions.pdftoppm
    PdfinfoPath = $commands.pdfinfo
    PdfinfoVersion = $versions.pdfinfo
    PdfimagesPath = $commands.pdfimages
    PdfimagesVersion = $versions.pdfimages
    MagickPath = $commands.magick
    MagickVersion = $versions.magick
    PdftotextPath = $(if ($commands.Contains("pdftotext")) { $commands.pdftotext } else { "" })
    PdftotextVersion = $(if ($versions.Contains("pdftotext")) { $versions.pdftotext } else { "" })
    Status = "preflight-passed"
}
