import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Tokenbar: one bar readout and one dashboard for every coding agent on the
// machine. The scanner (bin/tokenbar-scan) does the reading; this file only
// draws what it wrote, so opening the panel every few minutes costs one
// process and a few milliseconds.
Panel {
  id: root
  moduleName: "io.github.ishesatoshi.tokenbar"
  ipcTarget: "io.github.ishesatoshi.tokenbar"
  manageIpc: false

  Commons.Translations {
    id: translations
    directory: Qt.resolvedUrl("i18n")
  }
  readonly property var strings: translations

  // ---- settings ------------------------------------------------------

  readonly property string displayMode: String(setting("display", "cost"))
  readonly property string barRange: String(setting("range", "today"))
  readonly property int refreshSec: Math.max(30, Math.min(3600, Number(setting("refreshSec", 120))))
  readonly property bool showIcon: setting("showIcon", true) !== false

  // ---- paths ---------------------------------------------------------

  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME")
    || (Quickshell.env("HOME") + "/.cache")) + "/omarchy/tokenbar"
  readonly property string cachePath: cacheDir + "/usage.json"
  readonly property string scanPath: String(Qt.resolvedUrl("bin/tokenbar-scan")).replace(/^file:\/\//, "")

  // ---- state ---------------------------------------------------------

  property var payload: null
  property bool loading: false
  property string lastError: ""
  property double lastPayloadAt: 0
  // Bumped whenever the clock's day could have changed, so ranges that
  // depend on "today" re-evaluate even with no new scan.
  property int dayEpoch: 0

  property string range: "today"
  property string customKind: ""
  property string customValue: ""
  property string view: "home"
  // Wide mode lays the agents and models out side by side, the panel's
  // equivalent of Tokenbar's maximized dashboard.
  property bool wide: false
  property string agentId: ""
  property int cursorRow: 0
  property bool cursorActive: false
  property string note: ""

  readonly property var bounds: {
    var _tick = dayEpoch
    if (customKind === "day") return Model.dayBounds(customValue) || Model.bounds(range, new Date())
    if (customKind === "month") return Model.monthBounds(customValue) || Model.bounds(range, new Date())
    return Model.bounds(range, new Date())
  }
  readonly property var summary: payload && bounds
    ? Model.summarize(payload, bounds.from, bounds.to)
    : Model.emptySummary()
  readonly property var chart: {
    if (!bounds) return []
    return Model.chartSeries(summary, bounds.from, bounds.to, Model.bucketFor(bounds.from, bounds.to))
  }
  readonly property string bucket: bounds ? Model.bucketFor(bounds.from, bounds.to) : "day"
  readonly property string rangeName: customKind === "day"
    ? Model.formatDay(customValue)
    : customKind === "month"
      ? Model.formatMonth(customValue)
      : strings.t("panel.range." + range, range)
  readonly property int sourceCount: payload && payload.meta && payload.meta.sources
    ? payload.meta.sources.filter(function (entry) { return entry.ok }).length : 0
  readonly property int sourceTotal: payload && payload.meta && payload.meta.sources
    ? payload.meta.sources.length : 0
  readonly property string updatedLabel: {
    var _tick = dayEpoch
    return payload
      ? strings.t("panel.updated", "updated %1 ago").arg(Model.formatAge(Date.now() - lastPayloadAt)) : ""
  }

  // The bar's own readout, computed once per refresh rather than per paint.
  readonly property var barSummary: {
    var _tick = dayEpoch
    if (!payload) return Model.emptySummary()
    var window = Model.bounds(barRange, new Date())
    return Model.summarize(payload, window.from, window.to)
  }
  readonly property string barLabel: {
    if (!payload) return "—"
    var parts = []
    if (displayMode === "cost" || displayMode === "both") parts.push(Model.formatCost(barSummary.cost))
    if (displayMode === "tokens" || displayMode === "both") parts.push(Model.formatTokens(barSummary.tokens))
    return parts.join(" · ")
  }
  readonly property string barTooltip: {
    if (!payload) return strings.t("panel.title", "Tokenbar")
    var today = Model.dayTotal(payload, Model.todayKey())
    var week = Model.lastNDays(payload, 7)
    var month = Model.lastNDays(payload, 30)
    return strings.t("panel.title", "Tokenbar") + "\n"
      + strings.t("panel.range.today", "Today") + "  " + Model.formatCost(today.cost) + " · " + Model.formatTokens(today.tokens) + "\n"
      + strings.t("panel.range.7d", "7 days") + "  " + Model.formatCost(week.cost) + " · " + Model.formatTokens(week.tokens) + "\n"
      + strings.t("panel.range.30d", "30 days") + "  " + Model.formatCost(month.cost) + " · " + Model.formatTokens(month.tokens)
  }

  // ---- data ----------------------------------------------------------

  function adopt(text) {
    if (!text) return
    var parsed
    try {
      parsed = JSON.parse(String(text))
    } catch (error) {
      if (!payload) lastError = String(error)
      return
    }
    if (!parsed || parsed.schemaVersion !== 4) return
    // A cache read and a fresh scan can land in either order; the newer
    // payload always wins.
    if (payload && parsed.generatedAt && payload.generatedAt > parsed.generatedAt) return
    payload = parsed
    lastPayloadAt = Date.now()
    lastError = ""
    dayEpoch += 1
  }

  function refresh(force) {
    if (scanner.running) return
    loading = true
    var args = ["python3", scanPath, "--json"]
    if (force) args.push("--refresh")
    scanner.command = args
    scanner.running = true
  }

  function refreshIfStale() {
    if (!payload || Date.now() - lastPayloadAt > 20000) refresh(false)
  }

  FileView {
    id: cacheFile
    path: root.cachePath
    watchChanges: true
    printErrors: false
    blockLoading: true
    onLoaded: root.adopt(text())
    onFileChanged: reload()
  }

  Process {
    id: scanner
    command: ["python3", root.scanPath, "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.adopt(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") root.lastError = message
      }
    }
    onExited: function (code) {
      root.loading = false
      if (code !== 0 && !root.payload) root.lastError = "scanner exited " + code
    }
  }

  Timer {
    // Reading only the appended bytes is cheap enough to run often, and the
    // interval is the user's call in settings.
    interval: root.refreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  Timer {
    // Ranges are anchored to the local day; cross midnight without waiting
    // for a scan to notice.
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      if (Model.todayKey() !== root.lastKnownDay) {
        root.lastKnownDay = Model.todayKey()
        root.dayEpoch += 1
      }
      root.note = ""
    }
  }
  property string lastKnownDay: Model.todayKey()

  // ---- panel lifecycle ----------------------------------------------

  function open() {
    root.controller.show()
    refreshIfStale()
  }

  function close() {
    note = ""
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root, direction)
    return false
  }

  ShellIpc {
    target: "io.github.ishesatoshi.tokenbar"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh(true) }
  }

  // ---- navigation ----------------------------------------------------

  function setRange(next) {
    range = next
    customKind = ""
    customValue = ""
    cursorRow = 0
    cursorActive = false
  }

  function setDay(day) {
    if (!day) return
    customKind = "day"
    customValue = day
    cursorRow = 0
  }

  function setMonth(month) {
    if (!month) return
    customKind = "month"
    customValue = month
    cursorRow = 0
  }

  function clearCustom() {
    customKind = ""
    customValue = ""
    cursorRow = 0
  }

  function rowsInView() {
    if (view === "home") return summary.agents.length
    return summary.models.length
  }

  function moveCursor(dx, dy) {
    if (view === "home" && dx !== 0) {
      // Left and right walk the range, the way the chips read.
      var index = Model.RANGES.indexOf(range)
      if (index < 0) index = 0
      index = (index + dx + Model.RANGES.length) % Model.RANGES.length
      setRange(Model.RANGES[index])
      return
    }
    if (dy === 0) return
    var count = rowsInView()
    if (count === 0) return
    if (!cursorActive) {
      cursorActive = true
      cursorRow = Math.max(0, Math.min(cursorRow, count - 1))
      return
    }
    cursorRow = (cursorRow + dy + count) % count
  }

  function openAgent(id) {
    if (!id) return
    agentId = id
    view = "agent"
    cursorRow = 0
    cursorActive = false
  }

  function showModels() {
    view = "models"
    cursorRow = 0
    cursorActive = false
  }

  function back() {
    if (view !== "home") {
      view = "home"
      agentId = ""
      cursorRow = 0
      cursorActive = false
    } else if (customKind !== "") {
      clearCustom()
    }
  }

  function activateCursor() {
    if (view === "home") {
      var agent = summary.agents[Math.max(0, Math.min(cursorRow, summary.agents.length - 1))]
      if (agent) openAgent(agent.id)
      return
    }
    if (view === "models" && summary.models.length > 0) {
      var model = summary.models[Math.max(0, Math.min(cursorRow, summary.models.length - 1))]
      if (model) {
        // A model can be used by more than one agent; open the one that
        // spent the most on it.
        var owners = summary.agents.filter(function (entry) {
          return entry.models.some(function (item) { return item.n === model.n })
        })
        if (owners.length > 0) openAgent(owners[0].id)
      }
    }
  }

  function handleTextKey(text) {
    if (text === "r" || text === "R") { refresh(true); return }
    if (text === "c" || text === "C") { copySummary(); return }
    if (text === "b" || text === "B") { back(); return }
    if (text === "m" || text === "M") { view === "models" ? back() : showModels(); return }
    if (text === "w" || text === "W") { wide = !wide; return }
    if (text === "1") { setRange("today"); return }
    if (text === "7") { setRange("7d"); return }
    if (text === "3") { setRange("30d"); return }
  }

  // ---- sharing -------------------------------------------------------

  readonly property string shareText: {
    var lines = [strings.t("panel.title", "Tokenbar") + " — " + rangeName]
    lines.push(Model.formatCost(summary.cost) + " · " + Model.formatTokens(summary.tokens)
      + " " + strings.t("panel.tokens", "%1 tokens").replace("%1", "").trim())
    for (var i = 0; i < summary.agents.length; i++) {
      var agent = summary.agents[i]
      lines.push("  " + agent.name + "  " + Model.formatCost(agent.cost) + "  " + Model.formatTokens(agent.tokens))
    }
    for (var j = 0; j < Math.min(4, summary.models.length); j++) {
      var model = summary.models[j]
      lines.push("  " + model.n + "  " + Model.formatCost(model.cost) + "  " + Model.formatTokens(model.tokens))
    }
    lines.push("estimated from local logs")
    return lines.join("\n")
  }

  function copySummary() {
    if (!payload) return
    clipper.command = ["wl-copy", shareText]
    clipper.running = true
    note = strings.t("panel.copied", "Summary copied to the clipboard")
    noteTimer.restart()
  }

  Process {
    id: clipper
    command: ["wl-copy", ""]
    onExited: function (code) {
      if (code !== 0) {
        root.note = "wl-copy failed (" + code + ")"
        noteTimer.restart()
      }
    }
  }

  Timer {
    id: noteTimer
    interval: 2600
    onTriggered: root.note = ""
  }

  // The card is rendered by bin/tokenbar-card, which writes an SVG (and a
  // PNG when a converter is installed) at 2400x1350 in the current theme's
  // colours. Keeping it out of the shell means a card can never stall the
  // panel or depend on a hidden item being rendered.
  property string cardPath: ""
  readonly property string picturesDir: Quickshell.env("HOME") + "/Pictures/Tokenbar"

  function saveCard() {
    if (!payload || !bounds) return
    root.cardPath = ""
    cardProcess.running = false
    cardProcess.command = [
      "python3", String(Qt.resolvedUrl("bin/tokenbar-card")).replace(/^file:\/\//, ""),
      "--from", bounds.from,
      "--to", bounds.to,
      "--out", picturesDir,
      "--fg", String(root.bar ? root.bar.foreground : Commons.Color.foreground),
      "--bg", String(Commons.Color.background),
      "--accent", String(Commons.Color.accent),
      "--title", rangeName,
    ]
    cardProcess.running = true
  }


  Process {
    id: cardProcess
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var written = String(text || "").trim().split("\n").pop()
        if (written !== "") {
          root.cardPath = written
          root.note = root.strings.t("panel.saved", "Card saved to %1").arg(written)
        }
      }
    }
    onExited: function (code) {
      if (code !== 0) root.note = root.strings.t("panel.saveFailed", "Could not save the card")
      else if (root.cardPath === "") root.note = root.strings.t("panel.saveFailed", "Could not save the card")
      noteTimer.restart()
    }
  }

  // ---- bar button ----------------------------------------------------

  TextMetrics {
    id: valueMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.bar.iconFont
    text: root.barLabel
  }

  property Item anchorItem: button

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showIcon ? "\uf201" : ""
    labelText: root.vertical ? "" : root.barLabel
    // The pill grows with its value: a dollar amount is wider than an icon
    // slot, and clipping it would be worse than a wider widget.
    slotSize: root.vertical
      ? Style.bar.iconSlot
      : Math.max(Style.bar.iconSlot,
          (root.showIcon ? Style.bar.iconCanvas : 0) + valueMetrics.advanceWidth + Style.space(8))
    tooltipText: root.barTooltip
    active: root.loading
    onPressed: function (code) {
      if (code === Qt.RightButton) root.refresh(true)
      else if (code === Qt.MiddleButton) root.cycleDisplay()
      else root.toggle()
    }
  }

  function cycleDisplay() {
    var order = ["cost", "tokens", "both"]
    var next = order[(order.indexOf(displayMode) + 1) % order.length]
    if (root.bar && typeof root.bar.run === "function")
      root.bar.run("omarchy bar set io.github.ishesatoshi.tokenbar display " + next)
    else
      root.note = "display: " + next
  }

  // ---- panel ---------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(root.wide ? Style.space(820) : Style.space(470))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, root.wide ? Style.space(760) : Style.space(640))

    content: Dashboard {
      host: root
    }
  }

  // The panel's content is built lazily on first open; this is how the rest
  // of the file (and a smoke test) reaches it once it exists.
  readonly property Item dashboard: panel.loadedContent
}
