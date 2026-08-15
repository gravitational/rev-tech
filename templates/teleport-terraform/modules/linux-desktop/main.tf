##################################################################################
# modules/linux-desktop/main.tf
#
# Linux Desktop Access (Teleport 19+): one Ubuntu host running linux_desktop_service.
# Unlike Windows desktop access (windows-instance + desktop-service pair), the
# service runs ON the desktop host itself — Teleport starts a virtual X11 display
# with Xvfb and launches an Xfce session inside it. Outbound reverse tunnel only,
# no inbound ports.
#
# The service does NOT create host users (session setup fails user.Lookup if the
# login doesn't exist), so userdata pre-creates every login in var.desktop_logins.
#
# This module also owns the linux-desktop-access role instead of modules/demo-rbac:
# the linux_desktop_labels / linux_desktop_logins role fields and the LinuxDesktop
# token role exist only in the v19 provider (the 18.x provider rejects both
# client-side). Fold the role into demo-rbac once the pinned provider is 19 GA.
##################################################################################

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    # v19 staging provider — must match the address the profiles root pins.
    # LinuxDesktop token roles and linux_desktop_* role fields are 19-only.
    teleport = {
      source = "terraform-staging.releases.development.teleport.dev/gravitational/teleport"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

locals {
  user = lower(split("@", var.user)[0])

  # "" -> unprefixed canonical name; anything else -> "<prefix>-"
  p = var.name_prefix == "" ? "" : "${var.name_prefix}-"
}

resource "random_string" "token" {
  length  = 32
  special = false
}

resource "teleport_provision_token" "linux_desktop" {
  version = "v2"
  spec = {
    roles = ["LinuxDesktop", "Node"]
    name  = random_string.token.result
  }
  metadata = {
    expires = timeadd(timestamp(), "8h")
  }
  # timestamp() changes on every plan, causing perpetual drift noise.
  # The token only needs to live long enough for the instance to boot and register.
  lifecycle {
    ignore_changes = [metadata]
  }
}

resource "aws_instance" "linux_desktop" {
  # Demo hosts keep the AMI they were created with — data.aws_ami uses
  # most_recent, and a new upstream image must not replace healthy
  # instances on the next apply (e.g. mid-event).
  lifecycle {
    ignore_changes = [ami]
  }

  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id
  # Registers via outbound reverse tunnel — no public IP needed.
  associate_public_ip_address = null
  vpc_security_group_ids      = var.security_group_ids

  user_data = templatefile("${path.module}/userdata.tpl", {
    name               = "${var.env}-linux-desktop"
    token              = teleport_provision_token.linux_desktop.metadata.name
    proxy_address      = var.proxy_address
    env                = var.env
    team               = var.team
    desktop_logins     = join(" ", var.desktop_logins)
    xsessions_included = var.xsessions_included
    xsessions_excluded = var.xsessions_excluded
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    # Xfce + Xvfb + fonts land around 3-4 GB of packages on top of the base image.
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name = "${local.user}-${var.env}-linux-desktop"
  })
}

##################################################################################
# LINUX DESKTOP ACCESS — standing access to this profile's linux desktops.
# Persona logins first (userdata created them on the host), generic fallback last.
##################################################################################

resource "teleport_role" "linux_desktop_access" {
  count   = var.create_access_role ? 1 : 0
  version = "v7"

  metadata = {
    name        = "${local.p}linux-desktop-access"
    description = "Demo: access to ${var.env}-labeled Linux desktops"
  }

  spec = {
    allow = {
      linux_desktop_labels = {
        env  = [var.env]
        team = [var.team]
      }
      linux_desktop_logins = var.desktop_logins
    }
  }
}
