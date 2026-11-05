import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

// Development harness: draws the dashboard offscreen from a synthetic
// payload and writes PNGs, so the layout can be checked without a live bar
// and without a single line of real usage in a screenshot.
//
// Run from this directory:
//   OMARCHY_PATH=/usr/share/omarchy QT_QPA_PLATFORM=offscreen \
//     quickshell -p ./preview.qml
//
// The output is /tmp/preview-*.png.
ShellRoot {
  id: shell

  property var payload: null
  property string range: "30d"
  property string view: "home"
  property string agentId: ""
  property int cursorRow: 0
  property bool cursorActive: false
  property bool wide: false
  property string customKind: ""
  property string customValue: ""
  property string note: ""
  property bool loading: false
  property string lastError: ""

  readonly property var bounds: {
    if (customKind === "day") return Model.dayBounds(customValue) || Model.bounds(range, new Date())
    if (customKind === "month") return Model.monthBounds(customValue) || Model.bounds(range, new Date())
    return Model.bounds(range, new Date())
  }
  readonly property var summary: payload && bounds
    ? Model.summarize(payload, bounds.from, bounds.to) : Model.emptySummary()
  readonly property var chart: bounds
    ? Model.chartSeries(summary, bounds.from, bounds.to, Model.bucketFor(bounds.from, bounds.to)) : []
  readonly property string bucket: bounds ? Model.bucketFor(bounds.from, bounds.to) : "day"
  readonly property string rangeName: Model.rangeLabel(range)
  readonly property int sourceCount: payload && payload.meta
    ? payload.meta.sources.filter(function (entry) { return entry.ok }).length : 0
  readonly property int sourceTotal: payload && payload.meta ? payload.meta.sources.length : 0
  readonly property string updatedLabel: payload ? "updated 12s ago" : ""

  function moveCursor(dx, dy) {}
  function activateCursor() {}
  function close() {}
  function back() {}
  function switchPanel(direction) {}
  function handleTextKey(text) {}
  function setRange(value) { range = value }
  function setDay(value) { customKind = "day"; customValue = value }
  function setMonth(value) { customKind = "month"; customValue = value }
  function clearCustom() { customKind = ""; customValue = "" }
  function openAgent(id) { agentId = id; view = "agent" }
  function showModels() { view = "models" }
  function refresh(force) {}
  function copySummary() {}
  function saveCard() {}

  QtObject {
    id: stringsCatalog
    function t(key, fallback) {
      var map = {
        "panel.title": "Tokenbar",
        "panel.agents": "Agents",
        "panel.models": "Models",
        "panel.allModels": "All models",
        "panel.agent.activeDays": "active days",
        "panel.agent.costPerMillion": "per 1M tokens",
        "panel.agent.cacheHit": "cache hit",
        "panel.agent.perDay": "per active day",
        "panel.agent.prompts": "prompts",
        "panel.agent.topModels": "Models",
        "panel.range.today": "Today",
        "panel.range.7d": "7 days",
        "panel.range.30d": "30 days",
        "panel.range.90d": "90 days",
        "panel.range.1y": "1 year",
        "panel.range.wtd": "WTD",
        "panel.range.mtd": "MTD",
        "panel.range.qtd": "QTD",
        "panel.range.ytd": "YTD",
        "panel.custom.day": "Day",
        "panel.custom.month": "Month",
        "panel.custom.clear": "Clear",
        "panel.sources": "%1 of %2 sources",
        "panel.scan": "scan %1 ms",
        "panel.refresh": "Refresh",
        "panel.copy": "Copy summary",
        "panel.share": "Save card",
        "panel.back": "Back",
        "panel.emptyRange": "Nothing recorded in this range",
        "panel.unpriced": "%1 without a published price",
        "panel.wide": "Wide",
        "panel.compact": "Compact",
        "panel.hint": "1D/7D/30D switch · ↑↓ pick · ↵ open · b back · c copy · r refresh",
        "panel.hint.agent": "↓ ↑ pick a model · b back · c copy · r refresh",
        "panel.noData": "No usage recorded yet",
        "panel.noDataHint": "Once an agent writes a session, its tokens appear here on the next refresh.",
        "panel.unpricedHint": "Their tokens are counted; cost is shown as $0.",
      }
      return map[key] !== undefined ? map[key] : (fallback !== undefined ? fallback : key)
    }
    function tn(key, count, fallback) {
      var text = fallback !== undefined ? fallback : key
      if (count === 1) {
        var single = { "panel.tokens": "%1 token", "panel.prompts": "%1 prompt",
          "panel.agent.activeDays": "%1 active day", "panel.agent.sessions": "%1 session" }[key]
        if (single) text = single
      }
      return text
    }
  }

  readonly property var strings: stringsCatalog

  FileView {
    path: Qt.resolvedUrl("demo-payload.json").toString().replace(/^file:\/\//, "")
    blockLoading: true
    onLoaded: shell.payload = JSON.parse(text())
  }

  FloatingWindow {
    id: window
    visible: true
    color: "#101315"
    implicitWidth: shell.wide ? 820 : 470
    implicitHeight: 800

    Rectangle {
      id: frame
      width: shell.wide ? 820 : 470
      height: dashboard.height + 30
      color: "#101315"

      Dashboard {
        id: dashboard
        width: shell.wide ? 790 : 440
        x: 15
        y: 15
        host: shell
      }
    }
  }

  Timer {
    interval: 1200
    running: true
    onTriggered: frame.grabToImage(function (result) {
      result.saveToFile("/tmp/preview-home.png")
      console.log("PREVIEW home", dashboard.height)
      shell.range = "1y"
    })
  }
  Timer {
    interval: 2000
    running: true
    onTriggered: frame.grabToImage(function (result) {
      result.saveToFile("/tmp/preview-year.png")
      console.log("PREVIEW year", dashboard.height)
      shell.range = "30d"
      shell.view = "agent"
      shell.agentId = "factory"
    })
  }
  Timer {
    interval: 2800
    running: true
    onTriggered: frame.grabToImage(function (result) {
      result.saveToFile("/tmp/preview-agent.png")
      console.log("PREVIEW agent", dashboard.height)
      shell.view = "models"
      shell.agentId = ""
    })
  }
  Timer {
    interval: 3600
    running: true
    onTriggered: frame.grabToImage(function (result) {
      result.saveToFile("/tmp/preview-models.png")
      console.log("PREVIEW models", dashboard.height)
      shell.view = "home"
      shell.wide = true
    })
  }
  Timer {
    interval: 4400
    running: true
    onTriggered: frame.grabToImage(function (result) {
      result.saveToFile("/tmp/preview.png")
      console.log("PREVIEW wide", dashboard.height)
      // What a fresh install shows before any agent has written a line.
      shell.payload = null
      shell.wide = false
      // Range chips and the day picker have nothing to offer with no data.
      shell.customKind = ""
      shell.customValue = ""
    })
  }
  Timer {
    interval: 5200
    running: true
    onTriggered: {
      frame.grabToImage(function (result) {
        result.saveToFile("/tmp/preview-empty.png")
        console.log("PREVIEW empty", dashboard.height)
        Qt.quit()
      })
    }
  }
}
