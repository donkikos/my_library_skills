# Storyteller Token Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add automatic, persistent Storyteller token refresh using environment-provided username and password.

**Architecture:** Extend the shared shell authentication helper to select an environment or file token, validate it with a protected endpoint, and refresh once on `401`. Keep operation scripts thin by passing their API base into the helper.

**Tech Stack:** Bash, curl, jq, shell integration tests

---

### Task 1: Authentication Contract Tests

**Files:**
- Create: `tests/test_storyteller_auth.sh`

- [ ] **Step 1: Write failing tests**

Create a fake `curl` that records requests and returns controlled status and
token responses. Cover environment-token precedence, saved-token reuse,
refresh and persistence after `401`, bootstrap without a token, and rejection
of incomplete credentials.

- [ ] **Step 2: Verify tests fail**

Run: `bash tests/test_storyteller_auth.sh`

Expected: FAIL because `resolve_token` does not validate or refresh tokens.

### Task 2: Shared Authentication Helper

**Files:**
- Modify: `skills/storyteller/scripts/_common.sh`
- Modify: `skills/storyteller/scripts/list_books.sh`
- Modify: `skills/storyteller/scripts/upload_epub_m4b.sh`
- Modify: `skills/storyteller/scripts/update_title_series.sh`
- Modify: `skills/storyteller/scripts/queue_alignment.sh`
- Modify: `skills/storyteller/scripts/diagnose_alignment_error.sh`

- [ ] **Step 1: Implement minimal refresh behavior**

Add helpers to request and securely save a token. Change `resolve_token` to
accept the API base, validate selected tokens, refresh once on `401`, and
bootstrap from complete credentials when no token exists.

- [ ] **Step 2: Pass API base from each operation script**

Change each call to:

```bash
TOKEN="$(resolve_token "$TOKEN_FILE" "$API_BASE")"
```

- [ ] **Step 3: Verify focused tests pass**

Run: `bash tests/test_storyteller_auth.sh`

Expected: `storyteller auth: ok`

### Task 3: Documentation and Regression Checks

**Files:**
- Modify: `skills/storyteller/SKILL.md`
- Modify: `skills/storyteller/references/api-workflows.md`
- Modify: `tests/test_skill_runtime_contracts.sh`

- [ ] **Step 1: Update the documented contract**

Document `STORYTELLER_USERNAME_OR_EMAIL`, `STORYTELLER_PASSWORD`, token
precedence, `401` refresh, secure persistence, and incomplete-variable errors.

- [ ] **Step 2: Add documentation contract assertions**

Require both credential variable names and the documented refresh behavior.

- [ ] **Step 3: Run all tests and syntax checks**

Run:

```bash
bash tests/test_storyteller_auth.sh
bash tests/test_skill_runtime_contracts.sh
for file in skills/storyteller/scripts/*.sh tests/*.sh; do bash -n "$file"; done
```

Expected: both test scripts report `ok`; syntax checks produce no output.

- [ ] **Step 4: Review the diff**

Run: `git diff --check && git diff --stat && git status --short`

Expected: no whitespace errors; only planned files plus the user's existing
untracked files appear.
