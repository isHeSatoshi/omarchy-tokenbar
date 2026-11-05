// Range math, aggregation and formatting tests for Model.js.
//
// Node has no Qt, so the two date formatters are given a stub: every other
// function under test is pure arithmetic over the payload shape that
// bin/tokenbar-scan writes.
//
// Run: node tests/model.test.mjs

import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import assert from "node:assert/strict"

const here = dirname(fileURLToPath(import.meta.url))
const source = readFileSync(join(here, "..", "Model.js"), "utf8")

globalThis.Qt = {
  formatDate: (date, format) => {
    const pad = (n) => String(n).padStart(2, "0")
    const months = ["January", "February", "March", "April", "May", "June", "July",
      "August", "September", "October", "November", "December"]
    const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    if (format === "MMMM yyyy") return `${months[date.getMonth()]} ${date.getFullYear()}`
    if (format === "d MMM") return `${date.getDate()} ${months[date.getMonth()].slice(0, 3)}`
    return `${days[date.getDay()]} ${date.getDate()} ${months[date.getMonth()].slice(0, 3)}`
  },
}

// Model.js is a QML JS library: drop the pragma and hand back its functions
// from a Function context, which is the same scope QML gives them.
const body = source.replace(/^\.pragma library\s*$/m, "")
const names = ["bounds", "monthBounds", "dayBounds", "daysBetween", "summarize", "isPriced",
  "chartSeries", "bucketFor", "formatCost", "formatTokens", "formatPercent", "formatAge",
  "formatDay", "formatMonth", "rangeLabel", "dayTotal", "lastNDays", "todayKey", "emptySummary"]
const Model = new Function(`${body}\nreturn { ${names.join(", ")} }`)()

let passed = 0
function test(name, fn) {
  fn()
  passed += 1
  console.log(`  ok  ${name}`)
}

// A payload with two agents over three days, in the scanner's own encoding.
const payload = {
  schemaVersion: 4,
  agentIds: ["agy", "factory"],
  modelNames: ["gemini-3.8-flash-high", "gpt-6.1-sol", "mystery-9"],
  agents: [
    { id: "agy", name: "Antigravity" },
    { id: "factory", name: "Droid" },
  ],
  days: [
    { d: "2026-11-03", r: [[0, 0, 100, 10, 0, 0, 1000000]], a: [[0, 1, 2]] },
    { d: "2026-11-04", r: [[1, 1, 200, 20, 30, 0, 5000000]], a: [[1, 2, 5]] },
    { d: "2026-11-05", r: [[1, 2, 7, 3, 0, 0, 0], [0, 0, 50, 5, 0, 0, 500000]], a: [[0, 1, 1], [1, 3, 4]] },
    { d: "2020-01-01", r: [[1, 1, 999, 999, 999, 999, 999999999]], a: [] },
  ],
  unpriced: [{ n: "mystery-9", tokens: 10 }],
  meta: { sources: [] },
}

test("bounds covers seven inclusive days", () => {
  const now = new Date(2026, 10, 5)
  const range = Model.bounds("7d", now)
  assert.equal(range.from, "2026-10-30")
  assert.equal(range.to, "2026-11-05")
  assert.equal(Model.daysBetween(range.from, range.to), 7)
})

test("bounds for week, month, quarter and year to date start on the local boundary", () => {
  const now = new Date(2026, 10, 5) // Thursday 5 November 2026
  assert.equal(Model.bounds("wtd", now).from, "2026-11-02")
  assert.equal(Model.bounds("mtd", now).from, "2026-11-01")
  assert.equal(Model.bounds("qtd", now).from, "2026-10-01")
  assert.equal(Model.bounds("ytd", now).from, "2026-01-01")
  assert.equal(Model.bounds("today", now).from, "2026-11-05")
})

test("a month and a day resolve to their own inclusive bounds", () => {
  assert.deepEqual(Model.monthBounds("2026-02"), { from: "2026-02-01", to: "2026-02-28" })
  assert.deepEqual(Model.dayBounds("2026-11-05"), { from: "2026-11-05", to: "2026-11-05" })
  assert.equal(Model.dayBounds("nonsense"), null)
})

test("summarize adds only the days in range", () => {
  const summary = Model.summarize(payload, "2026-11-03", "2026-11-04")
  assert.equal(summary.cost, 6000000)
  assert.equal(summary.tokens, 110 + 250)
  assert.equal(summary.prompts, 7)
  assert.deepEqual(summary.agents.map((a) => a.id), ["factory", "agy"])
  assert.equal(summary.activeDays, 2)
})

test("summarize keeps a day with prompts but no tokens in the active count", () => {
  const summary = Model.summarize(payload, "2026-11-05", "2026-11-05")
  assert.equal(summary.tokens, 65)
  assert.equal(summary.prompts, 5)
  assert.equal(summary.activeDays, 1)
})

test("summarize can narrow to one agent", () => {
  const summary = Model.summarize(payload, "2026-11-03", "2026-11-05", "agy")
  assert.equal(summary.tokens, 165)
  assert.equal(summary.cost, 1500000)
  assert.equal(summary.prompts, 3)
  assert.deepEqual(summary.agents.map((a) => a.id), ["agy"])
})

test("a model without a price is kept and marked unpriced", () => {
  const summary = Model.summarize(payload, "2026-11-05", "2026-11-05")
  const mystery = summary.models.find((m) => m.n === "mystery-9")
  assert.ok(mystery)
  assert.equal(mystery.priced, false)
  assert.equal(Model.isPriced(payload, "gpt-6.1-sol"), true)
})

test("agent metrics describe its own mix", () => {
  const summary = Model.summarize(payload, "2026-11-04", "2026-11-04")
  const agent = summary.agents[0]
  assert.equal(agent.costPerMillion, Math.round(5000000 / 250 * 1000000))
  assert.equal(agent.cacheHitRate, 30 / 230)
})

test("agent rows carry the sessions, prompts and active days of the range", () => {
  const summary = Model.summarize(payload, "2026-11-03", "2026-11-05")
  const factory = summary.agents.find((a) => a.id === "factory")
  // 5 + 4 prompts and 2 + 3 sessions, over the 4th and 5th.
  assert.equal(factory.prompts, 9)
  assert.equal(factory.sessions, 5)
  assert.equal(factory.activeDays, 2)

  const agy = summary.agents.find((a) => a.id === "agy")
  // 2 prompts on the 3rd from activity, 1 on the 5th, and a token-only day.
  assert.equal(agy.prompts, 3)
  assert.equal(agy.sessions, 2)
  assert.equal(agy.activeDays, 2)
})

test("a day with prompts but no token rows still names its agent", () => {
  const summary = Model.summarize(payload, "2026-11-05", "2026-11-05", "agy")
  assert.equal(summary.agents.length, 1)
  assert.equal(summary.agents[0].id, "agy")
  assert.equal(summary.agents[0].sessions, 1)
  assert.equal(summary.agents[0].models.length, 1)
})

test("chartSeries fills empty days and folds buckets", () => {
  const day = Model.chartSeries({ series: [{ date: "2026-11-04", cost: 10, tokens: 1, prompts: 0 }] },
    "2026-11-03", "2026-11-05", "day")
  assert.equal(day.length, 3)
  assert.equal(day[1].cost, 10)
  assert.equal(day[0].cost, 0)

  const week = Model.chartSeries({ series: [{ date: "2026-11-04", cost: 10, tokens: 1, prompts: 0 }] },
    "2026-10-26", "2026-11-08", "week")
  // Two Mondays: 26 Oct and 2 Nov.
  assert.equal(week.length, 2)
  assert.equal(week[1].cost, 10)
})

test("bucket width follows the range length", () => {
  assert.equal(Model.bucketFor("2026-11-01", "2026-11-10"), "day")
  assert.equal(Model.bucketFor("2026-09-01", "2026-11-10"), "week")
  assert.equal(Model.bucketFor("2025-11-01", "2026-11-10"), "month")
})

test("formatters stay compact", () => {
  assert.equal(Model.formatCost(0), "$0.00")
  assert.equal(Model.formatCost(4000000), "<$0.01")
  assert.equal(Model.formatCost(1234567890), "$1.23")
  assert.equal(Model.formatCost(2340000000000), "$2.3k")
  assert.equal(Model.formatTokens(999), "999")
  assert.equal(Model.formatTokens(12300), "12k")
  assert.equal(Model.formatTokens(2500000), "2.5M")
  assert.equal(Model.formatTokens(2100000000), "2.1B")
  assert.equal(Model.formatPercent(0.6666), "67%")
  assert.equal(Model.formatAge(5000), "5s")
  assert.equal(Model.formatAge(120000), "2m")
})

test("dayTotal answers the bar without building a range", () => {
  assert.equal(Model.dayTotal(payload, "2026-11-05").cost, 500000)
  assert.equal(Model.dayTotal(payload, "2026-11-05").tokens, 65)
  assert.equal(Model.dayTotal(payload, "2026-01-01").cost, 0)
})

test("an unknown day is not counted as active", () => {
  const summary = Model.summarize(payload, "2026-11-06", "2026-11-06")
  assert.equal(summary.activeDays, 0)
  assert.equal(summary.tokens, 0)
  assert.deepEqual(summary.series, [])
})

console.log(`\n${passed} model tests passed`)
