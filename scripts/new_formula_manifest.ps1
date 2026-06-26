[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [int]$FormulaCount = 0,

    [string[]]$Formulas,

    [string[]]$Pages,

    [ValidateSet("csv", "md")]
    [string]$Format,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$fields = @(
    "Formula",
    "SourcePage",
    "SourceBlock",
    "VisualNumber",
    "MarkdownTag",
    "MarkdownAnchor",
    "ScreenshotAsset",
    "DiscoveryChecked",
    "TranscriptionChecked",
    "Uncertainty",
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

if (-not $Formulas -or $Formulas.Count -eq 0) {
    if ($FormulaCount -lt 1) {
        throw "Provide -FormulaCount or -Formulas."
    }
    $Formulas = 1..$FormulaCount | ForEach-Object { "Formula $_" }
}

if ($Pages -and $Pages.Count -ne $Formulas.Count) {
    throw "Pages count must match Formulas count."
}

$outputParent = Split-Path -Parent $OutputPath
if ($outputParent) {
    New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
}

$rows = New-Object System.Collections.Generic.List[object]
for ($index = 0; $index -lt $Formulas.Count; $index++) {
    $page = ""
    if ($Pages) {
        $page = $Pages[$index]
    }

    $rows.Add([pscustomobject][ordered]@{
        Formula = $Formulas[$index]
        SourcePage = $page
        SourceBlock = ""
        VisualNumber = ""
        MarkdownTag = ""
        MarkdownAnchor = ""
        ScreenshotAsset = ""
        DiscoveryChecked = ""
        TranscriptionChecked = ""
        Uncertainty = ""
        ReviewerNotes = ""
        Done = ""
    })
}

if ($Format -eq "csv") {
    $rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
} else {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Formula Fidelity Manifest")
    $lines.Add("")
    $lines.Add('Record both formula discovery from the rendered page and Markdown transcription. Use `MarkdownTag` values exactly as they appear inside `\tag{...}`.')
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
    Formulas = $rows.Count
    Fields = ($fields -join ",")
    Status = "OK"
}
