import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Search.js" as Search

// Fullscreen cheatsheet lookup. Structured after the built-in emoji overlay
// (shell/plugins/emojis/Emojis.qml): same layer-shell setup, same [menu] theme
// tokens, same keyboard-first model where typing goes straight into the filter
// instead of needing a focused text field.
Item {
  id: root

  // Injected by the shell's plugin loader.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "abelk.cheatsheets"
  readonly property string sourceDir: (manifest && manifest.__sourceDir) || ""

  property bool opened: false
  property string filterText: ""

  property var sheets: []
  property int sheetIndex: 0
  property var rows: []
  property int selectedIndex: -1
  property bool loaded: false
  property string loadError: ""
  property string copiedKeys: ""

  readonly property var activeSheet: sheets.length > 0 && sheetIndex < sheets.length
    ? sheets[sheetIndex] : null
  readonly property bool searching: filterText.length > 0

  // ------------------------------------------------------------ theming
  //
  // Shares the [menu] surface tokens, so a theme that styles the Omarchy menu
  // styles this too and nothing here needs a hardcoded color.
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color borderColor: Color.menu.border
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", borderColor, Math.max(1, Style.space(2)))
  readonly property color scrim: Color.menu.scrim
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property color accent: Color.accent

  readonly property string fontFamily: Style.font.menuFamily
  readonly property int cornerRadius: Style.cornerRadius
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int rowHeight: Math.max(Style.space(26), Style.font.body + Style.spacing.md * 2)
  readonly property int headerRowHeight: Math.max(Style.space(30), Style.font.bodySmall + Style.spacing.xl * 2)
  readonly property int sidebarWidth: Style.space(160)
  readonly property int keyColumnWidth: Style.space(220)

  // ------------------------------------------------------------ lifecycle

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.copiedKeys = ""
    if (!root.loaded) reload()
    else root.rebuild()
    detectFocusedTool.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  // The shell tracks open panels in its own map, so closing from inside the
  // overlay has to tell it — otherwise `shell toggle` sees a stale "open" and
  // the next press does nothing.
  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // ------------------------------------------------------------ data

  function reload() {
    if (loader.running) return
    root.loadError = ""
    loader.running = true
  }

  function applySheets(raw) {
    var parsed = []
    try {
      parsed = JSON.parse(raw)
    } catch (e) {
      root.loadError = "Could not parse the cheatsheet data: " + e
      root.loaded = true
      root.rebuild()
      return
    }

    if (!Array.isArray(parsed) || parsed.length === 0) {
      root.loadError = "No cheatsheets found. Add one to ~/.config/omarchy/cheatsheets/."
      root.sheets = []
      root.loaded = true
      root.rebuild()
      return
    }

    root.sheets = parsed
    root.loaded = true
    if (root.sheetIndex >= parsed.length) root.sheetIndex = 0
    root.rebuild()
  }

  // ------------------------------------------------------------ rows

  function rebuild() {
    var next = root.searching
      ? Search.searchRows(root.sheets, root.filterText, root.activeSheet ? root.activeSheet.id : "", 400)
      : Search.sheetRows(root.activeSheet)

    root.rows = next
    rowModel.clear()
    for (var i = 0; i < next.length; i++) rowModel.append(next[i])

    root.selectedIndex = Search.firstEntry(next)
    // Always land at the very top: the first row is a section header, and
    // positioning on the first *entry* would scroll it off screen. contentY is
    // set directly as well because positionViewAtBeginning alone does not
    // reliably take on a variable-height delegate that has not been laid out
    // yet — which is exactly the case right after the model is refilled.
    resultList.contentY = 0
    Qt.callLater(function() {
      resultList.positionViewAtBeginning()
      resultList.contentY = 0
    })
  }

  function setFilter(next) {
    root.filterText = next
    root.copiedKeys = ""
    root.rebuild()
  }

  function selectSheet(index) {
    if (root.sheets.length === 0) return
    var count = root.sheets.length
    root.sheetIndex = ((index % count) + count) % count
    root.copiedKeys = ""
    root.rebuild()
  }

  function cycleSheet(delta) {
    selectSheet(root.sheetIndex + delta)
  }

  // Scroll only when the row is actually off screen. positionViewAtIndex has to
  // lay out delegates from the top of the model to work out where an index
  // sits, and with variable-height rows that is O(n) — paying it on every
  // arrow key is what makes holding a key down feel like wading. When the row
  // is already visible, moving the selection is just a colour change.
  function ensureVisible(index) {
    if (index < 0) return
    var item = resultList.itemAtIndex(index)
    if (item) {
      var top = item.y - resultList.contentY
      if (top >= 0 && top + item.height <= resultList.height) return
      // One row off either edge: nudge by exactly that much, which avoids the
      // full relayout and keeps held-down arrows scrolling smoothly.
      var max = Math.max(0, resultList.contentHeight - resultList.height)
      var target = top < 0 ? item.y : item.y + item.height - resultList.height
      resultList.contentY = Math.max(0, Math.min(max, target))
      return
    }
    resultList.positionViewAtIndex(index, ListView.Contain)
  }

  function move(delta) {
    if (root.rows.length === 0) return
    var from = root.selectedIndex >= 0 ? root.selectedIndex : -1
    var next = from < 0 ? Search.firstEntry(root.rows) : Search.step(root.rows, from, delta)
    if (next < 0) return
    root.selectedIndex = next
    ensureVisible(next)
  }

  function movePage(delta) {
    // Rows are variable height now, so page size comes from the measured
    // average rather than the minimum row height.
    var average = rowModel.count > 0 && resultList.contentHeight > 0
      ? resultList.contentHeight / rowModel.count
      : root.rowHeight
    var perPage = Math.max(1, Math.floor(resultList.height / Math.max(1, average)) - 1)
    move(delta * perPage)
  }

  function moveEnd(toEnd) {
    if (root.rows.length === 0) return
    if (toEnd) {
      for (var i = root.rows.length - 1; i >= 0; i--) {
        if (root.rows[i].type === "entry") { root.selectedIndex = i; break }
      }
    } else {
      root.selectedIndex = Search.firstEntry(root.rows)
    }
    // Home and End are the two cases where jumping the whole list is the point,
    // so they go straight to the ends rather than through ensureVisible.
    if (toEnd) resultList.positionViewAtEnd()
    else resultList.positionViewAtBeginning()
  }

  function copySelected() {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.rows.length) return
    var row = root.rows[root.selectedIndex]
    if (!row || row.type !== "entry" || !row.keys) return
    copyProcess.command = ["wl-copy", "--", String(row.keys)]
    copyProcess.running = true
    root.copiedKeys = String(row.keys)
    copiedReset.restart()
  }

  // ------------------------------------------------------------ processes

  Process {
    id: loader
    command: ["bash", root.sourceDir + "/bin/cheatsheets-load", "--plugin-dir", root.sourceDir]
    stdout: StdioCollector {
      onStreamFinished: root.applySheets(text)
    }
    stderr: StdioCollector {
      onStreamFinished: if (text && text.length > 0) console.warn("cheatsheets: " + text)
    }
    onExited: function(code) {
      loader.running = false
      if (code !== 0 && !root.loaded) {
        root.loadError = "cheatsheets-load exited with status " + code
        root.loaded = true
      }
    }
  }

  Process { id: copyProcess }

  // Preselect the sheet matching whatever was focused when the overlay opened.
  // A layer surface never becomes the active window, so this still reports the
  // real one. Failure here is silent on purpose — it is a convenience, and
  // falling back to the current tab is a perfectly good outcome.
  Process {
    id: detectFocusedTool
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (root.searching || !root.opened) return
        var windowClass = ""
        try {
          windowClass = String(JSON.parse(text).class || "")
        } catch (e) {
          return
        }
        if (!windowClass) return

        for (var i = 0; i < root.sheets.length; i++) {
          var classes = root.sheets[i].windowClasses || []
          for (var c = 0; c < classes.length; c++) {
            if (String(classes[c]).toLowerCase() === windowClass.toLowerCase()) {
              root.selectSheet(i)
              return
            }
          }
        }
      }
    }
  }

  Timer {
    id: copiedReset
    interval: 1200
    onTriggered: root.copiedKeys = ""
  }

  ListModel { id: rowModel }

  // ------------------------------------------------------------ surface

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-cheatsheets"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(980), panel.width - Style.gapsOut * 4)
      height: Math.min(Style.space(660), panel.height - Style.gapsOut * 4)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      // Swallow clicks so they don't reach the dismiss handler behind the card.
      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.cycleSheet(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Backtab
                     || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
            root.cycleSheet(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down
                     || (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier))) {
            root.move(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up
                     || (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier))) {
            root.move(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.cycleSheet(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.cycleSheet(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown
                     || (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier))) {
            root.movePage(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp
                     || (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier))) {
            root.movePage(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.moveEnd(false)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.moveEnd(true)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.copySelected()
            event.accepted = true
          } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
            root.loaded = false
            root.reload()
            event.accepted = true
          } else if (event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        // ---------------------------------------------------- search line
        Item {
          id: header
          anchors { top: parent.top; left: parent.left; right: parent.right }
          height: Math.max(Style.space(34), Style.font.heading + Style.spacing.controlPaddingY * 2)

          Text {
            id: prompt
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            text: "󰍉 "
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: prompt.right
            anchors.right: counter.left
            anchors.rightMargin: Style.spacing.md
            text: root.filterText || "Search every cheatsheet…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          Text {
            id: counter
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            text: {
              if (root.copiedKeys) return "copied"
              if (!root.loaded) return "loading…"
              var count = 0
              for (var i = 0; i < root.rows.length; i++) if (root.rows[i].type === "entry") count++
              return count + (count === 1 ? " entry" : " entries")
            }
            color: root.copiedKeys ? root.accent : root.foreground
            opacity: root.copiedKeys ? 1 : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Rectangle {
          id: headerRule
          anchors { top: header.bottom; left: parent.left; right: parent.right }
          height: Math.max(1, Style.space(1))
          color: root.foreground
          opacity: 0.12
        }

        // ---------------------------------------------------- sheet list
        Item {
          id: sidebar
          anchors {
            top: headerRule.bottom
            bottom: footerRule.top
            left: parent.left
            topMargin: Style.spacing.md
            bottomMargin: Style.spacing.md
          }
          width: root.sidebarWidth
          visible: root.sheets.length > 0

          ListView {
            id: sheetList
            anchors.fill: parent
            model: root.sheets
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: Style.spacing.xxs

            delegate: Rectangle {
              id: sheetRow

              required property int index
              required property var modelData

              readonly property bool active: index === root.sheetIndex

              width: sheetList.width - Style.spacing.md
              height: Math.max(root.rowHeight, sheetLabel.implicitHeight + Style.spacing.md * 2)
              radius: root.cornerRadius
              color: active ? root.selectedBackground : "transparent"

              Text {
                id: sheetLabel
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.sm
                text: (modelData.icon ? modelData.icon + "  " : "") + modelData.name
                color: active ? root.selectedText : root.foreground
                opacity: active ? 1 : 0.72
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: active
                wrapMode: Text.Wrap
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectSheet(index)
              }
            }
          }
        }

        Rectangle {
          id: sidebarRule
          anchors {
            top: headerRule.bottom
            bottom: footerRule.top
            left: sidebar.right
            topMargin: Style.spacing.md
            bottomMargin: Style.spacing.md
          }
          width: Math.max(1, Style.space(1))
          color: root.foreground
          opacity: 0.12
          visible: sidebar.visible
        }

        // ---------------------------------------------------- entries
        Item {
          id: content
          anchors {
            top: headerRule.bottom
            bottom: footerRule.top
            left: sidebarRule.visible ? sidebarRule.right : parent.left
            right: parent.right
            topMargin: Style.spacing.md
            bottomMargin: Style.spacing.md
            leftMargin: sidebarRule.visible ? Style.spacing.lg : 0
          }

          ListView {
            id: resultList
            anchors.fill: parent
            model: rowModel
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            visible: rowModel.count > 0

            // The Omarchy sheet is 224 entries and every delegate is
            // variable-height, so laying one out is not free. Recycling them
            // and keeping a screen of them warm on each side is what keeps a
            // fast scroll from rebuilding the world.
            reuseItems: true
            cacheBuffer: Math.max(0, Math.round(height * 2))
            flickDeceleration: 6000
            maximumFlickVelocity: 6000

            // Qt's default wheel step is a few small lines, which reads as
            // sluggish on a list this long. Touchpads send pixelDelta and are
            // passed through at their own scale (they are already smooth);
            // mouse wheels send angleDelta in eighths of a degree, converted
            // here to three rows a notch.
            WheelHandler {
              acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
              onWheel: function(event) {
                var dy = event.pixelDelta.y !== 0
                  ? event.pixelDelta.y * 2
                  : (event.angleDelta.y / 120) * root.rowHeight * 3
                if (dy === 0) return
                var max = Math.max(0, resultList.contentHeight - resultList.height)
                resultList.contentY = Math.max(0, Math.min(max, resultList.contentY - dy))
              }
            }

            // Rows size to their content rather than to a fixed height: a
            // cheatsheet is full of long commands (`docker system prune -a
            // --volumes`), and eliding them defeats the point of looking one up.
            delegate: Item {
              id: row

              required property int index
              required property string type
              required property string title
              required property string keys
              required property string desc

              readonly property bool isSection: type === "section"
              readonly property bool hasCursor: !isSection && index === root.selectedIndex
              readonly property int verticalPadding: Style.spacing.md

              width: resultList.width
              height: isSection
                ? root.headerRowHeight
                : Math.max(root.rowHeight,
                           Math.max(keyText.implicitHeight, descText.implicitHeight)
                             + row.verticalPadding * 2)

              // Section header
              Text {
                visible: row.isSection
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.sm
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.spacing.xs
                text: row.title.toUpperCase()
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
              }

              // Entry row
              Rectangle {
                visible: !row.isSection
                anchors.fill: parent
                anchors.rightMargin: Style.spacing.sm
                radius: root.cornerRadius
                color: row.hasCursor ? root.selectedBackground : "transparent"

                Text {
                  id: keyText
                  anchors.top: parent.top
                  anchors.topMargin: row.verticalPadding
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.rowPaddingX
                  width: Math.min(root.keyColumnWidth, parent.width * 0.42)
                  text: row.keys
                  color: root.selectedText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  wrapMode: Text.Wrap
                }

                Text {
                  id: descText
                  anchors.top: parent.top
                  anchors.topMargin: row.verticalPadding
                  anchors.left: keyText.right
                  anchors.leftMargin: Style.spacing.lg
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  text: row.desc
                  color: root.foreground
                  opacity: 0.85
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  wrapMode: Text.Wrap
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onContainsMouseChanged: if (containsMouse) root.selectedIndex = row.index
                  onClicked: {
                    root.selectedIndex = row.index
                    root.copySelected()
                  }
                }
              }
            }
          }

          // Empty / error state
          Column {
            anchors.centerIn: parent
            spacing: Style.spacing.lg
            width: parent.width - Style.spacing.huge * 2
            visible: rowModel.count === 0

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.loadError ? "󰀦" : (root.loaded ? "󰈉" : "󱋖")
              color: root.accent
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: {
                if (root.loadError) return root.loadError
                if (!root.loaded) return "Loading cheatsheets…"
                if (root.searching) return "Nothing matches “" + root.filterText + "”"
                return "This cheatsheet is empty"
              }
              color: root.foreground
              opacity: 0.75
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        // ---------------------------------------------------- footer
        Rectangle {
          id: footerRule
          anchors { bottom: footer.top; left: parent.left; right: parent.right; bottomMargin: Style.spacing.sm }
          height: Math.max(1, Style.space(1))
          color: root.foreground
          opacity: 0.12
        }

        // The footer grows to fit the sheet note rather than eliding it — a
        // note that says "prefix is Ctrl+Space, with Ctrl+b kept as a…" has
        // thrown away the half that mattered.
        Item {
          id: footer
          anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
          height: Math.max(Style.space(18),
                           Math.max(noteText.implicitHeight, hint.implicitHeight)
                             + Style.spacing.sm * 2)

          Text {
            id: noteText
            anchors.top: parent.top
            anchors.topMargin: Style.spacing.sm
            anchors.left: parent.left
            anchors.right: hint.left
            anchors.rightMargin: Style.spacing.lg
            text: root.activeSheet && root.activeSheet.note && !root.searching
              ? root.activeSheet.note : ""
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }

          Text {
            id: hint
            anchors.top: parent.top
            anchors.topMargin: Style.spacing.sm
            anchors.right: parent.right
            text: "Tab sheet   ↑↓ move   ⏎ copy   ^R reload   Esc close"
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
