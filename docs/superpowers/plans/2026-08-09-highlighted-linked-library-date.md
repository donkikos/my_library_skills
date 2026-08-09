# Highlighted Linked Library Date Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the Highlighted v2 added-to-library date as a Logseq page link while preserving the source ISO value and all converted content.

**Architecture:** Keep v2 header parsing unchanged and add Logseq link brackets only in `convert_file` when rendering the parent block. Protect the output contract with an exact conversion test, then align the skill reference and regenerate the six ignored v2 outputs.

**Tech Stack:** Python 3 standard library, `unittest`, Markdown, and the existing standalone v2 converter CLI.

## Global Constraints

- Change only the v2 output format; v1 has no library date and remains unchanged.
- Keep `_parse_header` returning the plain source value `YYYY-MM-DD`.
- Render exactly `added-to-library:: [[YYYY-MM-DD]]`.
- Preserve property order: `reading-status::`, linked `added-to-library::`, then `#Highlighted #Highlights`.
- Do not modify any file in `tmp/highlighted/original_v2`.
- Keep the script standalone and add no dependency or storage path.
- Preserve every highlight, annotation, tag, blank line, bold marker decision, and metadata value.

---

### Task 1: Render the v2 library date as a Logseq link

**Files:**
- Modify: `tests/test_highlighted_to_logseq_v2.py:42-58`
- Modify: `skills/highlighted-to-logseq/scripts/convert_highlighted_v2.py:39-43`

**Interfaces:**
- Consumes: `_parse_header(...)` returning `added_to_library: str` as plain `YYYY-MM-DD`.
- Produces: `convert_file(source_path: pathlib.Path) -> str` with `added-to-library:: [[YYYY-MM-DD]]`.

- [ ] **Step 1: Change the exact-output test first**

In `EXPECTED_OUTPUT`, replace only the existing library-date line:

```python
"  added-to-library:: [[2025-12-03]]\n"
```

The surrounding lines remain:

```python
"- reading-status:: Reading\n"
"  added-to-library:: [[2025-12-03]]\n"
"  #Highlighted #Highlights\n"
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```sh
python3 -m unittest tests.test_highlighted_to_logseq_v2.HighlightedToLogseqV2Test.test_converter_renders_complete_v2_export -v
```

Expected: one assertion failure showing actual
`added-to-library:: 2025-12-03` versus expected
`added-to-library:: [[2025-12-03]]`.

- [ ] **Step 3: Add brackets only at the rendering boundary**

Change the v2 parent-block construction to:

```python
import_lines = [
    f"- reading-status:: {reading_status}",
    f"  added-to-library:: [[{added_to_library}]]",
    "  #Highlighted #Highlights",
]
```

Do not modify `_parse_header` or any v1 file.

- [ ] **Step 4: Run the focused and full converter suites**

Run:

```sh
python3 -m unittest tests.test_highlighted_to_logseq_v2 -v
python3 -m unittest discover -s tests -v
python3 -m py_compile skills/highlighted-to-logseq/scripts/convert_highlighted_v2.py tests/test_highlighted_to_logseq_v2.py
git diff --check
```

Expected: all tests pass, compilation succeeds, and the diff check is empty.

- [ ] **Step 5: Commit the tested converter change**

```sh
git add tests/test_highlighted_to_logseq_v2.py \
  skills/highlighted-to-logseq/scripts/convert_highlighted_v2.py
git commit -m "feat: link highlighted library dates"
```

---

### Task 2: Align skill guidance and regenerate v2 outputs

**Files:**
- Modify: `skills/highlighted-to-logseq/SKILL.md:52-55`
- Generate ignored files: `tmp/highlighted/processed_v2/*.md`

**Interfaces:**
- Consumes: the tested v2 converter CLI with caller-supplied input/output paths.
- Produces: skill guidance stating that `added-to-library::` contains a linked ISO date.
- Produces: six current local v2 Logseq pages without committing source or generated content.

- [ ] **Step 1: Establish the current skill-guidance baseline**

Give a fresh-context skill consumer this scenario using only the current
`skills/highlighted-to-logseq/SKILL.md`:

```text
For a v2 export with Added to library: 2023-11-10, state the exact generated
added-to-library property. Does the skill require the ISO date to be a Logseq
page link? Do not inspect converter code, tests, plans, specs, or outputs.
```

Expected baseline: it emits or permits `added-to-library:: 2023-11-10` and
cannot identify an explicit linked-date requirement.

- [ ] **Step 2: Add the minimal linked-date guidance**

Change the v2 output bullet to:

```markdown
- V1 puts imports beneath `#Highlights #Highlighted`. V2 puts
  `reading-status::` and `added-to-library:: [[YYYY-MM-DD]]` first in the
  import block, then `#Highlighted #Highlights`. Each highlight becomes one
  nested block quote; prefix every content line with `>`, including blank
  paragraph lines, and preserve its whitespace.
```

- [ ] **Step 3: Verify the updated skill behavior**

Repeat the Step 1 scenario with a fresh-context skill consumer.

Expected updated result:

```markdown
added-to-library:: [[2023-11-10]]
```

The consumer must identify the link syntax as required rather than optional.

- [ ] **Step 4: Record source hashes and regenerate all six v2 outputs**

Record hashes before conversion:

```sh
shasum -a 256 tmp/highlighted/original_v2/*.md
```

Run:

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

Expected: every before/after SHA-256 pair is identical.

- [ ] **Step 5: Audit all regenerated outputs**

For every source/output pair, load the converter and assert:

```python
actual_output == converter.convert_file(source_path)
```

Also assert the v2 parent prefix is exactly:

```python
[
    f"- reading-status:: {reading_status}",
    f"  added-to-library:: [[{added_to_library}]]",
    "  #Highlighted #Highlights",
]
```

Re-run the existing structural invariants: six files, 58 highlights, 30
annotations, 42 tag values, 70 blank/whitespace-only quote lines, eight
normalized multiparagraph favorites, no bold span crossing a separator, and
quote text unchanged after accounting only for paragraph-local bold markers.

- [ ] **Step 6: Run final verification and commit the skill**

Run:

```sh
python3 -m unittest discover -s tests -v
python3 -m py_compile skills/highlighted-to-logseq/scripts/convert_highlighted_v2.py tests/test_highlighted_to_logseq_v2.py
git diff --check
git status --short
```

Expected: all tests and compilation pass; the only tracked uncommitted change
is `skills/highlighted-to-logseq/SKILL.md`; ignored processed outputs do not
appear in Git status.

Commit:

```sh
git add skills/highlighted-to-logseq/SKILL.md
git commit -m "docs: document linked library dates"
```
