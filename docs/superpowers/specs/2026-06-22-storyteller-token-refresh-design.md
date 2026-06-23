# Storyteller Token Refresh Design

## Goal

Allow Storyteller scripts to recover from a missing or stale saved bearer token
when `STORYTELLER_USERNAME_OR_EMAIL` and `STORYTELLER_PASSWORD` are available.

## Authentication Flow

1. Prefer `STORYTELLER_TOKEN`, then the configured token file.
2. Validate the selected token against a protected Storyteller endpoint.
3. On HTTP `401`, request one replacement token from `/api/v2/token`.
4. Save the replacement to
   `${STORYTELLER_TOKEN_FILE:-$HOME/.config/storyteller-skill/.storyteller_token}`
   and continue with it.
5. If no token exists, use complete credentials to create and save one.
6. Fail clearly when credentials are incomplete or refresh fails.

Token directories use mode `700`; token files use mode `600`. Passwords are
sent through standard input to `curl`, not command-line arguments.

## Scope

Centralize this behavior in `scripts/_common.sh`. Existing operation scripts
continue resolving one bearer token before making their API calls. Update the
skill and API workflow reference to document variables, precedence, refresh,
and persistence.

## Testing

Use a fake `curl` executable to verify precedence, successful `401` refresh,
secure persistence, missing-token bootstrap, and incomplete-credential errors
without contacting a Storyteller server.
