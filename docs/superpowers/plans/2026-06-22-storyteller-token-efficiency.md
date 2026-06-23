# Storyteller Token-Efficiency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compress the Storyteller skill and API reference by 45–55% while preserving required operational guidance.

**Architecture:** Treat `SKILL.md` as the compact decision and workflow entrypoint, and `references/api-workflows.md` as the endpoint reference. Protect required content and word-count ceilings with the existing shell contract test.

**Tech Stack:** Markdown, Bash contract tests

---

### Task 1: Add Documentation Size Contracts

**Files:**
- Modify: `tests/test_skill_runtime_contracts.sh`

- [ ] **Step 1: Add failing word-count assertions**

Add:

```bash
assert_max_words() {
  local file="$1"
  local maximum="$2"
  local actual
  actual="$(wc -w < "$file" | tr -d ' ')"

  [ "$actual" -le "$maximum" ] ||
    fail "$file has $actual words; maximum is $maximum"
}
```

Then assert:

```bash
assert_max_words "$STORYTELLER_SKILL" 300
assert_max_words "$STORYTELLER_WORKFLOWS" 400
```

- [ ] **Step 2: Verify the test fails for size**

Run:

```bash
bash tests/test_skill_runtime_contracts.sh
```

Expected: FAIL because the current files contain about 638 and 598 words.

### Task 2: Compress the Main Skill

**Files:**
- Modify: `skills/storyteller/SKILL.md`

- [ ] **Step 1: Rewrite the frontmatter trigger**

Use a concise trigger-only description:

```yaml
description: Use when managing books, metadata, uploads, or alignment on a local Storyteller server.
```

- [ ] **Step 2: Reduce the body to operational decisions**

Retain only:

- API and token-file defaults.
- Authentication precedence and `401` refresh behavior.
- Bundled script list.
- Normal workflow.
- Processing-state safety.
- Diagnosis for authentication, active transcription, and transcription-path drift.
- Reference pointer.

Remove endpoint response details, duplicated request paths, and behavior already
explained by the reference or script names.

- [ ] **Step 3: Check the main skill word count**

Run:

```bash
wc -w skills/storyteller/SKILL.md
```

Expected: no more than 300 words.

### Task 3: Compress the API Reference

**Files:**
- Modify: `skills/storyteller/references/api-workflows.md`

- [ ] **Step 1: Consolidate authentication guidance**

Keep one compact section covering:

- `STORYTELLER_API_BASE`
- `STORYTELLER_TOKEN`
- `STORYTELLER_TOKEN_FILE`
- `STORYTELLER_USERNAME_OR_EMAIL`
- `STORYTELLER_PASSWORD`
- Clipboard bootstrap
- Persistent refresh after `401`

- [ ] **Step 2: Replace prose with an endpoint map**

Use concise bullets for:

```text
GET /api/v2/books
POST /api/v2/books/upload
PUT /api/v2/books/{bookId}
POST|DELETE /api/v2/books/{bookId}/process
GET /api/v2/books/{bookId}
GET /api/v2/books/events
```

Retain required TUS headers and metadata keys, diagnosis options, and the
cancel-edit-restart recovery sequence.

- [ ] **Step 3: Check the reference word count**

Run:

```bash
wc -w skills/storyteller/references/api-workflows.md
```

Expected: no more than 400 words.

### Task 4: Update Exact-Text Contracts

**Files:**
- Modify: `tests/test_skill_runtime_contracts.sh`

- [ ] **Step 1: Replace brittle prose assertions**

Keep assertions for required variables, default expansions, secure token
persistence, `401`, network distinction, and endpoint commands. Change exact
phrases only where compression makes the old wording obsolete.

- [ ] **Step 2: Run focused documentation tests**

Run:

```bash
bash tests/test_skill_runtime_contracts.sh
```

Expected: `skill runtime contracts: ok`.

### Task 5: Full Verification

**Files:**
- Verify only

- [ ] **Step 1: Run all relevant tests**

Run:

```bash
bash tests/test_storyteller_auth.sh
bash tests/test_skill_runtime_contracts.sh
for file in skills/storyteller/scripts/*.sh tests/*.sh; do bash -n "$file"; done
```

Expected: both test scripts report `ok`; syntax checks produce no output.

- [ ] **Step 2: Confirm reduction and scope**

Run:

```bash
wc -w skills/storyteller/SKILL.md skills/storyteller/references/api-workflows.md
git diff --check
git diff --stat
git status --short
```

Expected: each file is within its ceiling, no whitespace errors, no script
behavior changes, and the existing untracked `notes.md` remains untouched.

- [ ] **Step 3: Review preserved guidance**

Confirm the final docs still cover authentication precedence, persistent
refresh, script selection, upload workflow, processing safety, diagnosis, and
recovery.
