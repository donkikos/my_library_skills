---
name: calibre-library
description: Use Calibre CLI and Content Server workflows to diagnose library counts, reconcile missing series metadata, and safely update series/tags with lock-aware fallback between REST and local calibredb.
---

# Calibre Library Skill

Use this skill when you need reliable Calibre library diagnostics or metadata updates via `calibredb`, `sqlite3`, and the Calibre Content Server API.

## When to Use This Skill

Invoke this skill for tasks such as:

- Counting books in a series and validating counts against expected franchise totals
- Finding books that belong to a series but are missing `series` metadata
- Fixing `series` and `series_index` values safely
- Removing helper tags such as `_sort_` without deleting real genre tags
- Switching between Content Server API workflows and direct local library workflows when write access differs

Keywords: calibre, calibredb, metadata.db, content server, ajax, series, series_index, tags, `_sort_`

## Core Workflow

Use this sequence for every task:

1. Define target scope
   - Identify exact series and author variants to include.
2. Discover access mode
   - Check whether Content Server is reachable and write-enabled.
   - If not, use direct local `calibredb --library-path`.
3. Establish baseline counts
   - Compare series-based count vs author/title-based scope count.
4. Diagnose mismatch
   - List books inside scope that are missing target series assignment.
5. Apply minimal metadata changes
   - Set `series` and `series_index` only for missing books.
   - Remove `_sort_` only; preserve all other tags.
6. Verify final state
   - Re-run mismatch query and final expected count query.

## Source of Truth and Tool Priority

Use this precedence:

1. Current local CLI behavior (`calibredb --help`, command help pages)
2. Running Content Server responses (`/ajax/library-info`, `/ajax/search`, `/ajax/book/{id}`)
3. Direct SQLite inspection of `metadata.db` for read-only diagnostics

Prefer `calibredb` for writes. Use raw SQLite as read-only verification unless explicitly required otherwise.

## Write Path Decision Matrix

1. If Content Server is running and writes are allowed:
   - Use `calibredb --with-library 'http://host:port/#library_id' ...`
2. If Content Server is running but write calls return `Forbidden` or read-only:
   - Fallback to `calibredb --library-path '/path/to/Calibre Library' ...`
3. If Content Server is not reachable:
   - Use direct local `--library-path` mode.
4. If local mode reports lock conflicts from another Calibre process:
   - Use remote mode through the running Content Server, or ask user to stop conflicting process.

## Safety Posture

- Never bulk-overwrite tags unless requested.
- For `_sort_` cleanup, keep existing non-`_sort_` tags exactly as-is.
- Confirm target IDs before applying write commands.
- After writes, always verify:
  - no target books remain outside expected series
  - expected final count is met

## References (Load As Needed)

- End-to-end workflows and reconciliation patterns:
  - `references/workflows.md`
- Error handling and lock/read-only troubleshooting:
  - `references/troubleshooting.md`
- Copy/paste command recipes for common operations:
  - `references/command-recipes.md`
