# Calibre Workflows

## Workflow 1: Baseline Count Check

Goal: compare "books tagged in series" vs "books that likely belong in series."

1. Get count by exact series field:

```bash
sqlite3 '/path/to/Calibre Library/metadata.db' \
"select count(*)
 from books b
 join books_series_link bsl on b.id=bsl.book
 join series s on s.id=bsl.series
 where s.name='The Expanse';"
```

2. Get count by author variants to estimate in-scope franchise books:

```bash
sqlite3 '/path/to/Calibre Library/metadata.db' \
"select count(distinct b.id)
 from books b
 join books_authors_link bal on bal.book=b.id
 join authors a on a.id=bal.author
 where a.name in ('James S. A. Corey','James S.A. Corey');"
```

If author-scope count is greater, you likely have books missing `series` metadata.

## Workflow 2: Find Missing Series Assignments

Use `calibredb` for a lock-safe functional query:

```bash
calibredb --library-path '/path/to/Calibre Library' \
  list --search 'authors:"James S. A. Corey" and not series:"The Expanse"' --for-machine
```

When connected through Content Server:

```bash
calibredb --with-library 'http://localhost:8080/#Calibre_Library' \
  list --search 'authors:"James S. A. Corey" and not series:"The Expanse"' --for-machine
```

## Workflow 3: Inspect Before Mutating

Inspect each candidate ID first:

```bash
calibredb --library-path '/path/to/Calibre Library' show_metadata <id>
```

Capture current tags to avoid accidentally deleting non-`_sort_` tags.

## Workflow 4: Apply Series and Tag Fixes

For each target ID:

1. Set target `series` and `series_index`.
2. Remove `_sort_`.
3. Preserve all real tags.

Examples:

```bash
# Book with only _sort_ tag -> clear tags
calibredb --library-path '/path/to/Calibre Library' \
  set_metadata 101 --field 'series:The Expanse' --field 'series_index:5' --field 'tags:'

# Book with real tags + _sort_ -> keep real tags, drop _sort_
calibredb --library-path '/path/to/Calibre Library' \
  set_metadata 102 --field 'series:The Expanse' --field 'series_index:4' \
  --field 'tags:Fiction / Science Fiction / Action & Adventure,Fiction / Science Fiction / Space Opera,Fiction / Science Fiction / Hard Science Fiction'
```

## Workflow 5: Verify Completion

1. Ensure no remaining in-scope books are outside the series:

```bash
calibredb --library-path '/path/to/Calibre Library' \
  list --search 'authors:"James S. A. Corey" and not series:"The Expanse"' --for-machine
```

2. Ensure expected final count:

```bash
calibredb --library-path '/path/to/Calibre Library' \
  list --search 'authors:"James S. A. Corey" and series:"The Expanse"' --for-machine | jq 'length'
```

Expected success signals:

- mismatch query returns `[]`
- final count matches expected scope total
