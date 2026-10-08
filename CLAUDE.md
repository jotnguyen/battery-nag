# CLAUDE.md — battery-nag

A public repo: a battery alert that runs on a GL.iNet router. Read `README.md`, then
`docs/PLAN.md` (decisions, status, what is left).

## Non-negotiables

- **Nothing personal in git.** No keys, no real IP addresses (only GL.iNet's default
  192.168.8.1), no SIM or modem identifiers, hostnames, names, or trip details.
  `bash scripts/hygiene.sh` must print `hygiene-ok`. The git hooks in `.githooks/` run it
  on every commit and its message; never bypass them with `--no-verify`.
- **No AI attribution** in commits or PRs (`.claude/settings.json` turns it off).
- **No GL.iNet code here, and no change to GL.iNet files on a router.** Only call its
  ubus interface.
- **On a real router:** back up first (`sysupgrade -b`, copied somewhere private, never
  into this repo), stay read-only until the owner agrees to a change, and never type a
  password (key auth only).
- `openwrt/battery-nag` runs on BusyBox ash: POSIX sh only. `sh test/run.sh` must pass;
  CI also runs it under BusyBox, plus shellcheck.

## Hand-off

Work on a branch, not `main`. Each commit refreshes the branch's hand-off in
`.git/handoff/` (`scripts/write_handoff.sh`), and the next Claude Code session on that
branch sees it at start, `/clear` and compaction. Before you stop, leave the next step:
`bash scripts/write_handoff.sh --note "..."`.
