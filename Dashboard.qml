import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The panel body. All state lives on the Panel (host) so the bar readout and
// the dashboard always agree; this file draws the current view and forwards
// keys back.
Item {
  id: root

  property var host: null

  readonly property var strings: host ? host.strings : null
  readonly property var payload: host ? host.payload : null
  readonly property var summary: host ? host.summary : Model.emptySummary()
  readonly property var bounds: host ? host.bounds : null
  readonly property string view: host ? host.view : "home"
  readonly property int cursorRow: host ? host.cursorRow : 0
  readonly property bool cursorActive: host ? host.cursorActive : false
  readonly property bool wide: host ? host.wide === true : false
  readonly property color foreground: host && host.bar ? host.bar.foreground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Util.alpha(foreground, 0.55)
  readonly property color faint: Util.alpha(foreground, 0.35)
  readonly property color hoverFill: Style.selectedFillFor(foreground, accent)
  readonly property string fontFamily: host && host.bar ? host.bar.fontFamily : Style.font.family

  function tr(key, fallback) {
    return strings ? strings.t(key, fallback) : fallback
  }

  // A translated string with a count, so a language can pick its own plural
  // form. The catalog value still carries a %1, so fill it here; callers get
  // a finished string and never chain .arg() onto it. Pass `value` when the
  // number should be shown compactly ("232M") rather than in full.
  function trn(key, count, fallback, value) {
    var text = strings && typeof strings.tn === "function"
      ? strings.tn(key, count, fallback)
      : String(fallback || key)
    return String(text).replace("%1", value !== undefined ? value : Model.formatCount(count))
  }

  function agentSummary() {
    if (!host || !host.agentId || !payload || !bounds) return Model.emptySummary()
    return Model.summarize(payload, bounds.from, bounds.to, host.agentId)
  }

  readonly property var detail: agentSummary()

  implicitWidth: Style.space(440)
  implicitHeight: column.implicitHeight

  // ---- day and month options ----------------------------------------

  readonly property var dayOptions: {
    var out = [{ value: "", label: tr("panel.custom.day", "Day") }]
    if (!payload) return out
    var days = []
    for (var i = 0; i < payload.days.length; i++) days.push(payload.days[i].d)
    days.sort()
    days.reverse()
    for (var j = 0; j < Math.min(days.length, 120); j++)
      out.push({ value: days[j], label: Model.formatDay(days[j]) })
    return out
  }

  readonly property var monthOptions: {
    var out = [{ value: "", label: tr("panel.custom.month", "Month") }]
    if (!payload) return out
    var months = []
    var seen = ({})
    for (var i = 0; i < payload.days.length; i++) {
      var key = String(payload.days[i].d).slice(0, 7)
      if (!seen[key]) { seen[key] = true; months.push(key) }
    }
    months.sort()
    months.reverse()
    for (var j = 0; j < Math.min(months.length, 36); j++)
      out.push({ value: months[j], label: Model.formatMonth(months[j] + "-01") })
    return out
  }

  // ---- keys ----------------------------------------------------------

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    blocked: dayDropdown.popupOpen || monthDropdown.popupOpen
    onMoveRequested: function (dx, dy) { host.moveCursor(dx, dy) }
    onActivateRequested: host.activateCursor()
    onReturnRequested: host.activateCursor()
    onCloseRequested: host.close()
    onDeleteRequested: host.back()
    onTabRequested: function (direction) { host.switchPanel(direction) }
    onTextKey: function (text, modifiers) { host.handleTextKey(text) }
  }

  Flickable {
    id: scroll
    anchors.fill: parent
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: column
      width: scroll.width
      spacing: Style.space(10)

      // ---- header ---------------------------------------------------
      Item {
        width: parent.width
        height: Math.max(titleText.implicitHeight, headerRight.implicitHeight)

        Text {
          id: titleText
          textFormat: Text.PlainText
          text: root.tr("panel.title", "Tokenbar")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }

        Row {
          id: headerRight
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: root.host && root.host.loading
              ? root.tr("panel.scanning", "reading logs…")
              : (root.host ? root.host.updatedLabel : "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          PanelActionButton {
            // Corners inward when the panel is wide, outward when compact.
            iconText: root.wide ? "\u{f065}" : "\u{f066}"
            fontFamily: root.fontFamily
            foreground: root.dim
            tooltipText: root.wide
              ? root.tr("panel.compact", "Compact")
              : root.tr("panel.wide", "Wide")
            onClicked: root.host.wide = !root.host.wide
          }

          PanelActionButton {
            iconText: "\uf021"
            fontFamily: root.fontFamily
            foreground: root.dim
            tooltipText: root.tr("panel.refresh", "Refresh")
            onClicked: root.host.refresh(true)
          }
        }
      }

      // ---- hero -----------------------------------------------------
      Item {
        width: parent.width
        height: heroLeft.implicitHeight

        Column {
          id: heroLeft
          spacing: Style.space(1)
          width: Math.max(Style.space(120), parent.width - heroRight.width - Style.space(12))

          Text {
            textFormat: Text.PlainText
            text: Model.formatCost(root.summary.cost)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            text: root.tr("panel.tokens", "%1 tokens").arg(Model.formatTokens(root.summary.tokens))
              + "  ·  " + root.tr("panel.prompts", "%1 prompts").arg(root.summary.prompts)
              + "  ·  " + (root.host ? root.host.rangeName : "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Column {
          id: heroRight
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            text: root.trn("panel.agent.activeDays", root.summary.activeDays,
              root.summary.activeDays === 1 ? "%1 active day" : "%1 active days")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            // The catalog carries the %2 so a language can reorder the pair.
            text: root.tr("panel.sources", "%1 of %2 sources")
              .arg(root.host ? root.host.sourceCount : 0)
              .arg(root.host ? root.host.sourceTotal : 0)
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // ---- ranges ---------------------------------------------------
      Row {
        spacing: Style.space(4)

        Repeater {
          model: ["today", "7d", "30d", "90d", "1y"]
          delegate: Button {
            required property var modelData
            readonly property string label: modelData === "today" ? "1D"
              : modelData === "7d" ? "7D" : modelData === "30d" ? "30D"
              : modelData === "90d" ? "90D" : "1Y"
            text: label
            fontSize: Style.font.caption
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(3)
            foreground: root.foreground
            accent: root.accent
            selected: root.host && root.host.range === modelData && root.host.customKind === ""
            onClicked: root.host.setRange(modelData)
          }
        }
      }

      Row {
        spacing: Style.space(4)

        Repeater {
          model: ["wtd", "mtd", "qtd", "ytd"]
          delegate: Button {
            required property var modelData
            text: root.tr("panel.range." + modelData, modelData.toUpperCase())
            fontSize: Style.font.caption
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(3)
            foreground: root.foreground
            accent: root.accent
            selected: root.host && root.host.range === modelData && root.host.customKind === ""
            onClicked: root.host.setRange(modelData)
          }
        }

        Button {
          text: root.tr("panel.custom.clear", "Clear")
          fontSize: Style.font.caption
          horizontalPadding: Style.space(7)
          verticalPadding: Style.space(3)
          foreground: root.foreground
          accent: root.accent
          visible: root.host && root.host.customKind !== ""
          onClicked: root.host.clearCustom()
        }
      }

      Row {
        spacing: Style.space(6)

        Dropdown {
          id: dayDropdown
          width: Style.space(148)
          showLabel: false
          fontFamily: root.fontFamily
          foreground: root.foreground
          background: Commons.Color.popups.background
          value: root.host && root.host.customKind === "day" ? root.host.customValue : ""
          options: root.dayOptions
          onChanged: function (value) {
            if (value === "") root.host.clearCustom()
            else root.host.setDay(value)
          }
        }

        Dropdown {
          id: monthDropdown
          width: Style.space(148)
          showLabel: false
          fontFamily: root.fontFamily
          foreground: root.foreground
          background: Commons.Color.popups.background
          value: root.host && root.host.customKind === "month" ? root.host.customValue : ""
          options: root.monthOptions
          onChanged: function (value) {
            if (value === "") root.host.clearCustom()
            else root.host.setMonth(value)
          }
        }
      }

      // ---- home: chart, agents, models ------------------------------
      Column {
        id: homeColumn
        width: parent.width
        spacing: Style.space(10)
        visible: root.view === "home"

        Chart {
          width: parent.width
          points: root.host ? root.host.chart : []
          bucket: root.host ? root.host.bucket : "day"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onActivated: function (index) {
            var points = root.host ? root.host.chart : []
            if (index < 0 || index >= points.length) return
            if (root.host.bucket === "day") root.host.setDay(points[index].key)
            else if (root.host.bucket === "month") root.host.setMonth(points[index].key.slice(0, 7))
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.summary.tokens === 0
          text: root.tr("panel.emptyRange", "Nothing recorded in this range")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // Wide mode puts the models beside the agents; narrow stacks them.
        Row {
          width: parent.width
          spacing: Style.space(18)

          Column {
            id: agentsColumn
            width: root.wide ? Math.round((homeColumn.width - Style.space(18)) * 0.56) : homeColumn.width
            spacing: Style.space(2)

            PanelSectionHeader {
              text: root.tr("panel.agents", "Agents")
              foreground: root.foreground
              fontFamily: root.fontFamily
              visible: root.summary.agents.length > 0
            }

            Repeater {
              model: root.summary.agents

              delegate: Item {
                id: agentRow
                required property var modelData
                required property int index
                width: agentsColumn.width
                height: Style.space(46)

                readonly property bool hot: rowMouse.containsMouse
                  || (root.cursorActive && root.view === "home" && root.cursorRow === index)
                readonly property real share: root.summary.cost > 0 ? modelData.cost / root.summary.cost : 0

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: agentRow.hot ? root.hoverFill : "transparent"
                }

                Text {
                  id: agentName
                  textFormat: Text.PlainText
                  text: modelData.name
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(6)
                  width: Math.min(implicitWidth, parent.width - costText.width - Style.space(24))
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  text: Model.formatTokens(modelData.tokens) + " tok · " + Math.round(agentRow.share * 100) + "%"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(6)
                }

                Text {
                  id: costText
                  textFormat: Text.PlainText
                  text: Model.formatCost(modelData.cost, true)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(6)
                }

                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: Math.max(1, Style.space(2))
                  radius: height / 2
                  color: Util.alpha(root.foreground, 0.08)
                }
                Rectangle {
                  anchors.left: parent.left
                  anchors.bottom: parent.bottom
                  height: Math.max(1, Style.space(2))
                  width: Math.max(0, parent.width * agentRow.share)
                  radius: height / 2
                  color: Util.alpha(root.accent, 0.7)
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.host.openAgent(modelData.id)
                }
              }
            }
          }

          Column {
            id: modelsColumn
            width: root.wide ? homeColumn.width - agentsColumn.width - Style.space(18) : homeColumn.width
            spacing: Style.space(2)
            visible: root.wide

            Item {
              width: parent.width
              height: modelsHeader.implicitHeight

              PanelSectionHeader {
                id: modelsHeader
                text: root.tr("panel.models", "Models")
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Button {
                text: root.tr("panel.allModels", "All models")
                fontSize: Style.font.caption
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(2)
                foreground: root.dim
                accent: root.accent
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.host.showModels()
              }
            }

            Repeater {
              model: root.summary.models.slice(0, root.wide ? 9 : 6)

              delegate: Item {
                id: wideModelRow
                required property var modelData
                width: modelsColumn.width
                height: Style.space(26)

                readonly property bool hot: wideModelMouse.containsMouse

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: wideModelRow.hot ? root.hoverFill : "transparent"
                }

                Text {
                  textFormat: Text.PlainText
                  text: modelData.n
                  color: modelData.priced ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, parent.width - wideModelCost.width - Style.space(20))
                  elide: Text.ElideRight
                }

                Text {
                  id: wideModelCost
                  textFormat: Text.PlainText
                  text: modelData.priced ? Model.formatCost(modelData.cost, true) : "—"
                  color: modelData.priced ? root.foreground : root.faint
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                }

                MouseArea {
                  id: wideModelMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: root.host.showModels()
                }
              }
            }
          }
        }

        // Narrow mode keeps the model list under the agents.
        Column {
          width: parent.width
          spacing: Style.space(2)
          visible: !root.wide

          Item {
            width: parent.width
            height: narrowModelsHeader.implicitHeight
            visible: root.summary.models.length > 0

            PanelSectionHeader {
              id: narrowModelsHeader
              text: root.tr("panel.models", "Models")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Button {
              text: root.tr("panel.allModels", "All models")
              fontSize: Style.font.caption
              horizontalPadding: Style.space(6)
              verticalPadding: Style.space(2)
              foreground: root.dim
              accent: root.accent
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.host.showModels()
            }
          }

          Repeater {
            model: root.summary.models.slice(0, 6)

            delegate: Item {
              id: modelRow
              required property var modelData
              width: homeColumn.width
              height: Style.space(26)

              readonly property bool hot: modelMouse.containsMouse

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: modelRow.hot ? root.hoverFill : "transparent"
              }

              Text {
                textFormat: Text.PlainText
                text: modelData.n
                color: modelData.priced ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.left: parent.left
                anchors.leftMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - modelCost.width - Style.space(24))
                elide: Text.ElideRight
              }

              Text {
                id: modelCost
                textFormat: Text.PlainText
                text: modelData.priced ? Model.formatCost(modelData.cost, true) : "—"
                color: modelData.priced ? root.foreground : root.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }

              MouseArea {
                id: modelMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.host.showModels()
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.payload && root.payload.unpriced && root.payload.unpriced.length > 0
          text: root.payload
            ? root.tr("panel.unpriced", "%1 without a published price")
                .arg(root.payload.unpriced.length)
              + "  ·  " + root.payload.unpriced.slice(0, 3).map(function (entry) { return entry.n }).join(", ")
            : ""
          color: root.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }


      // ---- agent detail ---------------------------------------------
      Column {
        width: parent.width
        spacing: Style.space(10)
        visible: root.view === "agent"
        opacity: visible ? 1 : 0

        Behavior on opacity {
          NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic }
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: "‹ " + root.tr("panel.agents", "Agents")
            fontSize: Style.font.caption
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            foreground: root.dim
            accent: root.accent
            onClicked: root.host.back()
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: root.detail.agents.length > 0 ? root.detail.agents[0].name : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }

        Item {
          width: parent.width
          height: Math.max(agentHero.implicitHeight, agentCost.height)

          Column {
            id: agentHero
            spacing: Style.space(1)
            width: Math.max(Style.space(120), parent.width - agentCost.width - Style.space(12))

            Text {
              textFormat: Text.PlainText
              text: Model.formatCost(root.detail.cost)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              elide: Text.ElideRight
              text: root.trn("panel.tokens", root.detail.tokens, "%1 tokens",
                  Model.formatTokens(root.detail.tokens))
                + "  ·  " + root.trn("panel.prompts", root.detail.prompts, "%1 prompts")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Column {
            id: agentCost
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              text: Model.formatCost(root.detail.agents.length > 0 ? root.detail.agents[0].costPerMillion : 0, true)
                + " " + root.tr("panel.agent.costPerMillion", "per 1M tokens")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              text: Model.formatPercent(root.detail.agents.length > 0 ? root.detail.agents[0].cacheHitRate : 0)
                + " " + root.tr("panel.agent.cacheHit", "cache hit")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              text: Model.formatCost(root.detail.activeDays > 0
                  ? Math.round(root.detail.cost / root.detail.activeDays) : 0, true)
                + " " + root.tr("panel.agent.perDay", "per active day")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              text: {
                var days = root.trn("panel.agent.activeDays", root.detail.activeDays,
                  root.detail.activeDays === 1 ? "%1 active day" : "%1 active days")
                if (root.detail.agents.length === 0) return days
                var sessions = root.detail.agents[0].sessions
                return days + "  ·  " + root.trn("panel.agent.sessions", sessions,
                  sessions === 1 ? "%1 session" : "%1 sessions")
              }
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Chart {
          width: parent.width
          points: root.bounds
            ? Model.chartSeries(root.detail, root.bounds.from, root.bounds.to,
                Model.bucketFor(root.bounds.from, root.bounds.to))
            : []
          bucket: root.bounds ? Model.bucketFor(root.bounds.from, root.bounds.to) : "day"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
        }

        PanelSectionHeader {
          text: root.tr("panel.agent.topModels", "Models")
          foreground: root.foreground
          fontFamily: root.fontFamily
          visible: root.detail.models.length > 0
        }

        Repeater {
          model: root.detail.models

          delegate: Item {
            id: detailModel
            required property var modelData
            required property int index
            width: column.width
            height: Style.space(28)

            readonly property bool hot: detailMouse.containsMouse
              || (root.cursorActive && root.cursorRow === index)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: detailModel.hot ? root.hoverFill : "transparent"
            }

            Text {
              textFormat: Text.PlainText
              text: modelData.n
              color: modelData.priced ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, parent.width - detailCost.width - Style.space(24))
              elide: Text.ElideRight
            }

            Text {
              id: detailCost
              textFormat: Text.PlainText
              text: (modelData.priced ? Model.formatCost(modelData.cost, true) : "—")
                + "  ·  " + Model.formatTokens(modelData.tokens)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
            }

            MouseArea {
              id: detailMouse
              anchors.fill: parent
              hoverEnabled: true
            }
          }
        }
      }

      // ---- all models -----------------------------------------------
      Column {
        width: parent.width
        spacing: Style.space(8)
        visible: root.view === "models"

        Row {
          spacing: Style.space(8)

          Button {
            text: "‹ " + root.tr("panel.back", "Back")
            fontSize: Style.font.caption
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            foreground: root.dim
            accent: root.accent
            onClicked: root.host.back()
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: root.tr("panel.allModels", "All models")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }

        Repeater {
          model: root.summary.models

          delegate: Item {
            id: allModel
            required property var modelData
            required property int index
            width: column.width
            height: Style.space(30)

            readonly property bool hot: allMouse.containsMouse
              || (root.cursorActive && root.cursorRow === index)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: allModel.hot ? root.hoverFill : "transparent"
            }

            Text {
              textFormat: Text.PlainText
              text: modelData.n
              color: modelData.priced ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, parent.width - allTokens.width - allCost.width - Style.space(30))
              elide: Text.ElideRight
            }

            Text {
              id: allTokens
              textFormat: Text.PlainText
              text: Model.formatTokens(modelData.tokens)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.right: allCost.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: allCost
              textFormat: Text.PlainText
              text: modelData.priced ? Model.formatCost(modelData.cost, true) : "—"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
            }

            MouseArea {
              id: allMouse
              anchors.fill: parent
              hoverEnabled: true
            }
          }
        }
      }

      // ---- footer ---------------------------------------------------
      Item {
        width: parent.width
        height: footerRow.implicitHeight + Style.space(4)

        Row {
          id: footerRow
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          PanelActionButton {
            iconText: "\u{f0c5}"
            fontFamily: root.fontFamily
            foreground: root.dim
            tooltipText: root.tr("panel.copy", "Copy summary")
            onClicked: root.host.copySummary()
          }
          PanelActionButton {
            iconText: "\u{f019}"
            fontFamily: root.fontFamily
            foreground: root.dim
            tooltipText: root.tr("panel.share", "Save card")
            onClicked: root.host.saveCard()
          }
          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: root.host && root.host.note !== "" ? root.host.note
              : root.payload && root.payload.meta
                ? root.tr("panel.scan", "scan %1 ms").arg(root.payload.meta.scanMs)
                : ""
            color: root.host && root.host.note !== "" ? root.accent : root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: Math.min(implicitWidth, column.width - Style.space(80))
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.view === "home"
            ? root.tr("panel.hint", "")
            : root.tr("panel.hint.agent", "")
          color: root.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          visible: false
        }
      }
    }
  }
}
