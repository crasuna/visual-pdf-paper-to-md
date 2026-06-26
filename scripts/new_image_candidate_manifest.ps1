[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$ImageDir,

    [ValidateSet("csv", "md")]
    [string]$Format,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$fields = @(
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

if (-not $Format) {
    $extension = [System.IO.Path]::GetExtension($OutputPath).ToLowerInvariant()
    if ($extension -eq ".md" -or $extension -eq ".markdown") {
        $Format = "md"
    } else {
        $Format = "csv"
    }
}

if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
    throw "OutputPath already exists. Use -Force to overwrite: $OutputPath"
}

$rows = New-Object System.Collections.Generic.List[object]
$magick = (Get-Command magick -ErrorAction SilentlyContinue).Source
if ($ImageDir) {
    $imageDirItem = Get-Item -LiteralPath $ImageDir
    Get-ChildItem -LiteralPath $imageDirItem.FullName -File | Sort-Object Name | ForEach-Object {
        $width = ""
        $height = ""
        if ($magick) {
            $dimensions = & $magick identify -format "%w %h" $_.FullName 2>$null
            if ($LASTEXITCODE -eq 0 -and $dimensions) {
                $parts = $dimensions -split '\s+'
                $width = $parts[0]
                $height = $parts[1]
            }
        }
        $rows.Add([pscustomobject][ordered]@{
            Candidate = $_.FullName
            Width = $width
            Height = $height
            PageHint = ""
            MatchedFigure = ""
            Decision = ""
            RejectReason = ""
            Checked = ""
            Notes = ""
        })
    }
}

if ($rows.Count -eq 0) {
    $rows.Add([pscustomobject][ordered]@{
        Candidate = ""
        Width = ""
        Height = ""
        PageHint = ""
        MatchedFigure = ""
        Decision = ""
        RejectReason = ""
        Checked = ""
        Notes = ""
    })
}

$outputParent = Split-Path -Parent $OutputPath
if ($outputParent) {
    New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
}

if ($Format -eq "csv") {
    $rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
} else {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Image Candidate Manifest")
    $lines.Add("")
    $lines.Add('Decision values: `chosen`, `rejected`, or `unmatched`. Rejected candidates require `RejectReason`.')
    $lines.Add("")
    $lines.Add("| $($fields -join ' | ') |")
    $lines.Add("| $((1..$fields.Count | ForEach-Object { '---' }) -join ' | ') |")
    foreach ($row in $rows) {
        $values = foreach ($field in $fields) {
            ($row.$field -replace '\|', '\|')
        }
        $lines.Add("| $($values -join ' | ') |")
    }
    Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8
}

[pscustomobject]@{
    Manifest = (Get-Item -LiteralPath $OutputPath).FullName
    Format = $Format
    Candidates = $rows.Count
    Fields = ($fields -join ",")
    Status = "OK"
}
