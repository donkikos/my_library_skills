# Audible Skill Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the current Audible download-and-convert workflow into a self-contained skill in this repository while leaving `../audible` unchanged.

**Architecture:** The Audible skill owns its instructions, UI metadata, shell scripts, `pyproject.toml`, and `uv.lock`. Runtime scripts derive both the skill directory and repository root from their own locations, use the skill directory as the frozen uv project, and retain the repository-level `audible_data` default for behavioral compatibility.

**Tech Stack:** Bash, uv, Python 3.13, `audible-cli`, ffmpeg/ffprobe, jq, shell contract tests

---

## File Map

- Create `skills/audible-download-convert/SKILL.md`: Audible workflow instructions and runtime contract.
- Create `skills/audible-download-convert/agents/openai.yaml`: skill-list display metadata.
- Create `skills/audible-download-convert/pyproject.toml`: isolated `audible-cli` project definition.
- Create `skills/audible-download-convert/uv.lock`: frozen dependency graph copied from the source repository.
- Create `skills/audible-download-convert/scripts/download_and_convert.sh`: download orchestration using the skill-local uv project.
- Create `skills/audible-download-convert/scripts/convert_aax_to_m4b.sh`: AAX conversion implementation.
- Create `tests/test_audible_download_convert.sh`: migrated behavioral tests with skill-local path assertions.
- Modify `tests/test_skill_runtime_contracts.sh`: add Audible metadata, path, and forbidden-literal contracts.
- Modify `.gitignore`: ignore repository-local Audible runtime data.

### Task 1: Add Failing Audible Migration Tests

**Files:**
- Create: `tests/test_audible_download_convert.sh`
- Modify: `tests/test_skill_runtime_contracts.sh`

- [ ] **Step 1: Copy the existing behavioral test as the migration baseline**

Run:

```bash
cp ../audible/tests/test_download_and_convert.sh \
  tests/test_audible_download_convert.sh
chmod +x tests/test_audible_download_convert.sh
```

Expected: `tests/test_audible_download_convert.sh` exists and is executable.

- [ ] **Step 2: Change the behavioral test to expect the skill-local layout**

Apply this patch:

```diff
--- a/tests/test_audible_download_convert.sh
+++ b/tests/test_audible_download_convert.sh
@@
 REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
 DOWNLOAD_SCRIPT="$REPO_ROOT/skills/audible-download-convert/scripts/download_and_convert.sh"
-CONVERT_SCRIPT="$REPO_ROOT/convert_aax_to_m4b.sh"
+SKILL_DIR="$REPO_ROOT/skills/audible-download-convert"
+CONVERT_SCRIPT="$SKILL_DIR/scripts/convert_aax_to_m4b.sh"
@@
 ARG=--project
-ARG=$REPO_ROOT
+ARG=$SKILL_DIR
```

Expected: the fake uv log asserts that `--project` points to
`skills/audible-download-convert`, and the converter assertion points to the
skill-local script.

- [ ] **Step 3: Add Audible contracts to the shared runtime test**

Insert after the Storyteller path declarations:

```bash
AUDIBLE_SKILL="$ROOT_DIR/skills/audible-download-convert/SKILL.md"
AUDIBLE_DOWNLOAD="$ROOT_DIR/skills/audible-download-convert/scripts/download_and_convert.sh"
AUDIBLE_CONVERT="$ROOT_DIR/skills/audible-download-convert/scripts/convert_aax_to_m4b.sh"
AUDIBLE_PROJECT="$ROOT_DIR/skills/audible-download-convert/pyproject.toml"
AUDIBLE_LOCK="$ROOT_DIR/skills/audible-download-convert/uv.lock"
```

Insert before the final success message:

```bash
assert_frontmatter_contract \
  "$AUDIBLE_SKILL" '[bash, uv, ffmpeg, ffprobe, jq]'
assert_contains "$AUDIBLE_SKILL" \
  'AUDIBLE_DATA_DIR="${AUDIBLE_DATA_DIR:-$REPO_ROOT/audible_data}"'
assert_contains "$AUDIBLE_DOWNLOAD" \
  'SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"'
assert_contains "$AUDIBLE_DOWNLOAD" \
  'REPO_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"'
assert_contains "$AUDIBLE_DOWNLOAD" \
  'download_cmd=(uv run --project "$SKILL_DIR" --frozen audible)'
assert_contains "$AUDIBLE_DOWNLOAD" \
  'CONVERT_CMD="$SCRIPT_DIR/convert_aax_to_m4b.sh"'
assert_contains "$AUDIBLE_PROJECT" 'audible-cli==0.3.3'

for required_file in \
  "$AUDIBLE_SKILL" \
  "$AUDIBLE_DOWNLOAD" \
  "$AUDIBLE_CONVERT" \
  "$AUDIBLE_PROJECT" \
  "$AUDIBLE_LOCK"; do
  [[ -f "$required_file" ]] || fail "missing Audible migration file: $required_file"
done

assert_no_literal '/path/to/audible' \
  "$AUDIBLE_SKILL" "$AUDIBLE_DOWNLOAD" "$AUDIBLE_CONVERT"
assert_no_literal '../audible' \
  "$AUDIBLE_SKILL" "$AUDIBLE_DOWNLOAD" "$AUDIBLE_CONVERT"
```

Change the final line to:

```bash
echo "skill runtime contracts: ok"
```

- [ ] **Step 4: Run the tests and verify they fail because the skill is absent**

Run:

```bash
bash tests/test_audible_download_convert.sh
bash tests/test_skill_runtime_contracts.sh
```

Expected:

- Behavioral test fails because
  `skills/audible-download-convert/scripts/download_and_convert.sh` does not
  exist.
- Runtime-contract test fails because
  `skills/audible-download-convert/SKILL.md` does not exist.

- [ ] **Step 5: Commit the failing tests**

```bash
git add tests/test_audible_download_convert.sh tests/test_skill_runtime_contracts.sh
git commit -m "test: define audible skill migration contracts"
```

### Task 2: Migrate the Audible Runtime

**Files:**
- Create: `skills/audible-download-convert/pyproject.toml`
- Create: `skills/audible-download-convert/uv.lock`
- Create: `skills/audible-download-convert/scripts/download_and_convert.sh`
- Create: `skills/audible-download-convert/scripts/convert_aax_to_m4b.sh`

- [ ] **Step 1: Create the skill directories and copy current runtime files**

Run:

```bash
mkdir -p skills/audible-download-convert/scripts
cp ../audible/pyproject.toml skills/audible-download-convert/pyproject.toml
cp ../audible/uv.lock skills/audible-download-convert/uv.lock
cp ../audible/skills/audible-download-convert/scripts/download_and_convert.sh \
  skills/audible-download-convert/scripts/download_and_convert.sh
cp ../audible/convert_aax_to_m4b.sh \
  skills/audible-download-convert/scripts/convert_aax_to_m4b.sh
chmod +x skills/audible-download-convert/scripts/*.sh
```

Expected: all four runtime files exist under the skill, and both shell scripts
are executable.

- [ ] **Step 2: Make download orchestration resolve the skill-local project**

Replace:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
```

with:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"
```

Replace:

```bash
CONVERT_CMD="$REPO_ROOT/convert_aax_to_m4b.sh"
```

with:

```bash
CONVERT_CMD="$SCRIPT_DIR/convert_aax_to_m4b.sh"
```

Replace:

```bash
download_cmd=(uv run --project "$REPO_ROOT" --frozen audible)
```

with:

```bash
download_cmd=(uv run --project "$SKILL_DIR" --frozen audible)
```

- [ ] **Step 3: Run shell syntax checks**

Run:

```bash
bash -n skills/audible-download-convert/scripts/download_and_convert.sh
bash -n skills/audible-download-convert/scripts/convert_aax_to_m4b.sh
```

Expected: both commands exit 0 with no output.

- [ ] **Step 4: Run the behavioral test**

Run:

```bash
bash tests/test_audible_download_convert.sh
```

Expected:

```text
PASS
```

- [ ] **Step 5: Commit the runtime**

```bash
git add \
  skills/audible-download-convert/pyproject.toml \
  skills/audible-download-convert/uv.lock \
  skills/audible-download-convert/scripts/download_and_convert.sh \
  skills/audible-download-convert/scripts/convert_aax_to_m4b.sh
git commit -m "feat: migrate audible runtime into skill"
```

### Task 3: Add Audible Skill Instructions and Metadata

**Files:**
- Create: `skills/audible-download-convert/SKILL.md`
- Create: `skills/audible-download-convert/agents/openai.yaml`
- Modify: `.gitignore`

- [ ] **Step 1: Copy the current skill instructions**

Run:

```bash
cp ../audible/skills/audible-download-convert/SKILL.md \
  skills/audible-download-convert/SKILL.md
mkdir -p skills/audible-download-convert/agents
```

- [ ] **Step 2: Replace source-repository setup paths with skill-local setup**

In `SKILL.md`, replace the Frozen Environment command block with:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/skills/audible-download-convert"
AUDIBLE_DATA_DIR="${AUDIBLE_DATA_DIR:-$REPO_ROOT/audible_data}"

uv python install 3.13
UV_PROJECT_ENVIRONMENT="$AUDIBLE_VENV_DIR" \
  uv sync --project "$SKILL_DIR" --frozen --python 3.13
UV_PROJECT_ENVIRONMENT="$AUDIBLE_VENV_DIR" \
  uv run --project "$SKILL_DIR" --frozen audible --help
```

Replace both authentication command blocks so `--project` is
`"$SKILL_DIR"`:

```bash
UV_PROJECT_ENVIRONMENT="$AUDIBLE_VENV_DIR" \
  uv run --project "$SKILL_DIR" --frozen audible quickstart

UV_PROJECT_ENVIRONMENT="$AUDIBLE_VENV_DIR" \
  uv run --project "$SKILL_DIR" --frozen audible activation-bytes \
  > "$AUDIBLE_AUTHCODE_FILE"
```

Add this line to Runtime Configuration immediately before the path table:

```bash
AUDIBLE_DATA_DIR="${AUDIBLE_DATA_DIR:-$REPO_ROOT/audible_data}"
```

Expected: `SKILL.md` contains no `/path/to/audible` or `../audible` literal.

- [ ] **Step 3: Add generated-style UI metadata**

Create `skills/audible-download-convert/agents/openai.yaml` with:

```yaml
interface:
  display_name: "Audible Download Convert"
  short_description: "Download Audible titles and convert them to M4B"
  default_prompt: "Use $audible-download-convert to download an Audible title by ASIN and convert it to M4B."
```

- [ ] **Step 4: Ignore repository-local Audible data**

Append to `.gitignore`:

```gitignore
audible_data/
```

- [ ] **Step 5: Run runtime contracts and inspect skill metadata**

Run:

```bash
bash tests/test_skill_runtime_contracts.sh
sed -n '1,180p' skills/audible-download-convert/SKILL.md
sed -n '1,80p' skills/audible-download-convert/agents/openai.yaml
```

Expected:

```text
skill runtime contracts: ok
```

The displayed metadata must match the skill name and Audible
download-and-convert purpose.

- [ ] **Step 6: Commit instructions, metadata, and ignore rule**

```bash
git add \
  .gitignore \
  skills/audible-download-convert/SKILL.md \
  skills/audible-download-convert/agents/openai.yaml
git commit -m "docs: add audible skill guidance"
```

### Task 4: Verify the Complete Migration

**Files:**
- Verify all files created or modified in Tasks 1-3.
- Do not modify `../audible`.

- [ ] **Step 1: Run all repository shell tests**

Run:

```bash
for test_file in tests/*.sh; do
  echo "RUN $test_file"
  bash "$test_file"
done
```

Expected:

```text
RUN tests/test_audible_download_convert.sh
PASS
RUN tests/test_skill_runtime_contracts.sh
skill runtime contracts: ok
```

- [ ] **Step 2: Run syntax checks for every tracked shell script**

Run:

```bash
while IFS= read -r script; do
  bash -n "$script"
done < <(git ls-files '*.sh')
```

Expected: command exits 0 with no syntax errors.

- [ ] **Step 3: Verify the frozen project resolves without modifying it**

Run:

```bash
UV_PROJECT_ENVIRONMENT="${AUDIBLE_VENV_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/audible-download-convert/venv}" \
  uv lock --project skills/audible-download-convert --check
```

Expected: exit 0 and confirmation that the lockfile is current, with no
changes to `uv.lock`.

- [ ] **Step 4: Verify source independence and source preservation**

Run:

```bash
rg -n '/path/to/audible|\.\./audible|/Users/' \
  skills/audible-download-convert || true
git -C ../audible status --short
git status --short
```

Expected:

- no source-checkout or user-specific path appears in migrated files;
- `../audible` has no new changes;
- this repository shows only the intended migration changes plus the user's
  pre-existing untracked `notes.md`.

- [ ] **Step 5: Review the complete diff and recent commits**

Run:

```bash
git diff c4cbd90..HEAD --check
git diff c4cbd90..HEAD --stat
git log -4 --oneline
```

Expected:

- `git diff --check` exits 0;
- the stat contains only the migration plan, Audible skill/runtime/tests, the
  shared contract test, and `.gitignore`;
- commits are scoped to tests, runtime, and documentation.
