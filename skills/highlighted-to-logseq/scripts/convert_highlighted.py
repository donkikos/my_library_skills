#!/usr/bin/env python3
"""Convert Highlighted Markdown exports into Logseq book pages."""

from __future__ import annotations

import argparse
from collections.abc import Sequence
from pathlib import Path
import re
from typing import Literal, TypeAlias


PAGE_TYPE = "[[Template/Book]]"
BOOK_ICON = "📖"
MetadataKind: TypeAlias = Literal["annotation", "tag"]
Metadata: TypeAlias = tuple[MetadataKind, str]
Highlight: TypeAlias = tuple[list[str], list[Metadata]]


def convert_file(source_path: Path) -> str:
    """Convert one Highlighted export to Logseq Markdown."""
    lines = source_path.read_text(encoding="utf-8").splitlines()
    title, author, isbn, content_start = _parse_header(lines, source_path)
    highlights = _parse_highlights(lines[content_start:])
    if not highlights:
        raise ValueError(f"no highlights found in {source_path}")

    properties = [
        f"page-type:: {PAGE_TYPE}",
        f"icon:: {BOOK_ICON}",
        f"author:: [[{author}]]",
        "tags:: #book",
        "source:: #Highlighted",
        f"isbn:: {isbn}",
        f"title:: {title}",
    ]
    return "\n".join(properties + [""] + _render_highlights(highlights)) + "\n"


def _parse_header(lines: list[str], source_path: Path) -> tuple[str, str, str, int]:
    """Extract required book metadata and return the first content index."""
    title_match = re.match(r"# Highlights for [‘'](.+?)[’']$", lines[0]) if lines else None
    author_match = re.match(r"### by (.+)$", lines[1]) if len(lines) > 1 else None
    isbn_match = re.match(r"ISBN: (.+)$", lines[2]) if len(lines) > 2 else None
    if not title_match or not author_match or not isbn_match:
        raise ValueError(f"Unexpected Highlighted header in {source_path}")
    return (
        title_match.group(1),
        author_match.group(1),
        isbn_match.group(1),
        3,
    )


def _parse_highlights(lines: list[str]) -> list[Highlight]:
    """Group each quote with its source tags and nested annotations."""
    highlights: list[Highlight] = []
    segment: list[str] = []

    def finish_highlight() -> None:
        if segment:
            highlight = _parse_highlight_segment(segment)
            if highlight is not None:
                highlights.append(highlight)

    for line in lines:
        if line.startswith("> "):
            finish_highlight()
            segment = [line[2:]]
        elif not segment:
            continue
        else:
            segment.append(line)

    finish_highlight()
    return highlights


def _parse_highlight_segment(
    segment: list[str],
) -> Highlight | None:
    """Separate a quote from metadata only across a blank-line boundary."""
    while segment and _is_separator_line(segment[-1]):
        segment.pop()
    if not segment:
        return None

    saw_metadata = False
    suffix_start = len(segment)
    for index in range(len(segment) - 1, -1, -1):
        if index == 0:
            break
        line = segment[index]
        if _is_separator_line(line):
            suffix_start = index
        elif _is_metadata_line(line):
            suffix_start = index
            saw_metadata = True
        else:
            break

    metadata_start = next(
        (
            index
            for index in range(suffix_start, len(segment))
            if not _is_separator_line(segment[index])
        ),
        len(segment),
    )
    if (
        not saw_metadata
        or metadata_start == 0
        or not _is_separator_line(segment[metadata_start - 1])
    ):
        return segment, []

    metadata_lines = segment[metadata_start:]
    quote = segment[:suffix_start]
    if not any(not _is_separator_line(line) for line in quote):
        return None

    metadata: list[Metadata] = []
    for line in metadata_lines:
        if _is_tag_line(line):
            metadata.extend(("tag", tag) for tag in _parse_tags(line))
        elif not _is_separator_line(line):
            metadata.append(("annotation", line))
    return quote, metadata


def _is_metadata_line(line: str) -> bool:
    """Return whether a line belongs to Highlighted's metadata suffix."""
    return _is_page_marker(line) or _is_tag_line(line) or line.startswith("Note:")


def _is_separator_line(line: str) -> bool:
    """Return whether a line only separates quote content and metadata."""
    return not line.strip()


def _is_page_marker(line: str) -> bool:
    return re.fullmatch(r"p\. \d+", line) is not None


def _is_tag_line(line: str) -> bool:
    return re.fullmatch(r"#[^,#]+(?:,\s*#[^,#]+)*", line) is not None


def _parse_tags(line: str) -> list[str]:
    """Convert Highlighted's source tag notation to Logseq tag notation."""
    tags = []
    for value in re.findall(r"#([^,#]+)", line):
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
    """Convert one Highlighted export to the requested Logseq page path."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_file", type=Path, help="Highlighted Markdown export")
    parser.add_argument("output_file", type=Path, help="Logseq Markdown destination")
    args = parser.parse_args(arguments)

    _validate_distinct_paths(args.input_file, args.output_file)
    args.output_file.parent.mkdir(parents=True, exist_ok=True)
    args.output_file.write_text(convert_file(args.input_file), encoding="utf-8")


if __name__ == "__main__":
    main()
