[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPdf,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [switch]$UserAuthorized
)

$ErrorActionPreference = "Stop"

if (-not $UserAuthorized) {
    throw "Embedded PDF text extraction requires explicit authorization via -UserAuthorized."
}
if (Test-Path -LiteralPath $OutputPath) {
    throw "Refusing to overwrite an existing embedded-text draft: $OutputPath"
}
$inputItem = Get-Item -LiteralPath $InputPdf
if ($inputItem.Extension -ne ".pdf") {
    throw "InputPdf must be a PDF file."
}
$pdftotext = Get-Command pdftotext.exe -ErrorAction SilentlyContinue
if (-not $pdftotext) {
    $pdftotext = Get-Command pdftotext -ErrorAction Stop
}
$versionOutput = @(& $pdftotext.Source -v 2>&1)
if ($LASTEXITCODE -ne 0 -or $versionOutput.Count -eq 0) {
    throw "Unable to determine pdftotext version."
}
$outputParent = Split-Path -Parent $OutputPath
if ($outputParent -and -not (Test-Path -LiteralPath $outputParent)) {
    New-Item -ItemType Directory -Path $outputParent | Out-Null
}

$tempOutput = "$OutputPath.tmp-$([guid]::NewGuid().ToString('N'))"
$extractInput = $inputItem.FullName
$tempPdf = $null
if ($extractInput -match '[^\x00-\x7F]') {
    $tempPdf = Join-Path ([System.IO.Path]::GetTempPath()) ("visual-pdf-text-layer-" + [guid]::NewGuid().ToString("N") + ".pdf")
    Copy-Item -LiteralPath $inputItem.FullName -Destination $tempPdf
    $extractInput = $tempPdf
}
try {
    $toolMessages = @(& $pdftotext.Source -layout -enc UTF-8 $extractInput $tempOutput 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "pdftotext failed with exit code $LASTEXITCODE."
    }
    Move-Item -LiteralPath $tempOutput -Destination $OutputPath
} finally {
    if ($tempPdf -and (Test-Path -LiteralPath $tempPdf)) {
        Remove-Item -LiteralPath $tempPdf -Force
    }
    if (Test-Path -LiteralPath $tempOutput) {
        Remove-Item -LiteralPath $tempOutput -Force
    }
}

$outputItem = Get-Item -LiteralPath $OutputPath
[pscustomobject][ordered]@{
    SchemaVersion = "2"
    SourceMode = "embedded-text-assisted"
    FullName = $outputItem.FullName
    Sha256 = (Get-FileHash -LiteralPath $outputItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    Bytes = $outputItem.Length
    Tool = $pdftotext.Source
    ToolVersion = ([string]$versionOutput[0]).Trim()
    ToolParameters = "-layout -enc UTF-8"
    ToolMessages = ($toolMessages -join [Environment]::NewLine)
    UserAuthorized = $true
    Status = "draft-created"
}
