[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPdf,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [int]$Dpi = 300,

    [string]$Prefix = "page",

    [switch]$Clean
)

$ErrorActionPreference = "Stop"

if ($Dpi -lt 72 -or $Dpi -gt 600) {
    throw "Dpi must be between 72 and 600."
}

$inputItem = Get-Item -LiteralPath $InputPdf
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$outputPath = (Resolve-Path -LiteralPath $OutputDir).Path

if ($Clean) {
    Get-ChildItem -LiteralPath $outputPath -Filter "$Prefix-*.png" -ErrorAction SilentlyContinue | Remove-Item -Force
}

$pdftoppmCommand = Get-Command pdftoppm.exe -ErrorAction SilentlyContinue
if (-not $pdftoppmCommand) {
    $pdftoppmCommand = Get-Command pdftoppm -ErrorAction Stop
}
$pdftoppm = $pdftoppmCommand.Source
$outputPrefix = Join-Path $outputPath $Prefix
$renderInput = $inputItem.FullName
$tempPdf = $null

if ($renderInput -match '[^\x00-\x7F]') {
    $tempPdf = Join-Path $env:TEMP ("visual-pdf-render-" + [guid]::NewGuid().ToString("N") + ".pdf")
    Copy-Item -LiteralPath $inputItem.FullName -Destination $tempPdf -Force
    $renderInput = $tempPdf
}

try {
    & $pdftoppm -r $Dpi -png $renderInput $outputPrefix
    if ($LASTEXITCODE -ne 0) {
        throw "pdftoppm failed with exit code $LASTEXITCODE."
    }
} finally {
    if ($tempPdf -and (Test-Path -LiteralPath $tempPdf)) {
        Remove-Item -LiteralPath $tempPdf -Force
    }
}

$pages = Get-ChildItem -LiteralPath $outputPath -Filter "$Prefix-*.png" | Sort-Object `
    @{ Expression = { if ($_.BaseName -match '(\d+)$') { [int]$Matches[1] } else { [int]::MaxValue } } }, `
    Name
if ($pages.Count -eq 0) {
    throw "No rendered PNG pages were created in $outputPath."
}

$pages | Select-Object FullName, Length
