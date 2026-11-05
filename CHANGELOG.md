# Changelog

## 1.0.0

First release.

- Bar readout of today's token spend, with `cost`, `tokens` and `both` modes,
  a `today`/`7d`/`30d` window, and a configurable refresh interval.
- Dashboard with 1D/7D/30D/90D/1Y ranges, WTD/MTD/QTD/YTD calendar ranges, and
  a day or month picker.
- Daily chart that folds into weeks and months over long ranges; click a bar to
  drill into that day or month.
- Per-agent breakdown with share-of-spend bars, and a detail view with cost,
  cost per million tokens, cache hit rate, cost per active day, sessions,
  prompts, its own chart, and per-model rows.
- Per-model breakdown, including a full list and unpriced-model reporting.
- Wide two-column layout for the panel.
- Copy a plain-text summary, or save a 2400x1350 share card.
- Incremental scanner: byte offsets per log file, so an unchanged refresh is a
  few `stat` calls. Cold scan ~100 ms, warm scan ~48 ms on 25 files.
- Sources: Droid, Antigravity, Claude Code, Codex, OpenCode, Gemini CLI, and
  Omarchy's own agent usage records as a fallback.
- English catalog with plural forms; other languages get one file at a time.
