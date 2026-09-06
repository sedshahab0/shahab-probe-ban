#!/usr/bin/env bash
# Shahab Probe Ban — one-line installer (always fetches latest via jsDelivr CDN)
set -euo pipefail
INSTALL_URL="https://cdn.jsdelivr.net/gh/sedshahab0/shahab-probe-ban@main/probe-ban.sh"
INSTALL_PATH="/usr/local/sbin/probe-ban.sh"
[[ "$(id -u)" -eq 0 ]] || { echo "Run as root: sudo bash install.sh" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Install curl first: apt install curl" >&2; exit 1; }
tmp="$(mktemp)"
curl -fsSL "$INSTALL_URL" -o "$tmp"
bash -n "$tmp"
install -m 755 -o root -g root "$tmp" "$INSTALL_PATH"
rm -f "$tmp"
exec "$INSTALL_PATH" "${@:---wizard}"
