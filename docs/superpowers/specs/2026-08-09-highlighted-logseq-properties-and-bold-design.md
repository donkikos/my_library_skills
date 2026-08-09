# Highlighted Logseq Properties and Paragraph Bold Design

## Goal

Make generated Highlighted book pages follow Logseq block-property ordering and
render favorite highlights consistently in both Logseq and conventional Markdown
viewers, without changing or dropping exported content.

## Scope

- Update both the v1 and v2 standalone converters to normalize a favorite whose
  outer bold span crosses one or more paragraph separators.
- Update the v2 import parent block so its block properties precede its ordinary
  block content.
- Keep the v1 and v2 scripts independent; do not introduce a shared module.
- Regenerate the ignored processed fixtures only after tests pass.

## V2 Parent Block Layout

The v2 parent block will put Logseq block properties first and the import tags
after them in the same block:

```markdown
- reading-status:: Finished
  added-to-library:: 2023-11-10
  #Highlighted #Highlights
  - child highlight
```

This preserves the existing values and hierarchy while allowing Logseq to
recognize the property lines according to its block convention.

## Paragraph-Scoped Bold Normalization

Highlighted marks a favorite by wrapping the entire exported highlight in one
outer `**` pair. When that highlight contains blank lines, the span crosses
paragraph boundaries. Logseq accepts that form, but conventional Markdown
viewers may display the markers literally.

Each converter will normalize only an unambiguous multiparagraph outer wrapper:

1. The first nonblank content line begins with `**`.
2. The last nonblank content line ends with `**`.
3. At least one blank or whitespace-only content line separates paragraphs.
4. No additional unescaped `**` markers occur inside the wrapper.

For a matching highlight, the converter will remove the single outer wrapper
and wrap each nonblank paragraph independently:

```markdown
> **First paragraph.**
>
> **Second paragraph.**
```

A paragraph is a maximal run of nonblank lines. One marker pair surrounds the
whole paragraph, not each physical line. Leading and trailing whitespace remain
outside the inserted markers so the Markdown remains valid without losing the
original whitespace. Blank and whitespace-only lines remain present and render
as quoted blank lines.

Highlights with a single paragraph, nested or internal strong markers, an
unbalanced wrapper, or any other ambiguous structure remain unchanged.

## Data-Preservation Invariants

- Quote text is unchanged after removing the exporter-owned outer markers from
  the comparison and ignoring the newly inserted paragraph marker boundaries.
- The number and order of highlights, paragraphs, blank lines, tags, notes, page
  markers, and metadata values do not change.
- The existing list-marker protection remains available for bold paragraphs
  whose content could otherwise become a Markdown list.
- Conversion remains deterministic and never writes over its input.

## Testing and Verification

Add parallel tests for the independent v1 and v2 implementations covering:

- a two-paragraph outer-bold favorite;
- multiple blank separators and a multi-line paragraph;
- preservation of whitespace-only quoted separators;
- no rewrite for a single paragraph;
- no rewrite for nested, internal, or unbalanced bold markers;
- ordered-list-looking text at the start of a later bold paragraph;
- v2 block properties appearing before `#Highlighted #Highlights`.

Run both targeted test files, then reconvert the v1 and v2 source directories.
Audit the regenerated outputs against their sources for highlight counts,
metadata counts, paragraph/blank-line preservation, and normalized quote text.
Review the final diff before committing implementation changes.
