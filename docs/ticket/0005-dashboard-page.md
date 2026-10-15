# 0005: A data-nag page on the router, in the browser

Status: open
Priority: low

## Why

`data-nag report` answers "who used the data, and when", but only over SSH. On a phone,
or for someone who doesn't use SSH, a page at the router's address would be easier: today's
count, each device's day, and the last 48 hours as a bar chart. GL.iNet's own admin panel
doesn't show any of that. Its Clients page has per-device totals that mix Wi-Fi and cellular
and never reset by day, and its SIM data limit counts with the modem's own counter, which
reads low.

## What the router already has

On GL.iNet 4.x (seen on a GL-XE300, firmware 4.8.4):

| Port | Server | What |
|---|---|---|
| 80, 443 | nginx | GL.iNet's admin panel (the login page) |
| 8080, 8443 | uhttpd | OpenWrt's LuCI, serving `/www`, with CGI under `/cgi-bin` |
| 22 | dropbear | SSH |

The firewall drops input from the WAN zone (cellular, repeater, Ethernet WAN), so all of these
are reachable only from the router's own LAN and Wi-Fi.

## Options

- (a) **A CGI script on the uhttpd that's already running**: `/www/cgi-bin/data-nag`, at
  `http://192.168.8.1:8080/cgi-bin/data-nag`. No new process, no new port, nothing in RAM
  between page loads. The page runs `report` and `status` and prints HTML. The catch: uhttpd's
  CGI has no login, so anyone on the router's Wi-Fi can open it. It shows device names, LAN
  addresses and usage, nothing that changes the router.
- (b) **A second uhttpd instance** on its own port (say 8088), with HTTP basic auth from
  `/etc/httpd.conf`. It adds one more resident process and a password to manage.
- (c) **A static page written by `check`** into `/tmp`, served by (a) or (b). It costs RAM
  writes every 2 minutes, for a page that's mostly not looked at. (a) builds the same page on
  demand.
- Not: changing GL.iNet's nginx config or its admin panel. Those are GL.iNet's files, which
  this repo doesn't touch, and a firmware update would undo the change.

Recommendation: (a), behind a config switch (`PAGE=1`, off by default). Whoever is on the
router's Wi-Fi is usually its owner's own devices, and the page changes nothing. Add (b) if
the owner wants a password on it, for example when sharing the Wi-Fi.

uhttpd runs CGI scripts as root, so the script takes no input at all: it ignores the query
string and the request body, and only prints.

## The page

- Today's count, the rate at the last check, and whether the Wi-Fi uplink is up.
- Each device's day, with its kinds of traffic (from the day table).
- The last 48 hours as bars: an inline SVG that `awk` draws from the hourly bars. It needs
  no JavaScript and no library, and stays under 10 KB.
- The provider's balance, if `BALANCE_CMD` is set. Fetched at most once an hour and cached in
  `/tmp`, so reloading the page doesn't poll the provider (shared with ticket 0002).
- The flash wear figure, `/sys/class/ubi/ubi0/max_ec`, if it exists, with a note on what's
  normal.
- It refreshes itself every 2 minutes (`<meta http-equiv="refresh">`).

## Install and uninstall

`install` writes the CGI file only when `PAGE=1`. `uninstall` removes it. The CGI is a few
lines that call `/usr/bin/data-nag page`, so the logic stays in one file and in the tests.

## Acceptance

- Scenario test: `data-nag page` with the test state prints valid HTML holding the day table
  and the bars. It shows no ICCID and none of the provider's identifiers.
- Opens on a phone on the router's Wi-Fi, and is refused from the WAN side.
- The README and `docs/data-nag.md` show where the page is, and who can see it.
