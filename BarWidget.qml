import QtQuick
import qs.Ui

// Bar icon for the cheatsheet overlay.
//
// A plugin that declares both `overlay` and `bar-widget` is owned by the shell's
// panel loader rather than by the bar (shell.qml isBarWidgetPanelPlugin), so the
// widget cannot toggle a panel of its own — it goes through the same IPC route
// the keybinding uses. omarchy.menu's widget does exactly this.
BarWidget {
  id: root
  moduleName: "abelk.cheatsheets"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰘳"
    tooltipText: "Cheatsheets"
    onPressed: function(mouseButton) {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle abelk.cheatsheets")
    }
  }
}
