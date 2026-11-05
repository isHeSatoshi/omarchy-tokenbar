import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

// A column chart with no dependencies, sized to its container. Every bar is a
// bucket (a day, a week, or a month) from Model.chartSeries. Hovering one
// names its total above the plot; clicking a day bar asks the panel to filter
// to that day.
Item {
  id: root

  property var points: []
  property string bucket: "day"
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property int selected: -1
  property int hovered: -1

  signal activated(int index)

  implicitHeight: points.length > 1 ? Style.space(96) : 0
  visible: points.length > 1
  readonly property real plotHeight: Math.max(0, height - Style.space(26))
  readonly property real peak: {
    var highest = 0
    for (var i = 0; i < points.length; i++) highest = Math.max(highest, points[i].cost)
    return highest
  }
  readonly property real slot: points.length > 0 ? Math.max(1, (width - Style.space(2)) / points.length) : 0
  readonly property var hoveredPoint: hovered >= 0 && hovered < points.length ? points[hovered] : null

  function bucketLabel(point) {
    if (!point) return ""
    if (bucket === "month") return Model.formatMonth(point.key)
    if (bucket === "week") return Qt.formatDate(Model.parseKey(point.key), "d MMM")
    return Model.formatDay(point.key)
  }

  // A quiet baseline so an empty day still reads as a day.
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    y: root.plotHeight
    height: Math.max(1, Style.space(1))
    color: Util.alpha(root.foreground, 0.18)
  }

  Row {
    id: bars
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: root.plotHeight

    Repeater {
      model: root.points

      delegate: Item {
        id: cell
        required property var modelData
        required property int index
        width: root.slot
        height: root.plotHeight

        readonly property real share: root.peak > 0 ? modelData.cost / root.peak : 0
        readonly property bool hot: index === root.hovered
        readonly property bool chosen: index === root.selected

        Rectangle {
          id: bar
          width: Math.max(1, Math.min(cell.width - Math.max(1, Style.space(1)), Style.space(5)))
          anchors.horizontalCenter: parent.horizontalCenter
          y: cell.height - height
          height: cell.share > 0 ? Math.max(Style.space(2), cell.share * (root.plotHeight - Style.space(4))) : 0
          radius: Math.min(Style.cornerRadius, width / 2)
          color: cell.hot || cell.chosen ? root.accent : Util.alpha(root.accent, cell.share > 0 ? 0.55 : 0)
          opacity: cell.share > 0 ? (cell.hot || cell.chosen ? 1 : 0.75) : 0

          Behavior on height {
            NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
          }
          Behavior on color {
            ColorAnimation { duration: Style.duration(120) }
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton
          cursorShape: root.bucket === "week" ? Qt.ArrowCursor : Qt.PointingHandCursor
          onEntered: root.hovered = index
          onExited: if (root.hovered === index) root.hovered = -1
          onClicked: root.activated(index)
        }
      }
    }
  }

  // The hovered bucket, spelled out. Plain text: the label comes from model
  // ids and dates, and a bucket label must never promote itself to markup.
  Text {
    id: readout
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Style.space(18)
    textFormat: Text.PlainText
    visible: root.hoveredPoint !== null
    text: root.hoveredPoint
      ? root.bucketLabel(root.hoveredPoint) + "  ·  " + Model.formatCost(root.hoveredPoint.cost)
        + "  ·  " + Model.formatTokens(root.hoveredPoint.tokens)
      : ""
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
  }

  // First, middle and last bucket labels, so the axis reads without clutter.
  Row {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Style.space(14)

    Text {
      textFormat: Text.PlainText
      width: parent.width / 3
      text: root.points.length > 0 ? root.bucketLabel(root.points[0]) : ""
      color: Util.alpha(root.foreground, 0.6)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width / 3
      horizontalAlignment: Text.AlignHCenter
      text: root.points.length > 2 ? root.bucketLabel(root.points[Math.floor(root.points.length / 2)]) : ""
      color: Util.alpha(root.foreground, 0.6)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width / 3
      horizontalAlignment: Text.AlignRight
      text: root.points.length > 1 ? root.bucketLabel(root.points[root.points.length - 1]) : ""
      color: Util.alpha(root.foreground, 0.6)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
