# Plan

## Problem

A GL.iNet Puli (GL-XE300) carried as the day's hotspot ran its battery flat and
shut down with no warning. The phone lost its uplink with it. The web UI shows the
battery level, but nobody watches it.

The firmware does have a low-battery warning (`ubus call mcu set_warning`), but it
only reports to GL.iNet's cloud service, GoodCloud. With GoodCloud off, the warning
goes nowhere.

## Decisions

| Question | Decision | Why |
|---|---|---|
| Which device watches the battery? | The router itself | It's on whenever its battery matters, and it has the uplink. iOS can't poll in the background, and a laptop is often asleep or off the router's Wi-Fi. |
| How is the battery read? | `ubus call mcu status` | GL.iNet's daemon already talks to the battery chip. The web API needs the admin password; ubus needs nothing and changes no GL.iNet file. |
| Where do alerts go? | Pushover | It's already on the owner's phone and works on older iPhones. Each app gets its own token, so the router's can be revoked by itself. |
| Tailnet? | No | The router pushes outbound over whatever uplink it has, and nothing needs to reach it. Tailscale on a 128 MB router costs more than it buys. |
| Where does the code live? | This public repo | The code is generic and holds nothing personal. The owner's router notes stay in a private repo. |
| Phone and laptop batteries? | Not now | iOS already warns at 20% and 10%, and Safari exposes no battery API to a web page. Windows warns too, and a laptop is asleep exactly when it would matter. |

## Design

- Cron runs `battery-nag check` every 2 minutes. That is ~3 minutes of warning
  lost at worst, against hours of battery.
- `charging_status` from the daemon is its "plugged" flag: 1 while on external
  power, charging or full, and 0 on battery. This was read from the daemon's
  source; on 2026-10-09 the router read `100%`, `1` while plugged in.
- Low alerts fire only on battery; the last threshold is urgent (Pushover
  priority 1). The full alert fires only while plugged in.
- State is two values in `/tmp` (the lowest low alert pushed; whether full was
  pushed). Re-arming needs a 5-point gap, so a wobbling reading pushes once. A
  failed push isn't recorded, so the next run retries it.
- One file does everything (`install`, `setup`, `check`, `status`, `test`,
  `uninstall`), so installing means copying one file.
- It uses the stock OpenWrt cron service on `/etc/crontabs`. GL.iNet's own crond
  (`/tmp/gl_crontabs`, rebuilt by `/etc/init.d/gl_timer`) is left alone. Both read
  `system.cronloglevel` (10 on this firmware), so the extra crond doesn't fill the
  log.

## Steps

| # | Step | Status |
|---|---|---|
| 1 | Find the battery source on the router | Done: `ubus call mcu status` |
| 2 | Script and scenario tests (dash and BusyBox ash) | Done |
| 3 | Back up the router, install, check that cron runs it | Done 2026-10-09 |
| 4 | Pushover app token, then `battery-nag setup`; the test push arrives | Owner |
| 5 | Unplug the router for a minute: `battery-nag status` says "on battery" | Owner (confirms step 1's reading of the flag) |
| 6 | Merge the first PR, so the README's install line works from `main` | Owner |

## Later, if wanted

- **Unplugged alert.** A push when the router drops to battery, e.g. when a hotel
  key-card slot cuts the outlet it's charging from. About five lines.
- **Heartbeat.** A homelab could alert when the router goes silent for 30 minutes.
  But it would alert every time the router is switched off on purpose.
- **iPhone.** A Shortcuts personal automation, "Battery Level falls below 20%",
  running "Get Contents of URL" against Pushover. Only useful if someone else
  should hear about it; no code in this repo.
- **Windows laptops.** A scheduled task that reads `Win32_Battery` and pushes the
  same way.
- **ntfy** as a second push service, for people without Pushover.
- **Temperature.** The daemon reports it; GL.iNet's own warning defaults to 50 °C.

## Acceptance

- On battery, one push at 20% and one at 10%. Plugged in, one push at 100%.
- Nothing pushes while the battery is healthy, and a reading wobbling around a
  threshold pushes once.
- A failed push goes out on a later run.
- `battery-nag uninstall` puts the router back as backed up: same
  `/etc/sysupgrade.conf`, empty `/etc/crontabs`, stock cron idle.
