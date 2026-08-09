#!/usr/bin/env python3
"""Convert Highlighted v2 Markdown exports into Logseq book pages."""

from __future__ import annotations

import argparse
from collections.abc import Sequence
from pathlib import Path
import re
from typing import Literal, TypeAlias


PAGE_TYPE = "[[Template/Book]]"
BOOK_ICON = "📖"
FOOTER_START = "**Created with [Highlighted](https://usehighlighted.com)**."
MetadataKind: TypeAlias = Literal["annotation", "tag"]
Metadata: TypeAlias = tuple[MetadataKind, str]
Highlight: TypeAlias = tuple[list[str], list[Metadata]]


def convert_file(source_path: Path) -> str:
    """Convert one Highlighted v2 export to Logseq Markdown."""
    lines = source_path.read_text(encoding="utf-8").splitlines()
    title, author, isbn, reading_status, added_to_library, content_start = (
        _parse_header(lines, source_path)
    )
    highlights = _parse_highlights(lines[content_start:])
    if not highlights:
        raise ValueError(f"no highlights found in {source_path}")

    properties = [
        f"page-type:: {PAGE_TYPE}",
        f"icon:: {BOOK_ICON}",
        f"book-title:: {title}",
        f"book-author:: [[{author}]]",
        "tags:: #book",
        f"isbn:: {isbn}",
    ]
    import_lines = [
        "- #Highlighted #Highlights",
        f"  reading-status:: {reading_status}",
        f"  added-to-library:: {added_to_library}",
    ]
    import_lines.extend(f"  {line}" for line in _render_highlights(highlights))
    return "\n".join(properties + [""] + import_lines) + "\n"


def _parse_header(
    lines: list[str], source_path: Path
) -> tuple[str, str, str, str, str, int]:
    """Extract required v2 metadata and return the first content index."""
    title_match = re.fullmatch(r"# Highlights for (.+)", lines[0]) if lines else None
    author_match = (
        re.fullmatch(r"### (?!by(?:\s|$))(.+)", lines[1]) if len(lines) > 1 else None
    )
    isbn_match = re.fullmatch(r"ISBN: (.+)", lines[2]) if len(lines) > 2 else None
    status_match = (
        re.fullmatch(r"Reading status: (.+)", lines[3]) if len(lines) > 3 else None
    )
    added_match = (
        re.fullmatch(r"Added to library: (\d{4}-\d{2}-\d{2})", lines[4])
        if len(lines) > 4
        else None
    )
    if not all((title_match, author_match, isbn_match, status_match, added_match)):
        raise ValueError(f"Unexpected Highlighted v2 header in {source_path}")
    return (
        title_match.group(1),
        author_match.group(1),
        isbn_match.group(1),
        status_match.group(1),
        added_match.group(1),
        5,
    )


def _parse_highlights(lines: list[str]) -> list[Highlight]:
    """Group each v2 quote with directly attached metadata."""
    highlights: list[Highlight] = []
    segment: list[str] = []

    def finish_highlight() -> None:
        if segment:
            highlight = _parse_highlight_segment(segment)
            if highlight is not None:
                highlights.append(highlight)

    for line in lines:
        if line == FOOTER_START:
            break
        if line.startswith("> "):
            finish_highlight()
            segment = [line[2:]]
        elif segment:
            segment.append(line)

    finish_highlight()
    return highlights


def _parse_highlight_segment(segment: list[str]) -> Highlight | None:
    """Separate v2 quote content from its directly attached metadata."""
    while segment and _is_separator_line(segment[-1]):
        segment.pop()
    if not segment:
        return None

    suffix_start = len(segment)
    for index in range(len(segment) - 1, 0, -1):
        line = segment[index]
        if _is_separator_line(line) or _is_metadata_line(line):
            suffix_start = index
        else:
            break

    quote = segment[:suffix_start]
    if not any(not _is_separator_line(line) for line in quote):
        return None

    metadata: list[Metadata] = []
    for line in segment[suffix_start:]:
        if _is_tag_line(line):
            metadata.extend(("tag", tag) for tag in _parse_tags(line))
        elif _is_metadata_line(line):
            metadata.append(("annotation", line))
    return quote, metadata


def _is_metadata_line(line: str) -> bool:
    return _is_page_marker(line) or _is_tag_line(line) or line.startswith("Note:")


def _is_separator_line(line: str) -> bool:
    return not line.strip()


def _is_page_marker(line: str) -> bool:
    return re.fullmatch(r"p\. \d+", line) is not None


def _is_tag_line(line: str) -> bool:
    return re.fullmatch(r"Tags: [^,]+(?:,\s*[^,]+)*", line) is not None


def _parse_tags(line: str) -> list[str]:
    """Convert v2 comma-separated tags to Logseq tag notation."""
    tags = []
    for value in line.removeprefix("Tags: ").split(","):
        name = value.strip()
        tags.append(f"#[[{name}]]" if " " in name else f"#{name}")
    return tags


def _render_highlights(highlights: list[Highlight]) -> list[str]:
    """Render grouped highlights as Logseq blocks."""
    rendered: list[str] = []
    for quote, metadata in highlights:
        tags = [value for kind, value in metadata if kind == "tag"]
        annotations = [value for kind, value in metadata if kind == "annotation"]
        quote_lines = _render_quote_lines(quote)
        if tags:
            rendered.append(f"- tags:: {', '.join(tags)}")
            rendered.extend(f"  {line}" for line in quote_lines)
        else:
            rendered.append(f"- {quote_lines[0]}")
            rendered.extend(f"  {line}" for line in quote_lines[1:])
        rendered.extend(f"  - {annotation}" for annotation in annotations)
    return rendered


def _render_quote_lines(lines: list[str]) -> list[str]:
    """Render quote lines without letting list syntax interrupt bold spans."""
    rendered: list[str] = []
    strong_open = False
    for line in lines:
        protected_line = line
        if strong_open:
            protected_line = re.sub(
                r"^(\s{0,3}\d{1,9})([.)])(?=[ \t])",
                r"\1\\\2",
                protected_line,
            )
            protected_line = re.sub(
                r"([ \t]+)(\*\*)$",
                r"\2\1",
                protected_line,
            )
        rendered.append(_render_quote_line(protected_line))
        if len(re.findall(r"(?<!\\)\*\*", line)) % 2:
            strong_open = not strong_open
    return rendered


def _render_quote_line(line: str) -> str:
    return ">" if line == "" else f"> {line}"


def _validate_distinct_paths(source_path: Path, output_path: Path) -> None:
    """Reject input and output paths that identify the same file."""
    if source_path.resolve() == output_path.resolve():
        raise ValueError("Input and output paths identify the same file")
    try:
        if source_path.samefile(output_path):
            raise ValueError("Input and output paths identify the same file")
    except FileNotFoundError:
        pass


def main(arguments: Sequence[str] | None = None) -> None:
    """Convert a v2 export to the requested Logseq page path."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_file", type=Path, help="Highlighted v2 Markdown export")
    parser.add_argument("output_file", type=Path, help="Logseq Markdown destination")
    args = parser.parse_args(arguments)

    _validate_distinct_paths(args.input_file, args.output_file)
    converted = convert_file(args.input_file)
    args.output_file.parent.mkdir(parents=True, exist_ok=True)
    args.output_file.write_text(converted, encoding="utf-8")


if __name__ == "__main__":
    main()
