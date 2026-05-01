import base64
import logging
import os
import re
import subprocess
import threading
import time
from datetime import datetime
from pathlib import Path

import jwt
import requests
import uvicorn
from mcp.server.fastmcp import FastMCP
from mcp.server.fastmcp.server import TransportSecuritySettings

from packaging.version import InvalidVersion, Version

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

GIT_DATA_DIR = os.environ.get("GIT_DATA_DIR", "/data/teleport.git")
GITHUB_REPO = os.environ.get("GITHUB_REPO", "gravitational/teleport")
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
GITHUB_APP_ID = os.environ.get("GITHUB_APP_ID", "")
GITHUB_APP_INSTALLATION_ID = os.environ.get("GITHUB_APP_INSTALLATION_ID", "")
GITHUB_APP_PRIVATE_KEY_PATH = os.environ.get("GITHUB_APP_PRIVATE_KEY_PATH", "")

_USING_GITHUB_APP = bool(GITHUB_APP_ID and GITHUB_APP_INSTALLATION_ID and GITHUB_APP_PRIVATE_KEY_PATH)

mcp = FastMCP(
    "teleport-version-finder",
    stateless_http=True,
    transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
)

_STABLE_TAG_RE = re.compile(r"^v\d+\.\d+\.\d+$")

_token_lock = threading.Lock()
_cached_token: tuple[str, float] | None = None


def _mint_app_jwt() -> str:
    private_key = Path(GITHUB_APP_PRIVATE_KEY_PATH).read_text()
    now = int(time.time())
    payload = {"iat": now - 60, "exp": now + 540, "iss": GITHUB_APP_ID}
    return jwt.encode(payload, private_key, algorithm="RS256")


def _fetch_installation_token() -> tuple[str, float]:
    app_jwt = _mint_app_jwt()
    url = f"https://api.github.com/app/installations/{GITHUB_APP_INSTALLATION_ID}/access_tokens"
    resp = requests.post(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {app_jwt}",
        },
        timeout=10,
    )
    resp.raise_for_status()
    data = resp.json()
    expires_at = datetime.fromisoformat(data["expires_at"].replace("Z", "+00:00"))
    return data["token"], expires_at.timestamp()


def _get_auth_token() -> str:
    """Return a GitHub bearer token, refreshing App installation tokens as needed. May be empty."""
    global _cached_token
    if _USING_GITHUB_APP:
        with _token_lock:
            if _cached_token and _cached_token[1] - time.time() > 60:
                return _cached_token[0]
            token, exp = _fetch_installation_token()
            _cached_token = (token, exp)
            logger.info("minted GitHub App installation token (expires %s)", datetime.fromtimestamp(exp).isoformat())
            return token
    return GITHUB_TOKEN


def _git_auth_config() -> list[str]:
    """git -c args injecting current auth as HTTP Basic for github.com HTTPS."""
    token = _get_auth_token()
    if not token:
        return []
    creds = base64.b64encode(f"x-access-token:{token}".encode()).decode()
    return ["-c", f"http.extraHeader=Authorization: Basic {creds}"]


def _git(*args: str, auth: bool = False) -> str:
    cmd = ["git"]
    if auth:
        cmd.extend(_git_auth_config())
    cmd.extend(["--git-dir", GIT_DATA_DIR, *args])
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return result.stdout.strip()


def _verify_credentials() -> None:
    """Sanity-check that configured auth can reach GITHUB_REPO; raise SystemExit on failure.
    No-op if running unauthenticated."""
    if not _USING_GITHUB_APP and not GITHUB_TOKEN:
        return
    try:
        headers = _gh_headers()
    except Exception as exc:
        raise SystemExit(f"failed to mint GitHub credentials: {exc}")
    url = f"https://api.github.com/repos/{GITHUB_REPO}"
    try:
        resp = requests.get(url, headers=headers, timeout=10)
    except requests.RequestException as exc:
        raise SystemExit(f"failed to reach GitHub API to verify credentials: {exc}")
    if resp.status_code != 200:
        raise SystemExit(
            f"GitHub credentials rejected: GET /repos/{GITHUB_REPO} returned "
            f"{resp.status_code}: {resp.text[:200]}"
        )
    logger.info("GitHub credentials verified (can access %s)", GITHUB_REPO)


def _ensure_clone() -> None:
    if os.path.isdir(GIT_DATA_DIR):
        return
    logger.info("performing initial blobless clone (this may take a minute)...")
    cmd = ["git", *_git_auth_config(), "clone", "--bare", "--filter=blob:none",
           f"https://github.com/{GITHUB_REPO}.git", GIT_DATA_DIR]
    subprocess.run(cmd, check=True)
    logger.info("clone complete")


def _fetch() -> None:
    logger.info("fetching tags")
    try:
        _git("fetch", "--tags", "--force", auth=True)
        logger.info("fetch complete")
    except subprocess.CalledProcessError as exc:
        logger.error("fetch failed: %s", exc.stderr.strip())


def _start_fetch_scheduler() -> None:
    def loop() -> None:
        while True:
            time.sleep(3600)
            _fetch()

    threading.Thread(target=loop, daemon=True).start()


def _semver_key(tag: str) -> Version:
    try:
        return Version(tag.lstrip("v"))
    except InvalidVersion:
        return Version("0.0.0")


def _tags_containing(commit_hash: str) -> list[str]:
    try:
        raw = _git("tag", "--contains", commit_hash)
    except subprocess.CalledProcessError:
        return []
    tags = [t for t in (line.strip() for line in raw.splitlines()) if _STABLE_TAG_RE.match(t)]
    return sorted(tags, key=_semver_key)


_BACKPORT_BRANCH_RE = re.compile(r"^branch/v\d+")


def _gh_headers() -> dict[str, str]:
    headers = {"Accept": "application/vnd.github+json"}
    token = _get_auth_token()
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def _get_pr(pr_number: int) -> dict:
    """Fetch PR metadata from GitHub, or raise ValueError."""
    url = f"https://api.github.com/repos/{GITHUB_REPO}/pulls/{pr_number}"
    resp = requests.get(url, headers=_gh_headers(), timeout=10)
    if resp.status_code == 404:
        raise ValueError(f"PR #{pr_number} not found in {GITHUB_REPO}.")
    resp.raise_for_status()
    return resp.json()


def _pr_merge_commit(pr_number: int) -> str:
    """Return the merge commit SHA for a GitHub PR, or raise ValueError."""
    data = _get_pr(pr_number)
    sha = data.get("merge_commit_sha")
    if not sha:
        state = data.get("state", "unknown")
        raise ValueError(f"PR #{pr_number} has no merge commit (state: {state}).")
    return sha


def _find_backport_prs(pr_number: int) -> list[tuple[str, str]]:
    """Return (base_branch, merge_commit_sha) for merged backport PRs that cross-reference pr_number."""
    # Page through the timeline to collect cross-referenced merged PR numbers.
    candidate_pr_numbers: set[int] = set()
    page = 1
    while True:
        url = f"https://api.github.com/repos/{GITHUB_REPO}/issues/{pr_number}/timeline"
        resp = requests.get(url, headers=_gh_headers(), params={"per_page": 100, "page": page}, timeout=10)
        resp.raise_for_status()
        events = resp.json()
        if not events:
            break
        for event in events:
            if event.get("event") != "cross-referenced":
                continue
            source = event.get("source", {})
            issue = source.get("issue", {})
            pr_info = issue.get("pull_request")
            if pr_info and pr_info.get("merged_at"):
                candidate_pr_numbers.add(issue["number"])
        if len(events) < 100:
            break
        page += 1

    # Fetch each candidate and keep those targeting a backport branch.
    results: list[tuple[str, str]] = []
    for num in sorted(candidate_pr_numbers):
        try:
            data = _get_pr(num)
        except (ValueError, requests.HTTPError):
            continue
        base_ref = data.get("base", {}).get("ref", "")
        if not _BACKPORT_BRANCH_RE.match(base_ref):
            continue
        sha = data.get("merge_commit_sha")
        if sha:
            results.append((base_ref, sha))
    return results


@mcp.tool()
def find_earliest_version(commit_hash: str) -> str:
    """Return the earliest stable Teleport release tag containing the given commit hash."""
    tags = _tags_containing(commit_hash)
    if not tags:
        return f"No stable release found containing commit {commit_hash!r}."
    return tags[0]


@mcp.tool()
def find_all_versions(commit_hash: str) -> list[str]:
    """Return all stable Teleport release tags containing the given commit hash, oldest first."""
    return _tags_containing(commit_hash)


@mcp.tool()
def find_earliest_version_for_pr(pr_number: int) -> str:
    """Return the earliest stable Teleport release tag containing the merge commit of the given GitHub PR number."""
    try:
        sha = _pr_merge_commit(pr_number)
    except ValueError as exc:
        return str(exc)
    tags = _tags_containing(sha)
    if not tags:
        return f"No stable release found containing PR #{pr_number} (merge commit {sha!r})."
    return tags[0]


@mcp.tool()
def find_all_versions_for_pr(pr_number: int) -> list[str] | str:
    """Return all stable Teleport release tags containing the merge commit of the given GitHub PR number, oldest first."""
    try:
        sha = _pr_merge_commit(pr_number)
    except ValueError as exc:
        return str(exc)
    return _tags_containing(sha)


@mcp.tool()
def find_versions_for_master_pr(pr_number: int) -> dict[str, str] | str:
    """Given a master-branch PR number, find all merged backport PRs and return the earliest
    stable release tag per backport branch. Returns a dict like {"branch/v18": "v18.1.2"}."""
    try:
        backports = _find_backport_prs(pr_number)
    except (requests.HTTPError, requests.ConnectionError) as exc:
        return f"Failed to look up backports for PR #{pr_number}: {exc}"
    if not backports:
        return f"No merged backport PRs found for PR #{pr_number}."
    results: dict[str, str] = {}
    for base_ref, sha in backports:
        tags = _tags_containing(sha)
        results[base_ref] = tags[0] if tags else f"(merge commit {sha[:12]} not yet in a stable release)"
    return results


if __name__ == "__main__":
    if _USING_GITHUB_APP:
        logger.info("using GitHub App auth (app_id=%s, installation_id=%s)", GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID)
        if not Path(GITHUB_APP_PRIVATE_KEY_PATH).is_file():
            raise SystemExit(f"GITHUB_APP_PRIVATE_KEY_PATH {GITHUB_APP_PRIVATE_KEY_PATH!r} does not exist")
    elif GITHUB_TOKEN:
        logger.info("using GITHUB_TOKEN auth")
    else:
        logger.warning("no GitHub auth configured; subject to unauthenticated rate limits")
    _verify_credentials()
    _ensure_clone()
    _start_fetch_scheduler()
    uvicorn.run(
        mcp.streamable_http_app(),
        host=os.environ.get("HOST", "0.0.0.0"),
        port=int(os.environ.get("PORT", "8000")),
    )
