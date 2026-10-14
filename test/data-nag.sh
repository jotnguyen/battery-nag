#!/bin/sh
# Scenario tests for openwrt/data-nag. No router or network needed: each step
# fakes the modem's byte counter (DATA_NAG_BYTES) and the clock (DATA_NAG_NOW),
# and runs `check` with DRY_RUN=1, so a push is printed instead of sent. Exit
# status is the number of failures.
#
#   sh test/data-nag.sh                               # the shell named sh
#   SH="busybox sh" busybox sh test/data-nag.sh       # BusyBox ash, as on the router
# SH may be two words ("busybox sh"), so it is left unquoted on purpose.
# shellcheck disable=SC2086
set -u
cd "$(dirname "$0")/.." || exit 1
SH="${SH:-sh}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
export DATA_NAG_STATE="${tmp}/state" DATA_NAG_CONF="${tmp}/conf" \
  DATA_NAG_BATTERY_CONF="${tmp}/battery-conf" TZ=UTC
fails=0
T0=1791918000 # 19:00 UTC

# run <minutes after T0> <counter MB> [env...]: one check; prints the dry-run lines.
run() {
  t=$((T0 + $1 * 60))
  b=$(($2 * 1000000))
  shift 2
  env DATA_NAG_NOW="${t}" DATA_NAG_BYTES="${b}" DATA_NAG_WIFI="${WIFI:-0}" DRY_RUN=1 "$@" \
    ${SH} openwrt/data-nag check 2>/dev/null
}

# nag <minutes> <counter MB> [env...]: print "p<priority> <title>" or "-".
nag() {
  out="$(run "$@" | sed -n 's/^DRY RUN push \(p[0-9]\): \([^:]*\):.*/\1 \2/p')"
  echo "${out:--}"
}

# step <minutes> <counter MB> <expected> [why]
step() {
  got="$(nag "$1" "$2")"
  if [ "${got}" = "$3" ]; then
    echo "ok   +$1m ${2}MB -> $3${4:+  ($4)}"
  else
    echo "FAIL +$1m ${2}MB: want '$3', got '${got}'${4:+  ($4)}"
    fails=$((fails + 1))
  fi
}

# expect <label> <command...>: pass when the command succeeds.
expect() {
  label="$1"
  shift
  if "$@"; then
    echo "ok   ${label}"
  else
    echo "FAIL ${label}"
    fails=$((fails + 1))
  fi
}

# has <text> <needle>: true when the text contains the needle (called through expect).
# shellcheck disable=SC2317,SC2329
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

echo "== a push every 500 MB, urgent from 2 GB, a day starting at noon"
printf 'DEVICE_NAME=Puli\n' >"${DATA_NAG_CONF}"
step 0 5000 - "first run: counts from here, not from boot"
step 2 5400 -
step 4 5500 "p0 Puli cellular 500 MB"
step 6 5900 - "already pushed for 500 MB"
step 8 6000 "p0 Puli cellular 1.0 GB"
step 10 7600 "p1 Puli cellular 2.6 GB" "past 1.5, 2 and 2.5 GB at once: one push, urgent"
step 12 300 - "counter went back (modem reset): its 300 MB are added"
step 14 400 "p1 Puli cellular 3.0 GB"
step 302 900 "p1 Puli cellular 3.5 GB" "past midnight: the same night, the same count"
step 1022 1000 - "past noon: a new day, 100 MB so far"
step 1024 1500 "p0 Puli cellular 600 MB"

echo "== the push says how fast and whether Wi-Fi is up"
rm -f "${DATA_NAG_STATE}"
run 0 0 >/dev/null
msg="$(run 2 600)"
expect "rate in the message" has "${msg}" "Now 40 Mbit/s"
expect "Wi-Fi off in the message" has "${msg}" "all traffic is on the SIM"
msg="$(WIFI=1 run 4 1100)"
expect "Wi-Fi up in the message" has "${msg}" "Wi-Fi uplink is up"

echo "== no modem device: nothing counted, and the count carries on after"
rm -f "${DATA_NAG_STATE}"
step 0 100 -
got="$(env DATA_NAG_NOW=$((T0 + 120)) DATA_NAG_BYTES=none DRY_RUN=1 ${SH} openwrt/data-nag check 2>&1)"
expect "missing device -> no push" [ -z "${got}" ]
step 4 650 "p0 Puli cellular 550 MB"

echo "== a failed push is not recorded, so the next run retries it"
rm -f "${DATA_NAG_STATE}"
printf 'DEVICE_NAME=Puli\nPUSHOVER_USER=u\nPUSHOVER_TOKEN=t\nPUSHOVER_URL=http://127.0.0.1:9/\n' >"${DATA_NAG_CONF}"
run 0 0 >/dev/null
DATA_NAG_NOW=$((T0 + 120)) DATA_NAG_BYTES=700000000 DATA_NAG_WIFI=0 ${SH} openwrt/data-nag check 2>/dev/null
step 4 700 "p0 Puli cellular 700 MB" "retried"

echo "== keys from battery-nag's config; without any keys check pushes nothing"
rm -f "${DATA_NAG_STATE}"
printf 'DEVICE_NAME=Puli\n' >"${DATA_NAG_CONF}"
printf 'PUSHOVER_USER=u\nPUSHOVER_TOKEN=t\n' >"${DATA_NAG_BATTERY_CONF}"
expect "battery-nag keys found" sh -c "DATA_NAG_WIFI=0 ${SH} openwrt/data-nag status | grep -q 'keys set'"
rm -f "${DATA_NAG_BATTERY_CONF}"
DATA_NAG_NOW=${T0} DATA_NAG_BYTES=0 ${SH} openwrt/data-nag check 2>/dev/null
DATA_NAG_NOW=$((T0 + 120)) DATA_NAG_BYTES=900000000 DATA_NAG_WIFI=0 ${SH} openwrt/data-nag check 2>/dev/null
expect "no keys -> nothing recorded as pushed, usage counted" \
  sh -c "grep -qx 'pushed=0' '${DATA_NAG_STATE}' && grep -qx 'used=900000000' '${DATA_NAG_STATE}'"

echo "== reset, and custom steps"
DATA_NAG_NOW=$((T0 + 240)) ${SH} openwrt/data-nag reset >/dev/null
expect "reset zeroes the count" grep -qx 'used=0' "${DATA_NAG_STATE}"
printf 'DEVICE_NAME=Puli\nSTEP_MB=100\nURGENT_MB=\n' >"${DATA_NAG_CONF}"
step 6 950 - "50 MB since the reset"
step 8 1000 "p0 Puli cellular 100 MB"
step 10 3000 "p0 Puli cellular 2.1 GB" "URGENT_MB empty: never urgent"

echo
if [ "${fails}" -eq 0 ]; then echo "all ok"; else echo "${fails} failed"; fi
exit "${fails}"
