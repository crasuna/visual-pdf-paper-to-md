---
name: visual-pdf-paper-to-md
description: Academic PDF paper to Markdown transcription with complete body fidelity, formula fidelity, direct image export first for figure assets, and strict full-paper manifests. Supports visual-only transcription when OCR/PDF text extraction must be avoided, and text-layer-assisted drafts when the user explicitly allows PDF text extraction; in all cases final text must be verified against rendered page images. Use when references lists should be excluded, body text must be transcribed completely, figures/tables/formulas/citations should be preserved, formulas must be correctly represented, or paper layout must be reviewed visually.
---

# Visual PDF Paper to Markdown

## Core Rule

Use rendered page images as the final source of truth. When the user explicitly asks for visual-only transcription or says not to use text extraction, transcribe from rendered page images only and do not use OCR, embedded PDF text extraction, `pdftotext`, `pdfplumber`, `pypdf`, copy/paste from selectable PDF text, or external recognition services.

When the user explicitly allows PDF text extraction, use embedded PDF text only as a draft aid. Every sentence, heading, caption, table value, formula, citation marker, and symbol in the final Markdown must still be checked against the rendered page images, page by page and block by block. Do not use OCR or external recognition services in either mode.

Transcribe the body content completely. Do not summarize, paraphrase, translate, simplify, omit sentences, or silently normalize technical content.

Use tools only to support the visual workflow:

- Render PDF pages to images.
- Inspect images for layout, reading order, figures, tables, formulas, and cutoff points.
- Extract embedded PDF text only in text-layer-assisted mode, and record its use in the text layer draft manifest.
- Extract embedded PDF images for asset candidates.
- Record figure asset decisions before cropping.
- Crop figures, tables, or formula blocks into precise asset images only when direct image export is unavailable or visually incomplete.
- Maintain strict manifests for block coverage, metadata, reference cutoff, image candidates, figure assets, formulas, and text-layer draft provenance when used during full-paper jobs.
- Validate the final Markdown and local asset links.

## Source Modes

- `Visual-only`: Use when the user forbids text extraction, requests visual-only transcription, or the PDF text layer is misleading. Rendered page images are the only text source.
- `Text-layer-assisted`: Use only when the user explicitly permits text extraction. `pdftotext`, `pdfplumber`, or `pypdf` may create a rough draft, but visual inspection controls reading order, corrections, final wording, symbols, formulas, tables, captions, metadata, and reference cutoff.
- In text-layer-assisted mode, never mark a block complete until the rendered page image and final Markdown have been compared word by word. Record the draft source, visual anchors, corrections, Markdown anchor, and checked status in `scripts/new_text_layer_draft_manifest.ps1`.
- Do not treat a clean-looking text layer as reliable evidence. Record low-quality draft output, missing spaces, wrong order, or other corrections in `CorrectionsMade` and `Notes`; the visually checked Markdown always overrides the draft.

## Workflow

1. Confirm the PDF path, target Markdown path, and output asset folder.
2. Render pages with `scripts/render_pdf_pages.ps1`; use 300 DPI by default, or 400 DPI for small text, dense formulas, or complex figures.
3. Inspect rendered page images visually and determine reading order, section hierarchy, figure/table locations, equations, footnotes, and where the references list begins.
4. Read `references/workflow.md` before transcribing a full paper or any paper with two-column layout, figures, tables, formulas, appendices, or a references cutoff.
5. Choose the source mode. If text-layer-assisted mode is allowed, extract the embedded PDF text only after page rendering and initial visual layout inspection; create a text layer draft manifest with `scripts/new_text_layer_draft_manifest.ps1` and fill it while visually correcting the draft.
6. Create a page-level checklist with `scripts/new_transcription_checklist.ps1`, then create a block coverage manifest with `scripts/new_block_coverage_manifest.ps1` for every title, metadata block, heading, paragraph, caption, table, formula, acknowledgement, appendix, and cutoff block.
7. Create a metadata manifest with `scripts/new_metadata_manifest.ps1` and a reference cutoff manifest with `scripts/new_reference_cutoff_manifest.ps1`. Verify metadata and cutoff points visually from rendered page images.
8. For figures, first run `scripts/extract_pdf_images.ps1 -ListOnly`, then export candidate embedded images with `scripts/extract_pdf_images.ps1`, and record all candidates with `scripts/new_image_candidate_manifest.ps1`.
9. Create an asset decision manifest with `scripts/new_asset_decision_manifest.ps1`. Map every figure to exported candidates, choose `direct-export` when the export is visually complete, or record `crop-fallback` with a concrete fallback reason before any figure crop.
10. Fall back to `scripts/crop_pdf_region.ps1` only for figures with a recorded `crop-fallback` decision; pass `-AssetManifestPath`, `-Figure`, and `-RequireManifestDecision` for figure crops.
11. Write Markdown with complete body fidelity. Preserve all body text, punctuation, casing, Unicode symbols, citations such as `(1)`, `(2,3)`, `(10-12)`, and equation references such as `Eq. [1]`; in text-layer-assisted mode, visually verify and correct every draft block before treating it as final.
12. Convert formulas to Markdown/LaTeX when reliable; for complex or uncertain formulas, include the best verified LaTeX plus a formula crop and record discovery and transcription status in `scripts/new_formula_manifest.ps1`.
13. Exclude the reference list when requested. Keep citations in the body; remove the `REFERENCES` heading and bibliography entries.
14. Embed only verified direct exports or verified crops with relative Markdown image links.
15. Run `scripts/check_markdown_transcription.ps1 -StrictFullPaper` on full-paper jobs with `-ChecklistPath` and all required manifests. Add `-TextLayerAssisted -TextLayerDraftManifestPath ...` when embedded PDF text was used. Use `-ReferencePolicy Keep` only when the user explicitly asks to keep the reference list.

## Markdown Style Contract

Use one stable Markdown style for full-paper transcriptions.

- Use Unicode symbols in prose when the rendered page shows them, such as `μm²`, `±`, `Δ`, and `°C`; keep formulas in LaTeX.
- Use `#` for the paper title, `##` for main sections, and `###` for subsections. Do not over-heading metadata or abstract labels unless the paper presents them as section headings.
- Place each figure after its first in-text citation, even when the PDF visually floats the figure elsewhere.
- Name final figure assets as `figN.ext`, preserving the chosen asset extension; direct exports may remain `.jpg`, `.png`, or another original image extension.
- Keep figure images free of captions. Transcribe captions as editable Markdown immediately after the image, starting with `**Fig. N.**`.
- Convert clear tables to editable Markdown tables. Use a table image only when the visual structure is too uncertain, and record the reason in the block manifest notes.
- Use display math with `\tag{...}` for numbered formulas, and keep equation references in prose exactly as rendered.

## Text Fidelity Gate

Treat the body text as a complete transcription target.

- Transcribe page by page, column by column, and paragraph by paragraph in the paper's reading order.
- In text-layer-assisted mode, use the PDF text layer only as a draft; each final block must be visually compared against the rendered page image word by word before it is marked checked.
- Preserve title, authors, venue/date metadata when present, abstract labels, section headings, subsection headings, body paragraphs, captions, table titles, table notes, acknowledgements, appendices, equations, and in-text citations.
- Preserve original words, punctuation, capitalization, symbols, abbreviations, units, citation markers, and equation references.
- Remove only PDF layout artifacts: column-width line breaks, page headers, page footers, page numbers, watermarks, and publisher sidebars, unless the user asks to keep them.
- Merge a hyphenated line break only when visual inspection confirms the hyphen is a layout break rather than part of the word or term.
- Do not summarize, paraphrase, translate, reorder paragraphs, omit "minor" sentences, or smooth awkward original wording.
- If a word, symbol, or phrase is uncertain, mark it explicitly and list it in the final response instead of guessing.

## Block Coverage Gate

For full-paper transcription, page-level completion is not enough.

- Create a block coverage manifest and record every transcribed or intentionally omitted body block.
- In text-layer-assisted mode, create a text layer draft manifest and align each draft-derived block with its corresponding block coverage row.
- Use fixed fields: `Page`, `ColumnOrRegion`, `BlockType`, `Section`, `FirstWords`, `LastWords`, `MarkdownAnchor`, `Checked`, and `Notes`.
- Treat titles, author/venue metadata, abstract labels, headings, paragraphs, captions, tables, formulas, acknowledgements, appendices, and reference cutoff markers as blocks.
- Mark `Checked` only after visually comparing the block against the rendered page and confirming the matching Markdown location.
- `MarkdownAnchor` must be an exact literal substring that exists in the final Markdown; do not rely on fuzzy or approximate matching.
- In text-layer-assisted mode, every text-layer draft row must match a block coverage row by `Page + BlockType + MarkdownAnchor`.

## Metadata Audit Gate

Record paper metadata separately so repeated transcriptions do not drift.

- Create a metadata manifest for `Title`, `Authors`, `Journal`, `Year`, `VolumeIssuePages`, and `DOI`.
- Read metadata only from rendered page images unless the user allows another source.
- Use `N/A` only when a metadata field is visually absent from the paper, and explain it in `Notes`.
- Mark `Checked` only after the Markdown value matches the visually read value; strict checks require each non-`N/A` `MarkdownValue` to appear literally in the final Markdown.

## Formula Fidelity Gate

Use Markdown/LaTeX as the primary representation for formulas, with image crops as evidence when the formula is complex or uncertain.

- Preserve equation numbers with display math, for example `$$ ... \tag{1} $$`.
- Preserve superscripts, subscripts, Greek letters, vector/bold notation, fraction structure, roots, brackets, matrix or piecewise structure, integrals, summations, limits, differentials, units, punctuation, and equation-ending commas or periods.
- Keep equation references in prose, such as `Eq. [1]`, exactly as they appear.
- For aligned equations, multi-line derivations, or piecewise definitions, use LaTeX environments such as `aligned` or `cases` when they are reliable in Markdown.
- For formulas that cannot be confidently transcribed, write the confirmed LaTeX portion, include a cropped formula image, and record the uncertainty in the page checklist and final response.
- For papers with numbered display formulas, create a formula manifest and keep `MarkdownTag` values aligned with every Markdown `\tag{...}`.
- The formula manifest records both discovery and transcription: source page/block, visual number, Markdown tag, Markdown anchor, screenshot fallback, uncertainty, and review status.
- Never replace an equation with only prose unless the user explicitly asks for explanation rather than transcription.

## Image Export Gate

Treat direct export review as a hard gate for figure assets.

- Do not crop a figure before listing embedded image objects, exporting candidate images, visually comparing candidates against the rendered page, and recording the decision in the asset manifest.
- Rendering a page for text/layout review does not satisfy the export gate; rendered pages are comparison material, not permission to crop.
- For each figure, record the rendered page, export candidates, chosen asset, method, visual match conclusion, fallback reason when applicable, reviewer notes, and done status.
- Use `direct-export` when the exported image fully matches the paper figure; record `VisualMatch` as `complete` and list the export candidate file.
- Record every exported candidate in the image candidate manifest. Use `Decision=chosen`, `rejected`, or `unmatched`; every rejected candidate needs a concrete `RejectReason`.
- Use `crop-fallback` only after writing a concrete reason: no export candidate, incomplete export, missing axes/labels/legends/color bars/panel markers, split image objects, transparency mask, unreadable quality, or cannot match the rendered page.
- Use only these asset manifest values: `Method` is `direct-export` or `crop-fallback`; `VisualMatch` is `complete`, `incomplete`, or `not-matched`.
- Record `FirstCitationAnchor`, `PlacementBasis=first-citation`, and checked placement for every final figure asset. Use a unique snippet from the first body citation, not caption text.
- If a complete direct export is found after a crop was made, replace the crop with the direct export and update the manifest.
- Direct image export is only for figure assets; it is not OCR and must not be used to extract body text, captions, table data, or formulas.

## Image Asset Decision

Prefer direct image export over cropping when it produces a complete visual match. The detailed decision checklist lives in `references/workflow.md`.

- Use `pdfimages` through `scripts/extract_pdf_images.ps1` to list and export candidate embedded images.
- Use the exported image directly only when it contains the full figure as it appears in the paper.
- Use cropping only after the export gate decision is recorded for figures.
- Direct image export is only for figure assets; it is not OCR and must not be used to extract body text, captions, table data, or formulas.

## Screenshot Precision Gate

Treat every exported or cropped image as a quality-gated artifact. Use `references/workflow.md` for the detailed precision checklist.

- Preserve all content that belongs to the figure, table, or formula block: axes, tick labels, units, legends, color bars, scale bars, panel letters, table borders, column headers, equation numbers, and inset labels.
- Exclude caption text when the caption will be transcribed separately in Markdown.
- Reopen every created image and immediately replace, re-export, or re-crop it if visual review fails.

## Reference Cutoff Gate

When the user excludes the reference list, record the cutoff explicitly.

- Create a reference cutoff manifest with `ReferencePolicy`, `CutoffPage`, `CutoffHeading`, `LastIncludedBlock`, `ExcludedAfterHeading`, `Checked`, and `Notes`.
- For `ReferencePolicy=Exclude`, transcribe all body content before the references heading, including appendices or acknowledgements that appear before it.
- Do not transcribe the references heading or bibliography entries under `Exclude`.
- Keep all in-text citation markers in the body.

## Output Conventions

- Prefer an `电子版` directory near the source PDF when the workspace uses Chinese paper organization; otherwise use `markdown`.
- Place images in an assets directory beside the Markdown, for example `<paper-stem>_assets`.
- Place manifests beside the Markdown or inside the assets directory.
- If the target Markdown already exists, copy it to `<name>.md.bak` before overwriting.
- Do not include page headers, footers, page numbers, watermarks, publisher sidebars, or correspondence footnotes unless the user explicitly asks for them.
- Convert tables to editable Markdown tables when the visual structure is clear; otherwise embed a cropped table image and explain uncertainty.
- Write formulas in Markdown math where possible and preserve the original equation numbers.
- Final responses must list the Markdown path, asset directory, manifest/checklist paths, source mode, reference policy, validation commands, and uncertainties. If none remain, write that no visually uncertain transcription points were found.

## Helper Scripts

Use these scripts from the skill directory:

```powershell
.\scripts\render_pdf_pages.ps1 -InputPdf "paper.pdf" -OutputDir "$env:TEMP\paper-pages" -Dpi 300 -Clean
.\scripts\new_transcription_checklist.ps1 -InputPdf "paper.pdf" -OutputPath ".\paper_checklist.md" -RenderedImageDir "$env:TEMP\paper-pages"
.\scripts\new_text_layer_draft_manifest.ps1 -OutputPath ".\paper_assets\text_layer_draft_manifest.csv" -BlockCount 20 -Force
.\scripts\new_block_coverage_manifest.ps1 -OutputPath ".\paper_assets\block_coverage_manifest.csv" -BlockCount 20 -Force
.\scripts\new_metadata_manifest.ps1 -OutputPath ".\paper_assets\metadata_manifest.csv" -Force
.\scripts\new_reference_cutoff_manifest.ps1 -OutputPath ".\paper_assets\reference_cutoff_manifest.csv" -ReferencePolicy Exclude -Force
.\scripts\extract_pdf_images.ps1 -InputPdf "paper.pdf" -OutputDir ".\paper_assets\extracted" -ListOnly
.\scripts\extract_pdf_images.ps1 -InputPdf "paper.pdf" -OutputDir ".\paper_assets\extracted" -Clean -AllowNone
.\scripts\new_image_candidate_manifest.ps1 -OutputPath ".\paper_assets\image_candidate_manifest.csv" -ImageDir ".\paper_assets\extracted" -Force
.\scripts\new_asset_decision_manifest.ps1 -OutputPath ".\paper_assets\asset_decision_manifest.csv" -FigureCount 4 -Force
.\scripts\new_formula_manifest.ps1 -OutputPath ".\paper_assets\formula_manifest.csv" -FormulaCount 4 -Force
.\scripts\crop_pdf_region.ps1 -InputImage "$env:TEMP\paper-pages\page-1.png" -OutputImage ".\paper_assets\fig1.png" -Geometry "1200x700+300+450" -MinWidth 600 -MinHeight 300 -AssetManifestPath ".\paper_assets\asset_decision_manifest.csv" -Figure "Figure 1" -RequireManifestDecision
.\scripts\check_markdown_transcription.ps1 -MarkdownPath ".\paper.md" -ChecklistPath ".\paper_checklist.md" -BlockManifestPath ".\paper_assets\block_coverage_manifest.csv" -MetadataManifestPath ".\paper_assets\metadata_manifest.csv" -ReferenceCutoffManifestPath ".\paper_assets\reference_cutoff_manifest.csv" -ImageCandidateManifestPath ".\paper_assets\image_candidate_manifest.csv" -AssetManifestPath ".\paper_assets\asset_decision_manifest.csv" -FormulaManifestPath ".\paper_assets\formula_manifest.csv" -StrictFullPaper -RequireAssetManifest -ReferencePolicy Exclude
.\scripts\check_markdown_transcription.ps1 -MarkdownPath ".\paper.md" -ChecklistPath ".\paper_checklist.md" -BlockManifestPath ".\paper_assets\block_coverage_manifest.csv" -MetadataManifestPath ".\paper_assets\metadata_manifest.csv" -ReferenceCutoffManifestPath ".\paper_assets\reference_cutoff_manifest.csv" -ImageCandidateManifestPath ".\paper_assets\image_candidate_manifest.csv" -AssetManifestPath ".\paper_assets\asset_decision_manifest.csv" -FormulaManifestPath ".\paper_assets\formula_manifest.csv" -TextLayerDraftManifestPath ".\paper_assets\text_layer_draft_manifest.csv" -StrictFullPaper -TextLayerAssisted -RequireAssetManifest -ReferencePolicy Exclude
```

The scripts do not transcribe text. They only prepare image assets and check final-file integrity.
