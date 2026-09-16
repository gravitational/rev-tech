# Linux Desktop Module

Linux Desktop Access (Teleport 19+): one Ubuntu 24.04 host running `linux_desktop_service` with an Xfce desktop rendered through Xvfb. Unlike Windows desktop access (which pairs `windows-instance` with `desktop-service` as an RDP proxy), the service runs **on the desktop host itself** — Teleport starts a virtual X11 display per session and launches the desktop environment inside it. Outbound reverse tunnel only; no inbound ports.

## Overview

- **Use Case:** browser-based access to a full Linux desktop, with session recording
- **Teleport Features:** `linux_desktop_service`, xsession discovery from `/usr/share/xsessions`, session recording, `linux_desktop_labels` / `linux_desktop_logins` RBAC
- **Infrastructure:** Ubuntu 24.04 instance (Xfce + Xvfb), Teleport installed from the proxy's install script

## Requirements

- **Teleport 19+** cluster and the **v19 Terraform provider**. The `LinuxDesktop` token role and the `linux_desktop_*` role fields don't exist in the 18.x provider — it rejects them client-side. That's also why this module owns its own access role instead of `modules/demo-rbac` (18.x-pinned); fold the role into demo-rbac when the repo moves to the 19 GA provider.
- Ubuntu AMI. AL2023 ships no desktop environment packages, so this module doesn't use the shared `data.aws_ami.linux`.

## Usage

```hcl
module "linux_desktop" {
  source = "../modules/linux-desktop"

  env           = "dev"
  team          = "platform"
  user          = "engineer@company.com"
  proxy_address = "teleport.company.com"

  ami_id             = data.aws_ami.ubuntu.id
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]

  # Created on the host AND allowed by the access role — the service does not
  # auto-create users (no create_desktop_user equivalent for Linux).
  desktop_logins = ["bob", "ubuntu"]
  name_prefix    = "chris" # role becomes chris-linux-desktop-access
}
```

## What It Creates

- **EC2 instance** — Ubuntu 24.04, Xfce + Xvfb, Teleport `linux_desktop_service` + `ssh_service` (both labeled `env`/`team`; SSH gives you a debug path onto the box)
- **Provision token** — roles `["LinuxDesktop", "Node"]`, 8h expiry
- **Role `<prefix>linux-desktop-access`** (optional, `create_access_role`) — `linux_desktop_labels` matching `env`/`team`, `linux_desktop_logins` = `desktop_logins`

## Session discovery and filtering

Teleport offers one session per `.desktop` file in `/usr/share/xsessions` (this module installs only Xfce, so one entry). To filter on multi-DE hosts, set `xsessions_included` / `xsessions_excluded` — regexes matched against the filename without `.desktop`, e.g. `included = "^xfce$"`.

## Demo commands

Desktops are web UI / Teleport Connect only (no tsh):

```
https://<proxy>/web/desktops        # Connect → pick login → live Xfce session
tsh ssh ubuntu@dev-linux-desktop    # debug path onto the same host
tsh recordings ls                   # desktop sessions are recorded like everything else
```

## Variables

| Variable | Description | Default |
|---|---|---|
| `env`, `team`, `user`, `proxy_address` | The usual profile plumbing | — |
| `ami_id` | Ubuntu 24.04 AMI | — |
| `instance_type` | Xfce-in-Xvfb wants memory | `t3.medium` |
| `subnet_id`, `security_group_ids`, `tags` | Placement | — |
| `desktop_logins` | Host users to create + allow in the role | `["ubuntu"]` |
| `create_access_role` | Create `<prefix>linux-desktop-access` | `true` |
| `name_prefix` | Role-name prefix (`""` = canonical unprefixed) | `""` |
| `xsessions_included` / `xsessions_excluded` | Session filter regexes | `""` (off) |

## Outputs

| Output | Description |
|---|---|
| `instance_id`, `private_ip` | The host |
| `hostname` | Name the desktop registers under (`<env>-linux-desktop`) |
| `access_role_name` | Role to grant users/personas (null when `create_access_role = false`) |

## Troubleshooting

```bash
tsh ssh ubuntu@dev-linux-desktop
sudo journalctl -fu teleport            # registration + session launch logs
which Xvfb                              # must be in PATH for the service
ls /usr/share/xsessions/                # what Teleport discovers (expect xfce.desktop)
id bob                                  # desktop logins must exist on the host
tctl get linux_desktop                  # confirm registration
```

- **Desktop not listed:** wait for cloud-init to finish (`cloud-init status`), Xfce is a few GB of packages.
- **Session fails immediately:** the chosen login doesn't exist on the host — check `desktop_logins`.
- **Role rejected at apply:** you're on the 18.x provider; this module needs v19.
