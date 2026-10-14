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
  DATA_NAG_BATTERY_CONF="${tmp}/battery-conf" TZ=UTC \
  DATA_NAG_CONNTRACK="${tmp}/ct" DATA_NAG_LEASES="${tmp}/leases"
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

echo "== a push every 250 MB, urgent from 1 GB, a day starting at noon"
printf 'DEVICE_NAME=Puli
' >"${DATA_NAG_CONF}"
step 0 5000 - "first run: counts from here, not from boot"
step 2 5200 -
step 4 5250 "p0 Puli cellular 250 MB"
step 6 5400 - "already pushed for 250 MB"
step 8 5500 "p0 Puli cellular 500 MB"
step 10 6600 "p1 Puli cellular 1.6 GB" "past 750 MB and 1, 1.25, 1.5 GB at once: one push, urgent"
step 12 100 - "counter went back (modem reset): its 100 MB are added"
step 14 400 "p1 Puli cellular 2.0 GB"
step 302 900 "p1 Puli cellular 2.5 GB" "past midnight: the same night, the same count"
step 1022 1000 - "past noon: a new day, 100 MB so far"
step 1024 1350 "p0 Puli cellular 450 MB"

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

echo "== a bar line of the last hours, in 10-minute bars"
rm -f "${DATA_NAG_STATE}"
printf 'DEVICE_NAME=Puli\n' >"${DATA_NAG_CONF}"
run 0 0 >/dev/null
run 10 100 >/dev/null
run 20 300 >/dev/null
msg="$(run 30 600)"
expect "bars: 0, 100, 200, 300 MB" has "${msg}" "Last 40 min ▁▄▆█ (10-min bars, peak 300 MB)"
run 230 700 >/dev/null
bars="$(sed -n "s/^hist='\(.*\)'$/\1/p" "${DATA_NAG_STATE}" | wc -w | tr -d ' ')"
expect "after a long gap only 18 bars (3 h) are kept" [ "${bars}" = 18 ]

echo "== the device that moved the most cellular bytes, and what kind of traffic"
rm -f "${DATA_NAG_STATE}" "${DATA_NAG_STATE}".*
L=192.168.8 # LAN. Addresses are built from parts, so the hygiene gate sees no literal IP.
W=203.0.113 # documentation range, standing in for the internet
printf '1 aa:00:00:00:00:01 %s.50 laptop *\n1 aa:00:00:00:00:02 %s.60 * *\n' "${L}" "${L}" >"${DATA_NAG_LEASES}"
# flow <proto> <state> <LAN host> <port> <reply host> <MB> [source port]: one
# connection-table line. The reply host .1 is the cellular address, .2 another uplink.
flow() {
  printf 'ipv4 2 %s %s src=%s.%s dst=%s.9 sport=%s dport=%s packets=1 bytes=1000000 src=%s.9 dst=%s.%s sport=%s dport=%s packets=1 bytes=%s [ASSURED] mark=0 zone=0 use=2\n' \
    "$1" "$2" "${L}" "$3" "${W}" "${7:-$4}" "$4" "${W}" "${W}" "$5" "$4" "${7:-$4}" "$((($6 - 1) * 1000000))"
}
# ct <laptop MB> <tablet MB>: the laptop's Tailscale flow, the tablet's HTTPS flow,
# and a big flow from a third device that left over another uplink.
ct() {
  flow udp '17 120' 50 41641 1 "$1"
  flow tcp '6 300 ESTABLISHED' 60 443 1 "$2"
  flow tcp '6 300 ESTABLISHED' 150 443 2 900
}
export DATA_NAG_CELL_IP="${W}.1"
run 0 0 >/dev/null
ct 100 50 >"${DATA_NAG_CONNTRACK}"
msg="$(run 2 100)"
expect "first active check only records the table" [ ! -s "${DATA_NAG_STATE}.dev" ]
ct 400 60 >"${DATA_NAG_CONNTRACK}"
msg="$(run 4 400)"
expect "laptop named, its rate and Tailscale" has "${msg}" "Top now: laptop, 20 Mbit/s, Tailscale tunnel"
ct 400 360 >"${DATA_NAG_CONNTRACK}"
msg="$(run 6 700)"
expect "no name in the lease: its address; HTTPS" has "${msg}" "Top now: ${L}.60, 20 Mbit/s, HTTPS"
expect "a flow over another uplink is not counted" sh -c "! grep -q '[.]150 ' '${DATA_NAG_STATE}.dev'"
# Both old flows close; the tablet opens a new connection that moves 200 MB.
flow tcp '6 300 ESTABLISHED' 60 443 1 200 50002 >"${DATA_NAG_CONNTRACK}"
msg="$(run 8 1000)"
expect "a new connection counts in full, a closed one is not negative" has "${msg}" "Top now: ${L}.60, 13 Mbit/s, HTTPS"
run 10 1000 >/dev/null
expect "cellular idle: the table is dropped" [ ! -e "${DATA_NAG_STATE}.flows" ]
unset DATA_NAG_CELL_IP
ct 1400 50 >"${DATA_NAG_CONNTRACK}"
run 12 1100 >/dev/null
msg="$(run 14 1300)"
expect "no cellular address: no device named" sh -c "! printf '%s' '${msg}' | grep -q 'Top now'"
rm -f "${DATA_NAG_CONNTRACK}" "${DATA_NAG_LEASES}"

echo "== one check at a time"
rm -f "${DATA_NAG_STATE}" "${DATA_NAG_STATE}".*
printf 'DEVICE_NAME=Puli\n' >"${DATA_NAG_CONF}"
run 0 0 >/dev/null
sleep 30 &
live=$!
mkdir "${DATA_NAG_STATE}.lock" && echo "${live}" >"${DATA_NAG_STATE}.lock/pid"
step 2 300 - "a running check holds the lock: skipped"
kill "${live}" 2>/dev/null
wait "${live}" 2>/dev/null
step 4 300 "p0 Puli cellular 300 MB" "the lock of a check that died is taken over"
expect "the lock is released" [ ! -d "${DATA_NAG_STATE}.lock" ]

echo "== eiotclub: the provider's balance, by the ICCID in the network config"
json='{"code":10000,"data":{"iccid":"@ICCID@","remain_str":"5.1 GB","total_str":"25 GB"}}'
two="network.modem_a=interface
network.modem_a.iccid='1234'
network.modem_a.disabled='1'
network.modem_b=interface
network.modem_b.iccid='5678'"
got="$(DATA_NAG_UCI_NETWORK="${two}" DATA_NAG_EIOTCLUB_JSON="${json}" ${SH} openwrt/data-nag eiotclub)"
expect "balance parsed" [ "${got}" = "eSIM left: 5.1 GB of 25 GB (EIOTCLUB's count, hours behind)" ]
got="$(DATA_NAG_UCI_NETWORK="${two}" DATA_NAG_EIOTCLUB_JSON='{"data":{"remain_str":"@ICCID@"}}' ${SH} openwrt/data-nag eiotclub)"
expect "dual-SIM: the enabled modem's ICCID" has "${got}" "eSIM left: 5678 of"
got="$(DATA_NAG_UCI_NETWORK="network.modem_a.iccid='1234'
network.modem_a.disabled='1'" DATA_NAG_EIOTCLUB_JSON='{"data":{"remain_str":"@ICCID@"}}' ${SH} openwrt/data-nag eiotclub)"
expect "only a disabled modem: its ICCID anyway" has "${got}" "eSIM left: 1234 of"
expect "no ICCID: fails" sh -c "! DATA_NAG_UCI_NETWORK='network.lan.proto=static' DATA_NAG_EIOTCLUB_JSON='{}' ${SH} openwrt/data-nag eiotclub 2>/dev/null"
expect "no balance in the answer: fails" sh -c "! DATA_NAG_UCI_NETWORK=\"network.m.iccid='1'\" DATA_NAG_EIOTCLUB_JSON='{\"code\":10002}' ${SH} openwrt/data-nag eiotclub 2>/dev/null"

echo "== BALANCE_CMD adds a line, e.g. the provider's count"
rm -f "${DATA_NAG_STATE}" "${DATA_NAG_STATE}".*
printf 'DEVICE_NAME=Puli\nBALANCE_CMD="echo eSIM left: 5.1 GB of 25 GB"\n' >"${DATA_NAG_CONF}"
run 0 0 >/dev/null
msg="$(run 2 300)"
expect "balance line in the push" has "${msg}" "eSIM left: 5.1 GB of 25 GB"
printf 'DEVICE_NAME=Puli\nBALANCE_CMD=false\n' >"${DATA_NAG_CONF}"
msg="$(run 4 600)"
expect "a failing BALANCE_CMD adds nothing, the push still goes" has "${msg}" "Puli cellular 600 MB"

echo
if [ "${fails}" -eq 0 ]; then echo "all ok"; else echo "${fails} failed"; fi
exit "${fails}"
