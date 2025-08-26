# Rev Engineering Common Repo

## TL;DR (1‑minute start)

1. Clone this **repo**: `git clone git@github.com:gravitational/rev-tech.git`
2. Create a **feature branch**: `git switch -c feature/my-awesome-demo`.
3. Add your work under the right top‑level folder (see below), and include:
   * `README.md` (how to run/use)
   * sample config: `.env.example` (no secrets!)
   * quick test or smoke script if applicable
4. **Open a Pull Request (PR)** to `main`. Request reviewers.
5. Address comments; reviews are in, **merge** (squash).

---

## Table of Contents

- [Rev Engineering Common Repo](#rev-engineering-common-repo)
  - [TL;DR (1‑minute start)](#tldr-1minute-start)
  - [Table of Contents](#table-of-contents)
  - [What lives here](#what-lives-here)
  - [Repository structure](#repository-structure)
  - [Conventions \& required files](#conventions--required-files)
  - [Cloning \& submitting a PR](#cloning--submitting-a-pr)
    - [PR expectations](#pr-expectations)
  - [Contribution checklist](#contribution-checklist)
  - [Issue labels \& triage](#issue-labels--triage)
  - [Best Practices](#best-practices)
    - [Do's](#dos)
    - [Don'ts](#donts)
  - [FAQ \& common pitfalls](#faq--common-pitfalls)
    - [Advanced Git identity setup](#advanced-git-identity-setup)

---

## What lives here

* **`use-cases/`**: Sanitized, customer‑agnostic patterns that show *what to build* and *why*.
* **`proof-of-concepts/`**: Short‑lived, experimental demos proving feasibility.
* **`templates/`**: Production‑grade starter kits and reusable snippets for common scenarios.
* **`integrations/`**: Connectors and adapters to third‑party products/platforms.
* **`docs/`**: Any integration, solution, poc, etc that does not require code.
* **`tools/`**: Helper scripts to streamline workflows.
* **`archive/`**: Outdated code, useful for reference only.

Rule of thumb:

* If it’s **reusable** → `templates/` or `integrations/`.
* If it’s **storytelling**/**pattern** → `use-cases/`.
* If it’s **experimental** or unproven → `proof-of-concepts/`.

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
├─ archive
│     └── README.md
├─ .github/
│  ├─ workflows/
│  ├─ ISSUE_TEMPLATE/
│  └─ PULL_REQUEST_TEMPLATE.md
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
   * Expected output/screenshots
   * Troubleshooting
   * Support/owners

2. **`.env.example`** *(if any runtime config is needed)*

   ```ini
   # Copy to .env and fill values locally. Never commit real secrets.
   API_BASE_URL=https://api.example.com
   API_KEY=$$NOT_YOUR_API_KEY_HERE$$
   ```

---

## Cloning & submitting a PR

1. First-time setup (needed only once)

```bash
git config --global user.name "Your Name"
git config --global user.email "you@goteleport.com"
```

2. Clone the repository:

```bash
git clone git@github.com:gravitational/rev-tech.git
cd rev-tech
```

3. Create a branch on the repository:

```bash
git switch -c feature/<short-title>
```

4. Do work and push to the branch:

```bash
git status
git add path/to/files
git commit -m "feat(demos): add awesome demo with README"
git push -u origin feature/my-awesome-demo
```

5. Go to browser and switch to your branch, click `Create Pull Request`.

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
* [ ] PR title uses a sensible prefix (e.g., `feat:`, `fix:`, `docs:`, `add:`, `update:`, `remove:`)

---

## Issue labels & triage

Recommended labels:

* **type:** `use-case`, `poc`, `template`, `integration`, `docs`
* **status:** `draft`, `review`, `help-wanted`, `blocked`, `good-first-issue`
* **area:** `data`, `streaming`, `auth`, `ui`, `infra`, `cloud/<provider>`, `vendor/<name>`

---

## Best Practices

### Do's

* ✅ Always test your code/configs before committing
* ✅ Keep customer data anonymized
* ✅ Use meaningful commit messages
* ✅ Update existing solutions rather than duplicating
* ✅ Tag your submissions with relevant keywords
* ✅ Include error handling in scripts
* ✅ Document any dependencies clearly

### Don'ts

* ❌ Don't commit customer credentials or sensitive data
* ❌ Don't commit large binary files (use Git LFS if needed)
* ❌ Don't work directly on the main branch
* ❌ Don't merge your own PRs without review
* ❌ Don't forget to pull the latest changes before starting work

---

## FAQ & common pitfalls

Basic command quick list:

| Command         | Purpose                  | When to Use                |
| --------------- | ------------------------ | -------------------------- |
| `git status`    | Check what's changed     | Before adding/committing   |
| `git diff`      | See detailed changes     | Review before committing   |
| `git pull`      | Get latest changes       | Start of each work session |
| `git push`      | Upload your changes      | After committing           |
| `git stash`     | Temporarily save changes | Switch branches quickly    |
| `git stash pop` | Restore saved changes    | Return to stashed work     |

* **“My branch is behind `main`.”**
  `git fetch origin && git rebase origin/main` (or merge if you prefer).
* **“Accidentally committed a secret.”**
  Remove it, rotate the secret, and contact a repo admin to purge history.
  (Don’t rely solely on `git revert`; secrets may persist in history.)
* **“Merge conflicts!”**
  Update your branch (`rebase`/`merge`) and use your IDE’s conflict tool. Keep commits small to minimize conflicts.

### Advanced Git identity setup

For more advanced users. It is recommended that you setup git to automatically recognize your personal git and your work related repositories. If it doesn't exist, create `.config/git/` and create your main `config` file:

```bash
mkdir -p .config/git
touch .config/git/config
vi .config/git/config
```

Once you are editing the file, it should have content similar to this:

```conf
[user]
    name = Boris 'B' Kurktchiev
    # set to your normal github email
    email = kurktchiev@gmail.com
    signingkey = /Users/boris/.ssh/id_rsa.pub
# this include is important, you can have as many of these as includes as you want with different identities
# and matches for different orgs/repos
[includeIf "hasconfig:remote.*.url:git@github.com:gravitational/**"]
    path = config-work
[core]
    excludesfile = ~/.gitignore_global
    quotepath = false
    # set to your preferred code editor
    editor = code --wait -r
[push]
    default = simple
[filter "lfs"]
    clean = git-lfs clean -- %f
    smudge = git-lfs smudge -- %f
    required = true
    process = git-lfs filter-process
[pager]
    branch = false
[pull]
    rebase = true
[credential]
   # this uses the MacOS Keychain for password store
    helper = osxkeychain
[gpg]
    format = ssh
[gpg "ssh"]
   # if you store your SSH keys in 1Password leave this here, otherwise remove
    program = /Applications/1Password.app/Contents/MacOS/op-ssh-sign
[commit]
    gpgsign = true
[url "ssh://git@github.com/"]
    insteadOf = https://github.com/
[init]
    defaultBranch = main
```

Now in the same `.config/git` directory create a second file and name it `config-work`:

```bash
touch .config/git/config-work
vi .config/git/config-work
```

The contents should look like this:

```conf
[user]
  # set to your work email
  email = boris.kurktchiev@goteleport.com
```

Now when you edit any repositories under the `gravitational` org it will automatically use your work e-mail, while using your normal git for everything else.
