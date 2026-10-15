# 0002: data-nag: a daily summary and a low-balance alert

Status: open
Priority: medium

## Why

A step push says what's happening now. What runs out is the plan. With `BALANCE_CMD`, data-nag
can already read the provider's balance, but only as a line of text inside other pushes.

## What

- Keep `BALANCE_CMD`'s output as it is (one human line, put into pushes). Add a separate
  `BALANCE_BYTES_CMD` that prints only the bytes left, e.g. `data-nag eiotclub --bytes`, which prints
  EIOTCLUB's raw `remain` field. Existing configs keep working unchanged.
- `LOW_BALANCE_MB` (empty = off): push once when the bytes left fall under it (decimal MB, as the
  rest of data-nag; EIOTCLUB's app shows GiB, so 1000 here is 0.93 "GB" in the app); re-arm when it
  rises (a top-up).
- `SUMMARY_HOUR` (empty = off): once a day at that hour, if cellular moved any data in the last 24
  hours, push a summary of exactly the last 24 hours (not the noon-to-noon count, which `status`
  already shows; say "last 24 h" in the push so the two aren't confused). Example:
  "Last 24 h on cellular: 1.2 GB, peak 18 Mbit/s at 07:20, top device laptop
  (0.9 GB). eSIM left: 5.1 GB". The per-device part needs 0003.
- The balance is fetched at most once an hour, cached in `/tmp`, so the provider's API is
  never polled every 2 minutes.

## Acceptance

- Scenario tests with a fake `BALANCE_CMD`: crossing under the mark pushes once; a top-up re-arms;
  the summary pushes once a day and not on a day with no cellular data.

## Notes

EIOTCLUB's balance runs hours behind and counts in GiB. Say so in the push, as the balance line
does.
