#!/bin/sh
# Scenario tests for openwrt/battery-nag. No router or network needed: each step
# fakes a battery reading (BATTERY_NAG_READING) and runs `check` with DRY_RUN=1,
# so a push is printed instead of sent. Exit status is the number of failures.
#
#   sh test/run.sh                                    # the shell named sh
#   SH="busybox sh" busybox sh test/run.sh            # BusyBox ash, as on the router
# SH may be two words ("busybox sh"), so it is left unquoted on purpose.
# shellcheck disable=SC2086
set -u
cd "$(dirname "$0")/.." || exit 1
SH="${SH:-sh}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
export BATTERY_NAG_STATE="${tmp}/state" BATTERY_NAG_CONF="${tmp}/conf"
fails=0

# nag <percent> <plugged> [env...]: run one check, print "p<priority> <title>" or "-".
nag() {
  reading="$1 $2"
  shift 2
  out="$(env BATTERY_NAG_READING="${reading}" DRY_RUN=1 "$@" ${SH} openwrt/battery-nag check 2>/dev/null \
    | sed -n 's/^DRY RUN push \(p[0-9]\): \([^:]*\):.*/\1 \2/p')"
  echo "${out:--}"
}

# step <percent> <plugged> <expected> [why]
step() {
  got="$(nag "$1" "$2")"
  if [ "${got}" = "$3" ]; then
    echo "ok   $1% plugged=$2 -> $3${4:+  ($4)}"
  else
    echo "FAIL $1% plugged=$2: want '$3', got '${got}'${4:+  ($4)}"
    fails=$((fails + 1))
  fi
}

echo "== low and full alerts, defaults (low 20 10, full 100, gap 5)"
printf 'DEVICE_NAME=Puli\n' >"${BATTERY_NAG_CONF}"
step 50 0 -
step 21 0 -
step 20 0 "p0 Puli battery 20%"
step 19 0 - "already pushed"
step 21 0 - "wobble: no re-arm under 25"
step 20 0 -
step 10 0 "p1 Puli battery 10%" "the last threshold is urgent"
step 5 0 -
step 6 1 - "plugged in: no low alert while charging"
step 24 1 -
step 25 1 - "re-armed at 20 + 5"
step 20 0 "p0 Puli battery 20%"
step 30 1 -
step 9 0 "p1 Puli battery 9%" "skipped past 20 and 10: one push, the urgent one"
step 99 1 -
step 100 1 "p0 Puli charged 100%"
step 100 1 - "already pushed"
step 100 0 - "unplugged at full: nothing"
step 96 1 -
step 100 1 - "no re-arm above 95"
step 95 0 -
step 100 1 "p0 Puli charged 100%" "re-armed at 100 - 5"

echo "== a failed push is not recorded, so the next run retries it"
rm -f "${BATTERY_NAG_STATE}"
printf 'DEVICE_NAME=Puli\nPUSHOVER_USER=u\nPUSHOVER_TOKEN=t\nPUSHOVER_URL=http://127.0.0.1:9/\n' >"${BATTERY_NAG_CONF}"
BATTERY_NAG_READING="15 0" ${SH} openwrt/battery-nag check 2>/dev/null
step 15 0 "p0 Puli battery 15%" "retried"

echo "== not configured: check pushes nothing, but records that it ran"
rm -f "${BATTERY_NAG_STATE}"
printf 'DEVICE_NAME=Puli\n' >"${BATTERY_NAG_CONF}"
BATTERY_NAG_READING="15 0" ${SH} openwrt/battery-nag check 2>/dev/null
if grep -qx 'low=' "${BATTERY_NAG_STATE}" && grep -qx 'full=0' "${BATTERY_NAG_STATE}" \
  && grep -qE '^checked=[0-9]+$' "${BATTERY_NAG_STATE}"; then
  echo "ok   no keys -> no alert recorded, check time recorded"
else
  echo "FAIL state without keys: $(tr '\n' ' ' <"${BATTERY_NAG_STATE}" 2>/dev/null)"
  fails=$((fails + 1))
fi

echo "== config: full alert off, custom thresholds"
rm -f "${BATTERY_NAG_STATE}"
printf 'DEVICE_NAME=Puli\nFULL_PERCENT=\nLOW_PERCENTS="30 15 5"\n' >"${BATTERY_NAG_CONF}"
step 100 1 - "FULL_PERCENT empty"
step 30 0 "p0 Puli battery 30%"
step 15 0 "p0 Puli battery 15%"
step 5 0 "p1 Puli battery 5%"

echo "== a bad reading pushes nothing and fails"
if BATTERY_NAG_READING="abc 0" DRY_RUN=1 ${SH} openwrt/battery-nag check 2>/dev/null; then
  echo "FAIL a bad reading exited 0"
  fails=$((fails + 1))
else
  echo "ok   bad reading -> exit 1"
fi

echo
if [ "${fails}" -eq 0 ]; then echo "all ok"; else echo "${fails} failed"; fi
exit "${fails}"
