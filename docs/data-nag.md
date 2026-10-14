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
> eSIM left: 5.1 GB of 25 GB (EIOTCLUB's count, hours behind)

| Line | Where it comes from |
|---|---|
| Amount, rate | The modem's byte counter, every 2 minutes. The rate only shows from 1 Mbit/s |
| Wi-Fi uplink | Whether GL.iNet's repeater interface is up. If the router is on the SIM because the repeater is off, that's the thing to fix |
| Bar line | The cellular bytes per 10 minutes over the last 3 hours, scaled to the tallest bar. Shows once there are two bars |
| Top now | The device that moved the most cellular bytes since the last check, named from the DHCP leases, with the kind of traffic most of those bytes were |
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
- **Install counts from zero.** The first check after install, or after a reboot
  clears `/tmp`, starts from the counter's current value.
- **Per device** it reads the kernel's connection table (`/proc/net/nf_conntrack`,
  which counts bytes per connection when `net.netfilter.nf_conntrack_acct` is 1, as
  on GL.iNet 4.x). Only connections whose replies come back to the cellular
  address count. Each connection's bytes are compared with the last check's, so a
  download spread over many short connections still counts. Bytes a connection
  moved after the last check but before it closed are missed. The first check
  after cellular starts moving data only records the table, and nothing is named
  while the cellular address is unknown.
- **Nothing is written to flash** except the config at install. The count, the bars
  and the last device table live in `/tmp/data-nag.state*` (RAM).

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
| `/tmp/data-nag.state*` | The day's count and bars, the last connection and device tables, a lock (RAM) |

To remove it: `data-nag uninstall`. It leaves battery-nag's cron line alone.

## Check on it

```sh
data-nag status      # modem, Wi-Fi uplink, today's count, bars, devices, balance
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
