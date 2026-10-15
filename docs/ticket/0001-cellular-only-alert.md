# 0001: data-nag: push when cellular has been the only uplink for a while

Status: open
Priority: lowest. The owner ranked it below every other open ticket on 2026-10-15. Do 0002, 0003 and 0004 first; this one is not urgent.

## Why

On GL.iNet 4.x, disconnecting the repeater by hand in the admin panel is sticky. It stays off
even when the saved network is in range, and cellular carries everything from then on. data-nag
only speaks after 250 MB. At light use the SIM can carry a router's traffic for days before that,
and at heavy use the first push already means 250 MB is gone.

## What

- A new config value, `CELL_ONLY_MIN` (default 15). When cellular is up, the Wi-Fi uplink
  (repeater) is down, and that has lasted `CELL_ONLY_MIN` minutes, push once: "Router on
  cellular only for 15 min (40 MB). Reconnect the repeater if a Wi-Fi network is in range."
- Re-arm when the repeater is up again.
- "Cellular up" = the modem device has an IPv4 address, which data-nag already reads (`cell_ip`).
  See the hand-off below; no new uci or ubus parsing is needed.
- Optional, off by default: `CELL_ONLY_REPEAT_MIN` to push again every N minutes while it lasts.

## Acceptance

- Scenario tests: cellular-only for 14 min → nothing; 16 min → one push; repeater back → re-arm;
  both uplinks up (failover idle) → nothing.
- On a real router: disconnect the repeater in the admin panel; a push arrives within
  `CELL_ONLY_MIN` + 2 minutes.

## Not doing

Reconnecting the repeater automatically. Which network to rejoin, and whether its portal needs
accepting, is the owner's call.

## Hand-off for the next agent (2026-10-15)

Pick this up only after the other open tickets; it is the lowest priority.

**Read first:** `docs/data-nag.md`, then `openwrt/data-nag`: `check()`, `alert()`, `wifi_up()`,
`cell_ip()`, `load_state()`/`save_state()`. Then `test/data-nag.sh` to see how scenarios fake
the router.

**Simplest design (use this, not the uci parsing sketched above):**

- "Cellular is up" = `cell_ip` is non-empty. On GL.iNet 4.x the modem device (`wwan0`) has an
  IPv4 address only while the cellular interface is connected. It is empty when cellular is
  disabled, which is how this router sits by default. Tests already fake it with
  `DATA_NAG_CELL_IP`, and the Wi-Fi uplink with `DATA_NAG_WIFI`.
- Two new state values in `load_state`/`save_state`: `solo_since` (epoch when cellular-up and
  Wi-Fi-down was first seen, empty otherwise) and `solo_pushed` (0/1).
- In `check()`, after `read_bytes` succeeds and independent of `delta` (light use must still
  alert): if cellular is up and `wifi_up` is false, set `solo_since` if empty; once
  `t - solo_since >= CELL_ONLY_MIN * 60` and `solo_pushed = 0`, push. Priority 0 by day, and
  priority 1 between 22:00 and 07:00 local (`CELL_ONLY_URGENT_HOURS="22 7"`): this tends to
  start in the evening, and Pushover quiet hours would hold a priority-0 push until morning:
  "<name> on cellular only for <n> min (<mb used>). Reconnect the repeater if a Wi-Fi network is
  in range." Set `solo_pushed=1` only if the push succeeded. Otherwise clear both.
- `CELL_ONLY_MIN=15` in the defaults and in `write_conf`'s commented config; empty turns it off.
- Docs: a row in the "What a push looks like" table of `docs/data-nag.md`, and in the README
  index row for data-nag.

**Tests to add** to `test/data-nag.sh` (dash and BusyBox, both must pass): 14 min solo → no push;
16 min → one push; still solo at 30 min → no second push; Wi-Fi back → re-armed, so a new solo
spell pushes again; both up → nothing; cellular down → nothing; a failed push is retried; a spell
starting at 23:00 pushes at priority 1, one at 14:00 at priority 0.

**Rules that bite here:**

- `bash scripts/hygiene.sh` must print `hygiene-ok`. No literal IP addresses in tests (build them
  from parts, as the conntrack scenarios do), no ICCID or other SIM identifiers anywhere.
- BusyBox awk reads `out (x)` as a function call; use a separator variable. CI's shellcheck is
  older than the one on the VM, so a disable may need both codes (SC2317,SC2329).
- The owner's merge rule: a personal-info scan of the diff and commit messages, plus an
  adversarial review (`/code-review <PR url> high`), with findings fixed, before any merge.

**Deploying to the owner's router** (GL-XE300 at `192.168.8.1`, root, key auth, laptop on its Wi-Fi):

1. Back up first: `ssh root@192.168.8.1 'sysupgrade -b /tmp/b.tgz && cat /tmp/b.tgz && rm /tmp/b.tgz' > <private repo>/backup/xe300-sysupgrade-backup-<date>-before-<change>.tar.gz`.
   Never into this repo.
2. Keep the old script on the router (`cp /usr/bin/data-nag /root/data-nag.bak-<date>`), then
   `scp -O openwrt/data-nag root@192.168.8.1:/tmp/data-nag.new` (`-O`: no SFTP server),
   `sh -n` it, and move it to `/usr/bin/data-nag`.
3. On-target tests: `git archive HEAD openwrt test | ssh root@192.168.8.1 'mkdir /tmp/t && cd /tmp/t && tar xf - && sh test/run.sh && sh test/data-nag.sh; cd /; rm -rf /tmp/t'`.
4. Set `CELL_ONLY_MIN=15` in `/etc/data-nag.conf`, run `data-nag status`, and record what changed
   (old and new md5, config lines) in the private repo's `SESSION-NOTES.md`. That repo's
   ticket 0006 tracks this router's side.
5. After merge, check the router's md5 matches `git show origin/main:openwrt/data-nag | md5sum`.
