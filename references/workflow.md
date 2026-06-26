# Visual Paper Transcription Workflow

Use this checklist for academic PDF-to-Markdown transcription when the source must be read visually.

## Preparation

- Render all pages to PNG, preferably 300 DPI.
- Use 400 DPI when labels, equations, or table text are small enough that 300 DPI crops are hard to inspect.
- Treat Poppler font warnings during rendering as non-blocking only when PNG files are created and visual inspection confirms that text, symbols, equations, and figure labels render correctly.
- If rendered pages show missing glyphs, wrong symbols, garbled text, or visibly damaged formulas, switch rendering tools, increase DPI, or use screenshot/formula-image fallbacks before transcription.
- Open representative pages at high detail: first page, a typical body page, a figure-heavy page, and the last page.
- Identify page layout: one column, two column, mixed layout, footnotes, appendices, sidebars, and publisher watermarks.
- Decide the cutoff before transcribing: for most papers this is the `References`, `REFERENCES`, or `Bibliography` heading.
- Choose the source mode before drafting. Use visual-only when text extraction is forbidden or unreliable; use text-layer-assisted only when the user explicitly allows embedded PDF text extraction.
- Generate a page-level checklist with `scripts/new_transcription_checklist.ps1` and update it as each page is transcribed and reviewed.
- For full-paper jobs, also create block coverage, metadata, reference cutoff, image candidate, asset decision, and formula manifests before final verification. Create a text layer draft manifest when text-layer-assisted mode is used.

## Source Modes

- `Visual-only`: Rendered page images are the only text source. Do not use OCR, embedded PDF text extraction, selectable text copy/paste, or external recognition services.
- `Text-layer-assisted`: Embedded PDF text may be extracted with tools such as `pdftotext`, `pdfplumber`, or `pypdf` only to create a rough draft. The rendered page image remains the authority for every final word, symbol, citation, table value, caption, formula, and cutoff decision.
- In text-layer-assisted mode, record every draft-derived block in `scripts/new_text_layer_draft_manifest.ps1` with draft anchors, visual anchors, Markdown anchor, corrections, and visual checked status.
- Do not automatically trust the text layer quality. Record missing spaces, wrong reading order, bad ligatures, dropped symbols, or other low-quality draft behavior in `CorrectionsMade` and `Notes`.
- Do not use OCR or external recognition services in either mode.

## Markdown Style Contract

- Use Unicode symbols in prose when visually present, such as `μm²`, `±`, `Δ`, and `°C`; use LaTeX inside formulas.
- Use heading levels consistently: paper title `#`, main sections `##`, subsections `###`.
- Insert each figure after its first in-text citation, not at the PDF floating position.
- Name final figure assets `figN.ext`, preserving the selected image extension.
- Keep captions out of image assets and transcribe them as editable text beginning with `**Fig. N.**`.
- Convert visually clear tables to Markdown tables. Use a table image only with an uncertainty note.
- Use display math and `\tag{...}` for numbered formulas.

## Page-Level Checklist

- Record the reading order blocks for each page before writing: column order, abstract boxes, footnotes, figures, tables, appendices, and continuation paragraphs.
- Mark cross-page and cross-column paragraphs so the final Markdown preserves paragraph continuity.
- Track every formula number, figure number, table number, caption, and appendix block on the page.
- Record the reference-list cutoff page and the exact heading where transcription stops when references are excluded.
- Record uncertain words, symbols, or formulas immediately; resolve them during page review or report them in the final response.

## Block Coverage Manifest

- Create `scripts/new_block_coverage_manifest.ps1` for full-paper transcription.
- Record one row per transcribed or intentionally omitted block: title, metadata, heading, paragraph, caption, table, formula, acknowledgement, appendix, and cutoff marker.
- Fill `Page`, `ColumnOrRegion`, `BlockType`, `Section`, `FirstWords`, `LastWords`, `MarkdownAnchor`, `Checked`, and `Notes`.
- Use `FirstWords` and `LastWords` as visual anchors, not summaries.
- Use `MarkdownAnchor` as an exact literal substring that appears in the final Markdown; avoid anchors that are only conceptual labels or approximate paraphrases.
- Mark `Checked` only after comparing the rendered page block against the final Markdown.
- Do not treat page-level `Done` as sufficient when block rows are unchecked.

## Text Layer Draft Manifest

- Create `scripts/new_text_layer_draft_manifest.ps1` only when embedded PDF text is used as a draft aid.
- Record one row per draft-derived block with `Page`, `ColumnOrRegion`, `BlockType`, `Section`, `TextLayerTool`, `DraftSource`, `DraftFirstWords`, `DraftLastWords`, `VisualFirstWords`, `VisualLastWords`, `MarkdownAnchor`, `CorrectionsMade`, `VisualChecked`, and `Notes`.
- Use `DraftFirstWords` and `DraftLastWords` to identify what the PDF text layer produced; use `VisualFirstWords` and `VisualLastWords` to prove the final block was checked against the rendered page.
- Use `MarkdownAnchor` as the same literal Markdown substring recorded in the block coverage manifest for the corresponding row.
- In `Text-layer-assisted` verification, every text-layer draft row must match a block coverage row by `Page + BlockType + MarkdownAnchor`.
- Write `CorrectionsMade=none` only when visual comparison confirms the draft needed no correction.
- Mark `VisualChecked` only after word-by-word comparison against the rendered page image.

## Metadata Manifest

- Create `scripts/new_metadata_manifest.ps1` and fill `Title`, `Authors`, `Journal`, `Year`, `VolumeIssuePages`, and `DOI`.
- Read values from rendered page images. Do not repair metadata from external knowledge unless the user explicitly allows it.
- Use `N/A` only when a field is visually absent and explain that in `Notes`.
- Mark `Checked` only when the Markdown metadata matches the visually read value.
- In strict checks, every non-`N/A` `MarkdownValue` must appear literally in the final Markdown. If `MarkdownValue` is `N/A`, `Notes` must explain why the field is visually absent.

## Image Asset Decision

- Follow this gate in order for figure assets: list embedded objects -> export candidates -> inspect exported images -> map candidates to figures on rendered pages -> record the decision in the asset manifest -> only then crop fallback figures.
- First list embedded image objects with `scripts/extract_pdf_images.ps1 -ListOnly`.
- Export embedded images with `scripts/extract_pdf_images.ps1`; use `-AllowNone` when no embedded images is an acceptable fallback condition.
- Create an asset decision manifest with `scripts/new_asset_decision_manifest.ps1`.
- Create an image candidate manifest with `scripts/new_image_candidate_manifest.ps1` after exporting candidate images.
- Record every exported candidate, including masks, fragments, duplicate objects, and non-paper UI artifacts.
- Use `Decision=chosen` for the candidate that becomes a direct-export figure asset, `rejected` for candidates that were reviewed and rejected, and `unmatched` for candidates that cannot be mapped to a paper figure.
- Fill `RejectReason` for every rejected candidate.
- Use a directly exported image when it fully matches the paper figure on the rendered page. Record `Method=direct-export`, `VisualMatch=complete`, and the exported file in `ExportCandidates`.
- Fall back to page cropping only when direct export is absent, incomplete, or visually different from the rendered page, and only after writing `Method=crop-fallback`, `FallbackReason`, and a controlled `VisualMatch` value in the manifest.
- Common direct-export failures: a bitmap underlay without vector labels, a transparency mask, missing axes or legends, missing color bars, split multi-panel figures, duplicated fragments, or objects whose order does not match the visual reading order.
- Use only these manifest values: `Method` is `direct-export` or `crop-fallback`; `VisualMatch` is `complete`, `incomplete`, or `not-matched`.
- Confirm exported image order by comparing against rendered pages; do not assume `pdfimages` numbering equals figure numbering.
- Do not skip exported-image review just because rendered pages already exist.
- Do not treat cropping as the default figure workflow.
- Do not assume `pdfimages` file names or object order equal figure numbers.
- Ensure every final Markdown figure link appears as a `ChosenAsset` in the asset decision manifest.
- Ensure direct-export rows have at least one `ExportCandidates` entry marked `Decision=chosen` in the image candidate manifest.
- Fill `FirstCitationAnchor`, set `PlacementBasis=first-citation`, and mark `PlacementChecked` after confirming the Markdown figure is placed after its first citation.
- Use a short, unique `FirstCitationAnchor` from the first body citation sentence, such as a phrase containing `Fig. 1`; do not use caption text such as `**Fig. 1.**`.
- In strict checks, `FirstCitationAnchor` must appear literally in the final Markdown, `ChosenAsset` must match a Markdown image link, and the image link must appear after that anchor.
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
- In text-layer-assisted mode, treat extracted text as a draft to correct, not as evidence. Fix reading order, missing spaces, hyphenation, ligatures, mathematical symbols, superscripts/subscripts, units, and punctuation from the rendered page image.
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
- For papers with numbered display formulas, create a formula manifest with `scripts/new_formula_manifest.ps1`; every visual formula discovery and every Markdown `\tag{...}` must be recorded.
- Fill `SourcePage`, `SourceBlock`, `VisualNumber`, `MarkdownTag`, `MarkdownAnchor`, `DiscoveryChecked`, `TranscriptionChecked`, and `Done`.
- Set `MarkdownAnchor` to a literal formula substring in the final Markdown, such as the exact `\tag{...}` or a distinctive LaTeX fragment.
- If a formula is visually uncertain, include a formula crop as an asset, transcribe only the confirmed parts, and record the uncertainty in the checklist and formula manifest.
- Do not replace formulas with explanations. Explanations can be added only if the user separately asks for them.

## Reference List Cutoff

- Stop before the references list when the user asks not to extract references.
- Create `scripts/new_reference_cutoff_manifest.ps1` for full-paper jobs.
- Fill `ReferencePolicy`, `CutoffPage`, `CutoffHeading`, `LastIncludedBlock`, `ExcludedAfterHeading`, `Checked`, and `Notes`.
- Do not remove in-text citations just because the bibliography is excluded.
- If the final page has appendix content before references, transcribe appendix content first, then stop at the references heading.
- Mark `ExcludedAfterHeading` only after confirming no bibliography heading or entries remain in Markdown under `ReferencePolicy=Exclude`.

## Verification

- Compare the Markdown against rendered pages by page, column, and paragraph.
- Use the page-level checklist to confirm every body block, caption, table, formula, appendix block, and intentional reference-list omission is accounted for.
- Use the block coverage manifest to confirm every block row has visual anchors, a Markdown location, and a checked status.
- In text-layer-assisted mode, use the text layer draft manifest to confirm every draft-derived block has draft anchors, visual anchors, corrections recorded, a Markdown location, and `VisualChecked`.
- Confirm every `MarkdownAnchor` in block coverage, text layer draft, and formula manifests exists literally and exactly in the final Markdown.
- In text-layer-assisted mode, confirm each text-layer draft row links to a block coverage row by `Page + BlockType + MarkdownAnchor`.
- Check the metadata manifest for title, authors, journal, year, volume/issue/pages, and DOI.
- Check the reference cutoff manifest before relying on the absence of bibliography entries.
- Check that all image links resolve from the Markdown file location.
- Inspect all embedded images, not only their paths. Confirm each image is the intended figure/table/formula and is not a loose page screenshot.
- Run `scripts/check_markdown_transcription.ps1 -StrictFullPaper` with `-ChecklistPath` and all manifests for full-paper jobs. Add `-TextLayerAssisted -TextLayerDraftManifestPath ...` when embedded PDF text was used.
- Check the asset decision manifest. Confirm every Markdown image link is recorded as a chosen asset, every `crop-fallback` row has a reason, and every asset row is marked done after visual review.
- Confirm each asset decision row links `FirstCitationAnchor` to a real Markdown image placement after the first citation.
- Check the image candidate manifest. Confirm every direct-export candidate is chosen and every rejected candidate has a concrete reason.
- Check the formula manifest when present. Confirm every `MarkdownTag` appears in Markdown and every Markdown `\tag{...}` is recorded.
- Search for accidental bibliography headings or numbered reference entries.
- Check formula tags, equation references, key values, units, figure captions, table values, and appendix equation numbers.
- Record any visually uncertain words or symbols in the final response rather than silently guessing.

## Final Response Template

Use this structure after a full-paper transcription:

- Markdown: `<path>`
- Assets: `<path>`
- Manifests: checklist, block coverage, metadata, reference cutoff, image candidates, asset decisions, formulas, and text layer draft manifest when used
- Source mode: `Visual-only` or `Text-layer-assisted`
- Reference policy: `Exclude` or `Keep`, with cutoff summary when excluded
- Validation: commands run and pass/fail outcome
- Uncertainties: list unresolved visual transcription points, or state that no visually uncertain transcription points remain
