# Shahab Probe Ban

Auto-ban scanner IPs from nginx probe/honeypot logs via UFW.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sedshahab0/shahab-probe-ban/main/probe-ban.sh) --wizard
```

Run as root on Ubuntu/Debian. The wizard asks 6 questions (whitelist, auto-ban, TTL, CDN CIDRs, log path, confirm) and installs cron + config under `/etc/probe-ban/`.

Full Persian guide: [README.fa.md](README.fa.md)

## Commands

| Command | Description |
|---------|-------------|
| `--wizard` | Interactive setup |
| `run` | Process log (cron) |
| `--status` | Ban list |
| `--dry-run` | Preview bans |
| `--unban IP` | Remove ban |
| `--expire` | Drop expired bans |
