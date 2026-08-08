"""Tests for the bundled Highlighted-to-Logseq converter."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest


SKILL_DIR = Path(__file__).parents[1] / "skills" / "highlighted-to-logseq"
SCRIPT_PATH = SKILL_DIR / "scripts" / "convert_highlighted.py"


def load_converter():
    """Load the bundled script without installing a package."""
    spec = importlib.util.spec_from_file_location("convert_highlighted", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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

EXPECTED_OUTPUT = (
    "page-type:: [[Template/Book]]\n"
    "icon:: 📖\n"
    "author:: [[Example Author]]\n"
    "tags:: #book\n"
    "source:: #Highlighted\n"
    "isbn:: 9780000000000\n"
    "title:: Example Book\n\n"
    + EXPECTED_HIGHLIGHTS
)


class HighlightedToLogseqTest(unittest.TestCase):
    """Behavior of the bundled converter script."""

    def test_converter_renders_lossless_logseq_book_page(self) -> None:
        """It preserves quote content and renders only separated metadata."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            source.write_text(SOURCE, encoding="utf-8")

            output = converter.convert_file(source)

        self.assertEqual(output, EXPECTED_OUTPUT)

    def test_converter_rejects_malformed_header(self) -> None:
        """It rejects files that do not start with the Highlighted header."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            source.write_text("Example Book\n", encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "Unexpected Highlighted header"):
                converter.convert_file(source)

    def test_converter_rejects_valid_header_without_highlights(self) -> None:
        """It rejects valid Highlighted exports that have no quote content."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            source.write_text(
                "# Highlights for ‘Example Book’\n"
                "### by Example Author\n"
                "ISBN: 9780000000000\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ValueError, "no highlights"):
                converter.convert_file(source)

    def test_converter_rejects_blank_quote_with_separated_metadata(self) -> None:
        """It rejects metadata attached to a marker with no quote content."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            source.write_text(
                "# Highlights for ‘Example Book’\n"
                "### by Example Author\n"
                "ISBN: 9780000000000\n\n"
                "> \n\n"
                "Note: Verify attribution\n"
                "p. 1\n"
                "#Quotes\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ValueError, "no highlights"):
                converter.convert_file(source)

    def test_converter_handles_whitespace_only_metadata_separators(self) -> None:
        """It preserves internal whitespace while separating trailing metadata."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            source.write_text(
                "# Highlights for ‘Example Book’\n"
                "### by Example Author\n"
                "ISBN: 9780000000000\n\n"
                "> First paragraph\n"
                "  \n"
                "Second paragraph\n\n"
                "#Quotes\n\n"
                "  \n"
                "> Next highlight\n",
                encoding="utf-8",
            )

            output = converter.convert_file(source)

        self.assertEqual(
            output,
            "page-type:: [[Template/Book]]\n"
            "icon:: 📖\n"
            "author:: [[Example Author]]\n"
            "tags:: #book\n"
            "source:: #Highlighted\n"
            "isbn:: 9780000000000\n"
            "title:: Example Book\n\n"
            "- tags:: #Quotes\n"
            "  > First paragraph\n"
            "  >   \n"
            "  > Second paragraph\n"
            "- > Next highlight\n",
        )

    def test_converter_preserves_spanning_bold_around_numbered_citations(self) -> None:
        """It keeps numbered citations inside a valid spanning bold run."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            source.write_text(
                "# Highlights for ‘Example Book’\n"
                "### by Example Author\n"
                "ISBN: 9780000000000\n\n"
                "> **Highlighted claim [153].\n\n"
                "153. First citation.\n"
                "154. Second citation.  **\n\n"
                "#Scientific Papers\n\n"
                "> 1. Real list item.\n\n"
                "#Lists\n",
                encoding="utf-8",
            )

            output = converter.convert_file(source)

        self.assertEqual(
            output,
            "page-type:: [[Template/Book]]\n"
            "icon:: 📖\n"
            "author:: [[Example Author]]\n"
            "tags:: #book\n"
            "source:: #Highlighted\n"
            "isbn:: 9780000000000\n"
            "title:: Example Book\n\n"
            "- tags:: #[[Scientific Papers]]\n"
            "  > **Highlighted claim [153].\n"
            "  >\n"
            "  > 153\\. First citation.\n"
            "  > 154\\. Second citation.**  \n"
            "- tags:: #Lists\n"
            "  > 1. Real list item.\n",
        )

    def test_converter_keeps_first_note_line_as_quote_content(self) -> None:
        """It recognizes separated metadata after a metadata-like first line."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            source.write_text(
                "# Highlights for ‘Example Book’\n"
                "### by Example Author\n"
                "ISBN: 9780000000000\n\n"
                "> Note: quoted text\n\n"
                "p. 7\n",
                encoding="utf-8",
            )

            output = converter.convert_file(source)

        self.assertEqual(
            output,
            "page-type:: [[Template/Book]]\n"
            "icon:: 📖\n"
            "author:: [[Example Author]]\n"
            "tags:: #book\n"
            "source:: #Highlighted\n"
            "isbn:: 9780000000000\n"
            "title:: Example Book\n\n"
            "- > Note: quoted text\n"
            "  - p. 7\n",
        )

    def test_parser_preserves_interleaved_metadata_order(self) -> None:
        """It retains metadata order before rendering tags and annotations."""
        converter = load_converter()

        highlights = converter._parse_highlights(
            [
                "> Quote content",
                "",
                "Note: first annotation",
                "#First",
                "p. 3",
                "#Second",
            ]
        )

        self.assertEqual(
            highlights,
            [
                (
                    ["Quote content"],
                    [
                        ("annotation", "Note: first annotation"),
                        ("tag", "#First"),
                        ("annotation", "p. 3"),
                        ("tag", "#Second"),
                    ],
                )
            ],
        )

    def test_main_rejects_same_input_and_output_file(self) -> None:
        """It leaves a source unchanged when input and output are identical."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            original = SOURCE
            source.write_text(original, encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "same file"):
                converter.main([str(source), str(source)])

            self.assertEqual(source.read_text(encoding="utf-8"), original)

    @unittest.skipUnless(hasattr(Path, "symlink_to"), "symlinks unsupported")
    def test_main_rejects_symlink_alias_for_input_and_output(self) -> None:
        """It leaves a source unchanged when output is a symlink alias."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            alias = Path(directory) / "output.md"
            original = SOURCE
            source.write_text(original, encoding="utf-8")
            try:
                alias.symlink_to(source)
            except OSError as error:
                self.skipTest(f"symlinks unsupported: {error}")

            with self.assertRaisesRegex(ValueError, "same file"):
                converter.main([str(source), str(alias)])

            self.assertEqual(source.read_text(encoding="utf-8"), original)

    def test_main_rejects_hard_link_alias_for_input_and_output(self) -> None:
        """It leaves a source unchanged when output is a hard-link alias."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            alias = Path(directory) / "output.md"
            original = SOURCE
            source.write_text(original, encoding="utf-8")
            try:
                os.link(source, alias)
            except OSError as error:
                self.skipTest(f"hard links unsupported: {error}")

            with self.assertRaisesRegex(ValueError, "same file"):
                converter.main([str(source), str(alias)])

            self.assertEqual(source.read_text(encoding="utf-8"), original)

    def test_main_preserves_existing_output_when_input_is_invalid(self) -> None:
        """It does not replace an existing output when conversion fails."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            output = Path(directory) / "output.md"
            sentinel = "do not overwrite\n"
            source.write_text("not a Highlighted export\n", encoding="utf-8")
            output.write_text(sentinel, encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "Unexpected Highlighted header"):
                converter.main([str(source), str(output)])

            self.assertEqual(output.read_text(encoding="utf-8"), sentinel)


if __name__ == "__main__":
    unittest.main()
