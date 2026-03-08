# Module: app-demo-panel

Provisions an EC2 instance running a Flask identity panel behind Teleport Application Access. The app reads the `Teleport-Jwt-Assertion` header injected by Teleport's App Service and displays the logged-in user's identity, roles, and traits.

**Use case:** Show prospects what Teleport injects into every request — the user's Teleport identity flows through to internal apps with no extra login.

The Flask app lives in a separate standalone repo and is cloned at instance boot via `app_repo`. The reference implementation is at [`https://github.com/tenaciousdlg/app-demo-panel`](https://github.com/tenaciousdlg/app-demo-panel) — callers that use it as-is (data-plane and profiles) default to that repo. This keeps application code and infrastructure lifecycle separate.

---

## Usage

```hcl
module "demo_panel" {
  source = "../../modules/app-demo-panel"

  env              = var.env
  team             = var.team
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version
  app_repo         = var.app_repo          # Git URL for the Flask app
  ami_id           = data.aws_ami.linux.id
  instance_type    = "t3.micro"
  subnet_id        = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "demo_panel_registration" {
  source        = "../../modules/dynamic-registration"
  resource_type = "app"
  name          = "demo-panel-${var.env}"
  description   = "Teleport Demo Panel — shows identity injected via JWT header"
  uri           = "http://localhost:5000"
  public_addr   = "demo-panel-${var.env}.${var.proxy_address}"
  labels = {
    env                = var.env
    team               = var.team
    "teleport.dev/app" = "demo-panel"
  }
}
```

---

## Variables

| Variable | Description | Default |
|---|---|---|
| `env` | Environment label (e.g., `dev`, `prod`) | **required** |
| `user` | Tag value for resource creator | **required** |
| `proxy_address` | Teleport proxy hostname (no `https://`) | **required** |
| `teleport_version` | Teleport version to install | **required** |
| `app_repo` | Git URL for the Flask app (e.g., `https://github.com/org/app-demo-panel`) | **required** |
| `ami_id` | AMI ID for Amazon Linux 2023 | **required** |
| `instance_type` | EC2 instance type | **required** |
| `subnet_id` | Subnet to launch the instance in | **required** |
| `security_group_ids` | Security group IDs | **required** |
| `team` | Team label | `"platform"` |
| `tags` | Additional AWS tags | `{}` |

---

## Outputs

| Output | Description |
|---|---|
| `private_ip` | Private IP of the EC2 instance |

---

## How It Works

1. The EC2 instance boots, runs `git clone <app_repo>` to fetch the Flask app
2. Dependencies are installed via `pip3 install -r requirements.txt`
3. A systemd service starts `gunicorn` with `DEMO_ENV` and `DEMO_TEAM` environment variables set from Terraform
4. The Teleport App Service discovers the app via the `dynamic-registration` module and starts proxying
5. On each request, Teleport injects a `Teleport-Jwt-Assertion` JWT header containing the user's `sub`, `roles`, and `traits`
6. The Flask app decodes the JWT and renders a dashboard showing the user's identity

## Accessing the Panel

```bash
tsh apps login demo-panel-dev
# Open https://demo-panel-dev.<proxy> in browser
```

The panel shows:
- Username (from JWT `sub` claim)
- Roles assigned to the user
- Traits (team memberships, custom attributes)
- Environment label (from `DEMO_ENV`)
