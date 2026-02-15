# Command Recipes

Use these variables for reusable commands:

```bash
LIB='/Users/tigran/Calibre Library'
DB="$LIB/metadata.db"
URL='http://localhost:8080'
LID='Calibre_Library'
```

## Discover Library and Server State

```bash
find /Users/$USER -maxdepth 6 -name metadata.db 2>/dev/null | head -n 20
curl -sS "$URL/ajax/library-info"
```

## Count: Series vs Author Scope

```bash
sqlite3 "$DB" "select s.name, count(*)
from books_series_link bsl join series s on s.id=bsl.series
group by s.name having lower(s.name) like '%expanse%';"

sqlite3 "$DB" "select a.name, count(*)
from books_authors_link bal join authors a on a.id=bal.author
group by a.name having lower(a.name) like '%corey%';"
```

## Find Remaining Missing Series Books

Remote mode:

```bash
calibredb --with-library "$URL/#$LID" \
  list --search 'authors:"James S. A. Corey" and not series:"The Expanse"' --for-machine
```

Local mode fallback:

```bash
calibredb --library-path "$LIB" \
  list --search 'authors:"James S. A. Corey" and not series:"The Expanse"' --for-machine
```

## Inspect Candidate Metadata

```bash
calibredb --library-path "$LIB" show_metadata 101
calibredb --library-path "$LIB" show_metadata 102
calibredb --library-path "$LIB" show_metadata 107
```

## Apply Updates (Expanse Example)

```bash
calibredb --library-path "$LIB" \
  set_metadata 101 --field 'series:The Expanse' --field 'series_index:5' --field 'tags:'

calibredb --library-path "$LIB" \
  set_metadata 102 --field 'series:The Expanse' --field 'series_index:4' \
  --field 'tags:Fiction / Science Fiction / Action & Adventure,Fiction / Science Fiction / Space Opera,Fiction / Science Fiction / Hard Science Fiction'

calibredb --library-path "$LIB" \
  set_metadata 107 --field 'series:The Expanse' --field 'series_index:6' \
  --field 'tags:Fiction / Science Fiction / Space Opera,Fiction / Science Fiction / Action & Adventure'
```

## Verify Completion

```bash
calibredb --library-path "$LIB" \
  list --search 'authors:"James S. A. Corey" and not series:"The Expanse"' --for-machine

calibredb --library-path "$LIB" \
  list --search 'authors:"James S. A. Corey" and series:"The Expanse"' --for-machine | jq 'length'
```

Success conditions:

- first command returns `[]`
- second command returns expected total (e.g., `13`)
