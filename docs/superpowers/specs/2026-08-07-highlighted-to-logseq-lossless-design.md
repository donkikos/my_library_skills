# Lossless Highlighted to Logseq Design

## Goal

Convert Highlighted Markdown exports into Logseq book pages without modifying
the source export or discarding highlight text, paragraph boundaries, or
content indentation.

## Output Contract

Emit these page properties before the highlights:

```md
page-type:: [[Template/Book]]
icon:: 📖
book-title:: Book Title
book-author:: [[Author Name]]
tags:: #book
isbn:: 9780000000000
```

Use the custom `book-title` and `book-author` properties instead of Logseq's
special `title` property and the generic `author` property. This prevents
imported metadata from renaming the page or its file and scopes both fields to
books. Keep the title as plain text rather than creating a second page
reference; keep the author as a page reference.

Place all imported highlights beneath one `#Highlights #Highlighted` block.
The two tags identify both the subtree's role and its source without labeling
the entire book page as imported content. Keep each source highlight in one
child block and prefix every content line with `>`, including empty lines
between paragraphs:

```md
- #Highlights #Highlighted
  - tags:: #Quotes
    > First paragraph.
    >
    > Second paragraph.
    - Note: Source annotation
  - > Another highlight.
```

Do not strip leading or trailing whitespace from highlight content. Discard
only Highlighted's export boilerplate and separator whitespace outside a
highlight.

When a multi-paragraph `**` span contains a continuation line that Markdown
would parse as an ordered list, escape the marker's punctuation (for example,
render `153.` as `153\.` in the Markdown source). This keeps the span intact in
Logseq without changing its displayed text. Do not escape genuine numbered
lists outside an open strong-emphasis span. If whitespace immediately precedes
the closing `**`, place that whitespace after the delimiter so the delimiter
can close while retaining the source whitespace.

## Parsing

Recognize a new highlight only from a line beginning with `> `. Treat later
lines as quote content unless they form a trailing metadata section separated
from the quote by one or more empty lines. In that trailing section:

- Recognize `Note:` lines as notes.
- Recognize `p. N` lines as page markers.
- Recognize comma-separated `#tag` values as source tags.
- Allow blank separator lines between metadata entries without rendering them.

This boundary-aware rule keeps metadata-like text inside a quote when it is
not separated into the trailing metadata section. Preserve metadata order in
the internal representation, while rendering source tags as the highlight's
`tags::` block and notes/page markers as its child blocks. Nest every rendered
highlight one level below the shared `#Highlights #Highlighted` block.

Require at least one highlight. Reject an export that has a valid header but
no recognized highlight rather than producing a misleading metadata-only
page.

## File Safety

Resolve input and output paths before creating directories or writing. Reject
the operation when both paths identify the same file, including paths that use
relative components, symlinks, or hard links. Leave an existing output
untouched whenever input validation or conversion fails.

The skill accepts caller-supplied paths and does not prescribe storage
directories.

## Tests

Use deterministic standard-library `unittest` cases with hand-written exact
expected output. Cover:

- all page properties, including plain-text `book-title::` and linked
  `book-author::`, while excluding `title::`, `author::`, and `source::`;
- multiple highlights nested beneath one `#Highlights #Highlighted` block;
- blank quoted lines between paragraphs;
- numbered citation lines inside multi-paragraph bold text, without changing
  genuine numbered lists;
- leading and trailing quote whitespace;
- notes, page markers, and single- and multi-word tags;
- metadata-like text that remains quote content;
- malformed headers and valid headers with no highlights;
- direct, symlinked, and hard-linked input/output alias rejection;
- preservation of an existing output when conversion fails.

Run the converter against every locally available real export in temporary
destinations and verify source hashes before and after. The ignored exports
are audit inputs, not committed test fixtures.
