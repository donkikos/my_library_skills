# Highlighted to Logseq V2 Design

## Goal

Convert the newer Highlighted Markdown export format into Logseq book pages
without modifying source exports or changing the existing v1 converter.

## Isolation

Add a fully standalone script at
`skills/highlighted-to-logseq/scripts/convert_highlighted_v2.py`. Do not import
from, refactor, or otherwise modify `convert_highlighted.py`. Duplication is
intentional so v1 remains stable for older exports.

## V2 Input Contract

Require this five-line metadata header:

```md
# Highlights for Book Title
### Author Name
ISBN: 9780000000000
Reading status: Reading
Added to library: 2025-12-03
```

Allow blank lines and the optional `*Favorites are marked in bold.*` notice
between the header and the first highlight. A highlight begins with `> `.

Recognize metadata immediately following highlight text without requiring a
blank separator:

- `Note: ...` is an annotation.
- `p. N` is a page marker.
- `Tags: First, Multi Word` contains comma-separated source tags.

Stop parsing highlight data at Highlighted's fixed generated footer:

```md
**Created with [Highlighted](https://usehighlighted.com)**.
*Highlights may be protected by copyright.*
```

The optional favorites notice and fixed footer are exporter boilerplate and
are not rendered.

## Output Contract

Emit these page properties in this order:

```md
page-type:: [[Template/Book]]
icon:: 📖
book-title:: Book Title
book-author:: [[Author Name]]
tags:: #book
isbn:: 9780000000000
```

Place all imported content beneath one block. Put v2 library metadata on that
block rather than on the page:

```md
- #Highlighted #Highlights
  reading-status:: Reading
  added-to-library:: 2025-12-03
  - tags:: #First, #[[Multi Word]]
    > First paragraph.
    >
    > Second paragraph.
    - Note: Source annotation
    - p. 12
```

Keep each highlight in one child block. Prefix every quote content line with
`>`, including blank lines, and preserve its leading and trailing whitespace.
Render multi-word tags as Logseq page tags. Keep notes and page markers as
children of their highlight.

Retain v1's Markdown protections in the standalone implementation: escape an
ordered-list marker only while a cross-line `**` span is open, and move
whitespace immediately before a closing `**` after the delimiter. These
syntax-only adjustments preserve displayed text and whitespace.

## File Safety

Accept explicit caller-supplied input and output paths. Reject paths that
resolve to or identify the same file, including symlink and hard-link aliases,
before creating directories or writing. Leave an existing output untouched
when input validation or conversion fails.

## Tests and Real Exports

Add deterministic `unittest` coverage for:

- the complete v2 header and exact output;
- reading status and added date on the import block;
- directly attached tags, notes, and page markers;
- multi-paragraph quote preservation;
- favorites-notice and footer removal;
- multi-word tag rendering;
- malformed headers and exports with no highlights;
- direct, symlink, and hard-link input/output alias rejection;
- preserving an existing output when conversion fails.

Convert the three new real exports into `tmp/highlighted/processed`, verify
their source hashes remain unchanged, and confirm the output counts and
metadata against the originals. Run both v1 and v2 test modules to guard
against v1 regressions.
