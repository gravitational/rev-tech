# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

An MCP (Model Context Protocol) server exposing tools that answer "which Teleport release first contained this change?" Answers are derived from a local bare clone of `gravitational/teleport` plus the GitHub REST API for PR metadata.

## Running

The server is designed to run in Docker — the container handles the initial bare clone on first boot.

```
# Build + run with persistent git volume
docker compose up --build

# Local dev (requires an existing bare clone at $GIT_DATA_DIR)
pip install -r requirements.txt
GIT_DATA_DIR=/path/to/teleport.git python server.py
```

Key env vars: `GIT_DATA_DIR` (bare clone path, default `/data/teleport.git`), `GITHUB_REPO` (default `gravitational/teleport`), `HOST`, `PORT`. Auth is optional (public repo) but strongly recommended to avoid rate limits — pick one of:

- **GitHub App** (preferred): set `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, and `GITHUB_APP_PRIVATE_KEY_PATH` (path to the PEM inside the container).
- **Personal access token**: set `GITHUB_TOKEN`.

If all three App vars are set, App auth wins over `GITHUB_TOKEN`.

There are no tests, lints, or build scripts beyond `docker compose build`.

## Architecture

**Single-file server** (`server.py`) built on `FastMCP` (from `mcp[cli]`), served over streamable HTTP by `uvicorn`. All five tools are decorated with `@mcp.tool()` and share two core primitives:

- `_git(*args, auth=False)` shells out to `git --git-dir $GIT_DATA_DIR ...`. The repo is a **blobless bare clone** (`--filter=blob:none`) — commits and tags are local, but blob content is fetched lazily. Avoid tool logic that needs file contents. When `auth=True`, current credentials are injected via `-c http.extraHeader=Authorization: Basic ...` (x-access-token:<token>) so GitHub App installation tokens can be refreshed without re-cloning.
- `_tags_containing(sha)` runs `git tag --contains <sha>`, filters to stable tags matching `^v\d+\.\d+\.\d+$` (pre-releases like `v18.0.0-rc.1` are deliberately excluded), and sorts by `packaging.version.Version` so `v10` < `v11` lexical-vs-semver bugs don't creep in.

**Auth**: `_get_auth_token()` returns a bearer token for both API calls (`_gh_headers`) and git over HTTPS (`_git_auth_config`). If GitHub App env vars are set, it mints a short JWT (RS256, `iss`=App ID) and exchanges it at `/app/installations/{id}/access_tokens` for a 1-hour installation token, cached under `_token_lock` and refreshed 60s before expiry. Otherwise it falls back to `GITHUB_TOKEN`, or runs unauthenticated if neither is set. Tokens are never baked into the git remote URL — the clone uses an unauthenticated URL and each operation re-reads the current token. At startup, `_verify_credentials()` does a `GET /repos/{GITHUB_REPO}` with whatever auth is configured and exits with failure if the call is non-2xx (this is skipped entirely in unauthenticated mode).

**Fetch scheduler**: a daemon thread (`_start_fetch_scheduler`) runs `git fetch --tags --force` every hour to keep tags fresh. The first fetch does not happen at startup — `_ensure_clone()` in `__main__` primes the data, and the loop sleeps *before* the first fetch.

**PR → commit resolution** (`_pr_merge_commit`) reads `merge_commit_sha` from the GitHub PR API. This is the sha of the merge commit on the target branch, which is what `git tag --contains` needs.

**Backport discovery** (`_find_backport_prs`) is the non-obvious piece. Teleport uses backport branches named `branch/vNN` (regex `_BACKPORT_BRANCH_RE`). To map a master PR to its releases:

1. Page through `/issues/{pr}/timeline` collecting `cross-referenced` events pointing at *merged* PRs.
2. Fetch each candidate PR, keep only those whose `base.ref` matches `branch/vNN`.
3. Return `(base_branch, merge_commit_sha)` pairs — the caller (`find_versions_for_master_pr`) then runs `_tags_containing` per pair and returns `{"branch/v18": "v18.1.2", ...}`.

This cross-reference traversal is how the server answers "what version shipped this master PR?" across all maintained majors, rather than only the one where it was originally merged.

## Conventions to preserve

- Stable-tag regex `_STABLE_TAG_RE` intentionally rejects pre-release suffixes. Relaxing it changes the meaning of every tool's output.
- Tools must degrade to a human-readable string (not raise) on "not found" / GitHub errors — the return type unions like `list[str] | str` reflect this and MCP clients surface them directly to the user.
- `transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False)` is required because the server is typically fronted by a reverse proxy / called by MCP clients with arbitrary `Host` headers.
