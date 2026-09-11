import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Pomodoro timer for the bar.
//
// Durations live in the widget's shell.json entry rather than in QML state, so
// the manifest defaults apply, the settings panel can edit them, and a +/-
// adjustment survives a shell restart. Countdown state stays in memory and is
// relayed to the widget's peers, because one instance of this widget exists per
// monitor and all of them must show the same clock.
BarWidget {
  id: root
  moduleName: "joaobordignon.pomodoro"

  readonly property int workMinutes: clampMinutes(setting("workMinutes", 25), 25)
  readonly property int breakMinutes: clampMinutes(setting("breakMinutes", 5), 5)
  readonly property bool autoCycle: toBool(setting("autoCycle", true), true)
  readonly property int currentTargetMinutes: isBreak ? breakMinutes : workMinutes

  property bool isBreak: false
  property bool running: false
  property int totalSeconds: 0
  property int remainingSeconds: 0
  property double endTime: 0
  property string notifyHeadline: ""
  property string notifyBody: ""

  readonly property real progress: totalSeconds > 0
    ? Math.max(0.0, Math.min(1.0, (totalSeconds - remainingSeconds) / totalSeconds))
    : 0.0

  readonly property string phaseName: isBreak ? "Break" : "Work"
  readonly property string cycleLabel: workMinutes + "/" + breakMinutes
  readonly property string cycleName: String(setting("cycleName", ""))
  readonly property string cycleDisplay: cycleName ? (cycleName + " " + cycleLabel) : cycleLabel

  // An idle timer sitting at its full duration is showing the phase length
  // restated as a countdown, so those pixels carry the cycle instead. Anything
  // part-way through -- running, or paused mid-session -- shows the clock.
  readonly property bool atFullDuration: !running && totalSeconds > 0
    && remainingSeconds === totalSeconds

  // Theme tokens, not literals: the bar hands out foreground/urgent already
  // resolved for the current theme and for transparent-bar mode.
  readonly property color foregroundColor: bar ? bar.barForeground : Color.foreground
  readonly property color modeColor: isBreak ? Color.accent : (bar ? bar.urgent : Color.urgent)
  readonly property color markColor: running ? modeColor : foregroundColor
  readonly property color glyphColor: isBreak ? modeColor : markColor

  readonly property bool widgetHovered: mainHover.containsMouse
    || iconBtn.tooltipHovered || timeBtn.tooltipHovered || minusBtn.tooltipHovered
    || trackBtn.tooltipHovered || plusBtn.tooltipHovered || resetBtn.tooltipHovered

  function toBool(value, fallback) {
    if (value === undefined || value === null) return fallback
    if (typeof value === "string") return value !== "" && value !== "false" && value !== "0"
    return !!value
  }

  function clampMinutes(value, fallback) {
    var n = Math.round(Number(value))
    if (!isFinite(n) || n <= 0) n = fallback
    return Math.max(1, Math.min(180, n))
  }

  function formatTime(sec) {
    var m = Math.floor(sec / 60)
    var s = sec % 60
    return (m < 10 ? "0" + m : "" + m) + ":" + (s < 10 ? "0" + s : "" + s)
  }

  function peers() {
    var items = bar && typeof bar.moduleWidgets === "function"
      ? bar.moduleWidgets(moduleName) : []
    return items.length > 0 ? items : [root]
  }

  // A bar surface exists per monitor, so state changes have to reach every
  // live copy of this widget, not just the one that was clicked.
  function relay(method, arg) {
    var items = peers()
    for (var i = 0; i < items.length; i++) {
      if (items[i] && typeof items[i][method] === "function") items[i][method](arg)
    }
  }

  function requestToggle() { relay("doToggle") }
  function requestReset() { relay("doReset") }
  function requestSwitchMode() { relay("applyPhase", !isBreak) }

  // Every settings change goes through the shell rather than the file: the
  // shell rewrites the whole of shell.json from its in-memory copy, so an edit
  // made behind its back is lost on the next write. A null value drops the key.
  function writeEntry(changes) {
    var entry = { "id": moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    for (var change in changes) {
      if (changes[change] === null) delete entry[change]
      else entry[change] = changes[change]
    }

    // Applied locally first so the label moves on the click itself; the
    // shell.json write comes back through the bar as the same value.
    relay("applySettings", entry)
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, entry)
  }

  function requestAdjust(delta) {
    var next = clampMinutes(currentTargetMinutes + delta, currentTargetMinutes)
    if (next === currentTargetMinutes) return

    if (running) relay("shiftRunning", (next - currentTargetMinutes) * 60)

    var changes = {}
    changes[isBreak ? "breakMinutes" : "workMinutes"] = next
    // A hand-tuned duration is no longer the preset it was named after.
    changes["cycleName"] = null
    writeEntry(changes)
  }

  // Both durations in one write, so the bar never shows half of a new cycle.
  function applyCycle(workValue, breakValue, name) {
    var w = clampMinutes(workValue, workMinutes)
    var b = clampMinutes(breakValue, breakMinutes)
    var label = String(name || "")
    writeEntry({ "workMinutes": w, "breakMinutes": b, "cycleName": label ? label : null })
    return w + "/" + b
  }

  function applySettings(entry) {
    root.settings = entry
  }

  function resetToTarget() {
    totalSeconds = currentTargetMinutes * 60
    remainingSeconds = totalSeconds
    endTime = 0
  }

  function doToggle() {
    if (running) {
      remainingSeconds = Math.max(0, Math.round((endTime - Date.now()) / 1000))
      running = false
    } else {
      if (remainingSeconds <= 0) resetToTarget()
      endTime = Date.now() + (remainingSeconds * 1000)
      running = true
    }
  }

  function doReset() {
    running = false
    resetToTarget()
  }

  // Phase changes relay the phase itself rather than a toggle: a toggle
  // applied once per monitor is a coin flip on how many instances agree.
  function applyPhase(breakPhase) {
    running = false
    isBreak = breakPhase === true
    resetToTarget()
  }

  function beginPhase(breakPhase) {
    applyPhase(breakPhase)
    endTime = Date.now() + (remainingSeconds * 1000)
    running = true
  }

  function shiftRunning(deltaSec) {
    if (!running) return
    remainingSeconds = Math.max(10, remainingSeconds + deltaSec)
    totalSeconds = Math.max(remainingSeconds, totalSeconds + deltaSec)
    endTime = Date.now() + (remainingSeconds * 1000)
  }

  // Every instance reaches zero on its own; only one of them is allowed to
  // announce it, or a six-monitor desk gets six notifications.
  function handleFinished() {
    var items = peers()
    if (items[0] !== root) return

    // argv is snapshotted into plain properties first. The phase flips on the
    // next line, and a command still bound to isBreak would race the launch and
    // announce the phase that is starting instead of the one that just ended.
    notifyHeadline = isBreak ? "Break Finished!" : "Pomodoro Completed!"
    notifyBody = isBreak
      ? "Ready to get back to work!"
      : "Great job! Take a " + breakMinutes + "-minute break."
    notifyProcess.running = true
    soundProcess.running = true

    // Only the instance that announced drives the hand-off, so the next phase
    // is decided once and relayed, not raced between monitors.
    if (autoCycle) relay("beginPhase", !isBreak)
  }

  // Deferred: a settings change invalidates currentTargetMinutes while bindings
  // that read it (the tooltips) are still evaluating, and resetting the
  // countdown from inside that pass reads back as a binding loop.
  function syncIdleTarget() {
    if (!running) resetToTarget()
  }

  Component.onCompleted: resetToTarget()
  onCurrentTargetMinutesChanged: Qt.callLater(syncIdleTarget)

  Timer {
    id: tickTimer
    interval: 500
    repeat: true
    running: root.running
    onTriggered: {
      var left = Math.round((root.endTime - Date.now()) / 1000)
      if (left <= 0) {
        root.remainingSeconds = 0
        root.running = false
        root.handleFinished()
      } else {
        root.remainingSeconds = left
      }
    }
  }

  Process {
    id: notifyProcess
    command: [
      "omarchy-notification-send",
      "-g", "󱫠",
      "-u", "critical",
      root.notifyHeadline,
      root.notifyBody
    ]
  }

  Process {
    id: soundProcess
    command: ["canberra-gtk-play", "-i", "complete"]
  }

  IpcHandler {
    target: root.moduleName

    function reset(): void { root.requestReset() }
    function toggle(): void { root.requestToggle() }
    function start(): void { if (!root.running) root.requestToggle() }
    function pause(): void { if (root.running) root.requestToggle() }
    function add(): void { root.requestAdjust(1) }
    function sub(): void { root.requestAdjust(-1) }
    function mode(): void { root.requestSwitchMode() }

    function cycle(work: string, brk: string, name: string): string {
      return root.applyCycle(work, brk, name)
    }

    function auto(enabled: string): string {
      var on = root.toBool(enabled, true)
      root.writeEntry({ "autoCycle": on })
      return on ? "on" : "off"
    }

    function status(): string {
      return JSON.stringify({
        phase: root.isBreak ? "break" : "work",
        running: root.running,
        remainingSeconds: root.remainingSeconds,
        totalSeconds: root.totalSeconds,
        workMinutes: root.workMinutes,
        breakMinutes: root.breakMinutes,
        cycleName: root.cycleName,
        autoCycle: root.autoCycle
      })
    }
  }

  implicitWidth: root.vertical ? root.barSize : content.implicitWidth + Style.space(10)
  implicitHeight: root.vertical ? content.implicitHeight + Style.space(6) : root.barSize

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: Style.space(2)
    anchors.bottomMargin: Style.space(2)
    radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(4)
    color: root.widgetHovered ? Style.hoverFill : "transparent"
    border.width: root.running || root.widgetHovered ? Style.normalBorderWidth : 0
    border.color: root.running
      ? Qt.rgba(root.modeColor.r, root.modeColor.g, root.modeColor.b, 0.45)
      : Style.hoverBorderColor

    Behavior on border.color { ColorAnimation { duration: 180 } }
    Behavior on color { ColorAnimation { duration: 140 } }
  }

  // Bottom duration accent line
  Rectangle {
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.leftMargin: Style.space(2)
    height: Style.space(2)
    width: Math.round((parent.width - Style.space(4)) * root.progress)
    radius: height / 2
    color: root.running ? root.modeColor : Color.accent
    visible: root.progress > 0
  }

  // Wheel handling for the gaps between the buttons; each button forwards its
  // own wheel events, since a MouseArea with an onWheel handler consumes them.
  MouseArea {
    id: mainHover
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onWheel: function(wheel) { root.requestAdjust(wheel.angleDelta.y > 0 ? 1 : -1) }
  }

  // One positioner for both orientations. A Grid lays out only its visible
  // children, so the controls that are hidden on a vertical bar take no space
  // and, being invisible, are skipped by the bar's click routing too.
  Grid {
    id: content
    anchors.centerIn: parent
    columns: root.vertical ? 1 : 99
    spacing: Style.space(4)

    // Mode / run-state icon
    WidgetButton {
      id: iconBtn
      bar: root.bar
      // Phase only. Run state is carried by the border and by the digits
      // moving; a glyph that flipped to a play icon was describing the button,
      // not the session you were in.
      text: root.isBreak ? "󰅶" : "󱫠"
      tooltipText: root.phaseName + " · " + root.currentTargetMinutes + " min"
        + " · cycle " + root.cycleDisplay
        + " · click to " + (root.running ? "pause" : "start")
        + " · right-click to switch"
      foreground: root.glyphColor
      fixedWidth: root.vertical ? -1 : Style.space(18)
      fixedHeight: root.vertical ? Style.bar.iconSlot : -1
      fontSize: Style.bar.iconFont
      onPressed: function(button) {
        if (button === Qt.RightButton) root.requestSwitchMode()
        else root.requestToggle()
      }
      onWheelMoved: function(delta) { root.requestAdjust(delta > 0 ? 1 : -1) }
    }

    // Time remaining. Vertical bars are too narrow for mm:ss, so they get the
    // whole minutes left instead.
    WidgetButton {
      id: timeBtn
      bar: root.bar
      text: root.vertical
        ? String(Math.ceil(root.remainingSeconds / 60))
        : (root.atFullDuration ? root.cycleLabel : root.formatTime(root.remainingSeconds))
      tooltipText: root.atFullDuration
        ? ("Cycle " + root.cycleDisplay + " · " + root.phaseName + " "
           + root.currentTargetMinutes + " min · click to start")
        : ((root.running ? "Click to pause" : "Click to start")
           + " · right-click for " + (root.isBreak ? "work" : "break"))
      foreground: root.markColor
      horizontalMargin: 3
      fixedHeight: root.vertical ? Style.bar.iconSlot : -1
      onPressed: function(button) {
        if (button === Qt.RightButton) root.requestSwitchMode()
        else root.requestToggle()
      }
      onWheelMoved: function(delta) { root.requestAdjust(delta > 0 ? 1 : -1) }
    }

    WidgetButton {
      id: minusBtn
      bar: root.bar
      text: "−"
      tooltipText: "Shorten " + (root.isBreak ? "break" : "work") + " by 1 min"
      hasVisualContent: !root.vertical
      fixedWidth: Style.space(16)
      fontSize: Style.font.bodySmall
      onPressed: function(button) { root.requestAdjust(-1) }
      onWheelMoved: function(delta) { root.requestAdjust(delta > 0 ? 1 : -1) }

      Rectangle {
        z: -1
        anchors.centerIn: parent
        width: Style.space(16)
        height: Style.space(16)
        radius: Style.space(3)
        color: minusBtn.tooltipHovered ? Style.hoverFill : Style.normalFill
        border.width: minusBtn.tooltipHovered ? Style.hoverBorderWidth : 0
        border.color: Style.hoverBorderColor
      }
    }

    // Duration progress bar
    WidgetButton {
      id: trackBtn
      bar: root.bar
      labelVisible: false
      hasVisualContent: !root.vertical
      tooltipText: "Work " + root.workMinutes + " / Break " + root.breakMinutes
        + " · " + Math.round(root.progress * 100) + "% elapsed"
      fixedWidth: Style.space(44)
      onPressed: function(button) { root.requestToggle() }
      onWheelMoved: function(delta) { root.requestAdjust(delta > 0 ? 1 : -1) }

      Rectangle {
        anchors.centerIn: parent
        width: Style.space(44)
        height: Style.space(5)
        radius: height / 2
        color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.18)

        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: Math.round(parent.width * root.progress)
          radius: parent.radius
          color: root.running ? root.modeColor : Color.accent

          Behavior on width {
            NumberAnimation { duration: 250; easing.type: Easing.OutQuad }
          }
        }
      }
    }

    WidgetButton {
      id: plusBtn
      bar: root.bar
      text: "+"
      tooltipText: "Extend " + (root.isBreak ? "break" : "work") + " by 1 min"
      hasVisualContent: !root.vertical
      fixedWidth: Style.space(16)
      fontSize: Style.font.bodySmall
      onPressed: function(button) { root.requestAdjust(1) }
      onWheelMoved: function(delta) { root.requestAdjust(delta > 0 ? 1 : -1) }

      Rectangle {
        z: -1
        anchors.centerIn: parent
        width: Style.space(16)
        height: Style.space(16)
        radius: Style.space(3)
        color: plusBtn.tooltipHovered ? Style.hoverFill : Style.normalFill
        border.width: plusBtn.tooltipHovered ? Style.hoverBorderWidth : 0
        border.color: Style.hoverBorderColor
      }
    }

    WidgetButton {
      id: resetBtn
      bar: root.bar
      text: "󰦛"
      tooltipText: "Reset timer"
      hasVisualContent: !root.vertical
      foreground: resetBtn.tooltipHovered ? (root.bar ? root.bar.urgent : Color.urgent) : root.foregroundColor
      fixedWidth: Style.space(18)
      fontSize: Style.bar.iconFont
      onPressed: function(button) { root.requestReset() }
      onWheelMoved: function(delta) { root.requestAdjust(delta > 0 ? 1 : -1) }

      Rectangle {
        z: -1
        anchors.centerIn: parent
        width: Style.space(18)
        height: Style.space(16)
        radius: Style.space(3)
        color: resetBtn.tooltipHovered ? Style.hoverFill : Style.normalFill
        border.width: resetBtn.tooltipHovered ? Style.hoverBorderWidth : 0
        border.color: resetBtn.tooltipHovered ? (root.bar ? root.bar.urgent : Color.urgent) : Style.hoverBorderColor
      }
    }
  }
}
