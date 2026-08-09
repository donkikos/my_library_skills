# Highlighted Logseq Properties and Paragraph Bold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put v2 Logseq block properties before block content and make multiparagraph favorite highlights render as independently bold paragraphs in both converters.

**Architecture:** Each standalone converter gets its own private `_normalize_multiparagraph_bold(lines: list[str]) -> list[str]` helper, called immediately before quote-line rendering. The helper recognizes only one unambiguous exporter-owned outer bold pair, preserves the line list and whitespace, and inserts one strong pair around each paragraph; v2 separately reorders the parent block lines.

**Tech Stack:** Python 3 standard library, `unittest`, and the repository's existing converter CLIs.

## Global Constraints

- Keep v1 and v2 independent; do not add a shared module or dependency.
- Never modify any file in `tmp/highlighted/original` or `tmp/highlighted/original_v2`.
- Preserve all highlight text, whitespace-only lines, tags, notes, page markers, and metadata values.
- Normalize only a multiparagraph wrapper containing exactly two unescaped `**` markers.
- Keep single-paragraph and ambiguous bold structures unchanged.
- Put v2 `reading-status::` and `added-to-library::` before `#Highlighted #Highlights` in the same parent block.
- Keep caller-selected input and output paths; do not add fixed storage paths to the skill.
- Add no dependencies.

---

### Task 1: Normalize V1 multiparagraph favorites

**Files:**
- Modify: `tests/test_highlighted_to_logseq.py`
- Modify: `skills/highlighted-to-logseq/scripts/convert_highlighted.py:176-201`

**Interfaces:**
- Consumes: parsed quote lines as `list[str]`, including blank and whitespace-only separators.
- Produces: `_normalize_multiparagraph_bold(lines: list[str]) -> list[str]`.
- Produces: `_render_quote_lines(lines: list[str]) -> list[str]` that invokes the normalizer before existing Markdown protection.

- [ ] **Step 1: Change the existing citation test to require paragraph-scoped bold**

Rename `test_converter_preserves_spanning_bold_around_numbered_citations` to
`test_converter_normalizes_multiparagraph_bold_around_numbered_citations` and
change its expected quote fragment to:

```python
self.assertEqual(
    output,
    "page-type:: [[Template/Book]]\n"
    "icon:: 📖\n"
    "book-title:: Example Book\n"
    "book-author:: [[Example Author]]\n"
    "tags:: #book\n"
    "isbn:: 9780000000000\n\n"
    "- #Highlights #Highlighted\n"
    "  - tags:: #[[Scientific Papers]]\n"
    "    > **Highlighted claim [153].**\n"
    "    >\n"
    "    > **153. First citation.\n"
    "    > 154\\. Second citation.**  \n"
    "  - tags:: #Lists\n"
    "    > 1. Real list item.\n",
)
```

- [ ] **Step 2: Add focused conservative-normalization tests**

Add direct helper tests that preserve multiple blank separators and leave
single-paragraph, internal-bold, and unbalanced inputs untouched:

```python
def test_normalizer_preserves_whitespace_only_separators(self) -> None:
    converter = load_converter()

    normalized = converter._normalize_multiparagraph_bold(
        ["  **First line", "continues.  ", "", "  ", "Second paragraph.**  "]
    )

    self.assertEqual(
        normalized,
        [
            "  **First line",
            "continues.**  ",
            "",
            "  ",
            "**Second paragraph.**  ",
        ],
    )

def test_normalizer_leaves_nonmatching_bold_unchanged(self) -> None:
    converter = load_converter()
    cases = [
        ["**One paragraph.**"],
        ["**First paragraph.", "", "Second with **inline** bold.**"],
        ["**First paragraph.", "", "Unclosed second paragraph."],
    ]

    for lines in cases:
        with self.subTest(lines=lines):
            self.assertEqual(converter._normalize_multiparagraph_bold(lines), lines)
```

- [ ] **Step 3: Run the V1 tests and verify RED**

Run:

```sh
python3 -m unittest tests.test_highlighted_to_logseq -v
```

Expected: the renamed conversion test fails with the old cross-paragraph bold
output, and the direct tests fail because `_normalize_multiparagraph_bold` does
not exist.

- [ ] **Step 4: Implement the private V1 normalizer**

Add this helper immediately before `_render_quote_lines`:

```python
def _normalize_multiparagraph_bold(lines: list[str]) -> list[str]:
    """Replace one outer multiparagraph bold span with paragraph spans."""
    nonblank = [index for index, line in enumerate(lines) if line.strip()]
    if len(nonblank) < 2:
        return lines
    first_index, last_index = nonblank[0], nonblank[-1]
    if not any(_is_separator_line(line) for line in lines[first_index:last_index]):
        return lines
    if sum(len(re.findall(r"(?<!\\)\*\*", line)) for line in lines) != 2:
        return lines

    opening = re.match(r"^([ \t]*)\*\*", lines[first_index])
    closing = re.search(r"\*\*([ \t]*)$", lines[last_index])
    if opening is None or closing is None:
        return lines

    normalized = lines.copy()
    normalized[first_index] = (
        normalized[first_index][: opening.start()]
        + opening.group(1)
        + normalized[first_index][opening.end() :]
    )
    closing = re.search(r"\*\*([ \t]*)$", normalized[last_index])
    if closing is None:
        return lines
    normalized[last_index] = (
        normalized[last_index][: closing.start()]
        + closing.group(1)
        + normalized[last_index][closing.end() :]
    )

    paragraph_start: int | None = None
    for index in range(first_index, last_index + 2):
        at_separator = index > last_index or _is_separator_line(normalized[index])
        if paragraph_start is None and not at_separator:
            paragraph_start = index
        if paragraph_start is None or not at_separator:
            continue
        paragraph_end = index - 1
        normalized[paragraph_start] = re.sub(
            r"^([ \t]*)", r"\1**", normalized[paragraph_start], count=1
        )
        normalized[paragraph_end] = re.sub(
            r"([ \t]*)$", r"**\1", normalized[paragraph_end], count=1
        )
        paragraph_start = None
    return normalized
```

At the start of `_render_quote_lines`, normalize without mutating its caller:

```python
lines = _normalize_multiparagraph_bold(lines)
```

- [ ] **Step 5: Run V1 tests and static checks**

Run:

```sh
python3 -m unittest tests.test_highlighted_to_logseq -v
python3 -m py_compile skills/highlighted-to-logseq/scripts/convert_highlighted.py tests/test_highlighted_to_logseq.py
git diff --check
```

Expected: all V1 tests pass, compilation succeeds, and `git diff --check`
prints nothing.

- [ ] **Step 6: Commit the V1 implementation**

```sh
git add tests/test_highlighted_to_logseq.py \
  skills/highlighted-to-logseq/scripts/convert_highlighted.py
git commit -m "fix: normalize highlighted favorite paragraphs"
```

---

### Task 2: Normalize V2 favorites and order block properties

**Files:**
- Modify: `tests/test_highlighted_to_logseq_v2.py`
- Modify: `skills/highlighted-to-logseq/scripts/convert_highlighted_v2.py:39-44,171-196`

**Interfaces:**
- Consumes: the same quote-line contract as V1, implemented independently.
- Produces: a private V2 `_normalize_multiparagraph_bold(lines: list[str]) -> list[str]` with no V1 import.
- Produces: a v2 parent block whose properties precede `#Highlighted #Highlights`.

- [ ] **Step 1: Update the exact v2 parent-block expectation**

Change the parent block in `EXPECTED_OUTPUT` to:

```python
"- reading-status:: Reading\n"
"  added-to-library:: 2025-12-03\n"
"  #Highlighted #Highlights\n"
```

Keep every child highlight line and all page properties unchanged.

- [ ] **Step 2: Require paragraph-scoped bold in the V2 citation test**

Rename the test to
`test_converter_normalizes_multiparagraph_bold_around_numbered_citations` and
replace its quote assertions with:

```python
self.assertIn("    > **Highlighted claim [153].**\n", output)
self.assertIn("    > **153. First citation.\n", output)
self.assertIn("    > 154\\. Second citation.**  \n", output)
self.assertIn("  - tags:: #[[Scientific Papers]]\n", output)
```

- [ ] **Step 3: Add V2 conservative-normalization tests**

Add the following independent checks rather than importing V1 test helpers:

```python
def test_normalizer_preserves_whitespace_only_separators(self) -> None:
    converter = load_converter()

    normalized = converter._normalize_multiparagraph_bold(
        ["  **First line", "continues.  ", "", "  ", "Second paragraph.**  "]
    )

    self.assertEqual(
        normalized,
        [
            "  **First line",
            "continues.**  ",
            "",
            "  ",
            "**Second paragraph.**  ",
        ],
    )

def test_normalizer_leaves_nonmatching_bold_unchanged(self) -> None:
    converter = load_converter()
    cases = [
        ["**One paragraph.**"],
        ["**First paragraph.", "", "Second with **inline** bold.**"],
        ["**First paragraph.", "", "Unclosed second paragraph."],
    ]

    for lines in cases:
        with self.subTest(lines=lines):
            self.assertEqual(converter._normalize_multiparagraph_bold(lines), lines)
```

- [ ] **Step 4: Run the V2 tests and verify RED**

Run:

```sh
python3 -m unittest tests.test_highlighted_to_logseq_v2 -v
```

Expected: the exact output and citation assertions fail, and the direct tests
fail because the V2 helper does not exist.

- [ ] **Step 5: Implement the V2 changes independently**

Change the v2 parent-block construction to:

```python
import_lines = [
    f"- reading-status:: {reading_status}",
    f"  added-to-library:: {added_to_library}",
    "  #Highlighted #Highlights",
]
```

Add this independent implementation immediately before V2's
`_render_quote_lines`:

```python
def _normalize_multiparagraph_bold(lines: list[str]) -> list[str]:
    """Replace one outer multiparagraph bold span with paragraph spans."""
    nonblank = [index for index, line in enumerate(lines) if line.strip()]
    if len(nonblank) < 2:
        return lines
    first_index, last_index = nonblank[0], nonblank[-1]
    if not any(_is_separator_line(line) for line in lines[first_index:last_index]):
        return lines
    if sum(len(re.findall(r"(?<!\\)\*\*", line)) for line in lines) != 2:
        return lines

    opening = re.match(r"^([ \t]*)\*\*", lines[first_index])
    closing = re.search(r"\*\*([ \t]*)$", lines[last_index])
    if opening is None or closing is None:
        return lines

    normalized = lines.copy()
    normalized[first_index] = (
        normalized[first_index][: opening.start()]
        + opening.group(1)
        + normalized[first_index][opening.end() :]
    )
    closing = re.search(r"\*\*([ \t]*)$", normalized[last_index])
    if closing is None:
        return lines
    normalized[last_index] = (
        normalized[last_index][: closing.start()]
        + closing.group(1)
        + normalized[last_index][closing.end() :]
    )

    paragraph_start: int | None = None
    for index in range(first_index, last_index + 2):
        at_separator = index > last_index or _is_separator_line(normalized[index])
        if paragraph_start is None and not at_separator:
            paragraph_start = index
        if paragraph_start is None or not at_separator:
            continue
        paragraph_end = index - 1
        normalized[paragraph_start] = re.sub(
            r"^([ \t]*)", r"\1**", normalized[paragraph_start], count=1
        )
        normalized[paragraph_end] = re.sub(
            r"([ \t]*)$", r"**\1", normalized[paragraph_end], count=1
        )
        paragraph_start = None
    return normalized
```

Add this as the first line in V2's `_render_quote_lines`:

```python
lines = _normalize_multiparagraph_bold(lines)
```

Do not import any V1 module or helper.

- [ ] **Step 6: Run both converter suites and static checks**

Run:

```sh
python3 -m unittest tests.test_highlighted_to_logseq tests.test_highlighted_to_logseq_v2 -v
python3 -m py_compile skills/highlighted-to-logseq/scripts/convert_highlighted.py skills/highlighted-to-logseq/scripts/convert_highlighted_v2.py tests/test_highlighted_to_logseq.py tests/test_highlighted_to_logseq_v2.py
git diff --check
```

Expected: all tests pass, compilation succeeds, and the diff check is empty.

- [ ] **Step 7: Commit the V2 implementation**

```sh
git add tests/test_highlighted_to_logseq_v2.py \
  skills/highlighted-to-logseq/scripts/convert_highlighted_v2.py
git commit -m "fix: order highlighted import properties"
```

---

### Task 3: Align skill guidance and regenerate audited outputs

**Files:**
- Modify: `skills/highlighted-to-logseq/SKILL.md:48-60`
- Generate ignored files: `tmp/highlighted/processed/*.md`
- Generate ignored files: `tmp/highlighted/processed_v2/*.md`

**Interfaces:**
- Consumes: both converter CLIs and the source export directories supplied for this request.
- Produces: documentation of property-first v2 layout and paragraph-scoped favorite bold.
- Produces: regenerated local Logseq pages without committing export content.

- [ ] **Step 1: Update the skill's output contract**

Replace the current spanning-bold guidance with:

```markdown
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
```

- [ ] **Step 2: Run all repository tests before regenerating data**

Run:

```sh
python3 -m unittest discover -s tests -v
```

Expected: all discovered tests pass.

- [ ] **Step 3: Record source hashes, regenerate all requested v1 outputs, and verify hashes**

Record the command output before conversion:

```sh
shasum -a 256 tmp/highlighted/original/*.md
```

Run every v1 conversion using metadata parsed from each source instead of
recording concrete titles, authors, or filenames in the plan:

```sh
python3 -c 'import importlib.util, pathlib
script = pathlib.Path("skills/highlighted-to-logseq/scripts/convert_highlighted.py")
spec = importlib.util.spec_from_file_location("highlighted_v1", script)
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)
for source in pathlib.Path("tmp/highlighted/original").glob("*.md"):
    lines = source.read_text(encoding="utf-8").splitlines()
    title, author, _, _ = converter._parse_header(lines, source)
    output = pathlib.Path("tmp/highlighted/processed") / f"{author}___{title}.md"
    converter.main([str(source), str(output)])'
shasum -a 256 tmp/highlighted/original/*.md
```

Expected: the before and after source hashes are identical.

- [ ] **Step 4: Record source hashes, regenerate all requested v2 outputs, and verify hashes**

Record the command output before conversion:

```sh
shasum -a 256 tmp/highlighted/original_v2/*.md
```

Run every v2 conversion using metadata parsed from each source:

```sh
python3 -c 'import importlib.util, pathlib
script = pathlib.Path("skills/highlighted-to-logseq/scripts/convert_highlighted_v2.py")
spec = importlib.util.spec_from_file_location("highlighted_v2", script)
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)
for source in pathlib.Path("tmp/highlighted/original_v2").glob("*.md"):
    lines = source.read_text(encoding="utf-8").splitlines()
    title, author, *_ = converter._parse_header(lines, source)
    output = pathlib.Path("tmp/highlighted/processed_v2") / f"{author}___{title}.md"
    converter.main([str(source), str(output)])'
shasum -a 256 tmp/highlighted/original_v2/*.md
```

Expected: the before and after source hashes are identical.

- [ ] **Step 5: Audit the regenerated structure and normalization counts**

Run:

```sh
rg -n "^- (reading-status::|#Highlights #Highlighted)|^  (#Highlighted #Highlights|added-to-library::)" tmp/highlighted/processed tmp/highlighted/processed_v2
rg -n -U '^ {4}> \*\*[^\n]*\n(?: {4}>.*\n)* {4}>$' tmp/highlighted/processed tmp/highlighted/processed_v2
rg -n '^ {4}> \*\*|^ {4}>.*\*\*[[:blank:]]*$' tmp/highlighted/processed tmp/highlighted/processed_v2
```

Expected: v1 has one `#Highlights #Highlighted` parent per output; v2 has one
property-first `reading-status::` parent followed by `added-to-library::` and
`#Highlighted #Highlights`; no bold span crosses an emitted quoted blank line;
and the paragraph-local markers are visible around affected paragraphs.

- [ ] **Step 6: Run final verification and inspect scope**

Run:

```sh
python3 -m unittest discover -s tests -v
git diff --check
git status --short
git diff -- skills/highlighted-to-logseq/SKILL.md
```

Expected: all tests pass; only the intended tracked skill documentation remains
uncommitted; ignored processed exports do not appear in Git status.

- [ ] **Step 7: Commit the skill guidance**

```sh
git add skills/highlighted-to-logseq/SKILL.md
git commit -m "docs: document highlighted paragraph bold"
```

The ignored regenerated outputs remain local and must not be force-added.
