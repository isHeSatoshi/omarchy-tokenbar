#!/usr/bin/env python3
"""Regression tests for tokenbar-scan.

Each test builds a throwaway HOME holding the on-disk shapes the agents
write, runs the scanner the way the widget does, and checks the payload.
Sources that are not installed on this machine are covered the same way, so
their parsers are exercised even without that agent present.

Run: python3 tests/test_scan.py
"""

from __future__ import annotations

import json
import os
import shutil
import runpy
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import datetime as dt
from pathlib import Path

SCANNER = Path(__file__).resolve().parent.parent / "bin" / "tokenbar-scan"


def local_stamp(year: int, month: int, day: int, hour: int, minute: int = 0) -> str:
    """A UTC timestamp for a wall-clock time in the machine's own zone.

    The scanner buckets by local day, so a test that means "just before
    midnight" has to say it in local time rather than in UTC.
    """
    moment = dt.datetime(year, month, day, hour, minute).astimezone(dt.timezone.utc)
    return moment.strftime("%Y-%m-%dT%H:%M:%S.000Z")


def droid_log_line(stamp: str, session: str, model: str, tokens: tuple[int, int, int, int]) -> str:
    payload = {
        "count": 1,
        "inputTokens": tokens[0],
        "outputTokens": tokens[1],
        "cacheReadInputTokens": tokens[2],
        "cachedTokensWritten": tokens[3],
        "tags": {"sessionId": session, "modelId": model},
    }
    return f"[{stamp}] INFO: [Agent] Streaming result | Context: {json.dumps(payload)}"


class ScannerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.home = Path(tempfile.mkdtemp(prefix="tokenbar-test-"))
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "XDG_CACHE_HOME": str(self.home / "cache"),
            "XDG_STATE_HOME": str(self.home / "state"),
            "CLAUDE_CONFIG_DIR": str(self.home / ".claude"),
            "CODEX_HOME": str(self.home / ".codex"),
            "AGY_DIR": str(self.home / ".gemini" / "antigravity-cli"),
            "GEMINI_CLI_HOME": str(self.home / ".gemini"),
            "OPENCODE_DATA": str(self.home / ".local" / "share" / "opencode"),
        }
        self.env.pop("OPENCODE_DB", None)

    def tearDown(self) -> None:
        shutil.rmtree(self.home, ignore_errors=True)

    # -- helpers ---------------------------------------------------------

    def run_scan(self, *args: str) -> dict:
        result = subprocess.run(
            [sys.executable, str(SCANNER), *args],
            capture_output=True, text=True, env=self.env, timeout=120,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def factories(self) -> Path:
        return self.home / ".factory"

    def write(self, relative: str, text: str) -> Path:
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def append(self, path: Path, text: str) -> None:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(text)

    @staticmethod
    def totals(payload: dict, agent: str | None = None) -> int:
        total = 0
        for day in payload["days"]:
            for row in day["r"]:
                if agent is None or payload["agentIds"][row[0]] == agent:
                    total += sum(row[2:6])
        return total

    @staticmethod
    def agent(payload: dict, agent_id: str) -> dict:
        for entry in payload["agents"]:
            if entry["id"] == agent_id:
                return entry
        raise AssertionError(f"agent {agent_id} missing from {[a['id'] for a in payload['agents']]}")

    # -- factory ---------------------------------------------------------

    def test_factory_counts_each_call_once_and_prices_models(self) -> None:
        log = self.factories() / "logs" / "droid-log-single.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(
            droid_log_line("2026-11-05T10:00:00.000Z", "s1", "deepseek-v4.1-flash-1017", (1000, 200, 3000, 0))
            + "\n"
            + droid_log_line("2026-11-05T11:00:00.000Z", "s1", "gpt-6.1-sol", (10, 100, 500, 20))
            + "\n",
            encoding="utf-8",
        )
        payload = self.run_scan("--refresh")
        self.assertEqual(self.totals(payload, "factory"), 1000 + 200 + 3000 + 0 + 10 + 100 + 500 + 20)
        factory = self.agent(payload, "factory")
        self.assertEqual(factory["sessions"], 1)
        # deepseek-v4.1-flash-1017 folds to the v4-flash rate: $0.3/$1.2/$0.006.
        deepseek = next(m for m in factory["models"] if m["n"].startswith("deepseek"))
        self.assertTrue(deepseek["priced"])
        expected = (1000 * 0.3 + 200 * 1.2 + 3000 * 0.006) / 1_000_000
        self.assertAlmostEqual(deepseek["c"] / 1e9, expected, places=9)

    def test_factory_counts_typed_prompts_but_not_reminders_or_tool_results(self) -> None:
        sessions = self.factories() / "sessions" / "-home-user"
        sessions.mkdir(parents=True, exist_ok=True)
        rows = [
            {"type": "message", "timestamp": "2026-11-05T09:00:00Z",
             "message": {"role": "user", "content": [{"type": "text", "text": "add a widget"}]}},
            {"type": "message", "timestamp": "2026-11-05T09:01:00Z",
             "message": {"role": "user", "content": [{"type": "text", "text": "<system-reminder>noise"}]}},
            {"type": "message", "timestamp": "2026-11-05T09:02:00Z",
             "message": {"role": "user", "content": []}},
            {"type": "message", "timestamp": "2026-11-05T09:03:00Z",
             "message": {"role": "assistant", "content": [{"type": "text", "text": "done"}]}},
        ]
        (sessions / "abc.jsonl").write_text("\n".join(json.dumps(r) for r in rows) + "\n", encoding="utf-8")
        payload = self.run_scan("--refresh")
        self.assertEqual(self.agent(payload, "factory")["prompts"], 1)

    def test_rescan_replaces_rows_when_a_log_is_truncated(self) -> None:
        log = self.factories() / "logs" / "droid-log-single.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(droid_log_line("2026-11-05T10:00:00.000Z", "s1", "gpt-6.1-sol", (100, 10, 0, 0)) + "\n")
        first = self.run_scan("--refresh")
        self.assertEqual(self.totals(first, "factory"), 110)

        # Rotation that copies and truncates must not double the old rows.
        log.write_text(droid_log_line("2026-11-05T12:00:00.000Z", "s2", "gpt-6.1-sol", (7, 3, 0, 0)) + "\n")
        second = self.run_scan()
        self.assertEqual(self.totals(second, "factory"), 10)

    def test_warm_scan_picks_up_appended_lines_only(self) -> None:
        log = self.factories() / "logs" / "droid-log-single.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(droid_log_line("2026-11-05T10:00:00.000Z", "s1", "gpt-6.1-sol", (100, 10, 0, 0)) + "\n")
        self.run_scan("--refresh")
        self.append(log, droid_log_line("2026-11-05T10:05:00.000Z", "s1", "gpt-6.1-sol", (5, 1, 0, 0)) + "\n")
        second = self.run_scan()
        self.assertEqual(self.totals(second, "factory"), 116)
        self.assertEqual(self.agent(second, "factory")["sessions"], 1)

    def test_a_line_split_across_two_scans_is_counted_once(self) -> None:
        log = self.factories() / "logs" / "droid-log-single.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        line = droid_log_line("2026-11-05T10:00:00.000Z", "s1", "gpt-6.1-sol", (100, 10, 0, 0))
        log.write_text(line[:40], encoding="utf-8")
        self.assertEqual(self.totals(self.run_scan("--refresh"), "factory"), 0)
        self.append(log, line[40:] + "\n")
        self.assertEqual(self.totals(self.run_scan(), "factory"), 110)

    # -- antigravity -----------------------------------------------------

    def test_agy_tokens_and_model_selection_carry(self) -> None:
        transcript = self.home / ".gemini" / "antigravity-cli" / "brain" / "conv1" / ".system_generated" / "logs" / "transcript.jsonl"
        transcript.parent.mkdir(parents=True, exist_ok=True)
        steps = [
            {"step_index": 0, "type": "USER_INPUT", "created_at": "2026-11-05T10:00:00Z", "content": "hi"},
            {"step_index": 1, "type": "GENERIC", "created_at": "2026-11-05T10:00:05Z",
             "content": "Model Selection` from None to Gemini 3.8 Flash (High). No need to comment"},
            {"step_index": 2, "type": "PLANNER_RESPONSE", "created_at": "2026-11-05T10:00:10Z",
             "input_tokens": 100, "output_tokens": 20, "cache_read_tokens": 30, "thinking": "x" * 5000},
            {"step_index": 3, "type": "PLANNER_RESPONSE", "created_at": "2026-11-05T10:00:20Z",
             "input_tokens": 50, "output_tokens": 5, "cache_read_tokens": 0},
        ]
        transcript.write_text("\n".join(json.dumps(s) for s in steps) + "\n", encoding="utf-8")
        payload = self.run_scan("--refresh")
        agy = self.agent(payload, "agy")
        self.assertEqual(agy["tokens"], 205)
        self.assertEqual(agy["models"][0]["n"], "gemini-3.8-flash-high")
        self.assertTrue(agy["models"][0]["priced"])

    def test_agy_history_counts_prompts(self) -> None:
        root = self.home / ".gemini" / "antigravity-cli"
        root.mkdir(parents=True, exist_ok=True)
        (root / "history.jsonl").write_text(json.dumps(
            {"display": "make a widget", "timestamp": 1793878127331, "conversationId": "c1"}) + "\n")
        payload = self.run_scan("--refresh")
        self.assertEqual(self.agent(payload, "agy")["prompts"], 1)

    # -- claude ----------------------------------------------------------

    def test_claude_counts_each_reply_once(self) -> None:
        project = self.home / ".claude" / "projects" / "-home-user"
        project.mkdir(parents=True, exist_ok=True)
        reply = {
            "type": "assistant", "timestamp": "2026-11-05T10:00:00Z",
            "message": {"id": "msg_1", "model": "claude-opus-4-6", "usage": {
                "input_tokens": 10, "output_tokens": 200,
                "cache_read_input_tokens": 1000, "cache_creation_input_tokens": 500,
            }},
        }
        prompt = {"type": "user", "timestamp": "2026-11-05T09:59:00Z",
                  "message": {"role": "user", "content": "hello"}}
        tool = {"type": "user", "timestamp": "2026-11-05T10:00:01Z",
                "message": {"role": "user", "content": [{"type": "tool_result", "content": "ok"}]}}
        text = "\n".join(json.dumps(entry) for entry in (prompt, reply, reply, tool)) + "\n"
        (project / "session1.jsonl").write_text(text, encoding="utf-8")
        payload = self.run_scan("--refresh")
        claude = self.agent(payload, "claude")
        self.assertEqual(claude["tokens"], 1710)
        self.assertEqual(claude["prompts"], 1)
        self.assertEqual(claude["models"][0]["n"], "claude-opus-4-6")

    # -- codex -----------------------------------------------------------

    def test_codex_uses_last_token_usage_and_carries_model(self) -> None:
        session = self.home / ".codex" / "sessions" / "2026" / "11" / "05"
        session.mkdir(parents=True, exist_ok=True)
        rows = [
            {"timestamp": "2026-11-05T10:00:00Z", "type": "turn_context", "payload": {"model": "gpt-5.4"}},
            {"timestamp": "2026-11-05T10:00:05Z", "type": "event_msg", "payload": {
                "type": "token_count", "info": {"last_token_usage": {
                    "input_tokens": 1000, "cached_input_tokens": 800, "output_tokens": 50}}}},
        ]
        (session / "rollout-1.jsonl").write_text("\n".join(json.dumps(r) for r in rows) + "\n", encoding="utf-8")
        payload = self.run_scan("--refresh")
        codex = self.agent(payload, "codex")
        self.assertEqual(codex["tokens"], 200 + 50 + 800)
        self.assertEqual(codex["models"][0]["n"], "gpt-5.4")

    # -- gemini cli ------------------------------------------------------

    def test_gemini_transcript_maps_tokens(self) -> None:
        chat = self.home / ".gemini" / "tmp" / "project" / "chats"
        chat.mkdir(parents=True, exist_ok=True)
        document = {"messages": [
            {"type": "user", "timestamp": "2026-11-05T09:00:00Z"},
            {"type": "gemini", "model": "gemini-3.7-flash", "timestamp": "2026-11-05T09:00:05Z",
             "tokens": {"input": 100, "output": 20, "thoughts": 30, "cached": 40, "tool": 0, "total": 190}},
        ]}
        (chat / "session-1.json").write_text(json.dumps(document), encoding="utf-8")
        payload = self.run_scan("--refresh")
        gemini = self.agent(payload, "gemini")
        self.assertEqual(gemini["tokens"], 100 + 50 + 40)
        self.assertTrue(gemini["models"][0]["priced"])

    # -- opencode --------------------------------------------------------

    def test_opencode_sqlite_rows(self) -> None:
        root = self.home / ".local" / "share" / "opencode"
        root.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(root / "opencode.db")
        connection.execute("CREATE TABLE message (id TEXT, data TEXT)")
        connection.execute("INSERT INTO message VALUES (?, ?)", ("m1", json.dumps({
            "role": "assistant", "modelID": "claude-sonnet-4-6",
            "sessionID": "s1", "time": {"created": 1793878127331},
            "tokens": {"input": 12, "output": 34, "cache": {"read": 56, "write": 7}},
        })))
        connection.execute("INSERT INTO message VALUES (?, ?)", ("m2", json.dumps({
            "role": "user", "time": {"created": 1793878127331}, "tokens": {"input": 999}})))
        connection.commit()
        connection.close()
        payload = self.run_scan("--refresh")
        opencode = self.agent(payload, "opencode")
        self.assertEqual(opencode["tokens"], 12 + 34 + 56 + 7)
        # The database is cached by signature; a second run keeps the numbers.
        self.assertEqual(self.agent(self.run_scan(), "opencode")["tokens"], 109)

    # -- pricing and ranges ----------------------------------------------

    def test_published_prices_match_the_list_price_table(self) -> None:
        module = runpy.run_path(str(SCANNER))
        price_for = module["price_for"]
        # Anthropic bills cache writes; OpenAI and Google bill none.
        self.assertEqual(tuple(price_for("claude-opus-5-5")), (4.0, 20.0, 0.2, 5.0))
        self.assertEqual(tuple(price_for("claude-opus-4-6")), (5.0, 25.0, 0.5, 6.25))
        self.assertEqual(tuple(price_for("gpt-6.1-sol")), (2.0, 10.0, 0.1, 2.5))
        self.assertEqual(tuple(price_for("gpt-5.4")), (2.5, 15.0, 0.25, 0.0))
        self.assertEqual(tuple(price_for("deepseek-v4-flash")), (0.3, 1.2, 0.006, 0.0))
        self.assertEqual(tuple(price_for("gemini-3.5-flash")), (1.5, 9.0, 0.15, 0.0))
        self.assertEqual(tuple(price_for("gemini-3.8-flash-high")), (0.75, 3.75, 0.075, 0.0))
        self.assertIsNone(price_for("something-unreleased"))

    def test_model_ids_fold_to_one_spelling(self) -> None:
        module = runpy.run_path(str(SCANNER))
        normalize = module["normalize_model"]
        self.assertEqual(normalize("deepseek-v4.1-flash-1017"), "deepseek-v4.1-flash")
        self.assertEqual(normalize("Gemini 3.8 Flash (High)"), "gemini-3.8-flash-high")
        self.assertEqual(normalize("fireworks/accounts/f/models/gpt-6.1-sol"), "gpt-6.1-sol")
        self.assertEqual(normalize("claude-opus-4-6-20260205"), "claude-opus-4-6")

    def test_unpriced_models_are_named_not_silently_dropped(self) -> None:
        log = self.factories() / "logs" / "droid-log-single.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(droid_log_line("2026-11-05T10:00:00.000Z", "s1", "mystery-model-9", (100, 10, 0, 0)) + "\n")
        payload = self.run_scan("--refresh")
        self.assertEqual(payload["unpriced"][0]["n"], "mystery-model-9")
        self.assertEqual(payload["unpriced"][0]["tokens"], 110)
        self.assertEqual(self.agent(payload, "factory")["cost"], 0)

    def test_history_window_drops_older_days(self) -> None:
        log = self.factories() / "logs" / "droid-log-single.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(
            droid_log_line("2020-01-01T10:00:00.000Z", "s1", "gpt-5", (100, 10, 0, 0)) + "\n"
            + droid_log_line("2026-11-05T10:00:00.000Z", "s1", "gpt-5", (5, 1, 0, 0)) + "\n",
            encoding="utf-8",
        )
        payload = self.run_scan("--refresh", "--days", "30")
        self.assertEqual(self.totals(payload, "factory"), 6)

    def test_a_session_spanning_midnight_is_counted_once(self) -> None:
        log = self.factories() / "logs" / "droid-log-single.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(
            droid_log_line(local_stamp(2026, 11, 4, 23, 50), "late", "gpt-6.1-sol", (10, 1, 0, 0)) + "\n"
            + droid_log_line(local_stamp(2026, 11, 5, 0, 10), "late", "gpt-6.1-sol", (20, 2, 0, 0)) + "\n"
            + droid_log_line(local_stamp(2026, 11, 5, 9, 0), "next", "gpt-6.1-sol", (30, 3, 0, 0)) + "\n",
            encoding="utf-8",
        )
        payload = self.run_scan("--refresh")
        # The agent still reports the session once overall, and the per-day
        # counts add up to that same number.
        self.assertEqual(self.agent(payload, "factory")["sessions"], 2)
        per_day = sum(row[1] for day in payload["days"] for row in day["a"])
        self.assertEqual(per_day, 2)
        self.assertEqual([row[1] for day in payload["days"] for row in day["a"]], [1, 1])

    def test_payload_is_stable_across_repeated_scans(self) -> None:
        log = self.factories() / "logs" / "droid-log-single.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(droid_log_line("2026-11-05T10:00:00.000Z", "s1", "gpt-6.1-sol", (1, 2, 3, 4)) + "\n")
        first = self.run_scan("--refresh")
        second = self.run_scan()
        self.assertEqual(self.totals(first), self.totals(second))
        self.assertEqual(first["days"], second["days"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
