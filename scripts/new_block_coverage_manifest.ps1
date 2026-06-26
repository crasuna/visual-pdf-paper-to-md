[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [int]$BlockCount = 0,

    [string[]]$Blocks,

    [ValidateSet("csv", "md")]
    [string]$Format,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$fields = @(
    "Page",
    "ColumnOrRegion",
    "BlockType",
    "Section",
    "FirstWords",
    "LastWords",
    "MarkdownAnchor",
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

if (-not $Blocks -or $Blocks.Count -eq 0) {
    if ($BlockCount -lt 1) {
        throw "Provide -BlockCount or -Blocks."
    }
    $Blocks = 1..$BlockCount | ForEach-Object { "Block $_" }
}

$outputParent = Split-Path -Parent $OutputPath
if ($outputParent) {
    New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
}

$rows = New-Object System.Collections.Generic.List[object]
foreach ($block in $Blocks) {
    $rows.Add([pscustomobject][ordered]@{
        Page = ""
        ColumnOrRegion = ""
        BlockType = $block
        Section = ""
        FirstWords = ""
        LastWords = ""
        MarkdownAnchor = ""
        Checked = ""
        Notes = ""
    })
}

if ($Format -eq "csv") {
    $rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
} else {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Block Coverage Manifest")
    $lines.Add("")
    $lines.Add("Record every title, metadata block, heading, paragraph, caption, table, formula, acknowledgement, appendix, and intentional cutoff block.")
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
    Blocks = $rows.Count
    Fields = ($fields -join ",")
    Status = "OK"
}
