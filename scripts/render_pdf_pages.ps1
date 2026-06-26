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

$pdftoppm = (Get-Command pdftoppm -ErrorAction Stop).Source
$outputPrefix = Join-Path $outputPath $Prefix

& $pdftoppm -r $Dpi -png $inputItem.FullName $outputPrefix
if ($LASTEXITCODE -ne 0) {
    throw "pdftoppm failed with exit code $LASTEXITCODE."
}

$pages = Get-ChildItem -LiteralPath $outputPath -Filter "$Prefix-*.png" | Sort-Object `
    @{ Expression = { if ($_.BaseName -match '(\d+)$') { [int]$Matches[1] } else { [int]::MaxValue } } }, `
    Name
if ($pages.Count -eq 0) {
    throw "No rendered PNG pages were created in $outputPath."
}

$pages | Select-Object FullName, Length
