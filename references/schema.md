# Schema v2 reference

## Contents

- General rules
- job.csv
- blocks.csv
- assets.csv
- image_candidates.csv
- review_findings.csv
- Atomic updates

## General rules

The five CSV files under `_audit/manifests/` are the only normative manifests. Every row uses `SchemaVersion=2`. CSV is parsed by `Import-Csv`; Markdown tables are not accepted as data sources. IDs, paths, hashes, enums, and cross-references are case-stable and must not be inferred from prose.

Manifest paths are relative, never absolute. Package artifacts must resolve within the package root. `SourcePdfRelativePath` is the sole exception to the containment rule: it resolves from the package to the unchanged source PDF in `原始论文`, which is not copied into the package. Hashes use lowercase SHA-256. Stable IDs are never recycled during one job.

## job.csv

Exactly one row records the job:

- identity and source binding: `JobId`, `SourcePdfRelativePath`, `SourcePdfSha256`, `SourcePdfBytes`, `PageCount`;
- provenance: `SourceMode`, `DraftRelativePath`, `DraftSha256`, `DraftProducer`, `DraftToolPath`, `DraftToolVersion`, `DraftToolParameters`, `CodexInvokedOcr`, `EmbeddedTextAuthorized`;
- scope: `ReferencePolicy`, `CutoffPage`, `CutoffHeading`, `LastIncludedBlockId`, `ExternalMetadataPolicy`;
- output and tools: `MarkdownRelativePath`, `CreatedUtc`, path and version pairs for `pdftoppm`, `pdfinfo`, `pdfimages`, ImageMagick, and authorized `pdftotext`;
- lifecycle: `TranscriptionStatus`, `StructuralStatus`, `ReviewStatus`, `FinalStatus`.

Lifecycle values are field-specific:

| Field | Allowed values |
|---|---|
| `TranscriptionStatus` | `initialized`, `transcribed`, `needs-correction`, `needs-user-review`, `failed` |
| `StructuralStatus` | `initialized`, `structurally-valid`, `failed` |
| `ReviewStatus` | `initialized`, `review-pending`, `reviewing`, `needs-correction`, `needs-user-review`, `verified`, `verified-with-fallback`, `failed` |
| `FinalStatus` | `initialized`, `review-pending`, `needs-user-review`, `verified`, `verified-with-fallback`, `failed` |

The lifecycle helper owns workflow events but cannot write evidence states. Only the validator with `-CommitStatus` may write `structurally-valid`, `verified`, or `verified-with-fallback`.

Lifecycle helper events are fixed: `TranscriptionCompleted`, `ReviewStarted`, `ReviewerUnavailable`, `CorrectionRequired`, `CorrectionApplied`, `UserReviewRequired`, `FailTranscription`, `FailStructural`, `FailReview`, and `FailFinal`. `TranscriptionCompleted` is only `initialized -> transcribed`; paired `needs-correction` fields resume atomically through `CorrectionApplied`. Forward-stage preconditions are enforced. Failure events set their named stage and `FinalStatus=failed` while preserving other stage values; failed, evidence-complete, and user-review states cannot be revived through a status commit or helper edit.

With `ReferencePolicy=exclude`, record a real `CutoffPage`, whitespace-normalized `CutoffHeading`, and `LastIncludedBlockId`. With `keep`, all three fields are empty.

## blocks.csv

One row represents one visual block. Required identity and ordering fields are `BlockId`, `LogicalBlockId`, `Sequence`, `PageAssetId`, `Region`, and `Continuation`. `Sequence` is unique and contiguous.

Allowed block types are `title`, `author`, `affiliation`, `metadata`, `abstract-label`, `heading`, `paragraph`, `footnote`, `caption`, `table`, `formula`, `acknowledgement`, `appendix`, `declaration`, `copyright-license`, `reference-cutoff`, and `blank-page`.

`author` is one visual author block and may contain multiple authors. `metadata` is one composite publication-information block. The retired implementation-only names `authors`, `journal`, `year`, `volume-issue-pages`, and `doi` are invalid.

Each represented block records `VisualFirstWords`, `VisualLastWords`, one exact and unique `MarkdownAnchor`, `Representation`, `TranscriberChecked`, and `Uncertainty`. The anchor is the block's complete serialized Markdown, HTML, or asset representation after excluding only inter-block whitespace; it is not a short locator. Every prose or structured anchor must terminate at its declared `VisualLastWords` followed only by closing Markdown, HTML, or LaTeX syntax, so an anchor cannot absorb undeclared content. Represented anchor spans occur exactly once, follow `Sequence`, and do not overlap. Registered final-asset links also occur exactly once. The union of represented anchor spans and registered final-asset links covers every non-whitespace Markdown character, so undeclared prose, bibliography text, headings, or images fail Structural validation wherever they occur. Representation is `markdown`, `html`, `asset`, or `none`. Only a reference cutoff or explicit blank page normally uses `none`.

Draft-assisted rows additionally use `DraftFirstWords`, `DraftLastWords`, and `CorrectionsMade`. Formula rows use `Numbering=numbered|unnumbered`; numbered rows require `VisualNumber`, `MarkdownTag`, and a matching Markdown `\tag{...}`. An asset fallback uses `FallbackAssetId` and `Uncertainty=structured-fallback` and is allowed only for a formula or table.

Under `exclude`, exactly one `reference-cutoff` row is the final `Sequence`, uses `Representation=none`, and points to `CutoffPage`. Both visual anchors equal the normalized real `CutoffHeading`. No represented row may use `Section=references`. `LastIncludedBlockId` is the last represented block; only explicit `blank-page` rows with `Representation=none` may intervene. The last included block's unique Markdown anchor ends at the final non-whitespace Markdown character and cannot extend beyond that block's `VisualLastWords` except for closing Markdown, HTML, or LaTeX syntax. Detection of the recorded heading is language- and LF/CRLF-independent; runs of non-line-breaking whitespace inside a multi-word heading are equivalent to the normalized single spaces in `CutoffHeading`. Full-span Markdown coverage rejects unregistered bibliography material before as well as after the terminal anchor. Under `keep`, there is no cutoff row; at least one represented `Section=references` heading and one represented entry are required.

## assets.csv

Allowed `AssetType` values are `rendered-page`, `figure`, `table`, `formula`, and `review-evidence`. Every asset records path, SHA-256, byte size, dimensions, DPI where applicable, source method, visual match, and review state.

Every source page has exactly one 300 DPI baseline row named and identified as `page-####-300dpi`. A page may have at most one `page-####-400dpi` row. Without 400 DPI, the 300 DPI row is authoritative. With 400 DPI, the 300 DPI row remains archived and non-authoritative while the 400 DPI row is authoritative. `AssetId`, `Path`, `PageNumber`, and `Dpi` must encode the same identity. Every block points to its page's authoritative row. Final figure, table, and formula assets link to an appropriate block via `RelatedBlockId`.

Figure rules:

- `Path` uses `assets/figures/figN.ext`;
- `PlacementRule=first-citation`;
- `FirstCitationAnchor` and `CaptionAnchor` are required;
- direct export requires chosen `DerivedFromCandidateIds` and `VisualMatch=complete`;
- a page crop requires a concrete `FallbackReason`.

Table and formula assets use their own placement rule, do not use `FirstCitationAnchor`, and may be authoritative structured fallbacks. Review evidence stays under `_audit/review/evidence/` and is not final paper content.

## image_candidates.csv

Every exported candidate has `CandidateId`, PDF object or page hint when available, relative path, SHA-256, byte size, dimensions, optional `MatchedAssetId`, `Decision`, `RejectReason`, and `Checked`.

`Decision` is `chosen`, `rejected`, or `unmatched`. A rejected row always has a concrete reason. A chosen candidate links to exactly the final asset that claims it. Every exported candidate is retained even if it is a mask, fragment, duplicate, or irrelevant publisher object.

## review_findings.csv

Only the fresh reviewer writes this file. Each row records `ReviewId`, `ReviewerRunId`, `ReviewerContext=fresh`, `TargetType`, `TargetId`, `PageAssetId`, `Outcome`, `Category`, `Expected`, `Actual`, optional `EvidencePath`, `Blocking`, `Cycle`, `Resolution`, `RecheckOutcome`, and `Notes`.

Every finding points to the authoritative rendered-page row for the target's source page, not merely to any retained page version.

Every block and every final figure, table, or formula asset requires at least one closed fresh pass. `Cycle` is 1 or 2. Failed blockers remain visible; correction creates or updates explicit recheck information rather than erasing the original discrepancy.

## Atomic updates

When a script writes a manifest, write a complete CSV to a sibling temporary file and atomically replace the destination. Never stream partial rows into a normative manifest. The validator snapshots all six input hashes, repeats the comparison after validation, and checks the expected job hash immediately before replacement. Preserve the existing manifest if validation, concurrent-input detection, or replacement fails.
