---
name: highlighted-to-logseq
description: Use when converting old or new Markdown exports from the Highlighted app into Logseq book pages, including highlights, tags, notes, page markers, library metadata, ISBNs, and authors.
---

# Highlighted To Logseq

Convert one Highlighted Markdown export into one Logseq book page with the
repository's `[[Template/Book]]` metadata conventions.

## Choose the Converter

Use v1 when the header quotes the title and prefixes the author with `by`:

```md
# Highlights for ‘Book Title’
### by Author Name
```

```sh
python3 skills/highlighted-to-logseq/scripts/convert_highlighted.py \
  /path/to/highlighted-export.md \
  /path/to/logseq-page.md
```

Use v2 for an unquoted title, a bare author heading, and library metadata:

```md
# Highlights for Book Title
### Author Name
ISBN: 9780000000000
Reading status: Reading
Added to library: 2025-12-03
```

```sh
python3 skills/highlighted-to-logseq/scripts/convert_highlighted_v2.py \
  /path/to/highlighted-v2-export.md \
  /path/to/logseq-page.md
```

Both standalone scripts accept explicit caller-chosen paths, create the output
parent if needed, never modify the input, and reject direct, symlink, or
hard-link input/output aliases.

## Output Format

- Page properties: `page-type:: [[Template/Book]]`, `icon:: 📖`, plain-text
  `book-title::`, linked `book-author::`, `tags:: #book`, and `isbn::`.
  Do not emit Logseq's special `title::` property or a page-level source
  property.
- V1 puts imports beneath `#Highlights #Highlighted`. V2 puts
  `reading-status::` and `added-to-library::` first in the import block, then
  `#Highlighted #Highlights`. Each highlight becomes one nested block quote;
  prefix every content line with `>`, including blank paragraph lines, and
  preserve its whitespace.
- For an unambiguous favorite whose one outer `**` pair crosses blank quote
  lines, replace only that pair with one `**` pair per nonblank paragraph.
  Leave single-paragraph, nested, internal, unbalanced, or otherwise ambiguous
  bold unchanged. Escape ordered-list markers only when they would interrupt an
  open paragraph-local bold span. These are Markdown-only adjustments; rendered
  text and whitespace remain intact.
- Convert source tags into a preceding `tags::` block; make multi-word tags
  page tags such as `#[[Scientific Papers]]`.
- Keep `Note:` lines and `p. N` markers as nested blocks beneath their
  highlight.

## Verification

Run the skill test from the library repository root:

```sh
python3 -m unittest tests.test_highlighted_to_logseq -v
python3 -m unittest tests.test_highlighted_to_logseq_v2 -v
```
