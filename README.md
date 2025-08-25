# Rev Engineering Common Repo

## TL;DR (10‑minute start)

1. **Fork** this repository.
2. Clone your **fork**: `git clone git@github.com:yourusername/rev-tech.git`
3. Create a **feature branch**: `git switch -c feature/my-awesome-demo`.
4. Add your work under the right top‑level folder (see below), and include:
   * `README.md` (how to run/use)
   * sample config: `.env.example` (no secrets!)
   * quick test or smoke script if applicable
5. **Open a Pull Request (PR)** to `main`. Request reviewers.
6. Address comments; reviews are in, **merge** (squash).

---

## Table of Contents

* [What lives here](#what-lives-here)
* [Repository structure](#repository-structure)
* [Conventions & required files](#conventions--required-files)
* [Git quickstart (basic commands)](#git-quickstart-basic-commands)
* [Forking & submitting a PR](#forking--submitting-a-pr)
* [Contribution checklist](#contribution-checklist)
* [Issue labels & triage](#issue-labels--triage)
* [Security & data handling](#security--data-handling)
* [FAQ & common pitfalls](#faq--common-pitfalls)
* [Appendix: Templates & samples](#appendix-templates--samples)

---

## What lives here

* **`use-cases/`**: Sanitized, customer‑agnostic patterns that show *what to build* and *why*.
* **`proof-of-concepts/`**: Short‑lived, experimental demos proving feasibility.
* **`templates/`**: Production‑grade starter kits and reusable snippets for common scenarios.
* **`integrations/`**: Connectors and adapters to third‑party products/platforms.
* **`tools/`**: Helper scripts to streamline workflows

> Rule of thumb:
>
> * If it’s **reusable** → `templates/` or `integrations/`.
> * If it’s **storytelling**/**pattern** → `use-cases/`.
> * If it’s **experimental** or unproven → `proof-of-concepts/`.

---

## Repository structure

```text
.
├─ use-cases/
│  └─ <kebab-name>/
│     ├─ README.md
│     <IaC>/
│     ├─ README.md
├─ proof-of-concepts/
│  └─ <kebab-name>/
│     ├─ README.md
│     <api-integration>/
│     ├─ README.md
├─ templates/
│  └─ <kebab-name>/
│     ├─ README.md
│     <configurations>/
│     ├─ README.md
├─ integrations/
│  └─ <vendor>-<product>/
│     ├─ README.md
│     <slack>/
│     ├─ README.md
├─ tools/
│     ├── setup/
│     └── testing/
├─ docs/
├─ .github/
│  ├─ workflows/
│  ├─ ISSUE_TEMPLATE/
│  └─ PULL_REQUEST_TEMPLATE.md
└─ CODEOWNERS
```

**Naming:** use **kebab‑case** for folders; keep names concise and descriptive.
**Languages:** multistack welcome (Python/Node/Go/…); keep each example self‑contained.

---

## Conventions & required files

Every contribution (use‑case, POC, template, or integration) **must include**:

1. **`README.md`** *(how to use it)*

   * Purpose & audience
   * Prerequisites (versions, accounts)
   * Setup (step‑by‑step)
   * How to run (commands)
   * Expected output / screenshots
   * Troubleshooting
   * Support/owners

2. **`.env.example`** *(if any runtime config is needed)*

   ```ini
   # Copy to .env and fill values locally. Never commit real secrets.
   API_BASE_URL=https://api.example.com
   API_KEY=$$NOT_YOUR_API_KEY_HERE$$
   ```

---

## Git quickstart (basic commands)

> If you’re new to Git, this is enough to be productive.
| Command | Purpose | When to Use |
|---------|---------|-------------|
| `git status` | Check what's changed | Before adding/committing |
| `git diff` | See detailed changes | Review before committing |
| `git pull` | Get latest changes | Start of each work session |
| `git push` | Upload your changes | After committing |
| `git stash` | Temporarily save changes | Switch branches quickly |
| `git stash pop` | Restore saved changes | Return to stashed work |

```bash
# 1) First-time setup (once)
git config --global user.name "Your Name"
git config --global user.email "you@goteleport.com"

# 2) Clone the repo from your fork
git clone git@github.com:yourusername/rev-tech.git
cd rev-tech

# 3) Create a feature branch
git switch -c feature/my-awesome-demo

# 4) Work and commit
git status
git add path/to/files
git commit -m "feat(demos): add awesome demo with README"

# 5) Push your branch and open PR
git push -u origin feature/my-awesome-demo

# 6) Update your branch later with latest main (before merging)
git fetch origin
git rebase origin/main         # or: git merge origin/main
```

---

## Forking & submitting a PR

1. Click **Fork** on GitHub → your fork is `yourname/rev-tech`.
2. Clone your fork:

   ```bash
   git clone git@github.com:yourusername/rev-tech.git
   cd rev-tech
   git remote add upstream git@github.com:gravitational/rev-tech.git
   ```

3. Create a branch on your fork: `git switch -c feature/<short-title>`.
4. Push to your fork: `git push -u origin feature/<short-title>`.
5. Open a PR **from your fork/branch** → **to org/main**.
6. Keep fork in sync later:

   ```bash
   git fetch upstream
   git switch main
   git rebase upstream/main
   git push origin main --force-with-lease
   ```

### PR expectations

* Clear title: `feat(templates): kafka ingest starter`
* Description: what/why, setup summary, screenshots if useful
* Tick the **Contribution checklist** (below)
* Request reviewers

---

## Contribution checklist

Before opening (or merging) a PR:

* [ ] Placed content in the correct top‑level folder (`use-cases/`, `proof-of-concepts/`, `templates/`, `integrations/`)
* [ ] Added **`README.md`** with usage & troubleshooting
* [ ] Requested reviews
* [ ] PR title uses a sensible prefix (e.g., `feat:`, `fix:`, `docs:`)

---

## Issue labels & triage

Recommended labels:

* **type:** `use-case`, `poc`, `template`, `integration`, `docs`
* **status:** `draft`, `review`, `help-wanted`, `blocked`, `good-first-issue`
* **area:** `data`, `streaming`, `auth`, `ui`, `infra`, `cloud/<provider>`, `vendor/<name>`

---

## Security & data handling

* **No customer data** or identifiable information. Use sanitized, small samples only.
* **Never commit secrets**. Use `.env` (ignored by Git) and provide `.env.example`.
* If a demo requires credentials, document how to obtain *test* credentials.
* Large binaries (>50 MB)? Use **Git LFS** or link to generated artifacts.
* Third‑party code: include license/NOTICE and verify compatibility.

---

## FAQ & common pitfalls

* **“My branch is behind `main`.”**
  `git fetch origin && git rebase origin/main` (or merge if you prefer).

* **“Accidentally committed a secret.”**
  Remove it, rotate the secret, and contact a repo admin to purge history.
  (Don’t rely solely on `git revert`; secrets may persist in history.)

* **“Merge conflicts!”**
  Update your branch (`rebase`/`merge`) and use your IDE’s conflict tool. Keep commits small to minimize conflicts.
