# Highlighted Property Order Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render `book-title::` immediately before `book-author::` on every converted Logseq book page.

**Architecture:** Change only the order of existing page-property entries. Keep property values, highlight rendering, parsing, safety behavior, and all other output unchanged.

**Tech Stack:** Python 3 standard library and `unittest`.

## Global Constraints

- Work directly on `main` as explicitly requested.
- Do not modify original Highlighted exports.
- Make no output change except moving `book-title::` before `book-author::`.
- Add no dependencies.

---

### Task 1: Reorder book properties

**Files:**
- Modify: `tests/test_highlighted_to_logseq.py`
- Modify: `skills/highlighted-to-logseq/scripts/convert_highlighted.py`
- Modify: `skills/highlighted-to-logseq/SKILL.md`
- Modify: `docs/superpowers/plans/2026-08-09-highlighted-property-order.md`

**Interfaces:**
- Consumes: `convert_file(source_path: pathlib.Path) -> str`.
- Produces: the same output with `book-title::` immediately preceding `book-author::`.

- [x] **Step 1: Move `book-title::` before `book-author::` in every exact expected output**

- [x] **Step 2: Run `python3 -m unittest tests.test_highlighted_to_logseq -v` and verify RED from property order only**

- [x] **Step 3: Move `f"book-title:: {title}"` before `f"book-author:: [[{author}]]"` in `convert_file`**

- [x] **Step 4: Run `python3 -m unittest tests.test_highlighted_to_logseq -v` and verify GREEN**

- [x] **Step 5: List `book-title::` before `book-author::` in the skill's page-property summary**

- [x] **Step 6: Regenerate all nine processed pages and verify original source hashes remain unchanged**

- [x] **Step 7: Run final tests, `git diff --check`, privacy scan, and diff review**

- [x] **Step 8: Commit with `fix: order highlighted book properties`**
