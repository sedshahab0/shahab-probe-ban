#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Shahab Probe Ban
#  Auto-ban scanner IPs from nginx probe logs (UFW)
#  https://github.com/sedshahab0/shahab-probe-ban
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

if [[ ! -t 0 ]] && [[ -r /dev/tty ]]; then
  exec </dev/tty
fi

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="probe-ban.sh"
readonly INSTALL_PATH="/usr/local/sbin/${SCRIPT_NAME}"
readonly ENV_FILE="${PROBE_BAN_ENV:-/etc/probe-ban/security.env}"
readonly DEFAULT_LOG="/var/log/nginx/probes.log"
readonly DEFAULT_STATE="/var/lib/probe-ban"

LOG_FILE="$DEFAULT_LOG"
STATE_DIR="$DEFAULT_STATE"
STATE_FILE="${STATE_DIR}/probe-ban.offset"
BANNED_TSV="${STATE_DIR}/banned-ips.tsv"
BANNED_FILE="${STATE_DIR}/banned-ips.txt"
LOCK_FILE="${STATE_DIR}/probe-ban.lock"
ACTION_LOG="${STATE_DIR}/probe-ban.log"

WHITELIST_IPS=""
AUTO_BAN="1"
BAN_TTL_DAYS="30"
TRUSTED_CIDRS=""
SERVER_LABEL=""
ALERT_TELEGRAM="0"
TELEGRAM_ENV="/etc/probe-ban/telegram.env"
SYNC_PEER="0"
PUSH_PEER="0"
PEER_IP=""
PEER_SSH_KEY="/root/.ssh/probe-ban-sync"
PEER_SSH_HOST="probe-ban-peer"

R='\033[0m'
B='\033[1m'
D='\033[2m'
RED='\033[1;31m'
GRN='\033[1;32m'
YLW='\033[1;33m'
BLU='\033[1;34m'
MAG='\033[1;35m'
CYN='\033[1;36m'
WHT='\033[1;37m'

nl()  { printf '\n'; }

ask_line() {
  local prompt="$1" default="${2-}" input=""
  if [[ -n "$default" ]]; then
    printf '  %b%s%b %b[%s]%b ' "$WHT" "$prompt" "$R" "$D" "$default" "$R"
  else
    printf '  %b%s%b ' "$WHT" "$prompt" "$R"
  fi
  IFS= read -r input || true
  if [[ -z "$input" ]]; then
    printf '%s' "$default"
  else
    printf '%s' "$input"
  fi
}

ask_yes() {
  local prompt="$1" default="${2:-Y}" input="" yn
  if [[ "$default" =~ ^[Yy] ]]; then
    printf '  %b%s%b %b[Y/n]%b ' "$WHT" "$prompt" "$R" "$D" "$R"
  else
    printf '  %b%s%b %b[y/N]%b ' "$WHT" "$prompt" "$R" "$D" "$R"
  fi
  IFS= read -r input || true
  yn="${input:-$default}"
  [[ "$yn" =~ ^[Yy] ]]
}

die() {
  printf '\n  %b✗ %s%b\n\n' "$RED" "$1" "$R" >&2
  exit 1
}

ok()   { printf '  %b✓%b %s\n' "$GRN" "$R" "$1"; }
info() { printf '  %b•%b %s\n' "$CYN" "$R" "$1"; }
warn() { printf '  %b!%b %s\n' "$YLW" "$R" "$1"; }

hr() {
  printf '  %b────────────────────────────────────────────────────────────%b\n' "$D" "$R"
}

box_top()    { printf '  %b╭────────────────────────────────────────────────────────────╮%b\n' "$CYN" "$R"; }
box_bottom() { printf '  %b╰────────────────────────────────────────────────────────────╯%b\n' "$CYN" "$R"; }
box_line()   { printf '  %b│%b %-56s %b│%b\n' "$CYN" "$R" "$1" "$CYN" "$R"; }

clear_safe() {
  [[ -t 1 ]] || return 0
  printf '\033[2J\033[H'
}

banner() {
  clear_safe
  printf '\n'
  printf '%b' "$MAG"
  cat <<'EOF'
      ███████╗██╗  ██╗ █████╗ ██╗  ██╗ █████╗ ██████╗
      ██╔════╝██║  ██║██╔══██╗██║  ██║██╔══██╗██╔══██╗
      ███████╗███████║███████║███████║███████║██████╔╝
      ╚════██║██╔══██║██╔══██║██╔══██║██╔══██║██╔══██╗
      ███████║██║  ██║██║  ██║██║  ██║██║  ██║██████╔╝
      ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝
EOF
  printf '%b' "$R"
  printf '                         %bش   ه   ا   ب%b\n' "$WHT" "$R"
  printf '              %bPROBE BAN  ·  UFW  ·  NGINX LOG%b\n' "$CYN" "$R"
  printf '                    %bv%s%b\n\n' "$D" "$SCRIPT_VERSION" "$R"
}

stage() {
  local n="$1" title="$2"
  nl
  printf '  %b▸ مرحله %s/6  ·  %s%b\n' "$B$BLU" "$n" "$title" "$R"
  hr
}

need_root() {
  [[ "$(id -u)" -eq 0 ]] || die "این اسکریپت را با root اجرا کن:  sudo bash ${SCRIPT_NAME} --wizard"
}

script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  fi
  LOG_FILE="${PROBE_BAN_PROBE_LOG:-$DEFAULT_LOG}"
  STATE_DIR="${PROBE_BAN_STATE_DIR:-$DEFAULT_STATE}"
  STATE_FILE="${STATE_DIR}/probe-ban.offset"
  BANNED_TSV="${STATE_DIR}/banned-ips.tsv"
  BANNED_FILE="${STATE_DIR}/banned-ips.txt"
  LOCK_FILE="${STATE_DIR}/probe-ban.lock"
  ACTION_LOG="${STATE_DIR}/probe-ban.log"
  WHITELIST_IPS="${PROBE_BAN_WHITELIST_IPS:-}"
  AUTO_BAN="${PROBE_BAN_AUTO_BAN:-1}"
  BAN_TTL_DAYS="${PROBE_BAN_TTL_DAYS:-30}"
  TRUSTED_CIDRS="${PROBE_BAN_TRUSTED_CIDRS:-}"
  SERVER_LABEL="${PROBE_BAN_SERVER_LABEL:-$(hostname -s 2>/dev/null || echo server)}"
  ALERT_TELEGRAM="${PROBE_BAN_ALERT_TELEGRAM:-0}"
  TELEGRAM_ENV="${PROBE_BAN_TELEGRAM_ENV:-/etc/probe-ban/telegram.env}"
  SYNC_PEER="${PROBE_BAN_SYNC_PEER:-0}"
  PUSH_PEER="${PROBE_BAN_PUSH_PEER:-0}"
  PEER_IP="${PROBE_BAN_PEER_IP:-}"
  PEER_SSH_KEY="${PROBE_BAN_PEER_SSH_KEY:-/root/.ssh/probe-ban-sync}"
  PEER_SSH_HOST="${PROBE_BAN_PEER_SSH_HOST:-probe-ban-peer}"
}

is_valid_ipv4() {
  local ip="$1" a b c d
  [[ "$ip" =~ ^[0-9.]+$ ]] || return 1
  IFS=. read -r a b c d <<<"$ip"
  [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ && "$c" =~ ^[0-9]+$ && "$d" =~ ^[0-9]+$ ]] || return 1
  (( a <= 255 && b <= 255 && c <= 255 && d <= 255 )) || return 1
}

is_valid_ip() {
  [[ "$1" =~ ^[0-9a-fA-F:.]+$ ]]
}

ipv4_to_int() {
  local ip="$1" a b c d
  IFS=. read -r a b c d <<<"$ip"
  [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ && "$c" =~ ^[0-9]+$ && "$d" =~ ^[0-9]+$ ]] || return 1
  (( a <= 255 && b <= 255 && c <= 255 && d <= 255 )) || return 1
  echo $(( (a << 24) | (b << 16) | (c << 8) | d ))
}

ipv4_in_cidr() {
  local ip="$1" cidr="$2" network prefix ip_int network_int mask
  network="${cidr%/*}"
  prefix="${cidr#*/}"
  [[ "$prefix" =~ ^[0-9]+$ ]] && (( prefix >= 0 && prefix <= 32 )) || return 1
  ip_int="$(ipv4_to_int "$ip")" || return 1
  network_int="$(ipv4_to_int "$network")" || return 1
  if (( prefix == 0 )); then
    mask=0
  else
    mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
  fi
  (( (ip_int & mask) == (network_int & mask) ))
}

is_whitelisted_ip() {
  local ip="$1" entry cidr
  [[ "$ip" == "127.0.0.1" || "$ip" == "::1" ]] && return 0
  [[ -n "$PEER_IP" && "$ip" == "$PEER_IP" ]] && return 0
  if [[ -n "$WHITELIST_IPS" ]]; then
    IFS=',' read -ra entries <<<"$WHITELIST_IPS"
    for entry in "${entries[@]}"; do
      entry="$(echo "$entry" | xargs)"
      [[ -n "$entry" && "$ip" == "$entry" ]] && return 0
    done
  fi
  if [[ -n "$TRUSTED_CIDRS" ]]; then
    IFS=',' read -ra cidrs <<<"$TRUSTED_CIDRS"
    for cidr in "${cidrs[@]}"; do
      cidr="$(echo "$cidr" | xargs)"
      [[ -n "$cidr" ]] && ipv4_in_cidr "$ip" "$cidr" && return 0
    done
  fi
  return 1
}

ensure_state() {
  mkdir -p "$STATE_DIR"
  touch "$BANNED_TSV" "$BANNED_FILE" "$LOG_FILE" "$ACTION_LOG"
  load_env
  if [[ -s "$BANNED_FILE" && ! -s "$BANNED_TSV" ]]; then
    while IFS= read -r ip; do
      [[ -z "$ip" ]] && continue
      is_whitelisted_ip "$ip" && continue
      echo -e "${ip}\t$(date +%s)\t0\tlegacy" >>"$BANNED_TSV"
    done <"$BANNED_FILE"
  fi
  purge_whitelisted_bans
}

purge_whitelisted_bans() {
  local changed=0
  : >"${BANNED_TSV}.next"
  while IFS=$'\t' read -r ip banned_at expires path; do
    [[ -z "$ip" ]] && continue
    if is_whitelisted_ip "$ip"; then
      while ufw status numbered 2>/dev/null | grep -q "DENY IN.*${ip}"; do
        num="$(ufw status numbered 2>/dev/null | grep "DENY IN.*${ip}" | head -1 | sed -n 's/^\[\([0-9]*\)\].*/\1/p')"
        [[ -n "$num" ]] || break
        yes | ufw delete "$num" >/dev/null 2>&1 || break
      done
      echo "$(date -Is) removed whitelisted IP from ban list: $ip" >>"$ACTION_LOG"
      changed=1
      continue
    fi
    echo -e "${ip}\t${banned_at}\t${expires}\t${path}" >>"${BANNED_TSV}.next"
  done <"$BANNED_TSV"
  if [[ "$changed" == "1" ]]; then
    mv "${BANNED_TSV}.next" "$BANNED_TSV"
    rebuild_banned_txt
  else
    rm -f "${BANNED_TSV}.next"
  fi
}

epoch_expires() {
  local banned_at="$1"
  if [[ "$BAN_TTL_DAYS" == "0" ]]; then
    echo 0
    return
  fi
  echo $((banned_at + BAN_TTL_DAYS * 86400))
}

is_expired_row() {
  local expires="$1"
  [[ "$expires" != "0" && "$expires" -le "$(date +%s)" ]]
}

normalize_probe_path() {
  local raw="${1:-unknown}"
  if [[ "$raw" =~ ^(GET|POST|HEAD|PUT|DELETE|OPTIONS|PATCH)\ +([^[:space:]]+) ]]; then
    echo "${BASH_REMATCH[2]}"
    return
  fi
  echo "$raw"
}

ttl_label_fa() {
  if [[ "$BAN_TTL_DAYS" == "0" ]]; then
    echo "دائمی (تا حذف دستی)"
  else
    echo "${BAN_TTL_DAYS} روز"
  fi
}

format_ban_telegram() {
  local ip="$1" path="$2"
  local path_clean ttl now_human
  path_clean="$(normalize_probe_path "$path")"
  ttl="$(ttl_label_fa)"
  now_human="$(date '+%Y-%m-%d %H:%M %Z' 2>/dev/null || date -Is)"
  cat <<EOF
🛡 بن خودکار IP مهاجم

سرور: ${SERVER_LABEL}
آی‌پی مهاجم: ${ip}
مسیر مشکوک: ${path_clean}
مدت مسدودیت: ${ttl}
زمان شناسایی: ${now_human}

این IP به‌دلیل درخواست probe به مسیر غیرمجاز مسدود شد (UFW).
EOF
}

format_report_telegram() {
  local active="$1" events="$2"
  cat <<EOF
📊 گزارش روزانه probe-ban

سرور: ${SERVER_LABEL}
تعداد بن‌های فعال: ${active}
رویدادهای بن امروز: ${events}

جزئیات: probe-ban.sh --status
EOF
}

rebuild_banned_txt() {
  : >"$BANNED_FILE"
  while IFS=$'\t' read -r ip _ _ _; do
    [[ -n "$ip" ]] && echo "$ip" >>"$BANNED_FILE"
  done <"$BANNED_TSV"
}

row_exists() {
  local ip="$1"
  awk -F'\t' -v ip="$ip" '$1 == ip { found=1 } END { exit !found }' "$BANNED_TSV" 2>/dev/null
}

peer_ssh() {
  local cmd="$1"
  if [[ -f /root/.ssh/config ]] && grep -q "^Host ${PEER_SSH_HOST}" /root/.ssh/config 2>/dev/null; then
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$PEER_SSH_HOST" "$cmd"
  elif [[ -f "$PEER_SSH_KEY" ]]; then
    ssh -o BatchMode=yes -o ConnectTimeout=10 -i "$PEER_SSH_KEY" -o IdentitiesOnly=yes \
      -o StrictHostKeyChecking=accept-new "root@${PEER_IP}" "$cmd"
  else
    ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
      "root@${PEER_IP}" "$cmd"
  fi
}

merge_tsv_rows() {
  local src="$1" prefix="${2:-peer}"
  local imported=0
  while IFS=$'\t' read -r ip banned_at expires path; do
    [[ -z "$ip" ]] && continue
    is_whitelisted_ip "$ip" && continue
    is_expired_row "$expires" && continue
    row_exists "$ip" && continue
    if ! ufw_has_deny "$ip"; then
      ufw deny from "$ip" comment "probe-ban-${prefix}" >/dev/null 2>&1 || true
    fi
    echo -e "${ip}\t${banned_at}\t${expires}\t${prefix}:${path}" >>"$BANNED_TSV"
    imported=$((imported + 1))
  done <"$src"
  rebuild_banned_txt
  echo "$imported"
}

send_telegram() {
  local text="$1"
  [[ "$ALERT_TELEGRAM" == "1" ]] || return 0
  local token="" chat=""
  if [[ -f "$TELEGRAM_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$TELEGRAM_ENV"
    token="${TELEGRAM_BOT_TOKEN:-}"
    chat="${TELEGRAM_ALERT_CHAT_ID:-}"
  fi
  [[ -n "$token" && -n "$chat" ]] || return 0
  curl -sS --connect-timeout 8 --max-time 25 \
    -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    -d "chat_id=${chat}" \
    --data-urlencode "text=${text}" \
    -d "disable_web_page_preview=true" \
    >/dev/null 2>&1 || true
}

ufw_has_deny() {
  local ip="$1"
  ufw status numbered 2>/dev/null | grep -q "DENY IN.*${ip}"
}

ban_ip() {
  local ip="$1" path="${2:-unknown}" dry_run="${3:-0}"
  if is_whitelisted_ip "$ip" || ! is_valid_ip "$ip"; then
    return 0
  fi
  if row_exists "$ip"; then
    return 0
  fi
  local now expires
  now="$(date +%s)"
  expires="$(epoch_expires "$now")"
  if [[ "$dry_run" == "1" ]]; then
    echo "[dry-run] would ban $ip path=$path ttl_days=$BAN_TTL_DAYS"
    return 0
  fi
  if ! ufw_has_deny "$ip"; then
    ufw deny from "$ip" comment "probe-ban" >/dev/null 2>&1 || true
  fi
  echo -e "${ip}\t${now}\t${expires}\t${path}" >>"$BANNED_TSV"
  echo "$(date -Is) banning probe IP $ip path=$path server=$SERVER_LABEL" >>"$ACTION_LOG"
  send_telegram "$(format_ban_telegram "$ip" "$path")"
}

unban_ip() {
  local ip="$1"
  if ! row_exists "$ip"; then
    echo "IP not in ban list: $ip" >&2
    return 1
  fi
  awk -F'\t' -v ip="$ip" '$1 != ip { print }' "$BANNED_TSV" >"${BANNED_TSV}.tmp"
  mv "${BANNED_TSV}.tmp" "$BANNED_TSV"
  rebuild_banned_txt
  while ufw status numbered 2>/dev/null | grep -q "DENY IN.*${ip}"; do
    num="$(ufw status numbered 2>/dev/null | grep "DENY IN.*${ip}" | head -1 | sed -n 's/^\[\([0-9]*\)\].*/\1/p')"
    [[ -n "$num" ]] || break
    yes | ufw delete "$num" >/dev/null 2>&1 || break
  done
  echo "$(date -Is) unbanned $ip server=$SERVER_LABEL" >>"$ACTION_LOG"
  echo "Unbanned $ip"
}

expire_bans() {
  local now removed=0
  now="$(date +%s)"
  : >"${BANNED_TSV}.next"
  while IFS=$'\t' read -r ip banned_at expires path; do
    [[ -z "$ip" ]] && continue
    if [[ "$expires" != "0" && "$expires" -le "$now" ]]; then
      while ufw status numbered 2>/dev/null | grep -q "DENY IN.*${ip}"; do
        num="$(ufw status numbered 2>/dev/null | grep "DENY IN.*${ip}" | head -1 | sed -n 's/^\[\([0-9]*\)\].*/\1/p')"
        [[ -n "$num" ]] || break
        yes | ufw delete "$num" >/dev/null 2>&1 || break
      done
      echo "$(date -Is) expired ban $ip server=$SERVER_LABEL" >>"$ACTION_LOG"
      removed=$((removed + 1))
      continue
    fi
    echo -e "${ip}\t${banned_at}\t${expires}\t${path}" >>"${BANNED_TSV}.next"
  done <"$BANNED_TSV"
  mv "${BANNED_TSV}.next" "$BANNED_TSV"
  rebuild_banned_txt
  echo "Expired bans removed: $removed"
}

process_log() {
  local dry_run="${1:-0}"
  [[ "$AUTO_BAN" == "1" ]] || { echo "AUTO_BAN disabled"; return 0; }
  if ! command -v ufw >/dev/null 2>&1; then
    echo "ufw not installed — skip probe ban" >&2
    return 0
  fi

  local offset=0 file_size
  if [[ -f "$STATE_FILE" ]]; then
    offset="$(cat "$STATE_FILE" 2>/dev/null || echo 0)"
  fi
  file_size="$(wc -c <"$LOG_FILE" | tr -d ' ')"
  [[ "$offset" -gt "$file_size" ]] && offset=0
  [[ "$file_size" -le "$offset" ]] && return 0

  local new_bans=0
  while IFS= read -r line; do
    local ip path
    ip="${line%% *}"
    path="$(echo "$line" | awk -F'"' '{print $2}')"
    path="$(normalize_probe_path "$path")"
    [[ -z "$path" ]] && path="unknown"
    if [[ "$dry_run" == "1" ]]; then
      ban_ip "$ip" "$path" 1
    elif ! row_exists "$ip"; then
      ban_ip "$ip" "$path" 0
      new_bans=$((new_bans + 1))
    fi
  done < <(tail -c +"$((offset + 1))" "$LOG_FILE")

  [[ "$dry_run" == "0" ]] && { echo "$file_size" >"$STATE_FILE"; rebuild_banned_txt; }
  echo "Processed probe log (new_bans=$new_bans dry_run=$dry_run)"
}

sync_from_peer() {
  [[ "$SYNC_PEER" == "1" ]] || { echo "Peer sync disabled"; return 0; }
  [[ -n "$PEER_IP" ]] || { echo "PROBE_BAN_PEER_IP not set" >&2; return 1; }
  local remote_tsv
  remote_tsv="$(mktemp)"
  if ! peer_ssh "cat ${BANNED_TSV} 2>/dev/null || true" >"$remote_tsv" 2>/dev/null; then
    echo "Peer sync failed (SSH to $PEER_IP)" >&2
    rm -f "$remote_tsv"
    return 1
  fi
  local imported
  imported="$(merge_tsv_rows "$remote_tsv" "peer")"
  rm -f "$remote_tsv"
  echo "Imported $imported bans from peer $PEER_IP"
}

push_to_peer() {
  [[ "$PUSH_PEER" == "1" ]] || { echo "Peer push disabled"; return 0; }
  [[ -n "$PEER_IP" ]] || { echo "PROBE_BAN_PEER_IP not set" >&2; return 1; }
  local tmp="${STATE_DIR}/banned-ips.peer-import.tsv"
  if [[ -f /root/.ssh/config ]] && grep -q "^Host ${PEER_SSH_HOST}" /root/.ssh/config 2>/dev/null; then
    scp -o BatchMode=yes -o ConnectTimeout=10 "$BANNED_TSV" "${PEER_SSH_HOST}:${tmp}" >/dev/null 2>&1
    peer_ssh "${INSTALL_PATH} --import-peer ${tmp}" || return 1
  else
    scp -o BatchMode=yes -o ConnectTimeout=10 -i "$PEER_SSH_KEY" -o IdentitiesOnly=yes \
      "$BANNED_TSV" "root@${PEER_IP}:${tmp}" >/dev/null 2>&1
    peer_ssh "${INSTALL_PATH} --import-peer ${tmp}" || return 1
  fi
  echo "Pushed local ban list to peer $PEER_IP"
}

import_peer_file() {
  local file="$1"
  [[ -f "$file" ]] || { echo "Missing file: $file" >&2; return 1; }
  local imported
  imported="$(merge_tsv_rows "$file" "import")"
  echo "Imported $imported bans from $file"
}

print_status() {
  local active=0 expired=0
  echo "Probe ban security (${SERVER_LABEL})"
  echo "  env: $ENV_FILE"
  echo "  probe log: $LOG_FILE"
  echo "  banned tsv: $BANNED_TSV"
  echo "  whitelist: ${WHITELIST_IPS:-none}"
  echo "  trusted cidr: ${TRUSTED_CIDRS:-none}"
  echo "  ttl_days: $BAN_TTL_DAYS  auto_ban: $AUTO_BAN"
  while IFS=$'\t' read -r ip banned_at expires path; do
    [[ -z "$ip" ]] && continue
    if is_expired_row "$expires"; then
      expired=$((expired + 1))
    else
      active=$((active + 1))
      local exp_human="permanent"
      [[ "$expires" != "0" ]] && exp_human="$(date -d "@$expires" -Is 2>/dev/null || echo "$expires")"
      echo "  - $ip  expires=$exp_human  path=$path"
    fi
  done <"$BANNED_TSV"
  echo "Active: $active  Expired(pending cleanup): $expired"
  echo "UFW probe rules: $(ufw status numbered 2>/dev/null | grep -c 'probe-ban' || echo 0)"
}

print_report() {
  local day_prefix active new_lines report
  day_prefix="$(date +%Y-%m-%d)"
  active="$(awk -F'\t' 'NF && $1 != "" { c++ } END { print c+0 }' "$BANNED_TSV")"
  new_lines="$(grep -c "$day_prefix" "$ACTION_LOG" 2>/dev/null || echo 0)"
  report="$(format_report_telegram "$active" "$new_lines")"
  echo "$report"
  send_telegram "$report"
}

write_security_env() {
  local w_ips="$1" auto="$2" ttl="$3" cidrs="$4" log_path="$5" label="$6"
  mkdir -p /etc/probe-ban
  cat >"$ENV_FILE" <<EOF
# Generated by probe-ban.sh --wizard on $(date -Is)
PROBE_BAN_SERVER_LABEL=${label}
PROBE_BAN_WHITELIST_IPS=${w_ips}
PROBE_BAN_AUTO_BAN=${auto}
PROBE_BAN_TTL_DAYS=${ttl}
PROBE_BAN_TRUSTED_CIDRS=${cidrs}
PROBE_BAN_PROBE_LOG=${log_path}
PROBE_BAN_STATE_DIR=${DEFAULT_STATE}
PROBE_BAN_ALERT_TELEGRAM=0
PROBE_BAN_TELEGRAM_ENV=/etc/probe-ban/telegram.env
PROBE_BAN_SYNC_PEER=0
PROBE_BAN_PUSH_PEER=0
PROBE_BAN_BAN_CRON="*/5 * * * *"
PROBE_BAN_EXPIRE_CRON="15 4 * * *"
EOF
  chmod 600 "$ENV_FILE"
}

install_cron() {
  local cron_ban cron_expire
  cron_ban="${PROBE_BAN_BAN_CRON:-*/5 * * * *}"
  cron_expire="${PROBE_BAN_EXPIRE_CRON:-15 4 * * *}"
  {
    echo 'SHELL=/bin/bash'
    echo 'PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin'
    echo "${cron_ban} root ${INSTALL_PATH} run >>${DEFAULT_STATE}/probe-ban-cron.log 2>&1"
    echo "${cron_expire} root ${INSTALL_PATH} --expire >>${DEFAULT_STATE}/probe-ban-cron.log 2>&1"
  } >/etc/cron.d/probe-ban
  chmod 644 /etc/cron.d/probe-ban
}

install_self() {
  local src
  src="$(script_dir)/${SCRIPT_NAME}"
  [[ -f "$src" ]] || src="${BASH_SOURCE[0]}"
  install -m 755 -o root -g root "$src" "$INSTALL_PATH"
}

apply_wizard_config() {
  local w_ips="$1" auto="$2" ttl="$3" cidrs="$4" log_path="$5" label="$6"
  write_security_env "$w_ips" "$auto" "$ttl" "$cidrs" "$log_path" "$label"
  load_env
  mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")"
  touch "$BANNED_TSV" "$BANNED_FILE" "$LOG_FILE" "$ACTION_LOG"
  install_self
  install_cron
  if ! command -v ufw >/dev/null 2>&1; then
    warn "ufw نصب نیست. برای بن واقعی: apt install ufw"
  elif ufw status 2>/dev/null | grep -qi inactive; then
    warn "ufw غیرفعال است. برای اعمال بن: ufw enable"
  fi
}

wizard_setup() {
  local count i ip input_ips=() auto_val ttl_val use_cdn cidrs_val log_path label
  need_root
  banner
  info "ویزارد راه‌اندازی — ۶ سؤال. Enter = پیش‌فرض."
  nl

  stage 1 "وایت‌لیست IP"
  info "IPهایی که هرگز نباید بن شوند (سرور داخلی، مانیتورینگ، VPN)."
  count="$(ask_line "چند IP یا سرور وایت‌لیست دارید؟" "0")"
  [[ "$count" =~ ^[0-9]+$ ]] || die "تعداد باید عدد باشد."
  for ((i = 1; i <= count; i++)); do
    ip="$(ask_line "IP شماره ${i}")"
    is_valid_ipv4 "$ip" || die "IP نامعتبر: ${ip}"
    input_ips+=("$ip")
  done
  if ((${#input_ips[@]} > 0)); then
    WHITELIST_IPS=$(IFS=,; echo "${input_ips[*]}")
  else
    WHITELIST_IPS=""
  fi

  stage 2 "بن خودکار"
  if ask_yes "بن خودکار IP مهاجم فعال باشد؟" Y; then
    auto_val=1
  else
    auto_val=0
  fi

  stage 3 "مدت بن"
  ttl_val="$(ask_line "مدت بن (روز) — ۰ یعنی دائمی" "30")"
  [[ "$ttl_val" =~ ^[0-9]+$ ]] || die "مدت بن باید عدد باشد."

  stage 4 "CDN / reverse proxy"
  cidrs_val=""
  if ask_yes "از CDN یا reverse proxy جلوی سرور استفاده می‌کنید؟" N; then
    info "CIDRهای CDN را با کاما بده. مثال: 185.143.232.0/22,94.101.182.0/27"
    cidrs_val="$(ask_line "لیست CIDR (خالی = بعداً در env)" "")"
  fi

  stage 5 "مسیر لاگ probe"
  info "nginx باید درخواست‌های مشکوک را در این فایل بنویسد."
  log_path="$(ask_line "مسیر فایل لاگ probe" "$DEFAULT_LOG")"
  [[ -n "$log_path" ]] || die "مسیر لاگ خالی است."

  stage 6 "مرور نهایی"
  label="$(hostname -s 2>/dev/null || echo server)"
  box_top
  box_line "سرور          ${label}"
  box_line "وایت‌لیست     ${WHITELIST_IPS:-—}"
  box_line "بن خودکار     $([[ $auto_val -eq 1 ]] && echo بله || echo خیر)"
  box_line "مدت بن        $([[ $ttl_val -eq 0 ]] && echo دائمی || echo ${ttl_val} روز)"
  box_line "CDN CIDR      ${cidrs_val:-—}"
  box_line "لاگ probe     ${log_path}"
  box_line "env           ${ENV_FILE}"
  box_bottom
  nl
  ask_yes "با همین تنظیمات ذخیره و نصب شود؟" Y || die "لغو شد. چیزی روی سرور عوض نشد."

  nl
  printf '  %bدر حال ذخیره…%b\n' "$B$MAG" "$R"
  hr
  apply_wizard_config "$WHITELIST_IPS" "$auto_val" "$ttl_val" "$cidrs_val" "$log_path" "$label"
  banner
  ok "تنظیمات ذخیره شد: ${ENV_FILE}"
  ok "اسکریپت نصب شد: ${INSTALL_PATH}"
  ok "cron فعال شد: /etc/cron.d/probe-ban"
  nl
  info "وضعیت:  ${INSTALL_PATH} --status"
  info "تست:    ${INSTALL_PATH} --dry-run"
  info "آن‌بن:   ${INSTALL_PATH} --unban IP"
  nl
}

show_status_pretty() {
  banner
  load_env
  ensure_state
  printf '  %bوضعیت فعلی%b\n\n' "$WHT" "$R"
  print_status
  nl
}

menu() {
  need_root
  banner
  printf '  %b۱%b   راه‌اندازی / تنظیم دوباره (ویزارد)\n' "$CYN" "$R"
  printf '  %b۲%b   نمایش وضعیت بن‌ها\n' "$CYN" "$R"
  printf '  %b۳%b   تست dry-run (بدون بن واقعی)\n' "$CYN" "$R"
  printf '  %b۰%b   خروج\n\n' "$CYN" "$R"
  local choice
  choice="$(ask_line "انتخاب" "1")"
  case "$choice" in
    1) wizard_setup ;;
    2) show_status_pretty ;;
    3)
      load_env
      ensure_state
      process_log 1
      nl
      ;;
    0) nl; exit 0 ;;
    *) die "گزینه نامعتبر." ;;
  esac
}

main() {
  case "${1:-}" in
    --wizard|wizard) wizard_setup ;;
    --menu|menu) menu ;;
    --status) load_env; ensure_state; print_status ;;
    --dry-run) load_env; ensure_state; process_log 1 ;;
    --unban)
      [[ $# -ge 2 ]] || { echo "Usage: $0 --unban IP" >&2; exit 1; }
      load_env; ensure_state; unban_ip "$2"
      ;;
    --expire) load_env; ensure_state; expire_bans ;;
    --sync) load_env; ensure_state; sync_from_peer ;;
    --push) load_env; ensure_state; push_to_peer ;;
    --import-peer)
      [[ $# -ge 2 ]] || { echo "Usage: $0 --import-peer FILE" >&2; exit 1; }
      load_env; ensure_state; import_peer_file "$2"
      ;;
    --report) load_env; ensure_state; print_report ;;
    run)
      load_env; ensure_state
      exec 9>"$LOCK_FILE"
      if ! flock -n 9; then exit 0; fi
      process_log 0
      ;;
    -h|--help)
      cat <<EOF
Usage:
  ${SCRIPT_NAME}                 interactive menu (TTY) or process log (cron)
  ${SCRIPT_NAME} --wizard        setup wizard (6 questions)
  ${SCRIPT_NAME} run             process probe log (for cron)
  ${SCRIPT_NAME} --status        show ban list
  ${SCRIPT_NAME} --dry-run       show what would be banned
  ${SCRIPT_NAME} --unban IP      remove ban
  ${SCRIPT_NAME} --expire        remove expired bans
  ${SCRIPT_NAME} --sync          pull bans from peer
  ${SCRIPT_NAME} --push          push bans to peer
  ${SCRIPT_NAME} --report        daily report
EOF
      ;;
    "")
      if [[ -t 0 ]]; then
        menu
      else
        load_env
        ensure_state
        exec 9>"$LOCK_FILE"
        if ! flock -n 9; then exit 0; fi
        process_log 0
      fi
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
}

main "$@"
