# battery-nag

A GL.iNet travel router shuts down without a word when its battery runs flat, and
takes your connection with it. battery-nag makes it warn you first: a push to your
phone at 20% and again at 10%, and one more when it is fully charged.

It runs on the router itself, so it works wherever the router has an uplink, with
no phone app polling it and no laptop switched on. It reads the battery from
GL.iNet's own battery daemon (`ubus call mcu status`): no web login, no scraping,
and no change to any GL.iNet file. Pushes go through [Pushover](https://pushover.net).

Tested on a GL-XE300 (Puli), firmware 4.8.4 (OpenWrt 22.03). Other GL.iNet 4.x
routers with a battery should work if `ubus call mcu status` prints a
`charge_percent`.

## What it sends

| When | Push |
|---|---|
| On battery, at or under 20% | **Router battery 19%** Running on battery. Charge it soon. |
| On battery, at or under 10% | **Router battery 9%** About to shut down. Plug it in now. (urgent: sounds during Pushover quiet hours) |
| Plugged in, at 100% | **Router charged 100%** Full. You can unplug it. |

Each alert pushes once. It re-arms when the battery is 5 points back past the
threshold (25% for the low alerts, 95% for full), so a reading that wobbles around
20% doesn't push twice. The thresholds, the name in the title, and the gap are
all set in the config.

## Install

You need SSH access to the router as root, and a Pushover account. Pushover is free
for 30 days, then a one-time purchase per platform.

1. Back up the router first, and keep the file private (it holds Wi-Fi and VPN
   secrets):

   ```sh
   ssh root@192.168.8.1 'sysupgrade -b /tmp/backup.tar.gz && cat /tmp/backup.tar.gz && rm /tmp/backup.tar.gz' > router-backup.tar.gz
   ```

2. On the router (`ssh root@192.168.8.1`), fetch the script and install it:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/jotnguyen/battery-nag/main/openwrt/battery-nag -o /tmp/battery-nag
   sh /tmp/battery-nag install
   ```

   From a clone instead: `scp -O openwrt/battery-nag root@192.168.8.1:/tmp/`, then
   `ssh root@192.168.8.1 sh /tmp/battery-nag install`. (`-O` because the router has
   no SFTP server.)

3. At pushover.net, create an application for the router (any name, e.g.
   "battery-nag") and copy its API token. Your user key is at the top of the
   dashboard. Then:

   ```sh
   ssh -t root@192.168.8.1 battery-nag setup
   ```

   Paste both keys. It saves them and sends a test push.

## What it changes on the router

| Path | What |
|---|---|
| `/usr/bin/battery-nag` | The script |
| `/etc/battery-nag.conf` | Config with your Pushover keys, mode 600 |
| `/etc/crontabs/root` | One line: `battery-nag check` every 2 minutes |
| `/etc/sysupgrade.conf` | Two lines, so a firmware upgrade that keeps settings keeps the script and config |
| `/tmp/battery-nag.state` | Which alerts have fired (RAM, cleared on reboot) |

It changes no GL.iNet file. GL.iNet runs its own `crond` for its timers
(`/tmp/gl_crontabs`). This tool uses the stock OpenWrt cron service, which ships
enabled but stays idle until `/etc/crontabs` has a file in it.

To remove everything: `ssh root@192.168.8.1 battery-nag uninstall`.

## Check on it

```sh
battery-nag status          # reading, which alerts fired, whether keys are set
battery-nag test            # send a test push
logread -e battery-nag      # pushes sent and failed
```

## Limits

- **No uplink, no push.** If the router has neither cellular nor a Wi-Fi uplink,
  the alert can't get out. It retries every 2 minutes and goes out as soon as an
  uplink returns.
- **"Plugged in" means external power is connected.** A charger too weak to keep
  up still counts as plugged in, so no low alert fires while it's connected.
- **A GL.iNet firmware upgrade can change the battery daemon.** Run
  `battery-nag status` after one.

## Develop

`openwrt/battery-nag` runs on BusyBox ash, so it is POSIX sh only.
`sh test/run.sh` runs the scenarios with a faked battery reading and prints the
pushes instead of sending them. CI runs the scenarios under dash and BusyBox ash,
plus shellcheck and `scripts/hygiene.sh`, which keeps personal data out of this
public repo. [docs/PLAN.md](docs/PLAN.md) has the design decisions and what's left.

MIT licensed. Not affiliated with GL.iNet. The script talks to GL.iNet's battery
daemon through its ubus interface and contains no GL.iNet code.
