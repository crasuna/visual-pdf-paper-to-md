---
name: visual-pdf-paper-to-md
description: Visual transcription of academic PDF papers into Markdown with complete body transcription, formula fidelity, and direct image export first for figure assets. Use when the user asks to convert a paper PDF to an electronic Markdown version by reading rendered page images, especially when OCR or PDF text extraction must be avoided, references lists should be excluded, figures/tables/formulas/citations should be preserved, formulas must be correctly represented, figure assets should prefer pdfimages direct export before cropping, or paper layout must be reviewed visually.
---

# Visual PDF Paper to Markdown

## Core Rule

Transcribe from rendered page images only when the user requests visual-only PDF transcription. Do not use OCR, embedded PDF text extraction, `pdfplumber`, `pypdf`, copy/paste from selectable PDF text, or external recognition services.

Transcribe the body content completely. Do not summarize, paraphrase, translate, simplify, omit sentences, or silently normalize technical content.

Use tools only to support the visual workflow:

- Render PDF pages to images.
- Inspect images for layout, reading order, figures, tables, formulas, and cutoff points.
- Extract embedded PDF images for asset candidates.
- Record figure asset decisions before cropping.
- Crop figures, tables, or formula blocks into precise asset images only when direct image export is unavailable or visually incomplete.
- Validate the final Markdown and local asset links.

## Workflow

1. Confirm the PDF path, target Markdown path, and output asset folder.
2. Render pages with `scripts/render_pdf_pages.ps1`; use 300 DPI by default, or 400 DPI for small text, dense formulas, or complex figures.
3. Inspect rendered page images visually and determine reading order, section hierarchy, figure/table locations, equations, footnotes, and where the references list begins.
4. Read `references/workflow.md` before transcribing a full paper or any paper with two-column layout, figures, tables, formulas, appendices, or a references cutoff.
5. Create a page-level checklist with `scripts/new_transcription_checklist.ps1` and use it to track reading order, body blocks, formulas, figures/tables, uncertainties, and completion.
6. For figures, first run `scripts/extract_pdf_images.ps1 -ListOnly`, then export candidate embedded images with `scripts/extract_pdf_images.ps1`.
7. Create an asset decision manifest with `scripts/new_asset_decision_manifest.ps1`. Map every figure to exported candidates, choose `direct-export` when the export is visually complete, or record `crop-fallback` with a concrete fallback reason before any figure crop.
8. Fall back to `scripts/crop_pdf_region.ps1` only for figures with a recorded `crop-fallback` decision, and for tables, formulas, vector-only figures, or any directly exported image that is missing labels, legends, color bars, panel markers, or other PDF-overlaid content.
9. Write Markdown by visual transcription with complete body fidelity. Preserve all body text, punctuation, casing, symbols, citations such as `(1)`, `(2,3)`, `(10-12)`, and equation references such as `Eq. [1]`.
10. Convert formulas to Markdown/LaTeX when reliable; for complex or uncertain formulas, include the best verified LaTeX plus a formula crop and record the uncertainty.
11. Exclude the reference list when requested. Keep citations in the body; remove the `REFERENCES` heading and bibliography entries.
12. Embed only verified direct exports or verified crops with relative Markdown image links.
13. Run `scripts/check_markdown_transcription.ps1` on the final Markdown, passing `-AssetManifestPath` when a figure asset manifest exists.

## Text Fidelity Gate

Treat the body text as a complete transcription target.

- Transcribe page by page, column by column, and paragraph by paragraph in the paper's reading order.
- Preserve title, authors, venue/date metadata when present, abstract labels, section headings, subsection headings, body paragraphs, captions, table titles, table notes, acknowledgements, appendices, equations, and in-text citations.
- Preserve original words, punctuation, capitalization, symbols, abbreviations, units, citation markers, and equation references.
- Remove only PDF layout artifacts: column-width line breaks, page headers, page footers, page numbers, watermarks, and publisher sidebars, unless the user asks to keep them.
- Merge a hyphenated line break only when visual inspection confirms the hyphen is a layout break rather than part of the word or term.
- Do not summarize, paraphrase, translate, reorder paragraphs, omit "minor" sentences, or smooth awkward original wording.
- If a word, symbol, or phrase is uncertain, mark it explicitly and list it in the final response instead of guessing.

## Formula Fidelity Gate

Use Markdown/LaTeX as the primary representation for formulas, with image crops as evidence when the formula is complex or uncertain.

- Preserve equation numbers with display math, for example `$$ ... \tag{1} $$`.
- Preserve superscripts, subscripts, Greek letters, vector/bold notation, fraction structure, roots, brackets, matrix or piecewise structure, integrals, summations, limits, differentials, units, punctuation, and equation-ending commas or periods.
- Keep equation references in prose, such as `Eq. [1]`, exactly as they appear.
- For aligned equations, multi-line derivations, or piecewise definitions, use LaTeX environments such as `aligned` or `cases` when they are reliable in Markdown.
- For formulas that cannot be confidently transcribed, write the confirmed LaTeX portion, include a cropped formula image, and record the uncertainty in the page checklist and final response.
- Never replace an equation with only prose unless the user explicitly asks for explanation rather than transcription.

## Image Export Gate

Treat direct export review as a hard gate for figure assets.

- Do not crop a figure before listing embedded image objects, exporting candidate images, visually comparing candidates against the rendered page, and recording the decision in the asset manifest.
- Rendering a page for text/layout review does not satisfy the export gate; rendered pages are comparison material, not permission to crop.
- For each figure, record the rendered page, export candidates, chosen asset, method, visual match conclusion, fallback reason when applicable, reviewer notes, and done status.
- Use `direct-export` when the exported image fully matches the paper figure.
- Use `crop-fallback` only after writing a concrete reason: no export candidate, incomplete export, missing axes/labels/legends/color bars/panel markers, split image objects, transparency mask, unreadable quality, or cannot match the rendered page.
- If a complete direct export is found after a crop was made, replace the crop with the direct export and update the manifest.
- Direct image export is only for figure assets; it is not OCR and must not be used to extract body text, captions, table data, or formulas.

## Image Asset Decision

Prefer direct image export over cropping when it produces a complete visual match.

- Use `pdfimages` through `scripts/extract_pdf_images.ps1` to list and export candidate embedded images.
- Reopen each exported image and compare it against the rendered PDF page.
- Use the exported image directly when it contains the full figure as it appears in the paper.
- Do not use a direct export if it contains only a bitmap underlay, lacks PDF-overlaid axis labels or legends, exports a transparency mask, splits a multi-panel figure into unrelated pieces, or cannot be matched to the rendered page.
- Use precise cropping from rendered pages for tables, formulas, vector-only figures, composite figures, or incomplete direct exports only after the export gate decision is recorded for figures.
- Direct image export is only for figure assets; it is not OCR and must not be used to extract body text.

## Screenshot Precision Gate

Treat every exported or cropped image as a quality-gated artifact. An image asset is acceptable only when it passes visual review after creation.

- Preserve all content that belongs to the figure, table, or formula block: axes, tick labels, units, legends, color bars, scale bars, panel letters, table borders, column headers, equation numbers, and inset labels.
- Keep a small, even margin around the cropped object. Prefer a little extra whitespace over cutting off labels, curves, symbols, or borders.
- Exclude caption text when the caption will be transcribed separately in Markdown.
- Exclude unrelated body text, page headers, page footers, sidebars, watermarks, neighboring figures, and neighboring table rows.
- Re-crop immediately if any edge is tight, a label is clipped, a color bar is incomplete, the image includes unrelated prose, or the crop is too small to inspect comfortably.
- For multi-panel figures, crop the full figure when panels share legends, axes, or color bars; crop individual panels only when the paper layout and caption clearly treat them independently.

## Output Conventions

- Prefer an `电子版` directory near the source PDF when the workspace uses Chinese paper organization; otherwise use `markdown`.
- Place images in an assets directory beside the Markdown, for example `<paper-stem>_assets`.
- Place the figure asset decision manifest beside the Markdown or inside the assets directory.
- If the target Markdown already exists, copy it to `<name>.md.bak` before overwriting.
- Do not include page headers, footers, page numbers, watermarks, publisher sidebars, or correspondence footnotes unless the user explicitly asks for them.
- Convert tables to editable Markdown tables when the visual structure is clear; otherwise embed a cropped table image and explain uncertainty.
- Write formulas in Markdown math where possible and preserve the original equation numbers.

## Helper Scripts

Use these scripts from the skill directory:

```powershell
.\scripts\render_pdf_pages.ps1 -InputPdf "paper.pdf" -OutputDir "$env:TEMP\paper-pages" -Dpi 300 -Clean
.\scripts\new_transcription_checklist.ps1 -InputPdf "paper.pdf" -OutputPath ".\paper_checklist.md" -RenderedImageDir "$env:TEMP\paper-pages"
.\scripts\extract_pdf_images.ps1 -InputPdf "paper.pdf" -OutputDir ".\paper_assets\extracted" -ListOnly
.\scripts\extract_pdf_images.ps1 -InputPdf "paper.pdf" -OutputDir ".\paper_assets\extracted" -Clean
.\scripts\new_asset_decision_manifest.ps1 -OutputPath ".\paper_assets\asset_decision_manifest.csv" -FigureCount 4 -Force
.\scripts\crop_pdf_region.ps1 -InputImage "$env:TEMP\paper-pages\page-1.png" -OutputImage ".\paper_assets\fig1.png" -Geometry "1200x700+300+450" -MinWidth 600 -MinHeight 300
.\scripts\check_markdown_transcription.ps1 -MarkdownPath ".\paper.md" -AssetManifestPath ".\paper_assets\asset_decision_manifest.csv"
```

The scripts do not transcribe text. They only prepare image assets and check final-file integrity.
