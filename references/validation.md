# Validation and testing

## Structural validation

Run from the skill directory:

```powershell
.\scripts\check_markdown_transcription.ps1 `
  -MarkdownPath "<package>\paper.md" `
  -JobManifestPath "<package>\_audit\manifests\job.csv" `
  -BlockManifestPath "<package>\_audit\manifests\blocks.csv" `
  -AssetManifestPath "<package>\_audit\manifests\assets.csv" `
  -ImageCandidateManifestPath "<package>\_audit\manifests\image_candidates.csv" `
  -ReviewManifestPath "<package>\_audit\manifests\review_findings.csv" `
  -Phase Structural
```

Structural phase verifies source PDF existence, hash, byte size and real page count; Markdown binding; source-mode provenance; schema; block order and exact non-overlapping full-representation anchors; reverse coverage of every non-whitespace Markdown character by a block or registered final asset; formulas; page archive coverage and hashes; typed assets; candidate decisions; figure placement; LF/CRLF- and internal-whitespace-independent multilingual reference headings; and reference policy.

The command above is read-only and returns `Committed=false`. Add `-CommitStatus` only when the job should atomically record the validated result. Structural commit requires a completed transcription and unopened review/final stages, then writes `StructuralStatus=structurally-valid`; unresolved ordinary content remains structurally valid but commits `TranscriptionStatus=needs-user-review` and `FinalStatus=needs-user-review`.

## Final validation

Use the same command with `-Phase Final`. Final phase reruns structural validation and additionally requires fresh review coverage for every block and final asset, authoritative page references, no unresolved blocker, and review cycles no greater than two. Read-only Final computes a result but cannot complete the job. First Final commit requires `TranscriptionStatus=transcribed`, `StructuralStatus=structurally-valid`, `ReviewStatus=reviewing`, `FinalStatus=initialized`, and no failed field. It atomically writes matching `ReviewStatus` and `FinalStatus` values of `verified`, `verified-with-fallback`, or `needs-user-review`; only an identical previously committed state may repeat.

Before every commit the checker rehashes Markdown and all five manifests. A change aborts without writing. Atomic replacement likewise preserves the original job row on failure. Repeating an identical successful commit is byte-idempotent.

Final validation cannot prove that a human-like visual comparison truly occurred. It proves that source-bound evidence and independently attributed coverage records satisfy the protocol. Preserve this limitation in the final report.

## Regression suite

```powershell
pwsh -NoProfile -File ".\tests\run_tests.ps1"
```

The suite builds a copyright-free two-page PDF in a unique system temporary directory, exercises positive and negative fixtures, and removes only that verified temporary root. It tests source binding, overwrite refusal, source modes, canonical and retired block types, stable IDs and exact full-span anchors, reverse Markdown coverage, LF/CRLF multilingual reference rejection with exact, multi-space, and tab-separated headings in ATX and Setext form, formula numbering, typed fallbacks, multi-DPI archive authority, complete render ranges and transactional rollback, candidate decisions, strict exclude and keep reference coverage, lifecycle transitions, skipped-stage and failure-revival rejection, field enums, concurrent-input and atomic-replacement failure, figure placement, fresh review coverage, blockers, two-cycle limits, and explicit v1 rejection.

## Skill validation

```powershell
python "C:\Users\24493\.codex\skills\.system\skill-creator\scripts\quick_validate.py" "C:\Users\24493\.codex\skills\visual-pdf-paper-to-md"
python "C:\Users\24493\.codex\skills\skill-evaluator\scripts\check_skill.py" "C:\Users\24493\.codex\skills\visual-pdf-paper-to-md"
```

Also parse every PowerShell script, run `git diff --check`, and inspect `git ls-files --eol`. Static skill scores measure packaging and instruction quality, not transcription truth.
