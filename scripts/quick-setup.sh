#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║  OpenClaw NixOS — Quick Setup                   ║"
echo "  ║  One flake. Fully hardened. Your agents, secured ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Check we're on NixOS
if [ ! -f /etc/NIXOS ]; then
  echo -e "${RED}This script is designed for NixOS systems.${NC}"
  echo "You can still use the module manually — see the README."
  echo ""
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi

OUTPUT_DIR="${1:-./openclaw-config}"
mkdir -p "$OUTPUT_DIR"

echo -e "${BOLD}Domain Configuration${NC}"
echo "Your OpenClaw instance needs a domain for automatic TLS."
echo ""
read -p "  Domain (e.g., agents.example.com): " DOMAIN
DOMAIN="${DOMAIN:-agents.example.com}"

echo ""
echo -e "${BOLD}Model Provider${NC}"
echo "Which AI model provider? (anthropic, openai, ollama)"
echo ""
read -p "  Provider [anthropic]: " PROVIDER
PROVIDER="${PROVIDER:-anthropic}"

echo ""
read -sp "  API key (hidden): " API_KEY
echo ""

echo ""
echo -e "${BOLD}Telegram Bot (optional)${NC}"
read -p "  Enable Telegram? [y/N] " -n 1 -r
echo
TELEGRAM_ENABLED=false
TELEGRAM_TOKEN=""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  TELEGRAM_ENABLED=true
  read -sp "  Bot token (hidden): " TELEGRAM_TOKEN
  echo ""
fi

echo ""
echo -e "${BOLD}Discord Bot (optional)${NC}"
read -p "  Enable Discord? [y/N] " -n 1 -r
echo
DISCORD_ENABLED=false
DISCORD_TOKEN=""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  DISCORD_ENABLED=true
  read -sp "  Bot token (hidden): " DISCORD_TOKEN
  echo ""
fi

echo ""
echo -e "${BOLD}Tool Security${NC}"
echo "Default: allowlist (safe tools only). Add 'exec' for shell access."
read -p "  Enable exec tool? [y/N] " -n 1 -r
echo
EXEC_ENABLED=false
[[ $REPLY =~ ^[Yy]$ ]] && EXEC_ENABLED=true

# --- Generate secrets ---
SECRETS_DIR="$OUTPUT_DIR/secrets"
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

if [ -n "$API_KEY" ]; then
  echo "$API_KEY" > "$SECRETS_DIR/model-api-key"
  chmod 600 "$SECRETS_DIR/model-api-key"
fi

if [ "$TELEGRAM_ENABLED" = true ] && [ -n "$TELEGRAM_TOKEN" ]; then
  echo "$TELEGRAM_TOKEN" > "$SECRETS_DIR/telegram-token"
  chmod 600 "$SECRETS_DIR/telegram-token"
fi

if [ "$DISCORD_ENABLED" = true ] && [ -n "$DISCORD_TOKEN" ]; then
  echo "$DISCORD_TOKEN" > "$SECRETS_DIR/discord-token"
  chmod 600 "$SECRETS_DIR/discord-token"
fi

# --- Generate flake.nix ---
cat > "$OUTPUT_DIR/flake.nix" << 'FLAKE_EOF'
{
  description = "My OpenClaw deployment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    openclaw.url = "github:Scout-DJ/openclaw-nix";
  };

  outputs = { self, nixpkgs, openclaw }: {
    nixosConfigurations.openclaw = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        openclaw.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
FLAKE_EOF

# --- Generate configuration.nix ---
TOOLS_LIST='"read" "write" "edit" "web_search" "web_fetch" "message" "tts"'
if [ "$EXEC_ENABLED" = true ]; then
  TOOLS_LIST="$TOOLS_LIST \"exec\""
fi

TELEGRAM_BLOCK=""
if [ "$TELEGRAM_ENABLED" = true ]; then
  TELEGRAM_BLOCK="
    telegram = {
      enable = true;
      tokenFile = \"$SECRETS_DIR/telegram-token\";
    };"
fi

DISCORD_BLOCK=""
if [ "$DISCORD_ENABLED" = true ]; then
  DISCORD_BLOCK="
    discord = {
      enable = true;
      tokenFile = \"$SECRETS_DIR/discord-token\";
    };"
fi

cat > "$OUTPUT_DIR/configuration.nix" << EOF
{ config, pkgs, ... }:

{
  services.openclaw = {
    enable = true;
    domain = "$DOMAIN";
    modelProvider = "$PROVIDER";
    modelApiKeyFile = "$SECRETS_DIR/model-api-key";
    toolAllowlist = [ $TOOLS_LIST ];$TELEGRAM_BLOCK$DISCORD_BLOCK

    autoUpdate.enable = true;
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}
EOF

echo ""
echo -e "${GREEN}${BOLD}✓ Configuration generated!${NC}"
echo ""
echo "  Files created in: $OUTPUT_DIR/"
echo "    flake.nix          — Nix flake with OpenClaw module"
echo "    configuration.nix  — Your deployment config"
echo "    secrets/            — API keys (chmod 600)"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo ""
echo "  1. Review the generated config:"
echo "     cat $OUTPUT_DIR/configuration.nix"
echo ""
echo "  2. Copy to /etc/nixos (or your flake repo):"
echo "     sudo cp -r $OUTPUT_DIR/* /etc/nixos/"
echo ""
echo "  3. Deploy:"
echo "     sudo nixos-rebuild switch --flake /etc/nixos#openclaw"
echo ""
echo "  4. Check your auth token:"
echo "     sudo cat /var/lib/openclaw/auth-token"
echo ""
echo -e "${CYAN}  Your gateway will be at: https://$DOMAIN${NC}"
echo -e "${CYAN}  Bound to localhost:3000, fronted by Caddy with auto-TLS${NC}"
echo ""
echo -e "  ${BOLD}⚠ Move secrets to agenix/sops-nix for production!${NC}"
echo "  Plain files in secrets/ are fine for testing."
echo ""
