# Audible Skill Migration Design

## Goal

Move the current Audible download-and-convert functionality from `../audible`
into this repository without importing its git history or modifying the source
checkout.

## Repository Layout

Keep the Audible workflow self-contained:

```text
skills/audible-download-convert/
├── SKILL.md
├── agents/
│   └── openai.yaml
├── pyproject.toml
├── uv.lock
└── scripts/
    ├── convert_aax_to_m4b.sh
    └── download_and_convert.sh
```

The Python project and lockfile belong to this skill because the other skills
do not use `audible-cli`. Keeping them local avoids making the repository root
look like a shared Python application.

Do not migrate the standalone `README.md`, `.venv`, `.ruff_cache`, `.history`,
downloaded audiobook data, or source repository metadata.

## Runtime Behavior

Preserve the current behavior, arguments, environment variables, and locked
dependency versions.

Update path discovery so:

- `download_and_convert.sh` finds the skill directory from its own location.
- `uv` uses the skill-local `pyproject.toml` and `uv.lock`.
- The converter is invoked from the same `scripts` directory.
- The default `AUDIBLE_DATA_DIR` remains outside the skill's source files,
  using `<repository>/audible_data` for backward-compatible repository-local
  behavior.

Keep these existing configurable paths:

- `AUDIBLE_DATA_DIR`
- `AUDIBLE_VENV_DIR`
- `AUDIBLE_CONFIG_DIR`
- `AUDIBLE_AUTHCODE_FILE`

Authentication files, virtual environments, downloads, and converted books
must remain untracked runtime state.

## Documentation

Update `SKILL.md` so setup and direct `uv` commands use the skill directory as
the uv project path. Keep usage examples relative to the repository root.

Add `agents/openai.yaml` matching the skill metadata and intended trigger:
downloading Audible titles by ASIN and converting AAX files to M4B.

The source repository's README will not be copied because operational guidance
belongs in `SKILL.md` and duplicate documentation would drift.

## Tests

Migrate the existing shell tests and adapt expected paths to the skill-local
layout. Integrate them into this repository's test surface, either as a
dedicated test script under `tests/` or through the existing runtime-contract
test entrypoint.

Tests must cover:

- dry-run paths;
- forwarding the configured uv environment and Audible configuration;
- using the skill-local uv project;
- invoking the skill-local converter;
- rejecting an unreadable explicitly configured authcode file;
- existing Calibre and Storyteller runtime contracts remaining valid.

Run shell syntax checks for migrated scripts and execute all repository shell
tests.

## Migration Safety

Copy files from `../audible`; do not move, edit, or delete that checkout.
Exclude generated and sensitive runtime files. Review the final diff for
unexpected root-level dependencies and verify no absolute source-checkout paths
remain.

The user will retire `../audible` manually after reviewing the completed
migration.
