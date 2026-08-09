"""Tests for the standalone Highlighted-v2-to-Logseq converter."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest


SKILL_DIR = Path(__file__).parents[1] / "skills" / "highlighted-to-logseq"
SCRIPT_PATH = SKILL_DIR / "scripts" / "convert_highlighted_v2.py"


def load_converter():
    """Load the bundled v2 script without installing a package."""
    spec = importlib.util.spec_from_file_location("convert_highlighted_v2", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SOURCE = (
    "# Highlights for Example Book\n"
    "### Example Author\n"
    "ISBN: 9780000000000\n"
    "Reading status: Reading\n"
    "Added to library: 2025-12-03\n\n"
    "*Favorites are marked in bold.*\n\n"
    "> First paragraph.  \n\n"
    "Second paragraph.\n"
    "Note: Verify attribution\n"
    "p. 12\n"
    "Tags: Quotes, Scientific Papers\n\n"
    "> Another highlight.\n\n"
    "**Created with [Highlighted](https://usehighlighted.com)**.\n"
    "*Highlights may be protected by copyright.*\n"
)

EXPECTED_OUTPUT = (
    "page-type:: [[Template/Book]]\n"
    "icon:: 📖\n"
    "book-title:: Example Book\n"
    "book-author:: [[Example Author]]\n"
    "tags:: #book\n"
    "isbn:: 9780000000000\n\n"
    "- reading-status:: Reading\n"
    "  added-to-library:: 2025-12-03\n"
    "  #Highlighted #Highlights\n"
    "  - tags:: #Quotes, #[[Scientific Papers]]\n"
    "    > First paragraph.  \n"
    "    >\n"
    "    > Second paragraph.\n"
    "    - Note: Verify attribution\n"
    "    - p. 12\n"
    "  - > Another highlight.\n"
)


class HighlightedToLogseqV2Test(unittest.TestCase):
    """Behavior of the standalone v2 converter script."""

    def test_converter_renders_complete_v2_export(self) -> None:
        """It preserves v2 data while removing only exporter boilerplate."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            source.write_text(SOURCE, encoding="utf-8")

            output = converter.convert_file(source)

        self.assertEqual(output, EXPECTED_OUTPUT)

    def test_converter_normalizes_multiparagraph_bold_around_citations(
        self,
    ) -> None:
        """It gives each favorite paragraph its own valid bold span."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            source.write_text(
                "# Highlights for Example Book\n"
                "### Example Author\n"
                "ISBN: 9780000000000\n"
                "Reading status: Finished\n"
                "Added to library: 2025-12-03\n\n"
                "> **Highlighted claim [153].\n\n"
                "153. First citation.\n"
                "154. Second citation.  **\n"
                "Tags: Scientific Papers\n\n"
                "**Created with [Highlighted](https://usehighlighted.com)**.\n"
                "*Highlights may be protected by copyright.*\n",
                encoding="utf-8",
            )

            output = converter.convert_file(source)

        self.assertIn("    > **Highlighted claim [153].**\n", output)
        self.assertIn("    > **153. First citation.\n", output)
        self.assertIn("    > 154\\. Second citation.**  \n", output)
        self.assertIn("  - tags:: #[[Scientific Papers]]\n", output)

    def test_normalizer_preserves_whitespace_only_separators(self) -> None:
        """It changes bold boundaries without dropping source whitespace."""
        converter = load_converter()

        normalized = converter._normalize_multiparagraph_bold(
            ["  **First line", "continues.  ", "", "  ", "Second paragraph.**  "]
        )

        self.assertEqual(
            normalized,
            [
                "  **First line",
                "continues.**  ",
                "",
                "  ",
                "**Second paragraph.**  ",
            ],
        )

    def test_normalizer_leaves_nonmatching_bold_unchanged(self) -> None:
        """It does not reinterpret single, internal, or unbalanced bold."""
        converter = load_converter()
        cases = [
            ["**One paragraph.**"],
            ["**First paragraph.", "", "Second with **inline** bold.**"],
            ["**First paragraph.", "", "Unclosed second paragraph."],
        ]

        for lines in cases:
            with self.subTest(lines=lines):
                self.assertEqual(converter._normalize_multiparagraph_bold(lines), lines)

    def test_converter_rejects_v1_header(self) -> None:
        """It does not silently reinterpret a legacy export as v2."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            source.write_text(
                "# Highlights for ‘Example Book’\n"
                "### by Example Author\n"
                "ISBN: 9780000000000\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ValueError, "Unexpected Highlighted v2 header"):
                converter.convert_file(source)

    def test_converter_rejects_v2_header_without_highlights(self) -> None:
        """It rejects a valid v2 export that contains no highlight blocks."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            source.write_text(
                "# Highlights for Example Book\n"
                "### Example Author\n"
                "ISBN: 9780000000000\n"
                "Reading status: To read\n"
                "Added to library: 2025-12-03\n\n"
                "**Created with [Highlighted](https://usehighlighted.com)**.\n"
                "*Highlights may be protected by copyright.*\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ValueError, "no highlights"):
                converter.convert_file(source)

    def test_main_rejects_same_input_and_output_file(self) -> None:
        """It leaves a v2 source unchanged when paths are identical."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            source.write_text(SOURCE, encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "same file"):
                converter.main([str(source), str(source)])

            self.assertEqual(source.read_text(encoding="utf-8"), SOURCE)

    @unittest.skipUnless(hasattr(Path, "symlink_to"), "symlinks unsupported")
    def test_main_rejects_symlink_alias_for_input_and_output(self) -> None:
        """It leaves a v2 source unchanged when output is a symlink alias."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            alias = Path(directory) / "output.md"
            source.write_text(SOURCE, encoding="utf-8")
            try:
                alias.symlink_to(source)
            except OSError as error:
                self.skipTest(f"symlinks unsupported: {error}")

            with self.assertRaisesRegex(ValueError, "same file"):
                converter.main([str(source), str(alias)])

            self.assertEqual(source.read_text(encoding="utf-8"), SOURCE)

    def test_main_rejects_hard_link_alias_for_input_and_output(self) -> None:
        """It leaves a v2 source unchanged when output is a hard-link alias."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            alias = Path(directory) / "output.md"
            source.write_text(SOURCE, encoding="utf-8")
            try:
                os.link(source, alias)
            except OSError as error:
                self.skipTest(f"hard links unsupported: {error}")

            with self.assertRaisesRegex(ValueError, "same file"):
                converter.main([str(source), str(alias)])

            self.assertEqual(source.read_text(encoding="utf-8"), SOURCE)

    def test_main_preserves_existing_output_when_input_is_invalid(self) -> None:
        """It does not replace existing output when v2 conversion fails."""
        converter = load_converter()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.md"
            output = Path(directory) / "output.md"
            sentinel = "do not overwrite\n"
            source.write_text("not a Highlighted v2 export\n", encoding="utf-8")
            output.write_text(sentinel, encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "Unexpected Highlighted v2 header"):
                converter.main([str(source), str(output)])

            self.assertEqual(output.read_text(encoding="utf-8"), sentinel)


if __name__ == "__main__":
    unittest.main()
