# Visual Paper Transcription Workflow

Use this checklist for academic PDF-to-Markdown transcription when the source must be read visually.

## Preparation

- Render all pages to PNG, preferably 300 DPI.
- Use 400 DPI when labels, equations, or table text are small enough that 300 DPI crops are hard to inspect.
- Open representative pages at high detail: first page, a typical body page, a figure-heavy page, and the last page.
- Identify page layout: one column, two column, mixed layout, footnotes, appendices, sidebars, and publisher watermarks.
- Decide the cutoff before transcribing: for most papers this is the `References`, `REFERENCES`, or `Bibliography` heading.
- Generate a page-level checklist with `scripts/new_transcription_checklist.ps1` and update it as each page is transcribed and reviewed.

## Page-Level Checklist

- Record the reading order blocks for each page before writing: column order, abstract boxes, footnotes, figures, tables, appendices, and continuation paragraphs.
- Mark cross-page and cross-column paragraphs so the final Markdown preserves paragraph continuity.
- Track every formula number, figure number, table number, caption, and appendix block on the page.
- Record the reference-list cutoff page and the exact heading where transcription stops when references are excluded.
- Record uncertain words, symbols, or formulas immediately; resolve them during page review or report them in the final response.

## Image Asset Decision

- Follow this gate in order for figure assets: list embedded objects -> export candidates -> inspect exported images -> map candidates to figures on rendered pages -> record the decision in the asset manifest -> only then crop fallback figures.
- First list embedded image objects with `scripts/extract_pdf_images.ps1 -ListOnly`.
- Export embedded images with `scripts/extract_pdf_images.ps1`; use `-AllowNone` when no embedded images is an acceptable fallback condition.
- Create an asset decision manifest with `scripts/new_asset_decision_manifest.ps1`.
- Use a directly exported image when it fully matches the paper figure on the rendered page. Record `Method=direct-export`, `VisualMatch=complete`, and the exported file in `ExportCandidates`.
- Fall back to page cropping only when direct export is absent, incomplete, or visually different from the rendered page, and only after writing `Method=crop-fallback`, `FallbackReason`, and a controlled `VisualMatch` value in the manifest.
- Common direct-export failures: a bitmap underlay without vector labels, a transparency mask, missing axes or legends, missing color bars, split multi-panel figures, duplicated fragments, or objects whose order does not match the visual reading order.
- Use only these manifest values: `Method` is `direct-export` or `crop-fallback`; `VisualMatch` is `complete`, `incomplete`, or `not-matched`.
- Confirm exported image order by comparing against rendered pages; do not assume `pdfimages` numbering equals figure numbering.
- Do not skip exported-image review just because rendered pages already exist.
- Do not treat cropping as the default figure workflow.
- Do not assume `pdfimages` file names or object order equal figure numbers.
- Ensure every final Markdown figure link appears as a `ChosenAsset` in the asset decision manifest.
- When cropping a fallback figure, call `scripts/crop_pdf_region.ps1` with `-AssetManifestPath`, `-Figure`, and `-RequireManifestDecision`.
- Use direct exports only for images. Continue visual transcription for text, captions, formulas, and table data.

## Screenshot Precision Checklist

- Inspect the full rendered page first. If direct export is incomplete, make a rough crop, then refine the crop boundary.
- Keep all figure/table/formula-owned content: axes, tick labels, units, legends, color bars, scale bars, panel letters, inset labels, table borders, table headers, and equation numbers.
- Keep a small, even white margin. Extra whitespace is acceptable; clipped labels, curves, borders, or symbols are not.
- Exclude captions when captions are transcribed as Markdown text below the image.
- Exclude body prose, page headers, page footers, sidebars, watermarks, neighboring panels, and neighboring tables unless they are part of the intended figure.
- For multi-panel figures, verify each panel marker and any shared legend or color bar are present.
- For tables, verify the top header row, left label column, units, footnote markers, and bottom rule are visible.
- For formulas, verify the complete expression and equation number are visible.
- Reopen every exported or cropped image after creating it. Re-export, choose a different candidate, or re-crop if any required visual element is missing.

## Transcription

- Transcribe the body content completely: no summaries, paraphrases, translations, omitted sentences, or silent simplification.
- Preserve title, authors, venue/date metadata, abstract labels, headings, subheadings, body paragraphs, acknowledgements, appendices, captions, tables, and equations.
- Preserve body citation markers exactly: `(1)`, `(2,3)`, `(10-12)`, `(28,29)`, `[A1]`, `Eq. [1]`.
- Preserve punctuation, capitalization, symbols, abbreviations, units, and original wording even when the source phrasing is awkward.
- Remove visual line breaks from columns; merge hyphenated line breaks only when the word is clearly broken by layout.
- Omit headers, footers, page numbers, download notices, publisher side text, and copyright blocks unless they are part of the requested content.
- Convert clear tables to Markdown tables; keep units and `N/A` values.
- Embed figures as directly exported image assets when visually complete; otherwise embed precise cropped assets. Transcribe captions as editable Markdown text.

## Formula Fidelity

- Write reliably read formulas in Markdown/LaTeX and keep original numbering with `\tag{...}`.
- Preserve superscripts, subscripts, Greek letters, vector/bold notation, hats/bars/dots, fractions, roots, brackets, matrices, piecewise cases, integrals, sums, limits, differentials, units, and terminal punctuation.
- For aligned or multi-line equations, use `aligned`; for piecewise definitions, use `cases`.
- Verify equation references in prose still point to the correct displayed formula.
- For papers with numbered display formulas, create a formula manifest with `scripts/new_formula_manifest.ps1`; every Markdown `\tag{...}` should appear as a `MarkdownTag`.
- If a formula is visually uncertain, include a formula crop as an asset, transcribe only the confirmed parts, and record the uncertainty in the checklist and formula manifest.
- Do not replace formulas with explanations. Explanations can be added only if the user separately asks for them.

## Reference List Cutoff

- Stop before the references list when the user asks not to extract references.
- Do not remove in-text citations just because the bibliography is excluded.
- If the final page has appendix content before references, transcribe appendix content first, then stop at the references heading.

## Verification

- Compare the Markdown against rendered pages by page, column, and paragraph.
- Use the page-level checklist to confirm every body block, caption, table, formula, appendix block, and intentional reference-list omission is accounted for.
- Check that all image links resolve from the Markdown file location.
- Inspect all embedded images, not only their paths. Confirm each image is the intended figure/table/formula and is not a loose page screenshot.
- Run `scripts/check_markdown_transcription.ps1` with `-ChecklistPath` and `-RequireAssetManifest` for full-paper jobs.
- Check the asset decision manifest. Confirm every Markdown image link is recorded as a chosen asset, every `crop-fallback` row has a reason, and every asset row is marked done after visual review.
- Check the formula manifest when present. Confirm every `MarkdownTag` appears in Markdown and every Markdown `\tag{...}` is recorded.
- Search for accidental bibliography headings or numbered reference entries.
- Check formula tags, equation references, key values, units, figure captions, table values, and appendix equation numbers.
- Record any visually uncertain words or symbols in the final response rather than silently guessing.
