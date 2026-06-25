[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [int]$FigureCount = 0,

    [string[]]$Figures,

    [string[]]$RenderedPages,

    [ValidateSet("csv", "md")]
    [string]$Format,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$fields = @(
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

if (-not $Figures -or $Figures.Count -eq 0) {
    if ($FigureCount -lt 1) {
        throw "Provide -FigureCount or -Figures."
    }
    $Figures = 1..$FigureCount | ForEach-Object { "Figure $_" }
}

if ($RenderedPages -and $RenderedPages.Count -ne $Figures.Count) {
    throw "RenderedPages count must match Figures count."
}

$outputParent = Split-Path -Parent $OutputPath
if ($outputParent) {
    New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
}

$rows = New-Object System.Collections.Generic.List[object]
for ($index = 0; $index -lt $Figures.Count; $index++) {
    $renderedPage = ""
    if ($RenderedPages) {
        $renderedPage = $RenderedPages[$index]
    }

    $rows.Add([pscustomobject][ordered]@{
        Figure = $Figures[$index]
        RenderedPage = $renderedPage
        ExportCandidates = ""
        ChosenAsset = ""
        Method = ""
        VisualMatch = ""
        FallbackReason = ""
        ReviewerNotes = ""
        Done = ""
    })
}

if ($Format -eq "csv") {
    $rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
} else {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Asset Decision Manifest")
    $lines.Add("")
    $lines.Add('Allowed `Method` values: `direct-export`, `crop-fallback`.')
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
    Figures = $rows.Count
    Fields = ($fields -join ",")
    Status = "OK"
}
