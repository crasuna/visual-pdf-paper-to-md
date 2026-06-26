[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string[]]$Fields,

    [ValidateSet("csv", "md")]
    [string]$Format,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$manifestFields = @(
    "Field",
    "SourcePage",
    "VisualValue",
    "MarkdownValue",
    "Checked",
    "Notes"
)

if (-not $Fields -or $Fields.Count -eq 0) {
    $Fields = @("Title", "Authors", "Journal", "Year", "VolumeIssuePages", "DOI")
}

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

$outputParent = Split-Path -Parent $OutputPath
if ($outputParent) {
    New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
}

$rows = foreach ($field in $Fields) {
    [pscustomobject][ordered]@{
        Field = $field
        SourcePage = ""
        VisualValue = ""
        MarkdownValue = ""
        Checked = ""
        Notes = ""
    }
}

if ($Format -eq "csv") {
    $rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
} else {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Metadata Manifest")
    $lines.Add("")
    $lines.Add("Audit paper metadata from rendered page images. Use `N/A` only when the field is visually absent.")
    $lines.Add("")
    $lines.Add("| $($manifestFields -join ' | ') |")
    $lines.Add("| $((1..$manifestFields.Count | ForEach-Object { '---' }) -join ' | ') |")
    foreach ($row in $rows) {
        $values = foreach ($field in $manifestFields) {
            ($row.$field -replace '\|', '\|')
        }
        $lines.Add("| $($values -join ' | ') |")
    }
    Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8
}

[pscustomobject]@{
    Manifest = (Get-Item -LiteralPath $OutputPath).FullName
    Format = $Format
    Rows = @($rows).Count
    Fields = ($manifestFields -join ",")
    Status = "OK"
}
