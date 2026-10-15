# 0004: One copy of the shared code, and a test of install and uninstall

Status: open
Priority: low

## Why

The data-nag review found `push`, `setup`, `append_line`, `install` and `uninstall` copied
almost verbatim from battery-nag. A fix to one (a Pushover change, the cron handling) has to be
made twice. Each tool stays one file on purpose, so it installs with one `curl`. And install and
uninstall, the riskiest code (cron, `/etc/sysupgrade.conf`), have no automated test.

## Options

- (a) Keep the copies, and add a CI check that the functions meant to match are identical in both
  files (extract them by name and diff them). Today only `push` and `append_line` match exactly;
  `setup`, `install`, `uninstall`, `test_push` and `write_conf` differ on purpose (config
  names, the modem check, state files). Either list the matching ones in the check, or first
  move the differences into variables so more functions can match.
- (b) A `lib/common.sh` concatenated into each script by a tiny build step, with the built
  files committed so `curl` still works. CI fails if they're stale.
- (c) One multi-call script, `glinet-utilities battery|data ...`. Simplest code, but a bigger
  change for anyone who installed the separate tools.

Recommendation: (a) now, since it costs little and keeps installs as they are.

## Install test

Run `install`, `check`, `status` and `uninstall` in an OpenWrt rootfs container
(`openwrt/rootfs` on Docker Hub) with stubbed `ubus`, `/etc/init.d/cron` and a fake
`/sys/class/net/wwan0`. Assert that `/etc/crontabs/root` and `/etc/sysupgrade.conf` end
byte-identical to how they started.
