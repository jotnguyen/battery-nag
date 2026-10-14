# data-nag: cellular data alert

A GL.iNet router with a SIM falls back to cellular when its Wi-Fi uplink
(repeater) drops or is switched off, and it says nothing about it. A video left
playing overnight then runs over the SIM. On a travel eSIM that is gigabytes
gone before morning. data-nag pushes to your phone at every 500 MB of cellular
data in a day, and the pushes turn urgent from 2 GB so they get through
Pushover's quiet hours, which is when a forgotten stream runs.

It runs on the router from the same cron as battery-nag and uses battery-nag's
Pushover keys if they are there.

## What it sends

| When | Push |
|---|---|
| 500 MB, 1 GB, 1.5 GB of cellular data in the day | **Router cellular 500 MB** 500 MB of cellular data since 12:00. Now 18 Mbit/s: something is streaming or downloading. Wi-Fi uplink is off: all traffic is on the SIM. |
| 2 GB, 2.5 GB, 3 GB, ... | The same push, urgent (Pushover priority 1: it sounds during quiet hours) |

The rate part only appears when the last 2 minutes ran at 1 Mbit/s or more.
The Wi-Fi part says whether the repeater uplink is up. If the router is on the
SIM because the repeater is off, that's the thing to fix.

A jump past several steps between two checks pushes once. The step, the urgent
mark and the reset hour are all set in `/etc/data-nag.conf`.

## How it counts

- **Where the bytes come from.** The kernel's counters for the modem's network
  device: `/sys/class/net/wwan0/statistics/rx_bytes` plus `tx_bytes`. On GL.iNet
  routers with a built-in Quectel modem that device is `wwan0`. (GL.iNet calls the
  Wi-Fi repeater interface `wwan`, which isn't the same thing.) These are the
  bytes that went over the SIM, both ways, which is what a carrier bills.
- **Every 2 minutes** cron runs `data-nag check`. It adds the bytes since the last
  check to the day's count. If the counter went backwards (a reboot, or the modem
  was reset and its device recreated), it adds what the new counter holds.
- **The day starts at noon** (`RESET_HOUR=12`), not midnight. A stream that runs
  from 23:00 to 07:00 is one night's count, not two halves that each stay under
  the alert.
- **Install counts from zero.** The first check after install, or after a reboot
  clears `/tmp`, starts from the counter's current value. Only data used from
  then on counts.
- **Nothing is written to flash** except the config at install. The count lives in
  `/tmp/data-nag.state` (RAM), so a reboot starts it again.

## Install

battery-nag's install steps apply ([README](../README.md#install)). Back up the
router first, then on the router:

```sh
curl -fsSL https://raw.githubusercontent.com/jotnguyen/battery-nag/main/openwrt/data-nag -o /tmp/data-nag
sh /tmp/data-nag install
data-nag test           # one test push; uses battery-nag's keys if it is installed
```

Without battery-nag, run `ssh -t root@192.168.8.1 data-nag setup` to enter the
Pushover keys.

| Path | What |
|---|---|
| `/usr/bin/data-nag` | The script |
| `/etc/data-nag.conf` | Config, mode 600 |
| `/etc/crontabs/root` | One line: `data-nag check` every 2 minutes |
| `/etc/sysupgrade.conf` | Two lines, so a firmware upgrade that keeps settings keeps both files |
| `/tmp/data-nag.state` | The day's count (RAM) |

To remove it: `data-nag uninstall`. It leaves battery-nag's cron line alone.

## Check on it

```sh
data-nag status      # bytes on the modem, Wi-Fi uplink, today's count, rate, alerts
data-nag reset       # start the day's count from zero again
logread -e data-nag  # pushes sent and failed
```

## Limits

- **It warns; it doesn't cut.** For a hard stop, GL.iNet's own data limit
  (admin panel, Cellular, Data Limit) disables the modem interface at a set
  amount per billing period. data-nag's pushes are the warning before that.
  Together they cover each other: an alert early, a cut-off at the budget.
- **The push needs an uplink.** If the SIM is the only uplink, the push goes out
  over it (a few kilobytes). With no uplink at all, the push waits for the next
  check that has one.
- **Up to 2 minutes late.** At 20 Mbit/s that is about 300 MB past a step.
- **A carrier counts its own way.** Expect the bill or the eSIM app to differ from
  the router's count by a few percent (headers, retransmissions, rounding).
- **Not per device.** The kernel counter covers the whole router. To find the
  device, look at the GL.iNet Clients page while it's happening.
