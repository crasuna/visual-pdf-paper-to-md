[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [ValidateSet("Exclude", "Keep")]
    [string]$ReferencePolicy = "Exclude",

    [ValidateSet("csv", "md")]
    [string]$Format,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$fields = @(
    "ReferencePolicy",
    "CutoffPage",
    "CutoffHeading",
    "LastIncludedBlock",
    "ExcludedAfterHeading",
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

$outputParent = Split-Path -Parent $OutputPath
if ($outputParent) {
    New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
}

$row = [pscustomobject][ordered]@{
    ReferencePolicy = $ReferencePolicy
    CutoffPage = ""
    CutoffHeading = ""
    LastIncludedBlock = ""
    ExcludedAfterHeading = ""
    Checked = ""
    Notes = ""
}

if ($Format -eq "csv") {
    @($row) | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
} else {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Reference Cutoff Manifest")
    $lines.Add("")
    $lines.Add('Record the exact references policy and cutoff point. For `Exclude`, stop before the bibliography heading and keep body citations.')
    $lines.Add("")
    $lines.Add("| $($fields -join ' | ') |")
    $lines.Add("| $((1..$fields.Count | ForEach-Object { '---' }) -join ' | ') |")
    $values = foreach ($field in $fields) {
        ($row.$field -replace '\|', '\|')
    }
    $lines.Add("| $($values -join ' | ') |")
    Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8
}

[pscustomobject]@{
    Manifest = (Get-Item -LiteralPath $OutputPath).FullName
    Format = $Format
    ReferencePolicy = $ReferencePolicy
    Fields = ($fields -join ",")
    Status = "OK"
}
