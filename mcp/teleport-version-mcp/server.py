import base64
import logging
import os
import re
import shutil
import subprocess
import threading
import time
from dataclasses import dataclass
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
GIT_DATA_DIR_E = os.environ.get("GIT_DATA_DIR_E", "/data/teleport.e.git")
GITHUB_REPO = os.environ.get("GITHUB_REPO", "gravitational/teleport")
GITHUB_REPO_E = os.environ.get("GITHUB_REPO_E", "gravitational/teleport.e")
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
GITHUB_APP_ID = os.environ.get("GITHUB_APP_ID", "")
GITHUB_APP_INSTALLATION_ID = os.environ.get("GITHUB_APP_INSTALLATION_ID", "")
GITHUB_APP_PRIVATE_KEY_PATH = os.environ.get("GITHUB_APP_PRIVATE_KEY_PATH", "")
GIT_SSH_KEY_PATH = os.environ.get("GIT_SSH_KEY_PATH", "")

_USING_GITHUB_APP = bool(GITHUB_APP_ID and GITHUB_APP_INSTALLATION_ID and GITHUB_APP_PRIVATE_KEY_PATH)
_E_VIA_SSH = bool(GIT_SSH_KEY_PATH)

_SSH_KNOWN_HOSTS = "/tmp/known_hosts"


@dataclass(frozen=True)
class _RepoConfig:
    name: str
    git_dir: str
    github_repo: str
    clone_url: str
    use_https_auth: bool
    api_accessible: bool


def _build_repos() -> dict[str, _RepoConfig]:
    teleport = _RepoConfig(
        name="teleport",
        git_dir=GIT_DATA_DIR,
        github_repo=GITHUB_REPO,
        clone_url=f"https://github.com/{GITHUB_REPO}.git",
        use_https_auth=True,
        api_accessible=True,
    )
    if _E_VIA_SSH:
        teleport_e = _RepoConfig(
            name="teleport.e",
            git_dir=GIT_DATA_DIR_E,
            github_repo=GITHUB_REPO_E,
            clone_url=f"git@github.com:{GITHUB_REPO_E}.git",
            use_https_auth=False,
            api_accessible=False,
        )
    else:
        teleport_e = _RepoConfig(
            name="teleport.e",
            git_dir=GIT_DATA_DIR_E,
            github_repo=GITHUB_REPO_E,
            clone_url=f"https://github.com/{GITHUB_REPO_E}.git",
            use_https_auth=True,
            api_accessible=True,
        )
    return {"teleport": teleport, "teleport.e": teleport_e}


_REPOS = _build_repos()

mcp = FastMCP(
    "teleport-version-finder",
    stateless_http=True,
    transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
)

_STABLE_TAG_RE = re.compile(r"^v\d+\.\d+\.\d+$")
_BACKPORT_BRANCH_RE = re.compile(r"^branch/v\d+")
_E_TRACKED_BRANCH_RE = re.compile(r"^(branch/v\d+|master|main)$")

_token_lock = threading.Lock()
_cached_token: tuple[str, float] | None = None


def _setup_ssh_key() -> None:
    """Copy the mounted SSH key to a 0600 file under /tmp.

    OpenSSH refuses private keys whose mode allows group/other read, but
    Docker's read-only volume mounts typically expose them as world-readable.
    Re-staging the key with the right perms sidesteps the check."""
    global GIT_SSH_KEY_PATH
    if not GIT_SSH_KEY_PATH:
        return
    src = Path(GIT_SSH_KEY_PATH)
    if not src.is_file():
        raise SystemExit(f"GIT_SSH_KEY_PATH {GIT_SSH_KEY_PATH!r} does not exist")
    dst = Path("/tmp/git-ssh-key")
    shutil.copyfile(src, dst)
    dst.chmod(0o600)
    GIT_SSH_KEY_PATH = str(dst)
    logger.info("staged SSH key for git operations at %s", GIT_SSH_KEY_PATH)


def _git_env() -> dict[str, str]:
    """Environment for `git` invocations. Adds GIT_SSH_COMMAND if an SSH key is configured."""
    env = dict(os.environ)
    if GIT_SSH_KEY_PATH:
        env["GIT_SSH_COMMAND"] = (
            f"ssh -i {GIT_SSH_KEY_PATH} -F /dev/null "
            f"-o UserKnownHostsFile={_SSH_KNOWN_HOSTS} "
            "-o StrictHostKeyChecking=accept-new "
            "-o IdentitiesOnly=yes"
        )
    return env


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


def _git(git_dir: str, *args: str, auth: bool = False) -> str:
    cmd = ["git"]
    if auth:
        cmd.extend(_git_auth_config())
    cmd.extend(["--git-dir", git_dir, *args])
    result = subprocess.run(cmd, capture_output=True, text=True, check=True, env=_git_env())
    return result.stdout.strip()


def _gh_headers() -> dict[str, str]:
    headers = {"Accept": "application/vnd.github+json"}
    token = _get_auth_token()
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def _resolve_repo(repo: str) -> _RepoConfig:
    if repo not in _REPOS:
        raise ValueError(f"Unknown repo {repo!r}; must be one of {sorted(_REPOS)}.")
    return _REPOS[repo]


def _api_unavailable_error(repo: str) -> str:
    return (
        f"GitHub API access to {repo} is not available in this configuration "
        f"(SSH-only mode). Look up the PR's merge commit SHA in GitHub and call "
        f"the commit-based tool with repo='{repo}' instead."
    )


def _detect_repo_for_commit(commit_hash: str) -> str | None:
    """Return the repo name whose clone contains commit_hash, or None if no clone contains it.
    If multiple clones contain it (extremely unlikely with full SHAs), prefer 'teleport'."""
    matches: list[str] = []
    for cfg in _REPOS.values():
        cmd = ["git", "--git-dir", cfg.git_dir, "cat-file", "-e", f"{commit_hash}^{{commit}}"]
        if subprocess.run(cmd, capture_output=True, text=True, env=_git_env()).returncode == 0:
            matches.append(cfg.name)
    if not matches:
        return None
    if "teleport" in matches:
        return "teleport"
    return matches[0]


def _verify_credentials() -> None:
    """Sanity-check that configured auth can reach every API-accessible repo; raise SystemExit on failure.
    No-op if running unauthenticated."""
    if not _USING_GITHUB_APP and not GITHUB_TOKEN:
        return
    try:
        headers = _gh_headers()
    except Exception as exc:
        raise SystemExit(f"failed to mint GitHub credentials: {exc}")
    for cfg in _REPOS.values():
        if not cfg.api_accessible:
            logger.info("skipping API credential check for %s (SSH-only mode)", cfg.name)
            continue
        url = f"https://api.github.com/repos/{cfg.github_repo}"
        try:
            resp = requests.get(url, headers=headers, timeout=10)
        except requests.RequestException as exc:
            raise SystemExit(f"failed to reach GitHub API to verify credentials for {cfg.github_repo}: {exc}")
        if resp.status_code != 200:
            raise SystemExit(
                f"GitHub credentials rejected for {cfg.github_repo}: GET /repos/{cfg.github_repo} returned "
                f"{resp.status_code}: {resp.text[:200]}"
            )
        logger.info("GitHub credentials verified (can access %s)", cfg.github_repo)


def _ensure_clone(cfg: _RepoConfig) -> None:
    if os.path.isdir(cfg.git_dir):
        return
    logger.info("performing initial blobless clone of %s ...", cfg.name)
    cmd = ["git"]
    if cfg.use_https_auth:
        cmd.extend(_git_auth_config())
    cmd.extend(["clone", "--bare", "--filter=blob:none", cfg.clone_url, cfg.git_dir])
    subprocess.run(cmd, check=True, env=_git_env())
    logger.info("clone of %s complete", cfg.name)


def _fetch(cfg: _RepoConfig) -> None:
    logger.info("fetching tags for %s", cfg.name)
    try:
        _git(cfg.git_dir, "fetch", "--tags", "--force", auth=cfg.use_https_auth)
        logger.info("fetch of %s complete", cfg.name)
    except subprocess.CalledProcessError as exc:
        logger.error("fetch of %s failed: %s", cfg.name, exc.stderr.strip())


def _start_fetch_scheduler() -> None:
    def loop() -> None:
        while True:
            time.sleep(3600)
            for cfg in _REPOS.values():
                _fetch(cfg)

    threading.Thread(target=loop, daemon=True).start()


def _semver_key(tag: str) -> Version:
    try:
        return Version(tag.lstrip("v"))
    except InvalidVersion:
        return Version("0.0.0")


def _tags_containing(commit_hash: str) -> list[str]:
    """Stable release tags in the OSS clone that contain commit_hash, oldest first."""
    try:
        raw = _git(GIT_DATA_DIR, "tag", "--contains", commit_hash)
    except subprocess.CalledProcessError:
        return []
    tags = [t for t in (line.strip() for line in raw.splitlines()) if _STABLE_TAG_RE.match(t)]
    return sorted(tags, key=_semver_key)


def _ref_exists(git_dir: str, ref: str) -> bool:
    cmd = ["git", "--git-dir", git_dir, "rev-parse", "--verify", "--quiet", ref]
    return subprocess.run(cmd, capture_output=True, text=True, env=_git_env()).returncode == 0


def _is_ancestor(git_dir: str, ancestor: str, descendant: str) -> bool:
    cmd = ["git", "--git-dir", git_dir, "merge-base", "--is-ancestor", ancestor, descendant]
    return subprocess.run(cmd, capture_output=True, text=True, env=_git_env()).returncode == 0


def _e_branches_containing(commit_sha: str) -> list[str]:
    """Branches in teleport.e that contain commit_sha, restricted to master/main/branch/vN.
    Sorted with master/main first, then branch/vN ascending by major version."""
    try:
        raw = _git(GIT_DATA_DIR_E, "branch", "--contains", commit_sha)
    except subprocess.CalledProcessError:
        return []
    branches: list[str] = []
    for line in raw.splitlines():
        # strip leading "* " or "  " from `git branch` output
        name = line.lstrip("*").strip()
        if _E_TRACKED_BRANCH_RE.match(name):
            branches.append(name)

    def sort_key(b: str) -> tuple[int, Version]:
        if b in ("master", "main"):
            return (0, Version("0.0.0"))
        ver = b.split("/", 1)[1].lstrip("v")
        try:
            return (1, Version(ver))
        except InvalidVersion:
            return (2, Version("0.0.0"))

    return sorted(branches, key=sort_key)


def _first_oss_commit_with_e_pointer(oss_branch: str, target_e_sha: str) -> str | None:
    """Return the first OSS commit on oss_branch whose `e` submodule pointer is target_e_sha
    or a descendant of it — i.e. the OSS commit that bumped the submodule to include the change."""
    try:
        raw = _git(GIT_DATA_DIR, "log", "--reverse", "--format=%H", oss_branch, "--", "e")
    except subprocess.CalledProcessError:
        return None
    for line in raw.splitlines():
        oss_commit = line.strip()
        if not oss_commit:
            continue
        try:
            ls_tree = _git(GIT_DATA_DIR, "ls-tree", oss_commit, "e")
        except subprocess.CalledProcessError:
            continue
        # Format: "<mode> <type> <sha>\t<path>", e.g. "160000 commit abc123\te"
        parts = ls_tree.split()
        if len(parts) < 3:
            continue
        pointer_sha = parts[2]
        if pointer_sha == target_e_sha or _is_ancestor(GIT_DATA_DIR_E, target_e_sha, pointer_sha):
            return oss_commit
    return None


def _find_e_versions(target_e_sha: str) -> dict[str, str | None] | str:
    """For an e commit, return earliest OSS stable tag per branch line.
    Values are tag strings, or None if the change has landed on the OSS branch but isn't yet tagged.
    Returns a human-readable string when nothing maps."""
    branches = _e_branches_containing(target_e_sha)
    if not branches:
        return f"No teleport.e release branch contains commit {target_e_sha!r}."
    results: dict[str, str | None] = {}
    for branch in branches:
        if not _ref_exists(GIT_DATA_DIR, branch):
            # OSS may not yet have a corresponding branch (e.g. brand-new release line).
            continue
        first_oss = _first_oss_commit_with_e_pointer(branch, target_e_sha)
        if not first_oss:
            results[branch] = None
            continue
        tags = _tags_containing(first_oss)
        results[branch] = tags[0] if tags else None
    if not results:
        return (f"teleport.e commit {target_e_sha!r} is on branches {branches!r}, "
                f"but no matching branches exist in {GITHUB_REPO} yet.")
    return results


def _earliest_tag_from_e_results(results: dict[str, str | None]) -> str | None:
    tags = [t for t in results.values() if t and _STABLE_TAG_RE.match(t)]
    if not tags:
        return None
    return min(tags, key=_semver_key)


def _get_pr(github_repo: str, pr_number: int) -> dict:
    """Fetch PR metadata from GitHub, or raise ValueError."""
    url = f"https://api.github.com/repos/{github_repo}/pulls/{pr_number}"
    resp = requests.get(url, headers=_gh_headers(), timeout=10)
    if resp.status_code == 404:
        raise ValueError(f"PR #{pr_number} not found in {github_repo}.")
    if resp.status_code in (401, 403):
        raise ValueError(
            f"GitHub denied access to {github_repo} PR #{pr_number} ({resp.status_code}). "
            f"The configured credentials may not have read access to this repository."
        )
    resp.raise_for_status()
    return resp.json()


def _pr_merge_commit(github_repo: str, pr_number: int) -> str:
    """Return the merge commit SHA for a GitHub PR, or raise ValueError."""
    data = _get_pr(github_repo, pr_number)
    sha = data.get("merge_commit_sha")
    if not sha:
        state = data.get("state", "unknown")
        raise ValueError(f"PR #{pr_number} has no merge commit (state: {state}).")
    return sha


def _find_backport_prs(pr_number: int) -> list[tuple[str, str]]:
    """Return (base_branch, merge_commit_sha) for merged backport PRs that cross-reference pr_number in OSS."""
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

    results: list[tuple[str, str]] = []
    for num in sorted(candidate_pr_numbers):
        try:
            data = _get_pr(GITHUB_REPO, num)
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
def find_earliest_version(commit_hash: str, repo: str | None = None) -> str:
    """Return the earliest stable Teleport release tag containing the given commit.

    repo="teleport": commit_hash is an OSS commit; uses `git tag --contains` directly.
    repo="teleport.e": commit_hash is an enterprise commit; walks OSS submodule history to find
    the OSS commit that bumped the `e` submodule to include this change, then resolves to a tag.
    repo=None (default): server checks both local clones and picks the one that contains the commit."""
    if repo is None:
        repo = _detect_repo_for_commit(commit_hash)
        if repo is None:
            return f"Commit {commit_hash!r} not found in either teleport or teleport.e clone."
    try:
        _resolve_repo(repo)
    except ValueError as exc:
        return str(exc)
    if repo == "teleport":
        tags = _tags_containing(commit_hash)
        if not tags:
            return f"No stable release found containing commit {commit_hash!r}."
        return tags[0]
    results = _find_e_versions(commit_hash)
    if isinstance(results, str):
        return results
    earliest = _earliest_tag_from_e_results(results)
    if earliest:
        return earliest
    return (f"teleport.e commit {commit_hash!r} has landed on OSS branch(es) "
            f"{sorted(results)!r} but is not yet in a stable release.")


@mcp.tool()
def find_all_versions(commit_hash: str, repo: str | None = None) -> list[str] | dict[str, str | None] | str:
    """Return every stable release tag containing the given commit.

    repo="teleport": list[str] of OSS tags, oldest first.
    repo="teleport.e": dict mapping each OSS branch line (e.g. "branch/v18", "master") to the
    earliest tag on that branch that includes the submodule bump, or None if not yet tagged.
    repo=None (default): server checks both local clones and picks the one that contains the commit."""
    if repo is None:
        repo = _detect_repo_for_commit(commit_hash)
        if repo is None:
            return f"Commit {commit_hash!r} not found in either teleport or teleport.e clone."
    try:
        _resolve_repo(repo)
    except ValueError as exc:
        return str(exc)
    if repo == "teleport":
        return _tags_containing(commit_hash)
    return _find_e_versions(commit_hash)


@mcp.tool()
def find_earliest_version_for_pr(pr_number: int, repo: str = "teleport") -> str:
    """Return the earliest stable Teleport release tag containing the merge commit of the given PR.

    repo="teleport" (default): PR is in gravitational/teleport.
    repo="teleport.e": PR is in gravitational/teleport.e; resolves to the e merge commit and
    walks OSS submodule history to find the earliest release. Requires GitHub API access to
    teleport.e — if the server is in SSH-only mode, this will return an error directing you
    to use the commit-based tool instead."""
    try:
        cfg = _resolve_repo(repo)
    except ValueError as exc:
        return str(exc)
    if not cfg.api_accessible:
        return _api_unavailable_error(repo)
    try:
        sha = _pr_merge_commit(cfg.github_repo, pr_number)
    except ValueError as exc:
        return str(exc)
    if repo == "teleport":
        tags = _tags_containing(sha)
        if not tags:
            return f"No stable release found containing PR #{pr_number} (merge commit {sha!r})."
        return tags[0]
    results = _find_e_versions(sha)
    if isinstance(results, str):
        return results
    earliest = _earliest_tag_from_e_results(results)
    if earliest:
        return earliest
    return (f"teleport.e PR #{pr_number} (merge commit {sha[:12]}) has landed on OSS branch(es) "
            f"{sorted(results)!r} but is not yet in a stable release.")


@mcp.tool()
def find_all_versions_for_pr(pr_number: int, repo: str = "teleport") -> list[str] | dict[str, str | None] | str:
    """Return every stable release tag containing the merge commit of the given PR.

    repo="teleport": list[str] of OSS tags, oldest first.
    repo="teleport.e": dict mapping each OSS branch line to the earliest tag on that branch
    that includes the submodule bump, or None if landed on OSS but not yet tagged. Requires
    GitHub API access to teleport.e — see find_earliest_version_for_pr for SSH-only mode behavior."""
    try:
        cfg = _resolve_repo(repo)
    except ValueError as exc:
        return str(exc)
    if not cfg.api_accessible:
        return _api_unavailable_error(repo)
    try:
        sha = _pr_merge_commit(cfg.github_repo, pr_number)
    except ValueError as exc:
        return str(exc)
    if repo == "teleport":
        return _tags_containing(sha)
    return _find_e_versions(sha)


@mcp.tool()
def find_versions_for_master_pr(pr_number: int) -> dict[str, str] | str:
    """Given a master-branch PR number in gravitational/teleport, find all merged backport PRs
    and return the earliest stable release tag per backport branch. Returns a dict like
    {"branch/v18": "v18.1.2"}.

    teleport.e is not supported here — for an e PR, use find_all_versions_for_pr with
    repo="teleport.e", which uses submodule-walk and naturally returns one entry per branch."""
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
    if _E_VIA_SSH:
        logger.info("teleport.e configured for SSH (key at %s); GitHub API access for it is disabled",
                    GIT_SSH_KEY_PATH)
    _setup_ssh_key()
    _verify_credentials()
    for cfg in _REPOS.values():
        _ensure_clone(cfg)
    _start_fetch_scheduler()
    uvicorn.run(
        mcp.streamable_http_app(),
        host=os.environ.get("HOST", "0.0.0.0"),
        port=int(os.environ.get("PORT", "8000")),
    )
