# Highlighted to Logseq V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a standalone converter for newer Highlighted exports and convert every file in `tmp/highlighted/original_v2` into `tmp/highlighted/processed_v2` without modifying v1 or any source export.

**Architecture:** Implement v2 as one independent standard-library script with its own parser, renderer, and file-safety logic. Parse the five-line v2 header, directly attached highlight metadata, optional favorites notice, and fixed footer into the same conceptual quote/metadata model, then render a Logseq book page with v2 library metadata on the `#Highlighted #Highlights` block.

**Tech Stack:** Python 3 standard library and `unittest`.

## Global Constraints

- Do not import from, refactor, or modify `convert_highlighted.py`.
- Do not modify any file in `tmp/highlighted/original_v2` or the v1 folders.
- Accept only caller-supplied input and output paths.
- Preserve every highlight content line and its whitespace.
- Omit only the optional favorites explanation and fixed Highlighted footer.
- Add no dependencies.
- Work directly on `main` as previously authorized.

---

### Task 1: V2 parsing and rendering

**Files:**
- Create: `tests/test_highlighted_to_logseq_v2.py`
- Create: `skills/highlighted-to-logseq/scripts/convert_highlighted_v2.py`

**Interfaces:**
- Produces: `convert_file(source_path: pathlib.Path) -> str`.
- Produces: `_parse_header(lines: list[str], source_path: pathlib.Path) -> tuple[str, str, str, str, str, int]` containing title, author, ISBN, reading status, added date, and content start.
- Produces: `_parse_highlights(lines: list[str]) -> list[tuple[list[str], list[tuple[str, str]]]]`.

- [x] **Step 1: Write exact-output v2 tests before creating the script**

Create a v2 fixture with the five-line header, optional favorites notice, a
multi-paragraph highlight, directly attached `Note:`, `p. 12`, and
`Tags: Quotes, Scientific Papers`, a second untagged highlight, and the fixed
footer. Assert this exact output shape:

```md
page-type:: [[Template/Book]]
icon:: 📖
book-title:: Example Book
book-author:: [[Example Author]]
tags:: #book
isbn:: 9780000000000

- #Highlighted #Highlights
  reading-status:: Reading
  added-to-library:: 2025-12-03
  - tags:: #Quotes, #[[Scientific Papers]]
    > First paragraph.
    >
    > Second paragraph.
    - Note: Verify attribution
    - p. 12
  - > Another highlight.
```

Add separate tests for malformed/v1 headers, a valid v2 header with no
highlights, and the cross-paragraph bold/numbered-citation protection.

- [x] **Step 2: Run `python3 -m unittest tests.test_highlighted_to_logseq_v2 -v` and verify RED**

Expected: import fails because `convert_highlighted_v2.py` does not exist.

- [x] **Step 3: Implement standalone header and body parsing**

Use exact regular expressions for:

```python
r"# Highlights for (.+)$"
r"### (?!by(?:\s|$))(.+)$"
r"ISBN: (.+)$"
r"Reading status: (.+)$"
r"Added to library: (\d{4}-\d{2}-\d{2})$"
r"p\. \d+"
r"Tags: [^,]+(?:,\s*[^,]+)*"
```

Ignore pre-highlight blank lines and the exact favorites notice. Stop before
the exact generated-footer start. Start segments only on `> ` lines. In each
segment, scan backward through blank and recognized metadata lines without
requiring a blank boundary; never classify the segment's first line as
metadata. Convert comma-separated `Tags:` values to `#Tag` or
`#[[Multi Word]]`, and preserve notes/page markers as ordered annotations.

- [x] **Step 4: Implement standalone rendering**

Emit page properties in the approved order, then:

```python
import_lines = [
    "- #Highlighted #Highlights",
    f"  reading-status:: {reading_status}",
    f"  added-to-library:: {added_to_library}",
]
import_lines.extend(f"  {line}" for line in _render_highlights(highlights))
```

Duplicate v1's quote-line, tag, annotation, and bold-span rendering behavior
inside v2. Do not import any v1 symbol.

- [x] **Step 5: Run the v2 tests and verify GREEN**

Run:

```sh
python3 -m unittest tests.test_highlighted_to_logseq_v2 -v
python3 -m unittest tests.test_highlighted_to_logseq -v
```

Expected: both suites pass and v1 remains unchanged.

---

### Task 2: Standalone v2 file safety

**Files:**
- Modify: `tests/test_highlighted_to_logseq_v2.py`
- Modify: `skills/highlighted-to-logseq/scripts/convert_highlighted_v2.py`

**Interfaces:**
- Produces: `main(arguments: collections.abc.Sequence[str] | None = None) -> None`.
- Produces: a `ValueError` before directory creation or writing when input and output identify the same file.

- [x] **Step 1: Add direct, symlink, hard-link, and invalid-input safety tests**

Use real temporary files. Assert aliased paths raise `ValueError` containing
`same file`, leave the source unchanged, and invalid input leaves an existing
output's sentinel content unchanged.

- [x] **Step 2: Run the v2 tests and verify RED**

Expected: safety tests fail because `main` and alias validation do not exist.

- [x] **Step 3: Add the standalone CLI and pre-write validation**

Duplicate v1's `argparse` CLI and resolved/same-file checks inside v2. Validate
paths, fully convert input, then create the output parent and write once.

- [x] **Step 4: Run both v1 and v2 suites and verify GREEN**

```sh
python3 -m unittest tests.test_highlighted_to_logseq_v2 -v
python3 -m unittest tests.test_highlighted_to_logseq -v
```

---

### Task 3: Skill documentation and real v2 conversion

**Files:**
- Modify: `skills/highlighted-to-logseq/SKILL.md`
- Modify: `docs/superpowers/specs/2026-08-09-highlighted-to-logseq-v2-design.md`
- Modify: `docs/superpowers/plans/2026-08-09-highlighted-to-logseq-v2.md`
- Generate ignored files: `tmp/highlighted/processed_v2/*.md`

**Interfaces:**
- Documents when to select v1 versus v2 without prescribing storage paths.
- Converts every caller-selected v2 export into a caller-selected destination.

- [x] **Step 1: Document v2 selection and CLI usage**

Add the v2 command with placeholder input/output paths. Distinguish v1's
quoted title/`### by` header from v2's unquoted title/`### Author` plus reading
status and added date. Document the `#Highlighted #Highlights` block metadata.

- [x] **Step 2: Update the spec's real-export scope to every file currently in `original_v2`**

Audit every caller-selected v2 export. Detect matching v1 exports from parsed
metadata without recording concrete titles or filenames in tracked files.

- [x] **Step 3: Convert and audit all six real v2 exports**

Create outputs named `<author>___<title>.md` in `processed_v2`. Compare source
SHA-256 hashes before and after. For every output verify the approved page
properties, exactly one `#Highlighted #Highlights` block, both library metadata
properties, no generated footer, and highlight/tag/annotation totals matching
the source. For every detected v1/v2 pair, compare parsed highlight text, tags,
notes, and page markers after normalizing only known export syntax differences.
Report any genuine content differences instead of forcing equality.

- [x] **Step 4: Run final verification**

```sh
python3 -m unittest tests.test_highlighted_to_logseq_v2 -v
python3 -m unittest tests.test_highlighted_to_logseq -v
git diff --check
```

Run `ruff` only if already available. Review the final diff for v1 changes,
fixed storage paths in the skill, private values, dependencies, and scope
creep.

- [x] **Step 5: Commit**

```sh
git add docs/superpowers/plans/2026-08-09-highlighted-to-logseq-v2.md \
  docs/superpowers/specs/2026-08-09-highlighted-to-logseq-v2-design.md \
  skills/highlighted-to-logseq/SKILL.md \
  skills/highlighted-to-logseq/scripts/convert_highlighted_v2.py \
  tests/test_highlighted_to_logseq_v2.py
git commit -m "feat: add highlighted converter v2"
```
