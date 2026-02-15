# Troubleshooting

## 1) `Another calibre program ... is running`

Symptom:

- local `calibredb --library-path ...` operations fail with lock/concurrency error

Cause:

- Calibre GUI or another Calibre process holds the library lock

Actions:

1. Prefer remote mode through an active Content Server:
   - `calibredb --with-library 'http://localhost:8080/#<library_id>' ...`
2. If no Content Server exists, stop conflicting process and retry local mode.

## 2) `Forbidden` when writing via Content Server

Symptom:

- `set_metadata` via `--with-library http://...` returns `Forbidden`

Cause:

- server is read-only for current connection (auth/local-write policy)

Actions:

1. Fallback to local direct mode:
   - `calibredb --library-path '/path/to/Calibre Library' ...`
2. Or reconfigure server for write access (auth or local write), then retry remote mode.

Default for this skill: fallback to local `--library-path` when safe.

## 3) REST/API endpoint unreachable

Symptom:

- `curl http://localhost:8080/ajax/library-info` returns connection refused

Cause:

- Content Server not started, different port, or network namespace mismatch

Actions:

1. Confirm listener/port on host.
2. If unavailable, use local `calibredb --library-path` mode.
3. If running in restricted sandbox, rerun network checks with required permissions.

## 4) Series count still too low after updates

Symptom:

- count by `series:"The Expanse"` is still below expected

Likely causes:

- author name variants split data (`James S. A. Corey` vs `James S.A. Corey`)
- some titles missing expected author mapping
- title set includes novellas/short fiction not yet curated

Actions:

1. Query by both author variants.
2. List IDs not in series and inspect metadata one-by-one.
3. Update `series` and `series_index` for missing IDs.

## 5) Tag cleanup accidentally drops real tags

Risk:

- replacing full `tags:` list without preserving current tags

Safe pattern:

1. `show_metadata <id>` first.
2. Rebuild tags list minus `_sort_` only.
3. Apply with explicit `--field 'tags:...'`.

Use empty `tags:` only when the book had `_sort_` and nothing else.
