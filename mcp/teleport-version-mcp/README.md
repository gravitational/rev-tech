# teleport-version-mcp

An MCP (Model Context Protocol) server that answers **"which Teleport release first contained this change?"** for commits and PRs in either `gravitational/teleport` (OSS) or `gravitational/teleport.e` (the enterprise submodule).

It maintains local blobless bare clones of both repos (for fast `git tag --contains` and submodule-walk lookups), uses the GitHub REST API for PR metadata and backport discovery, and exposes the results as MCP tools over streamable HTTP.

## How `teleport.e` is handled

`teleport.e` is private and does not carry release tags of its own — it ships as a git submodule (mounted at `e/`) inside `teleport`. To answer "what release contains this enterprise change?" the server runs the algorithm below for any `teleport.e` commit (or PR resolved to its merge commit):

1. Find which release branches in `teleport.e` (`master`, `branch/vN`) contain the target commit.
2. For each, walk the corresponding OSS branch's history of commits that touched the `e/` submodule pointer, looking for the first commit whose pointer is the target commit or a descendant of it. That OSS commit is when the bump landed.
3. Run `git tag --contains` against that OSS commit to find the earliest stable release that shipped it.

The result is a per-branch dict, e.g. `{"branch/v18": "v18.1.2", "master": null}` — `null` meaning landed on OSS but not yet tagged.

## Tools

All tools filter to **stable release tags only** (`vX.Y.Z`). Pre-releases like `v18.0.0-rc.1` are deliberately excluded. OSS tags are sorted by semver, oldest first.

Each tool that takes a `repo` parameter accepts `"teleport"` or `"teleport.e"`. PR-based tools default to `"teleport"`. Commit-based tools auto-detect the repo by checking which local clone contains the SHA, so a bare commit hash works without specifying `repo`.

### `find_earliest_version(commit_hash: str, repo: str | None = None) -> str`
Earliest stable tag containing the given commit. For `teleport.e`, this is the earliest tag across all branches that have shipped the submodule bump. If `repo` is omitted, the server detects which repo the commit lives in.

### `find_all_versions(commit_hash: str, repo: str | None = None) -> list[str] | dict[str, str | None]`
- `repo="teleport"`: list of every stable OSS tag containing the commit, oldest first.
- `repo="teleport.e"`: dict mapping each OSS branch line to the earliest tag on that branch that includes the bump, or `null` if the bump has landed but no release has been tagged yet.

### `find_earliest_version_for_pr(pr_number: int, repo: str = "teleport") -> str`
Looks up the PR's `merge_commit_sha` on GitHub, then resolves it the same way as `find_earliest_version`. Useful when somebody pastes a URL like `https://github.com/gravitational/teleport.e/pull/8251`.

### `find_all_versions_for_pr(pr_number: int, repo: str = "teleport") -> list[str] | dict[str, str | None]`
Same shape as `find_all_versions`, keyed off a PR number instead of a commit.

### `find_versions_for_master_pr(pr_number: int) -> dict[str, str]`
**OSS-only.** Walks the GitHub timeline of the given master-branch PR to find cross-referenced merged backport PRs targeting `branch/vNN`, then reports the earliest stable release per backport branch:

```json
{
  "branch/v18": "v18.1.2",
  "branch/v17": "v17.4.5",
  "branch/v16": "v16.7.9"
}
```

For `teleport.e`, you don't need this tool — `find_all_versions_for_pr(..., repo="teleport.e")` already returns one entry per branch line via the submodule walk.

## Running

### Docker (recommended)

The container performs the initial bare clones on first boot and stores them in a named volume, so restarts are fast.

```sh
docker compose up --build
```

The server listens on `http://0.0.0.0:8000` by default. Override with `PORT`.

### Local development

Requires existing bare clones at `GIT_DATA_DIR` and `GIT_DATA_DIR_E`.

```sh
pip install -r requirements.txt
GIT_DATA_DIR=/path/to/teleport.git \
GIT_DATA_DIR_E=/path/to/teleport.e.git \
python server.py
```

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `GIT_DATA_DIR` | `/data/teleport.git` | Path to the OSS bare clone. |
| `GIT_DATA_DIR_E` | `/data/teleport.e.git` | Path to the enterprise bare clone. |
| `GITHUB_REPO` | `gravitational/teleport` | OSS repo to clone and query. |
| `GITHUB_REPO_E` | `gravitational/teleport.e` | Enterprise repo to clone and query. |
| `HOST` | `0.0.0.0` | Bind host. |
| `PORT` | `8000` | Bind port. |
| `GITHUB_TOKEN` | *(unset)* | Personal access token (fallback auth). |
| `GITHUB_APP_ID` | *(unset)* | GitHub App ID. |
| `GITHUB_APP_INSTALLATION_ID` | *(unset)* | Installation ID for the App. |
| `GITHUB_APP_PRIVATE_KEY_PATH` | *(unset)* | Path (inside the container) to the App's PEM private key. |
| `GIT_SSH_KEY_PATH` | *(unset)* | Path (inside the container) to an SSH private key. When set, teleport.e is cloned via SSH instead of HTTPS, and GitHub API access for teleport.e is disabled. See "SSH-only mode for teleport.e" below. |

### Authentication

`teleport.e` is private, so authentication is required to clone it and to look up its PRs. Pick one of:

- **GitHub App** (preferred). Set all three `GITHUB_APP_*` vars. The App must have **read access** to both `GITHUB_REPO` and `GITHUB_REPO_E` — typically an org-level install on `gravitational/*` covers this. Installation tokens are minted on demand via RS256 JWT and refreshed automatically ~60s before expiry.
- **Personal access token**. Set `GITHUB_TOKEN`. The token must have read access to both repos.

If all three App vars are set, App auth wins over `GITHUB_TOKEN`. At startup the server performs a `GET /repos/{repo}` against each configured repo to verify credentials and exits if any call fails.

Required GitHub App permissions:

- **Repository → Contents: Read** (clone + fetch)
- **Repository → Metadata: Read** (auto-granted; covers credential verification)
- **Repository → Pull requests: Read** (PR lookups)
- **Repository → Issues: Read** (timeline traversal for `find_versions_for_master_pr`)

To mount a GitHub App PEM via compose, uncomment the volume line in `compose.yml` and set `GITHUB_APP_PRIVATE_KEY_PATH=/secrets/github-app.pem`.

### SSH-only mode for teleport.e

If your GitHub App doesn't have access to `gravitational/teleport.e` (e.g. company policy prevents granting it), you can fall back to cloning teleport.e via SSH using a deploy key or user SSH key with read access:

1. Place the SSH private key on the host (e.g. `/home/ubuntu/.credentials/teleport-version-mcp/teleport-e.key`).
2. Mount it into the container at `/secrets/teleport-e.key:ro` (uncomment the line in `compose.yml`).
3. Set `GIT_SSH_KEY_PATH=/secrets/teleport-e.key` in the environment.

In SSH-only mode the server:

- Clones and fetches teleport.e via `git@github.com:...` using the configured key.
- Skips the startup credential check for teleport.e.
- Returns a clear error from `find_earliest_version_for_pr(..., repo="teleport.e")` and `find_all_versions_for_pr(..., repo="teleport.e")` since PR → merge-commit lookups require GitHub API access. Commit-based tools (`find_earliest_version`, `find_all_versions`) work fully against the local clone.

The container copies the mounted key to a private path with `0600` permissions at startup so OpenSSH's strict-modes check doesn't reject it. Host-key verification uses `accept-new` against `/tmp/known_hosts` — github.com's key is recorded on first connection.

## How it stays fresh

A background thread runs `git fetch --tags --force` against both clones every hour, so new tags and submodule-bump commits show up without restarting the container. The clones are blobless (`--filter=blob:none`) — commits and trees are local, but file blobs are fetched lazily and aren't needed for any of the tools.

## Connecting a client

The server speaks MCP over streamable HTTP. Point any MCP-aware client at the server's URL (e.g. `http://localhost:8000/mcp`) and the tools above will be discovered automatically. Sessions are stateless, so server restarts don't strand client connections.
