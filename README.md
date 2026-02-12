# 🔒 openclaw-nix

**One flake. Fully hardened. Your agents, secured.**

A NixOS module for deploying [OpenClaw](https://github.com/openclaw/openclaw) with security defaults that actually make sense. Because 15,200 exposed control panels on the public internet is not a configuration choice — it's a crisis.

> Presented at **SCaLE 23x / PlanetNix** · March 5–8, 2026 · Pasadena, CA

---

## The Problem

OpenClaw has 180K+ GitHub stars. It's the most popular agent infrastructure platform in the world. It's also, according to CrowdStrike and SecurityScorecard reports, one of the most commonly misconfigured:

- **15,200+ exposed admin panels** on the public internet
- Default installs bind to `0.0.0.0` with no auth
- Tool execution in `full` mode = unrestricted shell access
- No TLS, no firewall rules, no sandboxing out of the box

Most of these aren't malicious deployments. They're people who followed the quickstart, got it working, and moved on. The defaults failed them.

## The Solution

```nix
services.openclaw.enable = true;
services.openclaw.domain = "agents.example.com";
```

That's it. Two lines. You get:

| Security Layer | What It Does |
|---|---|
| **Gateway auth** | Auto-generated token, required for all connections |
| **Localhost binding** | Gateway never touches the public internet directly |
| **Caddy reverse proxy** | Automatic TLS via Let's Encrypt, security headers |
| **Tool allowlists** | Only safe tools enabled — no `exec`, no `full` mode |
| **systemd hardening** | `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, capability dropping |
| **Firewall** | Only ports 443 (HTTPS) and 22 (SSH) open |
| **Fail2ban** | SSH brute-force protection with incremental bans |
| **Dedicated user** | Runs as `openclaw` user, not root, not your account |

## Quick Start

### Interactive Setup

```bash
nix run github:Scout-DJ/openclaw-nix#quick-setup
```

Walks you through domain, API keys, Telegram/Discord setup, and generates a ready-to-deploy NixOS config.

### Manual Setup

**1. Add to your flake inputs:**

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    openclaw.url = "github:Scout-DJ/openclaw-nix";
  };

  outputs = { self, nixpkgs, openclaw }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        openclaw.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

**2. Configure:**

```nix
# configuration.nix
{ config, pkgs, ... }:

{
  services.openclaw = {
    enable = true;
    domain = "agents.example.com";

    # Model provider
    modelProvider = "anthropic";
    modelApiKeyFile = "/run/secrets/anthropic-api-key";

    # Telegram bot
    telegram = {
      enable = true;
      tokenFile = "/run/secrets/telegram-bot-token";
    };

    # Tool security (defaults shown — you don't need to set these)
    toolSecurity = "allowlist";
    toolAllowlist = [
      "read" "write" "edit"
      "web_search" "web_fetch"
      "message" "tts"
    ];
  };
}
```

**3. Deploy:**

```bash
sudo nixos-rebuild switch --flake .#myhost
```

**4. Get your auth token:**

```bash
sudo cat /var/lib/openclaw/auth-token
```

## Module Options

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | bool | `false` | Enable OpenClaw |
| `domain` | string | `""` | Public domain (enables Caddy + TLS) |
| `gatewayPort` | port | `3000` | Local gateway port |
| `authTokenFile` | path | `/var/lib/openclaw/auth-token` | Auth token file (auto-generated) |
| `toolSecurity` | enum | `"allowlist"` | `"deny"` or `"allowlist"` (no `"full"`) |
| `toolAllowlist` | list | safe defaults | Permitted tools |
| `modelProvider` | string | `"anthropic"` | AI model provider |
| `modelApiKeyFile` | path | `null` | API key file path |
| `telegram.enable` | bool | `false` | Enable Telegram plugin |
| `telegram.tokenFile` | path | `null` | Telegram bot token file |
| `discord.enable` | bool | `false` | Enable Discord plugin |
| `discord.tokenFile` | path | `null` | Discord bot token file |
| `autoUpdate.enable` | bool | `false` | Enable auto-update timer |
| `autoUpdate.schedule` | string | `"weekly"` | Update schedule (systemd calendar) |
| `openFirewall` | bool | `true` | Configure firewall rules |
| `extraGatewayConfig` | attrs | `{}` | Additional gateway config |

## systemd Hardening Details

The gateway service runs with these protections:

```
NoNewPrivileges=yes        # No privilege escalation
PrivateTmp=yes             # Isolated /tmp
PrivateDevices=yes         # No access to physical devices
ProtectSystem=strict       # Read-only filesystem (except StateDirectory)
ProtectHome=yes            # No access to /home
ProtectKernelTunables=yes  # No sysctl writes
ProtectKernelModules=yes   # No module loading
ProtectKernelLogs=yes      # No kernel log access
ProtectControlGroups=yes   # No cgroup writes
ProtectClock=yes           # No clock changes
ProtectHostname=yes        # No hostname changes
RestrictNamespaces=yes     # No new namespaces
RestrictRealtime=yes       # No realtime scheduling
RestrictSUIDSGID=yes       # No SUID/SGID
LockPersonality=yes        # No personality changes
CapabilityBoundingSet=     # All capabilities dropped
UMask=0077                 # Restrictive file creation
```

## Why NixOS?

- **Declarative** — Your security config is code, version-controlled, reproducible
- **Atomic** — Deploys succeed completely or roll back completely
- **Auditable** — `nixos-rebuild dry-run` shows exactly what changes
- **Reproducible** — Same config = same system, every time, on every machine

The default-insecure problem exists because imperative setups drift. NixOS doesn't drift.

## Production Notes

### Secrets Management

The quick-setup script stores secrets as plain files for convenience. For production, use:

- **[agenix](https://github.com/ryantm/agenix)** — age-encrypted secrets in your repo
- **[sops-nix](https://github.com/Mic92/sops-nix)** — Mozilla SOPS integration

### Adding exec/browser Tools

If your agents need shell or browser access:

```nix
services.openclaw.toolAllowlist = [
  "read" "write" "edit"
  "web_search" "web_fetch"
  "message" "tts"
  "exec"      # ⚠ Shell access — sandbox appropriately
  "browser"   # ⚠ Browser automation
];
```

Understand that `exec` gives your agents shell access within the systemd sandbox. The hardening limits blast radius, but it's still shell access.

## Running Example

This module powers the OpenClaw deployment at **substation** (`5.78.90.129`), running OpenClaw `2026.2.6-3` with the full hardening stack.

## Contributing

Issues and PRs welcome at [github.com/Scout-DJ/openclaw-nix](https://github.com/Scout-DJ/openclaw-nix).

## License

MIT

---

*Built by [Scout-DJ](https://github.com/Scout-DJ) · Presented at PlanetNix @ SCaLE 23x · March 2026*
