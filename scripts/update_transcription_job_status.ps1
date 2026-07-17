[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$JobManifestPath,

    [Parameter(Mandatory = $true)]
    [ValidateSet(
        "TranscriptionCompleted",
        "ReviewStarted",
        "ReviewerUnavailable",
        "CorrectionRequired",
        "CorrectionApplied",
        "UserReviewRequired",
        "FailTranscription",
        "FailStructural",
        "FailReview",
        "FailFinal"
    )]
    [string]$Event
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "transcription_manifest_common.ps1")

$jobItem = Get-Item -LiteralPath $JobManifestPath
if ($jobItem.Extension.ToLowerInvariant() -ne ".csv") {
    throw "job manifest must be a v2 CSV file: $JobManifestPath"
}
$initialHash = Get-FileSha256Lower -Path $jobItem.FullName
$jobs = @(Import-Csv -LiteralPath $jobItem.FullName)
if ($jobs.Count -ne 1) {
    throw "job.csv must contain exactly one row."
}
$job = $jobs[0]

$requiredFields = @("SchemaVersion", "TranscriptionStatus", "StructuralStatus", "ReviewStatus", "FinalStatus")
$missingFields = @($requiredFields | Where-Object { $_ -notin $job.PSObject.Properties.Name })
if ($missingFields.Count -gt 0) {
    throw "job.csv is missing required lifecycle fields: $($missingFields -join ', ')."
}
if ([string]$job.SchemaVersion -ne "2") {
    throw "Unsupported manifest schema '$($job.SchemaVersion)'; v2 is required and v1 is not accepted."
}

$allowedStates = [ordered]@{
    TranscriptionStatus = @("initialized", "transcribed", "needs-correction", "needs-user-review", "failed")
    StructuralStatus = @("initialized", "structurally-valid", "failed")
    ReviewStatus = @("initialized", "review-pending", "reviewing", "needs-correction", "needs-user-review", "verified", "verified-with-fallback", "failed")
    FinalStatus = @("initialized", "review-pending", "needs-user-review", "verified", "verified-with-fallback", "failed")
}
foreach ($field in $allowedStates.Keys) {
    if ($allowedStates[$field] -notcontains [string]$job.$field) {
        throw "job.csv has invalid $field '$($job.$field)'."
    }
}

$verifiedStates = @("verified", "verified-with-fallback")
$hasVerifiedState = $verifiedStates -contains [string]$job.ReviewStatus -or $verifiedStates -contains [string]$job.FinalStatus
$hasUserReviewState = @($job.TranscriptionStatus, $job.ReviewStatus, $job.FinalStatus) -contains "needs-user-review"
if ($hasVerifiedState -or $hasUserReviewState) {
    throw "Lifecycle state is terminal; event '$Event' is not allowed."
}
if ([string]$job.FinalStatus -eq "failed") {
    throw "Lifecycle state is terminal after failure; event '$Event' is not allowed."
}

switch ($Event) {
    "TranscriptionCompleted" {
        if ([string]$job.TranscriptionStatus -eq "needs-correction" -or [string]$job.ReviewStatus -eq "needs-correction") {
            throw "Correction states must be resumed with CorrectionApplied, not TranscriptionCompleted."
        }
        if ([string]$job.TranscriptionStatus -ne "initialized") {
            throw "TranscriptionCompleted requires TranscriptionStatus=initialized."
        }
        $job.TranscriptionStatus = "transcribed"
    }
    "ReviewStarted" {
        if ([string]$job.StructuralStatus -ne "structurally-valid") {
            throw "ReviewStarted requires StructuralStatus=structurally-valid."
        }
        if ([string]$job.TranscriptionStatus -ne "transcribed") {
            throw "ReviewStarted requires TranscriptionStatus=transcribed."
        }
        if ([string]$job.ReviewStatus -notin @("initialized", "review-pending")) {
            throw "ReviewStarted requires ReviewStatus=initialized or review-pending."
        }
        if ([string]$job.FinalStatus -notin @("initialized", "review-pending")) {
            throw "ReviewStarted requires FinalStatus=initialized or review-pending."
        }
        $job.ReviewStatus = "reviewing"
        $job.FinalStatus = "initialized"
    }
    "ReviewerUnavailable" {
        if ([string]$job.StructuralStatus -ne "structurally-valid") {
            throw "ReviewerUnavailable requires StructuralStatus=structurally-valid."
        }
        if ([string]$job.TranscriptionStatus -ne "transcribed") {
            throw "ReviewerUnavailable requires TranscriptionStatus=transcribed."
        }
        if ([string]$job.ReviewStatus -notin @("initialized", "reviewing", "review-pending")) {
            throw "ReviewerUnavailable requires ReviewStatus=initialized, reviewing, or review-pending."
        }
        if ([string]$job.FinalStatus -notin @("initialized", "review-pending")) {
            throw "ReviewerUnavailable requires FinalStatus=initialized or review-pending."
        }
        $job.ReviewStatus = "review-pending"
        $job.FinalStatus = "review-pending"
    }
    "CorrectionRequired" {
        if ([string]$job.ReviewStatus -ne "reviewing") {
            throw "CorrectionRequired requires ReviewStatus=reviewing."
        }
        if ([string]$job.TranscriptionStatus -ne "transcribed") {
            throw "CorrectionRequired requires TranscriptionStatus=transcribed."
        }
        $job.TranscriptionStatus = "needs-correction"
        $job.ReviewStatus = "needs-correction"
    }
    "CorrectionApplied" {
        if ([string]$job.TranscriptionStatus -ne "needs-correction" -or [string]$job.ReviewStatus -ne "needs-correction") {
            throw "CorrectionApplied requires both TranscriptionStatus and ReviewStatus to equal needs-correction."
        }
        $job.TranscriptionStatus = "transcribed"
        $job.ReviewStatus = "reviewing"
    }
    "UserReviewRequired" {
        $job.TranscriptionStatus = "needs-user-review"
        $job.ReviewStatus = "needs-user-review"
        $job.FinalStatus = "needs-user-review"
    }
    "FailTranscription" {
        $job.TranscriptionStatus = "failed"
        $job.FinalStatus = "failed"
    }
    "FailStructural" {
        $job.StructuralStatus = "failed"
        $job.FinalStatus = "failed"
    }
    "FailReview" {
        $job.ReviewStatus = "failed"
        $job.FinalStatus = "failed"
    }
    "FailFinal" {
        $job.FinalStatus = "failed"
    }
}

Write-AtomicCsvRow -Path $jobItem.FullName -Row $job -ExpectedExistingSha256 $initialHash

[pscustomobject][ordered]@{
    SchemaVersion = "2"
    Event = $Event
    Committed = $true
    TranscriptionStatus = [string]$job.TranscriptionStatus
    StructuralStatus = [string]$job.StructuralStatus
    ReviewStatus = [string]$job.ReviewStatus
    FinalStatus = [string]$job.FinalStatus
}
