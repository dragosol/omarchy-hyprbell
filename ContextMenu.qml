// A notification's right-click menu.
//
// Drawn the way Hyprdrive's dock menu is: one plate in the window border,
// a glyph column so every label starts at the same x, quiet hints on the
// right, and rows that carry their own choices as chips - a choice lit in the
// accent while it is on, so a row is a setting you can read, not a submenu
// you have to open. It grows out of the point you clicked and its rows
// follow it in, and it shrinks back into that point when it goes.
//
// It is its own popup rather than part of the notification surface: that
// surface is one card wide and clipped, and a menu that can be cut in half is
// worse than none. A Hyprland focus grab dismisses it on a click anywhere
// else, the way every other menu on the desktop goes.
//
// What the rows say and do belongs to the service (Service.qml, menuRows and
// menuDo). This only draws them and reports which was chosen.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

PopupWindow {
  id: menu

  property var host: null              // the notification surface it opens from
  property var daemon: null
  property bool want: false            // the service wants it up on this output
  property int serial: 0               // bumped for every opening
  property real atX: 0                 // the click, in the host's coordinates
  property real atY: 0
  property var rows: []
  property int windowBorderWidth: 2
  property real fontScale: 1

  signal chosen(string id, string value)
  signal dismissed()

  // ------------------------------------------------------------- metrics
  // Hyprdrive's: 13px labels, 14px in from the sides, 7px above and below,
  // a 9px separator, a glyph column 1.9 em wide, and chips 4px in from the
  // plate's edge with radii concentric to its corners.
  readonly property int fontPx: Math.round(Style.font.subtitle * fontScale)
  readonly property int smallPx: Math.round(Style.font.bodySmall * fontScale)
  readonly property int padX: Style.space(14)
  readonly property int padY: Style.space(7)
  readonly property int edge: Style.space(4)
  readonly property int sepH: Style.space(9)
  readonly property int glyphCol: Math.round(fontPx * 1.9)
  readonly property int hintGap: Style.space(18)
  readonly property int chipGap: Style.space(4)
  readonly property int chipPadX: Style.space(8)
  readonly property int lineH: Math.ceil(fontPx * 1.35)
  readonly property int rowH: lineH + 2 * padY
  readonly property int minW: Style.space(240)
  readonly property int maxW: Style.space(420)
  readonly property real plateRadius: Style.cornerRadius
  readonly property real innerRadius: Math.max(0, plateRadius - edge)

  readonly property color ink: Commons.Color.notifications.text
  readonly property color dim: Qt.darker(ink, 1.4)
  readonly property color accent: Commons.Color.accent
  // The theme's urgent colour, lifted: on dark themes it is a deep red that
  // reads as disabled at menu size.
  readonly property color danger: {
    var c = Commons.Color.urgent
    var hue = c.hslHue < 0 ? 0 : c.hslHue
    return Qt.hsla(hue, Math.max(0.55, c.hslSaturation), Math.max(0.66, c.hslLightness), 1)
  }
  function tint(c, a) { var q = Qt.lighter(c, 1.0); return Qt.rgba(q.r, q.g, q.b, a) }
  readonly property color hoverFill: tint(ink, 0.08)
  readonly property color chipFill: tint(ink, 0.06)
  readonly property color chipHover: tint(ink, 0.13)
  readonly property color litFill: tint(accent, 0.22)
  readonly property color litHover: tint(accent, 0.32)

  // The footer explains whatever the pointer is on; resting nowhere, it
  // says what the rules for this notification are right now.
  property string hoverDesc: ""
  readonly property string restingDesc: {
    for (var i = 0; i < rows.length; i++) if (rows[i].type === "footer") return String(rows[i].text || "")
    return ""
  }

  // ------------------------------------------------------------- placement
  // Down and to the left of the click: the notifications live against the
  // right edge, so that is where the room is. Up instead when there is not
  // enough below and more above. Slide keeps it on the output either way.
  readonly property real plateH: plate.implicitHeight
  readonly property bool up: host ? (atY + plateH + Style.space(8) > host.height && atY > host.height / 2) : false

  color: "transparent"
  visible: mapped
  property bool mapped: false
  implicitWidth: plate.width
  implicitHeight: Math.max(1, plate.implicitHeight)

  anchor {
    window: menu.host
    rect.x: Math.round(menu.atX + Style.space(6))
    rect.y: Math.round(menu.atY + (menu.up ? Style.space(6) : -Style.space(6)))
    rect.width: 1
    rect.height: 1
    edges: Edges.Top | Edges.Left
    gravity: (menu.up ? Edges.Top : Edges.Bottom) | Edges.Left
    adjustment: PopupAdjustment.Slide | PopupAdjustment.ResizeY
  }

  // A fresh popup maps at a whole-number scale before Qt hears the output's
  // fractional one; drawn in that first frame it would come out blurry and
  // then jump. Invisible until it matches the surface it opens from.
  readonly property bool scaleReady: !host || Math.round(devicePixelRatio * 120) === Math.round(host.devicePixelRatio * 120)

  // ------------------------------------------------------------- motion
  property real p: 0                   // 0 shut .. 1 open, eased
  readonly property int openMs: Style.duration(180)
  readonly property int closeMs: Style.duration(135)

  NumberAnimation {
    id: opening
    target: menu; property: "p"; to: 1
    duration: menu.openMs
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Style.easeOut
  }
  NumberAnimation {
    id: closing
    target: menu; property: "p"; to: 0
    duration: Math.round(menu.closeMs * Math.max(0.05, menu.p))
    easing.type: Easing.InCubic
    onFinished: if (!menu.want) menu.mapped = false
  }

  function show() {
    closing.stop()
    opening.stop()
    hoverDesc = ""
    p = 0
    mapped = true
    if (scaleReady) opening.start()
  }
  function hide() {
    opening.stop()
    if (!mapped) return
    if (closeMs <= 0) { p = 0; mapped = false; return }
    closing.start()
  }
  onScaleReadyChanged: if (scaleReady && mapped && want && p === 0 && !opening.running) opening.start()
  onWantChanged: want ? show() : hide()
  // Opened again on another card while already up: a popup is placed once,
  // when it maps, so it has to map again to move.
  onSerialChanged: if (want && mapped) { mapped = false; Qt.callLater(show) }

  HyprlandFocusGrab {
    active: menu.mapped && menu.want
    windows: [menu]
    onCleared: menu.dismissed()
  }

  // ------------------------------------------------------------- drawing
  BorderSurface {
    id: plate
    width: Math.round(Math.min(menu.maxW, Math.max(menu.minW, rowsColumn.widest + 2 * borderLeft)))
    implicitHeight: rowsColumn.implicitHeight + borderTop + borderBottom + 2 * menu.edge
    height: implicitHeight
    radius: menu.plateRadius
    color: Commons.Color.notifications.background
    borderSpec: Border.hyprlandActiveSpec(Commons.Color.notifications.border, menu.windowBorderWidth)
    // Grows out of the corner nearest the click.
    transformOrigin: menu.up ? Item.BottomRight : Item.TopRight
    scale: 0.94 + 0.06 * menu.p
    opacity: menu.scaleReady ? Math.min(1, menu.p * 1.6) : 0
    clip: true

    focus: true
    Keys.onEscapePressed: menu.dismissed()

    Column {
      id: rowsColumn
      x: plate.borderLeft
      y: plate.borderTop + menu.edge
      width: plate.width - plate.borderLeft - plate.borderRight

      property real widest: 0
      function measure() {
        var w = 0
        for (var i = 0; i < rowRepeater.count; i++) {
          var it = rowRepeater.itemAt(i)
          if (it) w = Math.max(w, it.need)
        }
        widest = w
      }

      Repeater {
        id: rowRepeater
        model: menu.rows.filter(function(r) { return r.type !== "footer" })
        onItemAdded: Qt.callLater(rowsColumn.measure)
        onItemRemoved: Qt.callLater(rowsColumn.measure)

        Item {
          id: rowItem
          required property var modelData
          required property int index
          readonly property string type: String(modelData.type || "")
          readonly property bool isSep: type === "sep"
          readonly property bool hasChips: type === "chips" || type === "scope"
          readonly property bool clickable: type === "action" || type === "toggle"
          width: rowsColumn.width
          height: isSep ? menu.sepH : menu.rowH
          readonly property real need: isSep ? 0
            : menu.padX + (glyph.text !== "" || type !== "header" ? menu.glyphCol : 0) + label.implicitWidth
              + (hasChips ? menu.hintGap + chipRow.implicitWidth + menu.edge
                 : type === "toggle" ? menu.hintGap + toggleTrack.width + menu.padX
                 : hint.text !== "" ? menu.hintGap + hint.implicitWidth + menu.padX
                 : menu.padX)
          onNeedChanged: Qt.callLater(rowsColumn.measure)

          // The cascade: each row a beat behind the one before, coming in
          // from the click's side.
          readonly property real arrive: Math.max(0, Math.min(1, (menu.p * 1.25) - index * 0.035))
          opacity: arrive
          transform: Translate { y: (1 - rowItem.arrive) * Style.space(4) * (menu.up ? 1 : -1) }

          readonly property bool rowHot: rowArea.containsMouse && clickable

          Rectangle {
            visible: rowItem.isSep
            x: menu.padX
            width: parent.width - 2 * menu.padX
            y: Math.floor(parent.height / 2)
            height: Math.max(1, Style.spacing.hairline)
            color: menu.tint(menu.ink, 0.12)
          }

          // The row's hover chip, inset from the plate's edge.
          Rectangle {
            visible: rowItem.clickable
            x: menu.edge
            width: parent.width - 2 * menu.edge
            height: parent.height
            radius: menu.innerRadius
            color: rowItem.rowHot ? menu.hoverFill : "transparent"
            Behavior on color { ColorAnimation { duration: Style.duration(140) } }
          }

          Text {
            id: glyph
            visible: !rowItem.isSep && text !== ""
            x: menu.padX
            width: menu.glyphCol
            anchors.verticalCenter: parent.verticalCenter
            text: String(rowItem.modelData.glyph || "")
            textFormat: Text.PlainText
            color: rowItem.modelData.danger ? menu.danger : menu.tint(menu.dim, 0.95)
            font.family: Style.font.family
            font.pixelSize: menu.fontPx
            scale: rowItem.rowHot ? 1.08 : 1
            Behavior on scale { NumberAnimation { duration: Style.duration(140) } }
          }

          Text {
            id: label
            visible: !rowItem.isSep
            x: menu.padX + (rowItem.type === "header" || rowItem.type === "scope" ? 0 : menu.glyphCol)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, (rowItem.hasChips ? chipRow.x - menu.hintGap / 2
                                : rowItem.type === "toggle" ? toggleTrack.x - menu.hintGap / 2
                                : hint.visible ? hint.x - menu.hintGap / 2
                                : parent.width - menu.padX) - x)
            text: String(rowItem.modelData.label || "")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: rowItem.modelData.danger ? menu.danger
                 : rowItem.type === "scope" ? menu.dim : menu.ink
            font.family: Style.font.family
            font.pixelSize: rowItem.type === "scope" ? menu.smallPx : menu.fontPx
            font.weight: rowItem.type === "header" ? Font.DemiBold : Font.Normal
          }

          Text {
            id: hint
            visible: !rowItem.isSep && !rowItem.hasChips && rowItem.type !== "toggle" && text !== ""
            anchors.right: parent.right
            anchors.rightMargin: menu.padX
            anchors.verticalCenter: parent.verticalCenter
            text: String(rowItem.modelData.hint || "")
            textFormat: Text.PlainText
            color: menu.dim
            font.family: Style.font.family
            font.pixelSize: menu.smallPx
          }

          // A switch for a row that is on or off. Lit in the accent when on;
          // outlined when only the app-wide rule has it on.
          Rectangle {
            id: toggleTrack
            visible: rowItem.type === "toggle"
            readonly property bool on: rowItem.modelData.on === true
            readonly property bool inherited: rowItem.modelData.inherited === true
            anchors.right: parent.right
            anchors.rightMargin: menu.padX
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(menu.fontPx * 2.1)
            height: Math.round(menu.fontPx * 1.15)
            radius: height / 2
            color: on ? menu.tint(menu.accent, rowItem.rowHot ? 0.55 : 0.42) : (rowItem.rowHot ? menu.chipHover : menu.chipFill)
            border.width: inherited ? Math.max(1, Style.spacing.hairline) : 0
            border.color: menu.tint(menu.accent, 0.6)
            Behavior on color { ColorAnimation { duration: Style.duration(140) } }

            Rectangle {
              readonly property real inset: Math.round(parent.height * 0.18)
              width: parent.height - 2 * inset
              height: width
              radius: width / 2
              y: inset
              x: toggleTrack.on ? parent.width - width - inset : inset
              color: toggleTrack.on ? menu.accent : menu.dim
              Behavior on x { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
            }
          }

          MouseArea {
            id: rowArea
            anchors.fill: parent
            visible: !rowItem.isSep
            hoverEnabled: true
            acceptedButtons: rowItem.clickable ? Qt.LeftButton : Qt.NoButton
            cursorShape: rowItem.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onContainsMouseChanged: {
              if (containsMouse) menu.hoverDesc = String(rowItem.modelData.desc || "")
              else if (menu.hoverDesc === String(rowItem.modelData.desc || "")) menu.hoverDesc = ""
            }
            onClicked: menu.chosen(String(rowItem.modelData.id || ""), "")
          }

          // The choices, against the right edge. A lit chip is the choice in
          // force; an outlined one is in force because the app-wide rule says
          // so; picking a lit chip again turns it off.
          Row {
            id: chipRow
            visible: rowItem.hasChips
            anchors.right: parent.right
            anchors.rightMargin: menu.edge + Style.space(2)
            anchors.verticalCenter: parent.verticalCenter
            spacing: menu.chipGap

            Repeater {
              model: rowItem.hasChips ? (rowItem.modelData.chips || []) : []

              Rectangle {
                id: chip
                required property var modelData
                readonly property bool on: modelData.on === true
                readonly property bool inherited: modelData.inherited === true
                readonly property bool hot: chipArea.containsMouse
                width: chipText.implicitWidth + 2 * menu.chipPadX
                height: menu.rowH - 2 * Style.space(5)
                radius: Math.min(height / 2, menu.innerRadius)
                color: on ? (hot ? menu.litHover : menu.litFill) : (hot ? menu.chipHover : menu.chipFill)
                border.width: inherited ? Math.max(1, Style.spacing.hairline) : 0
                border.color: menu.tint(menu.accent, 0.55)
                Behavior on color { ColorAnimation { duration: Style.duration(140) } }
                // A hovered chip pops in from smaller, as Hyprdrive's do.
                scale: chipArea.pressed ? 0.94 : 1
                Behavior on scale { NumberAnimation { duration: Style.duration(110); easing.type: Easing.OutCubic } }

                Text {
                  id: chipText
                  anchors.centerIn: parent
                  text: String(chip.modelData.label || "")
                  textFormat: Text.PlainText
                  color: chip.on || chip.inherited ? menu.accent : (chip.hot ? menu.ink : menu.tint(menu.ink, 0.78))
                  font.family: Style.font.family
                  font.pixelSize: menu.smallPx
                  font.weight: chip.on ? Font.DemiBold : Font.Normal
                }

                MouseArea {
                  id: chipArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  readonly property string desc: {
                    var d = rowItem.modelData.descs
                    var own = d && d[chip.modelData.value] ? String(d[chip.modelData.value]) : String(rowItem.modelData.desc || "")
                    return chip.inherited ? own + " (Set for the whole app.)" : own
                  }
                  onContainsMouseChanged: {
                    if (containsMouse) menu.hoverDesc = desc
                    else if (menu.hoverDesc === desc) menu.hoverDesc = String(rowItem.modelData.desc || "")
                  }
                  onClicked: menu.chosen(String(rowItem.modelData.id || ""), String(chip.modelData.value))
                }
              }
            }
          }
        }
      }

      // What the pointer is on, in a sentence. Two lines, always: a footer
      // that changes height under the pointer moves every row above it when
      // the menu has opened upwards.
      Item {
        width: rowsColumn.width
        height: menu.sepH
        Rectangle {
          x: menu.padX
          width: parent.width - 2 * menu.padX
          y: Math.floor(parent.height / 2)
          height: Math.max(1, Style.spacing.hairline)
          color: menu.tint(menu.ink, 0.12)
        }
      }
      Item {
        width: rowsColumn.width
        height: footer.lineCount2 + menu.padY * 2
        opacity: Math.max(0, Math.min(1, menu.p * 1.25 - 0.3))

        FontMetrics {
          id: footerMetrics
          font.family: Style.font.family
          font.pixelSize: menu.smallPx
        }

        Text {
          id: footer
          // Two of the font's own lines: guessing the line height from the
          // pixel size cut the second line off in JetBrains Mono.
          readonly property real lineCount2: Math.ceil(footerMetrics.lineSpacing) * 2 + 2
          x: menu.padX
          y: menu.padY - Style.space(2)
          width: parent.width - 2 * menu.padX
          height: lineCount2
          text: menu.hoverDesc !== "" ? menu.hoverDesc : menu.restingDesc
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
          lineHeight: 1.0
          color: menu.dim
          font.family: Style.font.family
          font.pixelSize: menu.smallPx
          verticalAlignment: Text.AlignTop
        }
      }
    }
  }
}
