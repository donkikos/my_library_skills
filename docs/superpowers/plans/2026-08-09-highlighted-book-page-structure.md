# Highlighted Book Page Structure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Emit book-specific metadata and group all Highlighted imports beneath one tagged subtree without labeling or renaming the whole Logseq book page.

**Architecture:** Keep header parsing unchanged, replace only the rendered page-property keys, and add one indentation layer around the existing highlight renderer. Preserve the established quote, metadata, whitespace, and file-safety behavior.

**Tech Stack:** Python 3 standard library and `unittest`.

## Global Constraints

- Do not modify original Highlighted exports.
- Emit `book-author:: [[Author Name]]` and plain-text `book-title:: Book Title`.
- Do not emit `author::`, `title::`, or `source::` page properties.
- Emit exactly one `- #Highlights #Highlighted` parent and nest every imported highlight below it.
- Preserve source tags, notes, page markers, quote lines, whitespace, and bold-rendering protections.
- Keep all input and output paths caller-supplied.
- Add no dependencies.

---

### Task 1: Render book metadata and imported highlight subtree

**Files:**
- Modify: `tests/test_highlighted_to_logseq.py`
- Modify: `skills/highlighted-to-logseq/scripts/convert_highlighted.py`
- Modify: `skills/highlighted-to-logseq/SKILL.md`
- Modify: `docs/superpowers/plans/2026-08-09-highlighted-book-page-structure.md`

**Interfaces:**
- Consumes: `convert_file(source_path: pathlib.Path) -> str` and the existing `_render_highlights(highlights: list[Highlight]) -> list[str]`.
- Produces: the same public converter interface with revised page properties and one additional output indentation level.

- [x] **Step 1: Revise exact-output tests first**

Change every expected page header to:

```python
"page-type:: [[Template/Book]]\n"
"icon:: 📖\n"
"book-author:: [[Example Author]]\n"
"tags:: #book\n"
"isbn:: 9780000000000\n"
"book-title:: Example Book\n\n"
"- #Highlights #Highlighted\n"
```

Indent each expected highlight line by two additional spaces. The main fixture must therefore contain this exact subtree:

```python
"- #Highlights #Highlighted\n"
"  - tags:: #Quotes, #[[Scientific Papers]]\n"
"    > First paragraph.  \n"
"    >\n"
"    >   Second paragraph.\n"
"    - Note: Verify attribution\n"
"    - p. 12\n"
"  - > Note: this sentence is quote content.\n"
```

The exact output makes `author::`, `title::`, and `source::` regressions fail and proves all highlight blocks share one imported-content parent.

- [x] **Step 2: Run the targeted suite and verify RED**

Run:

```sh
python3 -m unittest tests.test_highlighted_to_logseq -v
```

Expected: exact-output tests fail because the converter still emits `author::`, `source::`, and `title::`, and highlights remain top-level.

- [x] **Step 3: Implement the minimal renderer change**

Replace the property list in `convert_file` with:

```python
properties = [
    f"page-type:: {PAGE_TYPE}",
    f"icon:: {BOOK_ICON}",
    f"book-author:: [[{author}]]",
    "tags:: #book",
    f"isbn:: {isbn}",
    f"book-title:: {title}",
]
```

Then wrap the existing rendered highlight lines without changing their internal renderer:

```python
highlight_lines = ["- #Highlights #Highlighted"]
highlight_lines.extend(f"  {line}" for line in _render_highlights(highlights))
return "\n".join(properties + [""] + highlight_lines) + "\n"
```

- [x] **Step 4: Run the targeted suite and verify GREEN**

Run:

```sh
python3 -m unittest tests.test_highlighted_to_logseq -v
```

Expected: all converter tests pass.

- [x] **Step 5: Align the skill instructions**

Document `book-author::`, `book-title::`, removal of page-level source metadata, and the shared `#Highlights #Highlighted` parent. Retain the existing file-safety, quote-preservation, tag, annotation, and bold-rendering instructions.

- [x] **Step 6: Audit all real exports and source hashes**

Convert every `tmp/highlighted/original/*.md` into a new temporary directory. Verify:

```text
every source SHA-256 is unchanged
every output contains exactly one "- #Highlights #Highlighted"
every output contains book-author:: and book-title::
no output contains author::, title::, or source::
all existing highlight, annotation, tag, and quote-count audit totals remain unchanged
```

- [x] **Step 7: Run final checks**

Run:

```sh
python3 -m unittest tests.test_highlighted_to_logseq -v
git diff --check
```

Run configured `ruff` checks only if `ruff` is already available. Review the diff for unrelated changes and private paths or values.

- [x] **Step 8: Commit the implementation**

```sh
git add docs/superpowers/plans/2026-08-09-highlighted-book-page-structure.md \
  skills/highlighted-to-logseq/SKILL.md \
  skills/highlighted-to-logseq/scripts/convert_highlighted.py \
  tests/test_highlighted_to_logseq.py
git commit -m "feat: structure highlighted book page imports"
```
