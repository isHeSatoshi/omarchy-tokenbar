.pragma library
// Range math, aggregation and formatting for Tokenbar.
//
// The payload from bin/tokenbar-scan is deliberately thin: one row per day,
// agent and model, with token counts and an estimated cost in billionths of
// a dollar (nano). Everything a view needs is derived here, so a preset
// range and a hand-picked day are computed by the same code and cannot
// disagree.

var NANO = 1000000000

var RANGES = ["today", "7d", "30d", "90d", "1y", "wtd", "mtd", "qtd", "ytd"]

function pad(value) {
  return (value < 10 ? "0" : "") + value
}

function dateKey(date) {
  return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
}

function parseKey(text) {
  var parts = String(text || "").split("-")
  if (parts.length !== 3) return null
  var year = parseInt(parts[0], 10), month = parseInt(parts[1], 10), day = parseInt(parts[2], 10)
  if (!isFinite(year) || !isFinite(month) || !isFinite(day)) return null
  return new Date(year, month - 1, day)
}

function startOfDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

function addDays(date, days) {
  var next = startOfDay(date)
  next.setDate(next.getDate() + days)
  return next
}

function startOfWeek(date) {
  var day = startOfDay(date)
  var shift = (day.getDay() + 6) % 7 // Monday is the first day of the week
  return addDays(day, -shift)
}

function startOfMonth(date) {
  return new Date(date.getFullYear(), date.getMonth(), 1)
}

function startOfQuarter(date) {
  return new Date(date.getFullYear(), Math.floor(date.getMonth() / 3) * 3, 1)
}

function startOfYear(date) {
  return new Date(date.getFullYear(), 0, 1)
}

function todayKey(now) {
  return dateKey(startOfDay(now || new Date()))
}

// From and to are inclusive local date keys.
function bounds(range, now) {
  var today = startOfDay(now || new Date())
  var from = today
  switch (range) {
  case "today": from = today; break
  case "7d": from = addDays(today, -6); break
  case "30d": from = addDays(today, -29); break
  case "90d": from = addDays(today, -89); break
  case "1y": from = addDays(today, -364); break
  case "wtd": from = startOfWeek(today); break
  case "mtd": from = startOfMonth(today); break
  case "qtd": from = startOfQuarter(today); break
  case "ytd": from = startOfYear(today); break
  default: from = addDays(today, -6)
  }
  return { from: dateKey(from), to: dateKey(today) }
}

function monthBounds(text) {
  var match = /^(\d{4})-(\d{2})$/.exec(String(text || ""))
  if (!match) return null
  var year = parseInt(match[1], 10), month = parseInt(match[2], 10)
  var first = new Date(year, month - 1, 1)
  var last = new Date(year, month, 0)
  return { from: dateKey(first), to: dateKey(last) }
}

function dayBounds(text) {
  var date = parseKey(text)
  return date ? { from: dateKey(date), to: dateKey(date) } : null
}

function daysBetween(from, to) {
  var start = parseKey(from), end = parseKey(to)
  if (!start || !end) return 0
  return Math.round((end - start) / 86400000) + 1
}

function emptySummary() {
  return {
    cost: 0, tokens: 0, input: 0, output: 0, cacheRead: 0, cacheWrite: 0,
    prompts: 0, activeDays: 0, agents: [], models: [], series: [],
  }
}

function agentMeta(payload) {
  var meta = {}
  var list = (payload && payload.agents) || []
  for (var i = 0; i < list.length; i++) meta[list[i].id] = list[i]
  return meta
}

// Everything between two date keys, inclusive. Rows are
// [agentIndex, modelIndex, input, output, cacheRead, cacheWrite, costNano].
function summarize(payload, from, to, agentFilter) {
  var result = emptySummary()
  if (!payload || !payload.days || !from || !to) return result

  var meta = agentMeta(payload)
  var agents = {}
  var models = {}
  var names = payload.modelNames || []
  var ids = payload.agentIds || []

  for (var d = 0; d < payload.days.length; d++) {
    var day = payload.days[d]
    if (day.d < from || day.d > to) continue
    var dayCost = 0, dayTokens = 0, dayPrompts = 0

    var rows = day.r || []
    for (var r = 0; r < rows.length; r++) {
      var row = rows[r]
      var agentId = ids[row[0]] || "unknown"
      if (agentFilter && agentId !== agentFilter) continue
      var modelName = row[1] >= 0 ? (names[row[1]] || "unknown") : "unknown"
      var tokens = row[2] + row[3] + row[4] + row[5]
      var cost = row[6] || 0

      var agent = agents[agentId]
      if (!agent) {
        agent = agents[agentId] = {
          id: agentId,
          name: (meta[agentId] && meta[agentId].name) || agentId,
          cost: 0, tokens: 0, input: 0, output: 0, cacheRead: 0, cacheWrite: 0,
          sessions: 0, prompts: 0, models: {}, lastDay: "", dayKeys: {},
        }
      }
      agent.cost += cost
      agent.tokens += tokens
      agent.input += row[2]
      agent.output += row[3]
      agent.cacheRead += row[4]
      agent.cacheWrite += row[5]
      if (day.d >= agent.lastDay) agent.lastDay = day.d
      agent.dayKeys[day.d] = true

      var owner = agent.models[modelName]
      if (!owner) owner = agent.models[modelName] = { n: modelName, cost: 0, tokens: 0, priced: true }
      owner.cost += cost
      owner.tokens += tokens

      var model = models[modelName]
      if (!model) model = models[modelName] = { n: modelName, cost: 0, tokens: 0, agents: {} }
      model.cost += cost
      model.tokens += tokens
      model.agents[agentId] = true

      dayCost += cost
      dayTokens += tokens
    }

    var activity = day.a || []
    for (var a = 0; a < activity.length; a++) {
      var actId = ids[activity[a][0]] || "unknown"
      if (agentFilter && actId !== agentFilter) continue
      var actPrompts = activity[a][2] || 0
      result.prompts += actPrompts
      dayPrompts += actPrompts

      // Sessions and prompts belong to the agent they were recorded for, so
      // the drill-down can show the same counts the range total does.
      var actAgent = agents[actId]
      if (!actAgent) {
        actAgent = agents[actId] = {
          id: actId,
          name: (meta[actId] && meta[actId].name) || actId,
          cost: 0, tokens: 0, input: 0, output: 0, cacheRead: 0, cacheWrite: 0,
          sessions: 0, prompts: 0, models: {}, lastDay: "", dayKeys: {},
        }
      }
      actAgent.sessions += activity[a][1] || 0
      actAgent.prompts += actPrompts
      actAgent.dayKeys[day.d] = true
    }

    if (dayCost || dayTokens || dayPrompts) {
      result.series.push({ date: day.d, cost: dayCost, tokens: dayTokens, prompts: dayPrompts })
      result.activeDays += 1
    }
    result.cost += dayCost
    result.tokens += dayTokens
    for (var r2 = 0; r2 < rows.length; r2++) {
      var row2 = rows[r2]
      result.input += row2[2]
      result.output += row2[3]
      result.cacheRead += row2[4]
      result.cacheWrite += row2[5]
    }
  }

  var agentList = []
  for (var key in agents) {
    var entry = agents[key]
    entry.activeDays = 0
    for (var dayName in entry.dayKeys) entry.activeDays += 1
    delete entry.dayKeys
    var modelList = []
    var priced = true
    for (var modelKey in entry.models) {
      modelList.push(entry.models[modelKey])
      if (!isPriced(payload, modelKey)) priced = false
    }
    entry.models = modelList.sort(function (a, b) { return b.cost - a.cost || b.tokens - a.tokens })
    entry.priced = priced
    // The cost of a million of this agent's tokens, the way Tokenbar reports
    // it: what the same mix would cost at scale.
    entry.costPerMillion = entry.tokens > 0 ? Math.round(entry.cost / entry.tokens * 1000000) : 0
    entry.cacheHitRate = (entry.input + entry.cacheRead) > 0
      ? entry.cacheRead / (entry.input + entry.cacheRead) : 0
    agentList.push(entry)
  }
  result.agents = agentList.sort(function (a, b) { return b.cost - a.cost || b.tokens - a.tokens })

  var modelListAll = []
  for (var modelKey2 in models) {
    var modelEntry = models[modelKey2]
    modelEntry.priced = isPriced(payload, modelKey2)
    modelListAll.push(modelEntry)
  }
  result.models = modelListAll.sort(function (a, b) { return b.cost - a.cost || b.tokens - a.tokens })

  // Active days are counted from activity, not only from token rows: a day
  // with prompts and no recorded tokens still happened.
  var seen = {}
  for (var s = 0; s < result.series.length; s++) seen[result.series[s].date] = true
  for (var d2 = 0; d2 < payload.days.length; d2++) {
    var day2 = payload.days[d2]
    if (day2.d < from || day2.d > to) continue
    var acts = day2.a || []
    for (var a2 = 0; a2 < acts.length; a2++) {
      if (agentFilter && (ids[acts[a2][0]] || "unknown") !== agentFilter) continue
      seen[day2.d] = true
    }
  }
  result.activeDays = 0
  for (var dayKey in seen) result.activeDays += 1

  return result
}

function isPriced(payload, modelName) {
  var missing = (payload && payload.unpriced) || []
  for (var i = 0; i < missing.length; i++) {
    if (missing[i].n === modelName) return false
  }
  return true
}

// A contiguous series for the chart: every day in range, empty days zeroed,
// then folded into buckets so a year is never 365 slivers.
function chartSeries(summary, from, to, bucket) {
  var byDate = {}
  var points = summary.series || []
  for (var i = 0; i < points.length; i++) byDate[points[i].date] = points[i]

  var start = parseKey(from), end = parseKey(to)
  if (!start || !end) return []
  var buckets = []
  var cursor = startOfDay(start)
  var guard = 0
  while (cursor <= end && guard++ < 4000) {
    var key = dateKey(cursor)
    var bucketKey = key
    if (bucket === "week") {
      bucketKey = dateKey(startOfWeek(cursor))
    } else if (bucket === "month") {
      bucketKey = key.slice(0, 7) + "-01"
    }
    var entry = buckets[buckets.length - 1]
    if (!entry || entry.key !== bucketKey) {
      entry = { key: bucketKey, label: bucketKey, cost: 0, tokens: 0, prompts: 0, days: 0 }
      buckets.push(entry)
    }
    var point = byDate[key]
    if (point) {
      entry.cost += point.cost
      entry.tokens += point.tokens
      entry.prompts += point.prompts
      entry.days += 1
    }
    cursor = addDays(cursor, 1)
  }
  return buckets
}

function bucketFor(from, to) {
  var count = daysBetween(from, to)
  if (count <= 45) return "day"
  if (count <= 190) return "week"
  return "month"
}

// ---- formatting ---------------------------------------------------------

function formatCost(nano, precise) {
  var dollars = (nano || 0) / NANO
  if (dollars <= 0) return "$0.00"
  if (dollars < 0.01) return "<$0.01"
  if (dollars >= 1000) return "$" + (dollars / 1000).toFixed(1) + "k"
  if (precise && dollars < 10) return "$" + dollars.toFixed(2)
  return "$" + dollars.toFixed(dollars >= 100 ? 0 : 2)
}

function formatTokens(count) {
  var value = count || 0
  if (value >= 1e9) return (value / 1e9).toFixed(1) + "B"
  if (value >= 1e6) return (value / 1e6).toFixed(value >= 1e7 ? 0 : 1) + "M"
  if (value >= 1e3) return (value / 1e3).toFixed(value >= 1e4 ? 0 : 1) + "k"
  return String(value)
}

function formatCount(count) {
  return String(count || 0)
}

function formatPercent(fraction) {
  return Math.round((fraction || 0) * 100) + "%"
}

function formatAge(ms) {
  var seconds = Math.max(0, Math.round((ms || 0) / 1000))
  if (seconds < 60) return seconds + "s"
  if (seconds < 3600) return Math.round(seconds / 60) + "m"
  if (seconds < 86400) return Math.round(seconds / 3600) + "h"
  return Math.round(seconds / 86400) + "d"
}

function formatDay(key) {
  var date = parseKey(key)
  if (!date) return String(key || "")
  return Qt.formatDate(date, "ddd d MMM")
}

function formatMonth(key) {
  var date = parseKey(key)
  if (!date) return String(key || "")
  return Qt.formatDate(date, "MMMM yyyy")
}

function rangeLabel(range) {
  switch (range) {
  case "today": return "Today"
  case "7d": return "7 days"
  case "30d": return "30 days"
  case "90d": return "90 days"
  case "1y": return "1 year"
  case "wtd": return "Week to date"
  case "mtd": return "Month to date"
  case "qtd": return "Quarter to date"
  case "ytd": return "Year to date"
  default: return range
  }
}

// What the bar says at a glance: one day's totals, without building a range.
function dayTotal(payload, key) {
  var total = { cost: 0, tokens: 0 }
  if (!payload || !payload.days) return total
  for (var i = 0; i < payload.days.length; i++) {
    var day = payload.days[i]
    if (day.d !== key) continue
    var rows = day.r || []
    for (var r = 0; r < rows.length; r++) {
      total.cost += rows[r][6] || 0
      total.tokens += rows[r][2] + rows[r][3] + rows[r][4] + rows[r][5]
    }
  }
  return total
}

function lastNDays(payload, days, now) {
  var today = startOfDay(now || new Date())
  var from = dateKey(addDays(today, -(days - 1)))
  return summarize(payload, from, dateKey(today))
}
