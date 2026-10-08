#!/usr/bin/env bash
# Write a short hand-off for the current branch, so the next agent starts from
# ~40 lines of facts instead of re-reading a transcript or re-deriving the state
# with git. Mechanical facts only: commits, changed files, uncommitted work, the
# open PR. Everything under "## Notes" is kept across rewrites, so a session can
# leave next steps there (by hand or with --note).
#
# The file lives in the clone's git dir, shared by its worktrees and never
# committed: <git-common-dir>/handoff/<branch, / as __>.md
#
# Usage:
#   bash scripts/write_handoff.sh                 # rewrite the facts, keep Notes
#   bash scripts/write_handoff.sh --pr            # also the branch's open PR (needs gh)
#   bash scripts/write_handoff.sh --note "text"   # append a dated line under Notes
#   bash scripts/write_handoff.sh --path          # print the file path only
#   bash scripts/write_handoff.sh --session-start # enable .githooks, print the hand-off
# Called by .githooks/post-commit, .githooks/pre-push (--pr), and the Claude Code
# SessionStart hook in .claude/settings.json (--session-start). Skips main/master
# and a detached HEAD. Adapted from the hand-off in the author's homelab repo.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
with_pr=0
note=
mode=facts
while [ $# -gt 0 ]; do
  case "$1" in
    --pr) with_pr=1 ;;
    --note) note="$2"; shift ;;
    --path) mode=path ;;
    --session-start) mode=session ;;
  esac
  shift
done

if [ "${mode}" = session ]; then
  [ -n "$(git config --local --get core.hooksPath || true)" ] || git config --local core.hooksPath .githooks
fi

branch="$(git symbolic-ref --quiet --short HEAD || true)"
case "${branch}" in
  '' | master | main) exit 0 ;;
esac

dir="$(git rev-parse --path-format=absolute --git-common-dir)/handoff"
file="${dir}/${branch//\//__}.md"
case "${mode}" in
  path)
    echo "${file}"
    exit 0
    ;;
  session)
    [ -f "${file}" ] || exit 0
    echo "Hand-off for this branch from an earlier session (${file}). Trust it over"
    echo "re-deriving; add next steps under its Notes with scripts/write_handoff.sh --note."
    echo
    head -n 80 "${file}"
    exit 0
    ;;
esac
mkdir -p "${dir}"

base=origin/main
git rev-parse --verify --quiet "${base}" >/dev/null || base=main

placeholder="_(none yet: next steps, open questions, what not to redo)_"
notes="$(sed -n '/^## Notes$/,$p' "${file}" 2>/dev/null | tail -n +2 | grep -vxF "${placeholder}" || true)"
[ -z "${note}" ] || notes="${notes:+${notes}
}- $(date +%Y-%m-%d) ${note}"
[ -n "${notes}" ] || notes="${placeholder}"

pr=
if [ "${with_pr}" -eq 1 ] && command -v gh >/dev/null 2>&1; then
  pr="$(gh pr view "${branch}" --json number,title,state,isDraft,url,body \
    --template '#{{.number}} {{.title}} ({{.state}}{{if .isDraft}}, draft{{end}}) {{.url}}
{{.body}}' 2>/dev/null | head -n 40 | sed '2,$s/^/> /' || true)"
fi
# The body is quoted above so its own "## " headings cannot end the PR section.
# A plain commit (no --pr) keeps the PR section from the last --pr run.
[ -n "${pr}" ] || [ "${with_pr}" -eq 1 ] \
  || pr="$(sed -n '/^## PR$/,/^## /p' "${file}" 2>/dev/null | sed '1d;$d' | sed '1{/^$/d};${/^$/d}' || true)"

{
  echo "# Hand-off: ${branch}"
  echo
  echo "Updated $(date '+%Y-%m-%d %H:%M %Z') by scripts/write_handoff.sh. Facts below are"
  echo "regenerated on every commit/push; only the Notes section is kept."
  echo
  echo "## Commits ahead of ${base}"
  echo
  git log --format='- %h %s' "${base}..HEAD" | head -n 20
  echo
  echo "## Files changed vs ${base}"
  echo
  git diff --name-status "${base}...HEAD" | head -n 40 | sed 's/^/    /'
  echo
  echo "## Uncommitted"
  echo
  status="$(git status --short | head -n 20 | sed 's/^/    /')"
  echo "${status:-clean}"
  echo
  echo "## PR"
  echo
  if [ -n "${pr}" ]; then echo "${pr}"; else echo "none open (or not checked)"; fi
  echo
  echo "## Notes"
  echo "${notes}"
} >"${file}.tmp"
mv "${file}.tmp" "${file}"
