# data-nag: cellular data alert

A GL.iNet router with a SIM falls back to cellular when its Wi-Fi uplink
(repeater) drops or is switched off, and it says nothing about it. Whatever runs
behind it then runs over the SIM: a video left playing overnight, or a laptop
pulling a 5 GB operating system update. On a travel eSIM that's gigabytes gone
before anyone looks. data-nag pushes to your phone at every 250 MB of cellular
data in a day. From 1 GB the pushes turn urgent, so they get through Pushover's
quiet hours.

It runs on the router from the same cron as battery-nag and uses battery-nag's
Pushover keys if they are there.

## What a push looks like

> **Puli cellular 750 MB**
> 750 MB of cellular data since 12:00. Now 18 Mbit/s: something is streaming or downloading. Wi-Fi uplink is off: all traffic is on the SIM.
> Last 1 h ▁▁▂▅▇█ (10-min bars, peak 160 MB)
> Top now: laptop, 15 Mbit/s, HTTP (often OS updates)
> Today so far: laptop 600 MB, phone 150 MB
> eSIM left: 5.1 GB of 25 GB (EIOTCLUB's count, hours behind)

| Line | Where it comes from |
|---|---|
| Amount, rate | The modem's byte counter, every 2 minutes. The rate only shows from 1 Mbit/s |
| Wi-Fi uplink | Whether GL.iNet's repeater interface is up. If the router is on the SIM because the repeater is off, that's the thing to fix |
| Bar line | The cellular bytes per 10 minutes over the last 3 hours, scaled to the tallest bar. Shows once there are two bars |
| Top now | The device that moved the most cellular bytes since the last check, named from the DHCP leases, with the kind of traffic most of those bytes were |
| Today so far | Each device's cellular bytes since the day started, the top three. Shows once two or more devices have used cellular that day |
| Balance | Optional: the first line of `BALANCE_CMD`, e.g. what the SIM provider says is left |

Pushes come at 250 MB, 500 MB, 750 MB and so on. A jump past several steps between two
checks pushes once. The step, the urgent mark and the reset hour are all set in
`/etc/data-nag.conf`.

### Kinds of traffic

The router can't see inside HTTPS, so the kind is a guess from protocol and port:

| Kind | Rule | Usually |
|---|---|---|
| Tailscale tunnel | UDP, port 41641 | A device on a Tailscale exit node or talking to its tailnet. Its contents are hidden from the router |
| QUIC (YouTube, Google) | UDP 443 | YouTube and other Google services, most video in apps |
| HTTPS | TCP 443 | Web, streaming, app downloads |
| HTTP (often OS updates) | TCP 80 | Windows Update and Microsoft Store downloads, other CDN downloads |
| DNS, WireGuard VPN, other | port 53, UDP 51820, anything else | |

A device that sends everything through a Tailscale exit node or a VPN shows up as
one tunnel. Tailscale relayed over its DERP servers (TCP 443) shows as HTTPS.
On that device itself, Windows records which app used how much per
network and per hour: Settings, Network & internet, Data usage.

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
- **Install counts from zero.** The first check after install starts from the
  counter's current value.
- **A restart carries on.** See [Kept through a restart](#kept-through-a-restart).
- **Per device** it reads the kernel's connection table (`/proc/net/nf_conntrack`,
  which counts bytes per connection when `net.netfilter.nf_conntrack_acct` is 1, as
  on GL.iNet 4.x). Only connections whose replies come back to the cellular
  address count. Each connection's bytes are compared with the last check's, so a
  download spread over many short connections still counts. Bytes a connection
  moved after the last check but before it closed are missed. The first check
  after cellular starts moving data only records the table, and nothing is named
  while the cellular address is unknown.
- **The day per device.** Each check's bytes per device and kind go into a day
  table, which starts empty with the day. `data-nag report` prints it, and the
  push adds "Today so far" from it.

## The day per device: `data-nag report`

```
Cellular since 12:00 (day 20261015): 1.9 GB
  phone 1.4 GB: QUIC (YouTube, Google) 1.2 GB, HTTPS 200 MB
  laptop 500 MB: Tailscale tunnel 500 MB
  The devices add up to 96% of that (connections that open and close between checks are missed).
Per hour, last 48 h:
  Thu 11:00  870 MB
  Thu 15:00  250 MB
  ...
```

A device with no name in the DHCP leases shows by its address. A phone with a
private Wi-Fi address is one of those; give it a name in the router's admin panel
(Clients) or turn the private address off for the router's network.

## Kept through a restart

The count, the bars and the day table live in `/tmp` (RAM), which a restart
empties. A travel router restarts a lot: its battery runs flat, or someone
power-cycles it because the Wi-Fi is acting up. Without a copy the day's count
starts again from zero, so the 250 MB steps start again too, and the day's
history is gone.

So while cellular moves data, data-nag copies its state and the day table to
`/etc/data-nag.saved` and `/etc/data-nag.saved.day` (flash), at most every
`SAVE_MIN` minutes (10). Nothing is written while the SIM is idle. After a restart
`/tmp` is empty, so the next check reads the copy and adds the modem's counter,
which also started from zero at the restart. At most the last `SAVE_MIN` minutes of
counting are lost. Each file is written beside the old one and renamed over it, so
a power cut mid-write leaves the old copy or the new one, never half of one.
`SAVE_MIN=` (empty) turns this off. To start the count again, use `data-nag reset`,
not `rm /tmp/data-nag.state`: an empty `/tmp` reads as a restart, and the next check
would add the modem's whole counter again.

### Why that doesn't wear out the flash

Measured on a GL-XE300 (firmware 4.8.4) on 2026-10-15:

| | |
|---|---|
| Flash for settings | 128 MiB SPI NAND (GigaDevice), single-level cell: the durable kind, not an SD card or eMMC |
| Layout | 1024 erase blocks of 128 KiB, 0 bad, 20 kept spare. `/overlay` (where `/etc` changes go) is UBIFS on UBI, 92.7 MB, 2% used |
| Wear so far | UBI's erase counter: highest block 7, average 3, since the firmware was written in April 2023 |

The numbers, taking the worst case at every step:

- **Writes.** At most one copy per 10 minutes, and only while cellular is in use:
  144 a day if the SIM is busy around the clock.
- **Cost of a write.** Two files of under 2 KB. UBIFS writes them in 2 KiB pages into
  its journal and erases a 128 KiB block only when it reclaims space. Assume each
  copy costs a whole block erase anyway: 144 erases a day.
- **Spread.** UBI spreads erases over all 1024 blocks (wear levelling, with
  counters you can read). 144 / 1024 is 0.14 erases per block per day, about 50 a
  year.
- **Endurance.** GigaDevice rates its GD5F SPI NAND family at 100,000 erase cycles
  per block. Take a tenth of that, 10,000, and 50 a year lasts about 200 years.
  At the full rating, about 2,000.

The thing that does wear flash out is many writes landing on the same few blocks
with nothing spreading them, as on a cheap SD card. UBI is there to prevent that,
and the counters show it working: three years of GL.iNet's own config and client
database writes have put 3 to 7 erases on each block.

To watch it: `cat /sys/class/ubi/ubi0/max_ec` (the most-erased block). It should
still be in the tens a year from now.

## The provider's balance (EIOTCLUB)

The router's count is exact, but it only covers this router since it booted. The
provider's number is the one that runs out. For an EIOTCLUB eSIM, data-nag can
ask EIOTCLUB's shop API, which answers by ICCID alone:

```sh
data-nag eiotclub
# eSIM left: 5.1 GB of 25 GB (EIOTCLUB's count, hours behind)
```

Set `BALANCE_CMD="/usr/bin/data-nag eiotclub"` in `/etc/data-nag.conf` to add that
line to every push, to `data-nag status` and to `data-nag test`. It's only asked
when one of those runs, not every 2 minutes. The ICCID is read from the modem
interface in `/etc/config/network`; set `ICCID=` in the config if that fails.

Two things to know about that number:

- **EIOTCLUB's "GB" is a GiB** (2^30 bytes): 25 GB is 26,843,545,600 bytes. The
  router counts in decimal GB, so 10 GB on the router is 9.3 GB in EIOTCLUB's app.
- **It runs hours behind.** Use it for "how much is left", and the router's count
  for "what is happening now".

Anyone who has an EIOTCLUB ICCID can read that eSIM's balance from this
API. Treat the ICCID as private: it's printed in the app, on the order page and in
the shop URL.

Any other provider: point `BALANCE_CMD` at a command that prints one line.

## Install

battery-nag's install steps apply ([README](../README.md#install)). Back up the
router first, then on the router:

```sh
curl -fsSL https://raw.githubusercontent.com/jotnguyen/glinet-utilities/main/openwrt/data-nag -o /tmp/data-nag
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
| `/tmp/data-nag.state*` | The day's count and bars, the day's device table, the last connection and device tables, a lock (RAM) |
| `/etc/data-nag.saved*` | A copy of the count, the bars and the day's device table, for after a restart (flash; every 10 minutes at most, only while cellular is in use) |

To remove it: `data-nag uninstall`. It leaves battery-nag's cron line alone.

## Check on it

```sh
data-nag status      # modem, Wi-Fi uplink, today's count, bars, devices, balance
data-nag report      # the day per device and kind of traffic, the last 48 h per hour
data-nag reset       # start the day's count from zero again
logread -e data-nag  # pushes sent and failed
```

## Limits

- **It warns; it doesn't cut.** For a hard stop, GL.iNet's own data limit
  (admin panel, Internet, Cellular, SIM limit settings) disables the SIM at a set
  amount per period. It counts with the modem's own counter, which can read well
  under the real figure for downloads, so set its cap low.
- **No picture.** A push carries text; the router has no image tools. The bar line
  is the picture. A chart image would need another machine to draw it.
- **The push needs an uplink.** If the SIM is the only uplink, the push goes out
  over it (a few kilobytes). With no uplink at all, the push waits for the next
  check that has one.
- **Up to 2 minutes late.** At 20 Mbit/s that is about 300 MB past a step.
- **A carrier counts its own way.** Expect the provider's figure to differ from
  the router's by a few percent, on top of the GiB difference above.
