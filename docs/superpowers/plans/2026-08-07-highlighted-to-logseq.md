# Lossless Highlighted to Logseq Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert one Highlighted Markdown export into one Logseq book page without modifying the export or discarding highlight text, paragraph boundaries, or content indentation.

**Architecture:** Parse the required header, split the body into highlight segments, and recognize annotations only in a trailing metadata section separated from quote content by blank lines. Render every quote content line with a blockquote marker, reject aliased input/output paths before writing, and keep all paths caller-supplied.

**Tech Stack:** Python 3 standard library and `unittest`.

## Global Constraints

- Do not modify source exports.
- Do not prescribe input or output storage directories.
- Do not add third-party dependencies.
- Preserve every highlight content line and its whitespace.
- Render blank paragraph separators as quoted blank lines.
- Add `source:: #Highlighted` to page properties.
- Do not commit automatically because the repository already contains staged user changes.

---

### Task 1: Lossless parsing and rendering

**Files:**
- Modify: `tests/test_highlighted_to_logseq.py`
- Modify: `skills/highlighted-to-logseq/scripts/convert_highlighted.py`

**Interfaces:**
- Consumes: Highlighted Markdown with `# Highlights for`, `### by`, and `ISBN:` header lines.
- Produces: `convert_file(source_path: pathlib.Path) -> str`.
- Produces: `_parse_highlights(lines: list[str]) -> list[tuple[list[str], list[Metadata]]]`,
  where each `Metadata` value is an ordered `(kind, value)` pair for a tag or
  annotation.

- [x] **Step 1: Replace the broad synthetic assertion with exact-output tests**

Add tests whose literal expected output covers:

```python
SOURCE = (
    "# Highlights for ‘Example Book’\n"
    "### by Example Author\n"
    "ISBN: 9780000000000\n\n"
    "> First paragraph.  \n\n"
    "  Second paragraph.\n\n"
    "Note: Verify attribution\n"
    "p. 12\n"
    "#Quotes, #Scientific Papers\n\n"
    "> Note: this sentence is quote content.\n"
    "p. 9 is also quote content.\n"
    "# this is also quote content.\n"
)
```

The expected highlights must contain:

```python
EXPECTED_HIGHLIGHTS = (
    "- tags:: #Quotes, #[[Scientific Papers]]\n"
    "  > First paragraph.  \n"
    "  >\n"
    "  >   Second paragraph.\n"
    "  - Note: Verify attribution\n"
    "  - p. 12\n"
    "- > Note: this sentence is quote content.\n"
    "  > p. 9 is also quote content.\n"
    "  > # this is also quote content.\n"
)
```

Assert the complete returned string, including all page properties and the final newline. Add separate tests that reject a malformed header and a valid header with no highlights.

- [x] **Step 2: Run the targeted tests and verify RED**

Run:

```sh
python3 -m unittest tests.test_highlighted_to_logseq -v
```

Expected: FAIL because `source:: #Highlighted` is absent, blank lines are removed, continuation lines lack `>` markers, whitespace is stripped, metadata-like quote text is reclassified, and empty exports do not raise an error.

- [x] **Step 3: Implement boundary-aware highlight parsing**

Keep source lines verbatim after removing only the first highlight marker. For each highlight segment:

1. Remove separator-only blank lines at the segment end.
2. Scan backward through blank lines and recognized metadata lines.
3. Treat the suffix as metadata only when a blank line separates its first metadata line from quote content.
4. Preserve all earlier lines, including empty and whitespace-bearing lines, as quote content.
5. Reject conversions that contain no nonempty highlights.

Recognize metadata with exact helpers:

```python
def _is_page_marker(line: str) -> bool:
    return re.fullmatch(r"p\. \d+", line) is not None


def _is_tag_line(line: str) -> bool:
    return re.fullmatch(r"#[^,#]+(?:,\s*#[^,#]+)*", line) is not None
```

Render every quote line with `>`:

```python
def _render_quote_line(line: str) -> str:
    return ">" if line == "" else f"> {line}"
```

Add `source:: #Highlighted` after `tags:: #book`.

- [x] **Step 4: Run the targeted tests and verify GREEN**

Run:

```sh
python3 -m unittest tests.test_highlighted_to_logseq -v
```

Expected: all parsing and rendering tests PASS.

---

### Task 2: Input/output alias safety

**Files:**
- Modify: `tests/test_highlighted_to_logseq.py`
- Modify: `skills/highlighted-to-logseq/scripts/convert_highlighted.py`

**Interfaces:**
- Consumes: `main(arguments: Sequence[str] | None = None) -> None` input and output paths.
- Produces: a `ValueError` before directory creation or writing when paths resolve
  to the same location or identify the same existing filesystem object.

- [x] **Step 1: Add failing file-safety tests**

Use `tempfile.TemporaryDirectory` and real files to verify:

```python
with self.assertRaisesRegex(ValueError, "same file"):
    converter.main([str(source), str(source)])
self.assertEqual(source.read_text(encoding="utf-8"), original)
```

Add symlink and hard-link alias cases when supported. Add an invalid-input case with a pre-existing output and assert that its sentinel content remains unchanged.

- [x] **Step 2: Run the safety tests and verify RED**

Run:

```sh
python3 -m unittest tests.test_highlighted_to_logseq -v
```

Expected: direct, symlink, and hard-link alias tests FAIL because the source is overwritten.

- [x] **Step 3: Reject aliased paths before side effects**

Before `mkdir` or conversion, compare both resolved locations and, when both
paths exist, their filesystem identities:

```python
def _validate_distinct_paths(source_path: Path, output_path: Path) -> None:
    if source_path.resolve() == output_path.resolve():
        raise ValueError("Input and output paths identify the same file")
    try:
        if source_path.samefile(output_path):
            raise ValueError("Input and output paths identify the same file")
    except FileNotFoundError:
        pass
```

Call this helper at the start of `main` after argument parsing.

- [x] **Step 4: Run the safety tests and verify GREEN**

Run:

```sh
python3 -m unittest tests.test_highlighted_to_logseq -v
```

Expected: all safety and conversion tests PASS.

---

### Task 3: Skill instructions and validation

**Files:**
- Modify: `skills/highlighted-to-logseq/SKILL.md`
- Verify: `skills/highlighted-to-logseq/agents/openai.yaml`
- Modify: `docs/superpowers/plans/2026-08-07-highlighted-to-logseq.md`

**Interfaces:**
- Documents the existing two-path CLI without selecting directories for the caller.
- Documents lossless blockquote lines and `source:: #Highlighted`.

- [x] **Step 1: Exercise the historical skill instructions as the baseline**

Compare the pre-implementation `SKILL.md` with the approved design and record that it instructed agents to remove empty lines and use fixed root-level storage directories.

- [x] **Step 2: Update the minimal skill guidance**

State that callers choose explicit input and output paths. Document that the converter rejects aliased paths, prefixes every content line with `>`, preserves quoted blank lines and whitespace, and adds `source:: #Highlighted`. Remove the `Stored Artifacts` section and all fixed storage paths.

- [x] **Step 3: Validate code, skill metadata, and real exports**

Run:

```sh
python3 -m unittest tests.test_highlighted_to_logseq -v
python3 /path/to/skill-creator/scripts/quick_validate.py skills/highlighted-to-logseq
git diff --check
```

If `ruff` is available in the active environment, also run:

```sh
ruff format --check skills/highlighted-to-logseq/scripts/convert_highlighted.py tests/test_highlighted_to_logseq.py
ruff check skills/highlighted-to-logseq/scripts/convert_highlighted.py tests/test_highlighted_to_logseq.py
```

Convert every `tmp/highlighted/original/*.md` file to a newly created temporary directory, compare source SHA-256 hashes before and after, and confirm every output contains `source:: #Highlighted` and quoted blank paragraph lines where the source contains internal blank lines.

- [x] **Step 4: Review the final diff and mark this plan complete**

Check for accidental scope changes, dependencies, fixed storage paths, stale filenames, and unchecked steps. Mark each completed checkbox `[x]` only after its corresponding command or behavior has been verified.
