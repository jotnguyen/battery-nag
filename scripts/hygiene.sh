#!/usr/bin/env bash
# Hygiene gate for this public repo. Fails (exit 1) if content or a commit message
# holds something personal or secret: a private key, a GitHub or Tailscale token,
# a filled-in Pushover key, a long digit run (SIM ICCID/IMSI, IMEI, phone number),
# an IPv4 address other than GL.iNet's default 192.168.8.1 and loopback, a
# Tailscale node address, a Windows profile path, a personal email address, or an
# AI attribution trailer.
#
#   bash scripts/hygiene.sh              # the tracked tree (CI)
#   bash scripts/hygiene.sh --cached     # staged content (.githooks/pre-commit)
#   bash scripts/hygiene.sh --msg FILE   # a commit message (.githooks/commit-msg)
#
# It skips itself, because it holds the patterns as literals.
set -euo pipefail

mode=tree
msg_file=
case "${1:-}" in
  --cached) mode=cached ;;
  --msg)
    mode=msg
    # Resolve before the cd below: git passes a path relative to the worktree.
    msg_file="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
    ;;
esac
cd "$(dirname "$0")/.."
fail=0

# scan <grep flag> <ERE>: file:line hits in the tree, the index, or the message.
scan() {
  case "${mode}" in
    msg) grep -v '^#' "${msg_file}" | grep -n "$1" -E "$2" || true ;;
    cached) git grep --cached -n "$1" -E "$2" -- . ':!scripts/hygiene.sh' || true ;;
    *) git grep -n "$1" -E "$2" -- . ':!scripts/hygiene.sh' || true ;;
  esac
}

# report <label> <hits>
report() {
  [ -z "$2" ] && return 0
  echo "$1:"
  echo "$2"
  fail=1
}

report "SECRET (remove it)" "$(scan -I 'BEGIN [A-Z ]*PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|tskey-[a-z]+-[A-Za-z0-9]{8,}|PUSHOVER_(USER|TOKEN)=["'"'"']?[A-Za-z0-9]{8,}')"
report "LONG NUMBER: ICCID, IMSI, IMEI or phone? (remove it)" "$(scan -I '(^|[^0-9A-Za-z])[0-9]{11,}([^0-9A-Za-z]|$)')"
report "IP ADDRESS (only 192.168.8.1 and loopback; use <ip> otherwise)" \
  "$(scan -o '(^|[^0-9.])[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}([^0-9.]|$)' \
    | grep -vE ':[^0-9]?(192\.168\.8\.1|127\.0\.0\.1|0\.0\.0\.0)[^0-9]?$' || true)"
report "TAILSCALE ADDRESS (use <tailscale-ip>)" "$(scan -I 'fd7a:115c:a1e0:[0-9a-f:]*[0-9a-f]')"
report 'WINDOWS PROFILE PATH (use %USERPROFILE%)' "$(scan -i '[a-z]:[\\/]+users[\\/]+[a-z0-9._-]|c--users-[a-z0-9]')"
report "PERSONAL EMAIL (use you@example.com)" \
  "$(scan -i '[a-z0-9._%+-]+@(gmail|googlemail|icloud|me|mac|outlook|hotmail|live|msn|yahoo|aol|proton|protonmail|pm)\.(com|me|net)')"

attribution='^(Co-Authored-By: Claude|Claude-Session:)|Generated with \[?Claude Code'
if [ "${mode}" = msg ]; then
  grep -v '^#' "${msg_file}" | grep -qiE "${attribution}" \
    && report "ATTRIBUTION TRAILER in the commit message" "(remove the trailer)"
elif [ "${mode}" = tree ] && git log -1 --format=%B 2>/dev/null | grep -qiE "${attribution}"; then
  report "ATTRIBUTION TRAILER in the HEAD commit message" "(reword the commit)"
fi

[ "${fail}" -eq 0 ] && echo "hygiene-ok"
exit "${fail}"
