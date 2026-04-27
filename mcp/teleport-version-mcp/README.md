# teleport-version-mcp

An MCP (Model Context Protocol) server that answers **"which Teleport release first contained this change?"** for commits and PRs in `gravitational/teleport`.

It combines a local blobless bare clone of the Teleport repo (for fast `git tag --contains` lookups) with the GitHub REST API (for PR metadata and backport discovery), and exposes the results as MCP tools over streamable HTTP.

## Tools

All tools filter to **stable release tags only** (`vX.Y.Z`). Pre-releases like `v18.0.0-rc.1` are deliberately excluded. Tags are returned sorted by semver, oldest first.

### `find_earliest_version(commit_hash: str) -> str`
Earliest stable tag containing `commit_hash`. Returns a human-readable string if no release contains it.

### `find_all_versions(commit_hash: str) -> list[str]`
Every stable tag containing `commit_hash`, oldest first.

### `find_earliest_version_for_pr(pr_number: int) -> str`
Looks up the PR's `merge_commit_sha` on GitHub, then returns the earliest stable tag containing it. Useful when you know the PR number but not the commit.

### `find_all_versions_for_pr(pr_number: int) -> list[str] | str`
Same as above but returns every stable tag containing the merge commit.

### `find_versions_for_master_pr(pr_number: int) -> dict[str, str] | str`
For a PR merged to `master`, walks the GitHub timeline to find cross-referenced **merged backport PRs** targeting `branch/vNN`, then reports the earliest stable release per backport branch:

```json
{
  "branch/v18": "v18.1.2",
  "branch/v17": "v17.4.5",
  "branch/v16": "v16.7.9"
}
```

This is the tool to reach for when you want to know "what versions actually shipped this fix?" across all maintained majors.

## Running

### Docker (recommended)

The container performs the initial bare clone on first boot and stores it in a named volume so subsequent restarts are fast.

```sh
docker compose up --build
```

The server listens on `http://0.0.0.0:8000` by default. Override with `PORT`.

### Local development

Requires an existing bare clone at `GIT_DATA_DIR`.

```sh
pip install -r requirements.txt
GIT_DATA_DIR=/path/to/teleport.git python server.py
```

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `GIT_DATA_DIR` | `/data/teleport.git` | Path to the bare clone. |
| `GITHUB_REPO` | `gravitational/teleport` | Repo to clone and query. |
| `HOST` | `0.0.0.0` | Bind host. |
| `PORT` | `8000` | Bind port. |
| `GITHUB_TOKEN` | *(unset)* | Personal access token (fallback auth). |
| `GITHUB_APP_ID` | *(unset)* | GitHub App ID. |
| `GITHUB_APP_INSTALLATION_ID` | *(unset)* | Installation ID for the App. |
| `GITHUB_APP_PRIVATE_KEY_PATH` | *(unset)* | Path (inside the container) to the App's PEM private key. |

### Authentication

Auth is technically optional — the Teleport repo is public — but **strongly recommended** to avoid unauthenticated GitHub rate limits (60 req/hr). Pick one of:

- **GitHub App** (preferred). Set all three `GITHUB_APP_*` vars. Installation tokens are minted on demand via RS256 JWT and refreshed automatically ~60s before expiry.
- **Personal access token**. Set `GITHUB_TOKEN`.

If all three App vars are set, App auth wins over `GITHUB_TOKEN`. At startup the server performs a `GET /repos/{GITHUB_REPO}` to verify credentials and exits if the call fails.

To mount a GitHub App PEM via compose, uncomment the volume line in `compose.yml` and set `GITHUB_APP_PRIVATE_KEY_PATH=/secrets/github-app.pem`.

## How it stays fresh

A background thread runs `git fetch --tags --force` every hour so new release tags show up without restarting the container. The clone itself is blobless (`--filter=blob:none`) — commits and tags are local, but file contents are fetched lazily and aren't needed for any of the tools.

## Connecting a client

The server speaks MCP over streamable HTTP. Point any MCP-aware client at the server's URL (e.g. `http://localhost:8000/mcp`) and the five tools above will be discovered automatically.
