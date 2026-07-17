# Archival transcription workflow

## Contents

- Preflight and package creation
- Page archive and reading order
- Transcription
- Images and typed assets
- Reference cutoff
- Structural handoff
- Final report

## Preflight and package creation

Run `preflight_transcription.ps1` before creating anything. It is read-only and must establish:

- PowerShell 7 or later;
- a readable source PDF, its SHA-256, byte size, and page count;
- usable `pdftoppm`, `pdfinfo`, `pdfimages`, and ImageMagick `magick` paths;
- `pdftotext` only for an explicitly authorized embedded-text job;
- a valid source mode and any required user OCR artifact;
- an exact output root that does not exist;
- an estimated page archive size.

Missing dependencies are a hard stop. Explain how to install them; never install them automatically.

Initialize with `new_transcription_job.ps1`. The initializer creates exactly one new package and five v2 CSV files. If initialization fails, it may clean up only the exact directory it just created. It must never remove or alter a pre-existing directory.

## Page archive and reading order

Render all pages at 300 DPI as `page-0001-300dpi.png`, `page-0002-300dpi.png`, and so on. Hash and inspect every page. If 300 DPI is insufficient for a particular page, render only that page at 400 DPI as `page-0001-400dpi.png`. Retain its 300 DPI baseline as non-authoritative and make the 400 DPI row authoritative. Every block and review finding must cite the authoritative page AssetId.

The renderer reads the real PDF page count before rendering. A requested first or last page beyond that count fails before promotion. It stages all Poppler output under a unique `.render-*` child directory, verifies that every requested page was produced, and only then promotes canonical files. Without `-Clean`, any target conflict fails before promotion. `-Clean` replaces only the requested prefix, DPI, and page range; it never removes a different DPI, prefix, or unrequested page. Backup and promotion are one rollback transaction, so a locked or otherwise failing target restores every earlier target before staging cleanup.

Before drafting, inspect the full page sequence and identify:

- title and metadata regions;
- column order and cross-column continuation;
- headings, paragraphs, footnotes, captions, tables, and equations;
- appendices, acknowledgements, declarations, and copyright text;
- blank pages that are genuinely part of the source;
- the exact page and heading at which the bibliography begins.

Assign a continuous global reading sequence. A logical paragraph split by a page or column boundary uses multiple `BlockId` values with one `LogicalBlockId` and explicit continuation values.

## Transcription

Write in the source language and preserve spelling, punctuation, capitalization, citation markers, equation references, units, and awkward original wording. Remove line wrapping introduced only by the page layout. Merge a line-end hyphen only when the rendered page proves it is not lexical.

In draft-assisted modes, record the draft's first and last words and a non-empty correction account for every draft-derived block. The final Markdown is accepted only after a rendered-page comparison.

Treat `MarkdownAnchor` as the block's complete serialized representation, excluding only whitespace separators between blocks. Each prose or structured anchor ends at `VisualLastWords` plus closing Markdown, HTML, or LaTeX syntax; never widen an anchor to absorb undeclared text. Anchors must occur once, follow block `Sequence`, and never overlap. Every non-whitespace character in the final Markdown must be covered by one represented block anchor or one registered final-asset link; untracked prose, headings, bibliography entries, and images are structural failures even when inserted before the terminal block.

For formulas:

- use `Numbering=unnumbered` without `VisualNumber` or `MarkdownTag` when no number is printed;
- use `Numbering=numbered`, record both fields, and include the matching `\tag{...}` when a number is printed;
- preserve matrices, cases, alignment, punctuation, font distinctions, scripts, operators, and delimiters;
- use a precise formula asset when a reliable structured transcription cannot be confirmed.

For tables, choose `markdown`, `html`, or `asset`. An asset is the last resort, must be precise, and must carry the reason structured representation is not reliable.

## Images and typed assets

Run `pdfimages -list` and export all candidates. Keep every exported object under `_audit/candidates/`, including masks, fragments, rejected objects, and unmatched objects. Record a stable ID, hash, dimensions, decision, and reason where required.

For each figure:

1. Compare candidate objects with the authoritative rendered page.
2. Choose direct export only if axes, ticks, labels, legends, color bars, scale bars, panel letters, insets, and composite structure are all present.
3. Record `SourceMethod=direct-export`, the chosen candidate ID, and `VisualMatch=complete`.
4. If no complete candidate exists, record `SourceMethod=page-crop` and a concrete `FallbackReason` before cropping.
5. Place the final image after the exact `FirstCitationAnchor` and before its editable caption.

Table and formula visual fallbacks may use direct export only when a complete object exists; otherwise crop the authoritative page. Direct export is never a way to derive table data or LaTeX.

Every crop must have a pre-existing typed asset row and exact output path. Reopen the result and confirm dimensions, content boundaries, and absence of caption text where captions remain editable.

## Reference cutoff

Under the default `exclude` policy, the Markdown must not contain the recorded reference heading in any language or any bibliography entry. Heading rejection is identical for LF and CRLF files, and treats multiple spaces, tabs, or other non-line-breaking whitespace between heading words as equivalent to the normalized single spaces recorded in `CutoffHeading`. It must retain all in-text citations and all semantic content before the heading. Record the real `CutoffPage`, normalized `CutoffHeading`, and final represented `LastIncludedBlockId`. Include exactly one final `reference-cutoff` block with `Representation=none`, matching visual anchors, and the authoritative cutoff page. Do not create represented `Section=references` rows. Between the last represented block and cutoff, permit only explicit non-represented `blank-page` rows. The final represented block's Markdown anchor must end at Markdown EOF after trimming whitespace and at its visual last-word boundary; do not absorb bibliography text into a broader anchor. Full-span coverage rejects undeclared bibliography text at any earlier Markdown position as well.

Under `keep`, leave all cutoff fields empty, omit the cutoff block, and transcribe at least one bibliography heading and its entries as ordinary represented `Section=references` blocks. A keep job with no bibliography coverage is invalid.

## Structural handoff

After initial transcription, record `TranscriptionCompleted`; this event is not a correction shortcut. Structural commit requires `TranscriptionStatus=transcribed`, `ReviewStatus=initialized`, and `FinalStatus=initialized`. Run `-Phase Structural -CommitStatus` only after all page, block, asset, candidate, provenance, and cutoff records are complete. A passing committed result writes `StructuralStatus=structurally-valid`; unresolved ordinary content additionally commits `needs-user-review` and stops the workflow. Structural success means the package is source-bound and structurally self-consistent. It does not mean visual fidelity has been independently established.

Give the fresh reviewer only:

- source PDF path and hash;
- archived authoritative page assets;
- candidate Markdown;
- block and asset location records;
- candidate archive;
- the empty or review-owned `review_findings.csv` path;
- the permitted evidence output directory.

Do not provide draft reasoning, chat history, self-evaluation, or an assertion that the transcription is correct.

Use `ReviewStarted` before the reviewer begins. Use `ReviewerUnavailable` when no fresh reviewer can run. Record `CorrectionRequired` before primary-agent edits and `CorrectionApplied` before recheck. These events use `update_transcription_job_status.ps1`; direct lifecycle edits are not normative.

## Final report

Report:

- source PDF path and SHA-256;
- Markdown and package paths;
- source mode and draft provenance, if any;
- explicit reference policy and cutoff;
- structural validation result;
- fresh visual review coverage and result;
- final status and any visual fallback assets;
- unresolved uncertainty with page and evidence paths;
- exact validation commands.

Never collapse “structurally valid” and “visually verified” into one claim.
Final completion additionally requires `TranscriptionStatus=transcribed`, `StructuralStatus=structurally-valid`, `ReviewStatus=reviewing`, `FinalStatus=initialized`, then `check_markdown_transcription.ps1 -Phase Final -CommitStatus`, `Committed=true`, and an identical computed status in `job.csv FinalStatus`. An identical repeat commit is allowed and byte-idempotent. No commit may revive a failed lifecycle. A read-only Final result is diagnostic and cannot satisfy completion.
