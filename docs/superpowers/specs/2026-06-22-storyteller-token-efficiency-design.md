# Storyteller Token-Efficiency Design

## Goal

Reduce the combined Storyteller skill documentation by roughly 45–55% without
removing operationally important behavior.

## Structure

- Keep `SKILL.md` as a compact operational router of about 250–300 words.
- Keep `references/api-workflows.md` as the detailed endpoint reference at
  about 350–400 words.
- Shorten frontmatter description to triggering conditions only.

## Keep in `SKILL.md`

- Runtime defaults and authentication precedence.
- Bundled script names and the normal workflow.
- Processing-state safety rules.
- High-value diagnosis guidance for `401`, active transcription, and `ENOENT`.
- A pointer to the API reference for endpoint details and raw commands.

## Keep in the Reference

- Authentication variables and manual bootstrap command.
- Endpoint map for listing, upload, metadata, processing, and status.
- Required TUS metadata and request details.
- Diagnostic command options and recovery sequence.

## Remove or Consolidate

- Repeated endpoint descriptions already present in the reference.
- Explanations already enforced by bundled scripts.
- Duplicate token-refresh, network-error, and processing-state guidance.
- Low-value implementation detail that does not affect agent decisions.

## Verification

- Preserve runtime-contract assertions for required variables and behavior.
- Add word-count limits for both documentation files.
- Run existing authentication and runtime-contract tests.
- Confirm shell behavior and public interfaces are unchanged.
