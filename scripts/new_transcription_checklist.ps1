[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPdf,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$RenderedImageDir,

    [string]$ImagePrefix = "page",

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$inputItem = Get-Item -LiteralPath $InputPdf
$pdfinfoCommand = Get-Command pdfinfo.exe -ErrorAction SilentlyContinue
if (-not $pdfinfoCommand) {
    $pdfinfoCommand = Get-Command pdfinfo -ErrorAction Stop
}
$pdfinfo = $pdfinfoCommand.Source

if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
    throw "OutputPath already exists. Use -Force to overwrite: $OutputPath"
}

$infoInput = $inputItem.FullName
$tempPdf = $null
if ($infoInput -match '[^\x00-\x7F]') {
    $tempPdf = Join-Path $env:TEMP ("visual-pdf-info-" + [guid]::NewGuid().ToString("N") + ".pdf")
    Copy-Item -LiteralPath $inputItem.FullName -Destination $tempPdf -Force
    $infoInput = $tempPdf
}

try {
    $info = & $pdfinfo $infoInput
    if ($LASTEXITCODE -ne 0) {
        throw "pdfinfo failed with exit code $LASTEXITCODE."
    }
} finally {
    if ($tempPdf -and (Test-Path -LiteralPath $tempPdf)) {
        Remove-Item -LiteralPath $tempPdf -Force
    }
}

$pageCount = $null
foreach ($line in $info) {
    if ($line -match '^Pages:\s+(\d+)') {
        $pageCount = [int]$Matches[1]
        break
    }
}

if (-not $pageCount) {
    throw "Unable to determine page count from pdfinfo output."
}

$outputParent = Split-Path -Parent $OutputPath
if ($outputParent) {
    New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Visual PDF Transcription Checklist")
$lines.Add("")
$lines.Add(("- Source PDF: ``{0}``" -f $inputItem.FullName))
$lines.Add("- Page count: $pageCount")
$lines.Add("- Use this checklist while visually transcribing. Mark each page only after comparing Markdown against the rendered page image.")
$lines.Add("")
$lines.Add("| Page | Rendered image | Reading order blocks | Body paragraphs checked | Formulas checked | Figures/tables checked | Uncertainties | Done |")
$lines.Add("| --- | --- | --- | --- | --- | --- | --- | --- |")

for ($page = 1; $page -le $pageCount; $page++) {
    $rendered = ""
    if ($RenderedImageDir) {
        $rendered = Join-Path $RenderedImageDir "$ImagePrefix-$page.png"
    }
    $lines.Add("| $page | $rendered | [ ] | [ ] | [ ] | [ ] |  | [ ] |")
}

Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8

[pscustomobject]@{
    Checklist = (Get-Item -LiteralPath $OutputPath).FullName
    SourcePdf = $inputItem.FullName
    Pages = $pageCount
    Status = "OK"
}
