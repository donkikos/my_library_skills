# Highlighted Linked Library Date Design

## Goal

Render the v2 `added-to-library::` value as a Logseq page link so the ISO date
is navigable, without changing the source export or parsed metadata value.

## Output Contract

The v2 import parent block remains property-first and changes only the rendered
date value:

```markdown
- reading-status:: Finished
  added-to-library:: [[2023-11-10]]
  #Highlighted #Highlights
  - child highlight
```

`reading-status::` remains plain text. V1 remains unchanged because v1 exports
do not contain library metadata.

## Implementation

Keep `_parse_header` returning the source date as the plain ISO string
`YYYY-MM-DD`. Add `[[` and `]]` only when `convert_file` renders the v2 block.
This keeps parsing independent of Logseq output syntax and avoids a new helper
or abstraction for a single formatting rule.

Update the v2 exact-output test before changing the converter. Update the skill
reference to say that `added-to-library::` uses a linked ISO date.

## Verification

- Run the focused v2 suite and the full test suite.
- Regenerate all caller-selected files in `tmp/highlighted/processed_v2` from
  `tmp/highlighted/original_v2`.
- Verify every original SHA-256 remains unchanged.
- Verify every regenerated v2 parent block uses
  `added-to-library:: [[YYYY-MM-DD]]` after `reading-status::` and before
  `#Highlighted #Highlights`.
- Re-run the existing highlight, annotation, tag, blank-line, and bold
  preservation audit.
