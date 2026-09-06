# Shahab Probe Ban

Auto-ban scanner IPs from nginx probe/honeypot logs via UFW.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sedshahab0/shahab-probe-ban/main/probe-ban.sh) --wizard
```

Run as root on Ubuntu/Debian. Full guide (Persian): [README.md](README.md)

| Command | Description |
|---------|-------------|
| `--wizard` | Interactive setup |
| `run` | Process log (cron) |
| `--status` | Ban list |
| `--dry-run` | Preview bans |
| `--unban IP` | Remove ban |
| `--expire` | Drop expired bans |
