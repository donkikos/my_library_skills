---
name: highlighted-to-logseq
description: Use when converting Markdown exports from the Highlighted app into Logseq book pages, including preserving highlights, source tags, notes, page markers, ISBNs, and authors.
---

# Highlighted To Logseq

Convert one Highlighted Markdown export into one Logseq book page with the
repository's `[[Template/Book]]` metadata conventions.

## Convert One Export

Choose explicit input and output paths, then run the bundled standard-library
Python script:

```sh
python3 skills/highlighted-to-logseq/scripts/convert_highlighted.py \
  /path/to/highlighted-export.md \
  /path/to/logseq-page.md
```

The input must begin with Highlighted's book metadata:

```md
# Highlights for ‘Book Title’
### by Author Name
ISBN: 9780000000000
```

The script creates the output parent directory if needed and overwrites only
the output path provided by the caller. It never modifies the input export and
rejects input and output paths that identify the same file, including aliases
through symlinks and hard links.

## Output Format

- Page properties: `page-type:: [[Template/Book]]`, `icon:: 📖`, plain-text
  `book-title::`, linked `book-author::`, `tags:: #book`, and `isbn::`.
  Do not emit Logseq's special `title::` property or a page-level source
  property.
- Put all imported highlights beneath one `#Highlights #Highlighted` block so
  those tags describe only the imported subtree. Each highlight becomes one
  nested Logseq block quote. Prefix every content line with `>`, including
  blank paragraph lines, and preserve its leading and trailing whitespace.
- Preserve bold that spans quote paragraphs by escaping ordered-list markers
  only when they would otherwise interrupt an open `**` span, and move any
  whitespace immediately before its closing `**` after the delimiter. These
  are Markdown-only adjustments; rendered text and whitespace remain intact.
- Convert source tags into a preceding `tags::` block; make multi-word tags
  page tags such as `#[[Scientific Papers]]`.
- Keep `Note:` lines and `p. N` markers as nested blocks beneath their
  highlight.

## Verification

Run the skill test from the library repository root:

```sh
python3 -m unittest tests.test_highlighted_to_logseq -v
```
