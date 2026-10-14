# 0003: data-nag: per-device totals for the day (`data-nag report`)

Status: open
Priority: medium

## Why

"Top now" names the busiest device at push time. After a bad night, the question is "who used
the 9 GB". data-nag already computes per-connection byte deltas every 2 minutes; it throws
them away after picking the top device.

## What

- Add each check's per-device deltas into a day table in `/tmp` (address, bytes, bytes per kind),
  reset with the day at `RESET_HOUR`.
- `data-nag report`: the day's table, named from the leases, largest first:
  `laptop 6.1 GB (HTTP 4.8, Tailscale 1.3); 192.168.8.x 0.9 GB (QUIC)`.
- The step push adds "Today so far: laptop 6.1 GB, phone 0.9 GB" once there are two or more
  devices.
- Known gap: bytes on a connection that closes between two checks are missed. If that turns out
  large (compare the day total against the modem counter in `report`), consider reading
  `conntrack -E` events instead (needs the `conntrack` tool, which GL.iNet 4.x ships).

## Acceptance

- Scenario tests: two devices over several checks; a day rollover clears the table; `report` sums
  match the per-check deltas.
- `report` shows how much of the modem's count it accounts for ("covers 93% of 6.5 GB").
