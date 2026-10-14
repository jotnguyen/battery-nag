# 0001: data-nag: push when cellular has been the only uplink for a while

Status: open
Priority: high (the root cause of the incident that started data-nag)

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
- "Cellular up" = `ubus call network.interface.<modem iface> status` reports `up: true`. Find the
  interface from `uci show network` (the `proto=qcm|qmi|mbim` section), the way `eiotclub` finds
  the ICCID.
- Optional, off by default: `CELL_ONLY_REPEAT_MIN` to push again every N minutes while it lasts.

## Acceptance

- Scenario tests: cellular-only for 14 min → nothing; 16 min → one push; repeater back → re-arm;
  both uplinks up (failover idle) → nothing.
- On a real router: disconnect the repeater in the admin panel; a push arrives within
  `CELL_ONLY_MIN` + 2 minutes.

## Not doing

Reconnecting the repeater automatically. Which network to rejoin, and whether its portal needs
accepting, is the owner's call.
