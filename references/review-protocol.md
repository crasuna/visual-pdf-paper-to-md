# Independent visual review protocol

## Contents

- Independence boundary
- Coverage
- Findings
- Correction cycles
- Status decision

## Independence boundary

Start the reviewer with `fork_turns="none"` after structural validation succeeds. The reviewer must not inherit the transcription chat, draft reasoning, or the primary agent's confidence statements. It may read only the source-bound evidence package and the minimum location instructions needed to review it.

The reviewer must not edit the Markdown, `blocks.csv`, `assets.csv`, `image_candidates.csv`, or `job.csv`. It owns `review_findings.csv` and may create precise evidence images under `_audit/review/evidence/`.

Before review, record `ReviewStarted` through the lifecycle helper. If no fresh reviewer is available, record `ReviewerUnavailable`, which sets both review and final state to `review-pending`. Do not claim completion.

## Coverage

Compare every block to its authoritative rendered page, including title, author blocks, affiliations, composite metadata, abstract label, headings, every paragraph, footnotes, captions, tables, formulas, acknowledgements, appendices, declarations, copyright or license text, blank pages, and the reference cutoff.

For every block verify:

- global and local reading order;
- first and last visual anchors;
- exact wording, punctuation, casing, symbols, units, citations, and equation references;
- continuation across columns or pages;
- appropriate Markdown, HTML, asset, or omission representation;
- complete `MarkdownAnchor` span and sequence, with no semantic Markdown left outside a represented block or registered final-asset link.

Review every final figure, table, and formula asset. Confirm content completeness, crop boundaries, dimensions, source method, candidate linkage, fallback reason, and Markdown placement. For a figure, confirm it appears after its first body citation and that caption text remains editable.

## Findings

Write a pass row for each reviewed target even when no discrepancy exists. Do not record only failures. A finding identifies expected visual evidence, actual Markdown or asset content, category, page asset, blocking status, and optional evidence path.

Ordinary prose, symbol, or reading-order uncertainty is blocking. A structured formula or complex table mismatch may be resolved by a precise reviewed fallback asset; this does not authorize screenshot fallbacks for uncertain prose.

## Correction cycles

After a failed finding, record `CorrectionRequired`; the primary agent makes corrections and records `CorrectionApplied`. The same fresh reviewer then checks the corrected target and adjacent blocks affected by column or page continuity. Record cycle 1 or 2 and the recheck result.

After two unsuccessful cycles, stop automatic correction. Preserve the disagreement and evidence, record `UserReviewRequired`, and present the competing readings without guessing.

## Status decision

- Use `verified` only when every block and final asset has a fresh closed pass and no uncertainty remains.
- Use `verified-with-fallback` only when all ordinary text is confirmed and at least one formula or complex table uses an independently passed precise visual fallback.
- Use `needs-user-review` for unresolved words, symbols, order, or asset content.
- Use `failed` for source, schema, page, or structural failure.

The reviewer supplies evidence; the final validator checks coverage and closure. Neither a self-entered status nor a passing structural script independently proves that visual comparison occurred. Completion requires Final `-CommitStatus`, `Committed=true`, and a matching `job.csv FinalStatus`.
