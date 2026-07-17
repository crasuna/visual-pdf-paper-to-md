---
name: visual-pdf-paper-to-md
description: Faithful, complete academic PDF to Markdown transcription and audit using rendered pages as the final authority, source-bound v2 CSV manifests, typed assets, and independent full-coverage visual review. Use only when the user explicitly wants a full-paper PDF transcription or an audit of an existing full-paper transcription. Do not use for summaries, explanations, translations, local questions, ordinary PDF reading, or layout-only inspection.
---

# Visual PDF Paper to Markdown

Create an archival transcription package whose claims are bound to one source PDF. A structurally valid package is not yet visually verified; completion requires a fresh-context reviewer to compare every included block and final asset with the rendered pages.

## Non-negotiable contract

- Treat rendered PDF pages as the final authority for wording, reading order, metadata, formulas, tables, captions, footnotes, declarations, and the reference cutoff.
- Preserve the source language. Do not summarize, paraphrase, polish, translate, simplify, silently normalize, or omit semantic content.
- Preserve title, authors, affiliations, correspondence, funding, conflicts, data availability, copyright or license text, body footnotes, acknowledgements, appendices, and declarations when present.
- Remove only repeated headers and footers, page numbers, watermarks, download notices, and purely decorative publisher furniture.
- Never invoke OCR or an external recognition service. A user-provided OCR artifact is allowed only in `user-ocr-assisted` mode.
- Read the embedded PDF text layer only after explicit user authorization and only as a draft. It never overrides a rendered page.
- Default to `ReferencePolicy=exclude`: retain every in-text citation and all semantic content before the references heading; exclude the heading and bibliography entries.
- Use PDF-rendered metadata. Query DOI or publisher records only after explicit authorization, report differences, and never silently replace the PDF value.
- Refuse an existing output package. Do not overwrite it, partially update it, or create `.bak` files.
- Use schema v2 only. Do not accept, infer, or migrate v1 manifests.

## Source modes

Choose exactly one mode and record it permanently in `job.csv`:

- `visual-only` is the default. Do not extract embedded text and do not record draft fields.
- `embedded-text-assisted` requires explicit authorization. Use `extract_pdf_text_layer.ps1 -UserAuthorized`, archive the draft, and record its tool, provenance, and hash. Visually correct every draft-derived block.
- `user-ocr-assisted` accepts only a user-supplied artifact. Archive and hash it, set `DraftProducer=user-provided`, and keep `CodexInvokedOcr=false`.

Once a draft has been used, never relabel the task `visual-only`. In every mode, final evidence comes from archived rendered pages.

## Workflow

1. Read [workflow.md](references/workflow.md), [schema.md](references/schema.md), [review-protocol.md](references/review-protocol.md), and [validation.md](references/validation.md) before starting a job.
2. Run the read-only preflight. Confirm the source hash and page count, dependencies, source mode, reference policy, and that the exact output root does not exist.
3. Initialize one package at `电子版/<PDF-stem>/` with `new_transcription_job.ps1`. The source PDF remains in `原始论文`; record only its relative path, size, and SHA-256.
4. Render every page at 300 DPI into `_audit/pages/` as `page-####-300dpi.png`. Re-render only affected pages at 400 DPI as `page-####-400dpi.png`; retain the 300 DPI baseline and make the 400 DPI row authoritative for those pages.
5. Inspect all rendered pages and establish global reading order and the real reference cutoff before transcribing.
6. If authorized, create and archive the permitted draft. Align draft-derived text with block records and record corrections.
7. Transcribe every semantic block and maintain the five CSV manifests. Use stable IDs and one exact, unique full-serialization `MarkdownAnchor` per represented block. Represented anchors must follow `Sequence` without overlap; every non-whitespace Markdown character must belong to a represented block or one registered final-asset link.
8. Export every embedded image candidate with `extract_pdf_images.ps1`, retain all candidates, and record each as `chosen`, `rejected`, or `unmatched`.
9. Prefer a visually complete direct export for figures. Crop only after a typed fallback decision with a concrete reason. Reopen and inspect every final asset.
10. Record `TranscriptionCompleted` only for the initial `initialized -> transcribed` transition, then run `check_markdown_transcription.ps1 -Phase Structural -CommitStatus`. The validation must finish before it atomically commits `StructuralStatus`; correction recovery uses only `CorrectionApplied`.
11. After committed structural success, record `ReviewStarted` and start a cold reviewer with `fork_turns="none"`. The reviewer receives only the source path, archived pages, candidate Markdown, manifests, and review output path. The reviewer writes only `review_findings.csv` and evidence assets. If no reviewer is available, record `ReviewerUnavailable` and stop at `review-pending`.
12. Record `CorrectionRequired` and `CorrectionApplied` around corrections. Have the reviewer recheck affected blocks plus adjacent cross-page or cross-column continuations. Stop after two cycles and record `UserReviewRequired` if uncertainty remains.
13. Run `check_markdown_transcription.ps1 -Phase Final -CommitStatus`. Final commit requires `TranscriptionStatus=transcribed`, `StructuralStatus=structurally-valid`, an active review, and no failed stage. Report structural and independent visual results separately. Claim completion only when the result says `Committed=true` and its status equals `job.csv FinalStatus`.

## Representation rules

- Use `#` for the title, `##` for main sections, and `###` for subsections when this reflects the paper.
- Preserve Unicode prose symbols such as `μm²`, `±`, `Δ`, and `°C`.
- Use `\( ... \)` for inline math and `\[ ... \]` for display math. A numbered display formula includes `\tag{...}`.
- Use Markdown for simple tables, HTML for reliably understood row or column spans, and a precise visual asset only when structure cannot be confirmed.
- Place a figure after its first body citation. Use `assets/figures/figN.ext`; keep its caption out of the image and put editable caption text immediately after it.
- Table and formula assets use their own location rule and never pretend to be figures.
- Never guess uncertain ordinary prose, symbols, or reading order. Such uncertainty blocks verification.

## Completion states

- `verified`: every block and final asset has a fresh independent pass; no visual or structural uncertainty remains.
- `verified-with-fallback`: all prose is confirmed, but an independently reviewed formula or complex table asset remains the authoritative representation.
- `needs-user-review`: any ordinary prose, symbol, reading order, or asset content remains uncertain after at most two review cycles.
- `failed`: source binding, page completeness, schema, structural checks, or asset consistency failed.
- `review-pending`: use only when a fresh reviewer is unavailable. Never describe this state as complete.

Automated validation proves source binding and internal consistency, not that visual comparison happened. A status field or `Status=OK` is not evidence of visual truth by itself.
The checker is read-only unless `-CommitStatus` is present. Use `update_transcription_job_status.ps1` for workflow events; do not hand-edit lifecycle fields. Only the checker may commit `structurally-valid`, `verified`, or `verified-with-fallback`.

## Script entry points

```powershell
.\scripts\preflight_transcription.ps1 -InputPdf "paper.pdf" -OutputRoot "电子版\paper" -SourceMode visual-only
.\scripts\new_transcription_job.ps1 -InputPdf "paper.pdf" -OutputRoot "电子版\paper" -SourceMode visual-only
.\scripts\render_pdf_pages.ps1 -InputPdf "paper.pdf" -OutputDir "电子版\paper\_audit\pages" -Dpi 300 -Clean
.\scripts\render_pdf_pages.ps1 -InputPdf "paper.pdf" -OutputDir "电子版\paper\_audit\pages" -Dpi 400 -FirstPage 7 -LastPage 7
.\scripts\extract_pdf_images.ps1 -InputPdf "paper.pdf" -OutputDir "电子版\paper\_audit\candidates" -Clean -AllowNone
.\scripts\extract_pdf_text_layer.ps1 -InputPdf "paper.pdf" -OutputPath "电子版\paper\_audit\drafts\embedded.txt" -UserAuthorized
.\scripts\crop_pdf_region.ps1 -InputImage "page-0007-400dpi.png" -OutputImage "formula1.png" -Geometry "1200x500+200+900" -AssetManifestPath "assets.csv" -AssetId "formula-001" -RequireManifestDecision
.\scripts\update_transcription_job_status.ps1 -JobManifestPath "job.csv" -Event TranscriptionCompleted
.\scripts\check_markdown_transcription.ps1 -MarkdownPath "paper.md" -JobManifestPath "job.csv" -BlockManifestPath "blocks.csv" -AssetManifestPath "assets.csv" -ImageCandidateManifestPath "image_candidates.csv" -ReviewManifestPath "review_findings.csv" -Phase Structural -CommitStatus
```

Run the tests and both skill validators after changing this skill. Do not use helper scripts to transcribe text; they create, bind, archive, or validate evidence.
