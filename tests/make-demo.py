#!/usr/bin/env python3
"""Generate the synthetic payload the preview harness and README images use.

Deterministic: the same seed always writes the same file, so the checked-in
demo data never drifts. It is shaped exactly like bin/tokenbar-scan's output,
but no real machine's usage is in it.

Run: python3 tests/make-demo.py
"""

from __future__ import annotations

import datetime as dt
import json
import random
from pathlib import Path

SEED = 20261106
OUT = Path(__file__).resolve().parent / "demo-payload.json"

AGENTS = [
    ("factory", "Droid"),
    ("claude", "Claude Code"),
    ("agy", "Antigravity"),
    ("codex", "Codex"),
]

MODELS = {
    "factory": ["gpt-6.1-sol", "deepseek-v4.1-flash", "claude-opus-5-5"],
    "claude": ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5"],
    "agy": ["gemini-3.8-flash-high", "gemini-3.6-flash"],
    "codex": ["gpt-5.4", "gpt-5.4-mini"],
}

# Dollars per million tokens, matching the scanner's table closely enough for
# a preview: (input, output, cache read, cache write).
PRICES = {
    "gpt-6.1-sol": (2.0, 10.0, 0.1, 0.0),
    "deepseek-v4.1-flash": (0.3, 1.2, 0.006, 0.0),
    "claude-opus-5-5": (4.0, 20.0, 0.2, 5.0),
    "claude-sonnet-5-5": (2.0, 10.0, 0.1, 2.5),
    "claude-haiku-4-5": (1.0, 5.0, 0.1, 1.25),
    "gemini-3.8-flash-high": (0.75, 3.75, 0.075, 0.0),
    "gemini-3.6-flash": (0.75, 3.75, 0.075, 0.0),
    "gpt-5.4": (2.5, 15.0, 0.25, 0.0),
    "gpt-5.4-mini": (0.75, 4.5, 0.075, 0.0),
}


def main() -> None:
    rng = random.Random(SEED)
    today = dt.date(2026, 11, 6)
    names = sorted({model for models in MODELS.values() for model in models})
    model_index = {name: index for index, name in enumerate(names)}
    agent_ids = [agent for agent, _ in AGENTS]
    agent_index = {agent: index for index, agent in enumerate(agent_ids)}

    days = []
    for back in range(364, -1, -1):
        day = today - dt.timedelta(days=back)
        weekend = day.weekday() >= 5
        if rng.random() < (0.55 if weekend else 0.12):
            continue
        weight = 1.0 - back / 520.0 + rng.random() * 0.5
        rows = []
        activity = []
        for agent in agent_ids:
            if rng.random() < 0.28:
                continue
            sessions = rng.randint(1, 4)
            prompts = rng.randint(2, 26)
            activity.append([agent_index[agent], sessions, prompts])
            for model in MODELS[agent]:
                if rng.random() < 0.35:
                    continue
                scale = weight * rng.uniform(0.4, 2.6)
                input_tokens = int(rng.uniform(20_000, 900_000) * scale)
                output_tokens = int(rng.uniform(2_000, 90_000) * scale)
                cache_read = int(input_tokens * rng.uniform(1.5, 22.0))
                cache_write = int(input_tokens * rng.uniform(0.0, 0.35))
                rates = PRICES[model]
                cost = (input_tokens * rates[0] + output_tokens * rates[1]
                        + cache_read * rates[2] + cache_write * rates[3]) / 1_000_000
                rows.append([agent_index[agent], model_index[model], input_tokens, output_tokens,
                             cache_read, cache_write, int(round(cost * 1_000_000_000))])
        if rows or activity:
            days.append({"d": day.isoformat(), "r": rows, "a": activity})

    totals = {agent: {"cost": 0, "tokens": 0, "sessions": set(), "prompts": 0, "days": 0,
                      "models": {}}
              for agent in agent_ids}
    unpriced_models = {"gpt-6.1-sol": 0}
    for day in days:
        for agent in agent_ids:
            if any(row[0] == agent_index[agent] for row in day["r"]):
                totals[agent]["days"] += 1
        for activity in day["a"]:
            agent = agent_ids[activity[0]]
            totals[agent]["prompts"] += activity[2]
            totals[agent]["sessions"].add((day["d"], activity[0]))
        for row in day["r"]:
            agent = agent_ids[row[0]]
            model = names[row[1]]
            tokens = row[2] + row[3] + row[4] + row[5]
            totals[agent]["cost"] += row[6]
            totals[agent]["tokens"] += tokens
            entry = totals[agent]["models"].setdefault(model, {"n": model, "c": 0, "tokens": 0})
            entry["c"] += row[6]
            entry["tokens"] += tokens

    agents = []
    for agent in agent_ids:
        entry = totals[agent]
        models = sorted(entry["models"].values(), key=lambda item: (-item["c"], -item["tokens"]))
        agents.append({
            "id": agent,
            "name": dict(AGENTS)[agent],
            "tokens": entry["tokens"],
            "cost": entry["cost"],
            "activeDays": entry["days"],
            "sessions": len(entry["sessions"]),
            "prompts": entry["prompts"],
            "models": [{"n": model["n"], "c": model["c"], "tokens": model["tokens"], "priced": True}
                       for model in models],
        })

    payload = {
        "schemaVersion": 4,
        "generatedAt": int(dt.datetime(2026, 11, 6, 9, 30).timestamp() * 1000),
        "historyDays": 365,
        "agents": agents,
        "agentIds": agent_ids,
        "modelNames": names,
        "days": days,
        "unpriced": [],
        "meta": {
            "scanMs": 38,
            "mode": "warm",
            "sources": [
                {"id": "factory", "ok": True, "files": 41, "rows": 128, "note": ""},
                {"id": "claude", "ok": True, "files": 22, "rows": 96, "note": ""},
                {"id": "agy", "ok": True, "files": 6, "rows": 31, "note": ""},
                {"id": "codex", "ok": True, "files": 9, "rows": 18, "note": ""},
                {"id": "opencode", "ok": False, "files": 0, "rows": 0, "note": "no opencode database"},
                {"id": "gemini", "ok": False, "files": 0, "rows": 0, "note": "no Gemini CLI transcripts"},
                {"id": "omarchy", "ok": True, "files": 23, "rows": 0, "note": "recent days only"},
            ],
            "files": 101,
            "pid": 4242,
        },
    }
    OUT.write_text(json.dumps(payload, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"{OUT} · {len(days)} days · {sum(len(d['r']) for d in days)} rows · "
          f"{OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
