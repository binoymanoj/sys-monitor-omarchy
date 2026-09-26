import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "SysMonitorModel.js" as Model

BarWidget {
  id: root
  moduleName: "sys-monitor"

  // Settings State
  property bool showMainIcon: true
  property bool iconOnly: false
  property string barIcon: ""
  property bool showCpu: true
  property bool showRam: true
  property bool showStorage: true
  property bool showExternalStorage: true
  property bool showNet: true
  property bool showNetUpload: false
  property bool showIcons: true
  property int refreshInterval: 2000

  // Metrics State
  property var cpuData: ({ usage: 0, cores: [], total: 0, idle: 0, rawCores: [] })
  property var memData: ({
    percent: 0,
    usedGB: "0.0",
    totalGB: "0.0",
    freeGB: "0.0",
    availableGB: "0.0",
    swapPercent: 0,
    swapUsedGB: "0.0",
    swapTotalGB: "0.0"
  })
  property var storageData: Model.defaultStorageData()
  property var netData: ({
    rxSpeed: 0,
    txSpeed: 0,
    rxFormatted: "0 B/s",
    txFormatted: "0 B/s",
    totalRx: 0,
    totalTx: 0,
    activeIface: "net"
  })
  property var loadAvg: ["0.00", "0.00", "0.00"]
  property string uptime: "0m"
  property string cpuModel: "Processor"
  property double lastUpdateTime: 0

  // Derived Properties
  readonly property int cpuPercent: cpuData ? (cpuData.usage || 0) : 0
  readonly property bool cpuUrgent: cpuPercent >= 85
  readonly property int ramPercent: memData ? (memData.percent || 0) : 0
  readonly property bool ramUrgent: ramPercent >= 90
  readonly property int storagePercent: storageData && storageData.internal ? (storageData.internal.percent || 0) : 0
  readonly property bool storageUrgent: storagePercent >= 90
  readonly property bool anyUrgent: cpuUrgent || ramUrgent || storageUrgent
  readonly property bool hasExternalStorage: storageData ? (storageData.hasExternal || false) : false
  readonly property var externalDrives: storageData && storageData.external ? storageData.external : []
  readonly property string externalBarText: {
    if (!externalDrives || externalDrives.length === 0) return ""
    if (externalDrives.length === 1) {
      var d = externalDrives[0]
      if (d.isMounted && d.percent !== undefined && d.percent !== null) {
        return d.percent + "%"
      } else if (d.label && d.label.length > 0) {
        return d.label
      } else {
        return "ext"
      }
    }
    var mounted = externalDrives.filter(function(x) { return x.isMounted })
    if (mounted.length > 0) {
      return mounted[0].percent + "% (" + externalDrives.length + ")"
    }
    return externalDrives.length + " ext"
  }
  readonly property string netDownSpeed: netData ? (netData.rxFormatted || "0 B/s") : "0 B/s"
  readonly property string netUpSpeed: netData ? (netData.txFormatted || "0 B/s") : "0 B/s"
  readonly property string activeIface: netData ? (netData.activeIface || "net") : "net"
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property color activeUrgentColor: bar ? bar.urgent : Color.urgent

  readonly property bool hasAnyStatVisible: showCpu || showRam || showStorage || (showExternalStorage && hasExternalStorage) || showNet || showNetUpload
  readonly property bool isIconOnlyMode: iconOnly || !hasAnyStatVisible
  readonly property bool hasAnyMetricVisible: true

  readonly property string tooltipString: {
    var str = "System Monitor\n" +
      "CPU: " + cpuPercent + "% (Load: " + loadAvg.join(", ") + ")\n" +
      "RAM: " + ramPercent + "% (" + memData.usedGB + "/" + memData.totalGB + " GB)\n" +
      "Storage: " + storagePercent + "% (" + ((storageData && storageData.internal) ? storageData.internal.usedFormatted : "0") + "/" + ((storageData && storageData.internal) ? storageData.internal.totalFormatted : "0") + ")\n"
    if (hasExternalStorage && externalDrives.length > 0) {
      for (var i = 0; i < externalDrives.length; i++) {
        var ext = externalDrives[i]
        if (ext.isMounted) {
          str += "External: " + ext.displayName + " (" + ext.usedFormatted + "/" + ext.sizeFormatted + " - " + ext.percent + "%)\n"
        } else {
          str += "External: " + ext.displayName + " (" + ext.sizeFormatted + " - Unmounted)\n"
        }
      }
    }
    str += "Net: ↓ " + netDownSpeed + " | ↑ " + netUpSpeed + " (" + activeIface + ")\n" +
      "Left-click: Configure & Details • Right-click: btop"
    return str
  }

  // Popup Lifecycle
  property bool previewOpen: false
  property bool popoutSwitchClosing: false
  readonly property bool opened: previewOpen

  function open() {
    previewOpen = true
    refresh()
  }

  function close() {
    previewOpen = false
  }

  function toggle() {
    previewOpen ? close() : open()
  }

  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  function openTaskManager() {
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-launch-terminal btop")
    } else {
      Quickshell.execDetached("omarchy-launch-terminal", ["btop"])
    }
  }

  function openMountPath(mountPath) {
    if (mountPath && mountPath.length > 0) {
      if (root.bar && typeof root.bar.run === "function") {
        root.bar.run("xdg-open \"" + mountPath + "\"")
      } else {
        Quickshell.execDetached("xdg-open", [mountPath])
      }
    }
  }

  // Shell IPC Handler
  IpcHandler {
    target: "sys-monitor"

    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  // System File Readers & Hardware Queries
  FileView { id: statFile; path: "/proc/stat"; printErrors: false }
  FileView { id: memFile; path: "/proc/meminfo"; printErrors: false }
  FileView { id: netFile; path: "/proc/net/dev"; printErrors: false }
  FileView { id: loadFile; path: "/proc/loadavg"; printErrors: false }
  FileView { id: upFile; path: "/proc/uptime"; printErrors: false }
  FileView {
    id: cpuInfoFile
    path: "/proc/cpuinfo"
    printErrors: false
    onLoaded: root.cpuModel = Model.parseCpuModel(text())
  }

  Process {
    id: storageProc
    command: ["lsblk", "-b", "-J", "-o", "NAME,TYPE,SIZE,FSAVAIL,FSUSED,FSUSE%,MOUNTPOINT,MOUNTPOINTS,FSTYPE,MODEL,ROTA,RM,HOTPLUG,TRAN,LABEL,PATH"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.storageData = Model.parseStorage(text)
      }
    }
  }

  function refresh() {
    var now = Date.now()
    var dt = root.lastUpdateTime > 0 ? (now - root.lastUpdateTime) / 1000.0 : 1.0
    root.lastUpdateTime = now

    statFile.reload()
    memFile.reload()
    netFile.reload()
    loadFile.reload()
    upFile.reload()

    if (!storageProc.running) {
      storageProc.running = true
    }

    root.cpuData = Model.parseCpuStat(statFile.text(), root.cpuData)
    root.memData = Model.parseMemInfo(memFile.text())
    root.netData = Model.parseNetDev(netFile.text(), root.netData, dt)
    root.loadAvg = Model.parseLoadAvg(loadFile.text())
    root.uptime = Model.parseUptime(upFile.text())
  }

  Timer {
    id: updateTimer
    interval: Math.max(500, root.refreshInterval)
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // Settings Persistence
  readonly property string stateDir: {
    var xdgState = Quickshell.env("XDG_STATE_HOME")
    return (xdgState && xdgState.length > 0)
      ? (xdgState + "/omarchy/settings")
      : (Quickshell.env("HOME") + "/.local/state/omarchy/settings")
  }
  readonly property string settingsPath: stateDir + "/sys-monitor.json"

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onFileChanged: reload()
  }

  function applySettingsFromHost() {
    root.showMainIcon = setting("showMainIcon", true) === true
    root.iconOnly = setting("iconOnly", false) === true
    root.barIcon = setting("barIcon", "") || ""
    root.showCpu = setting("showCpu", true) === true
    root.showRam = setting("showRam", true) === true
    root.showStorage = setting("showStorage", true) === true
    root.showExternalStorage = setting("showExternalStorage", true) === true
    root.showNet = setting("showNet", true) === true
    root.showNetUpload = setting("showNetUpload", false) === true
    root.showIcons = setting("showIcons", true) === true
    root.refreshInterval = Math.max(500, parseInt(setting("refreshInterval", 2000)) || 2000)
  }

  function loadSettings(raw) {
    if (!raw || raw.trim() === "") {
      applySettingsFromHost()
      return
    }
    try {
      var parsed = JSON.parse(raw)
      if (parsed && typeof parsed === "object") {
        if (parsed.showMainIcon !== undefined) root.showMainIcon = parsed.showMainIcon === true
        if (parsed.iconOnly !== undefined) root.iconOnly = parsed.iconOnly === true
        if (parsed.barIcon !== undefined && typeof parsed.barIcon === "string" && parsed.barIcon.length > 0) root.barIcon = parsed.barIcon
        if (parsed.showCpu !== undefined) root.showCpu = parsed.showCpu === true
        if (parsed.showRam !== undefined) root.showRam = parsed.showRam === true
        if (parsed.showStorage !== undefined) root.showStorage = parsed.showStorage === true
        if (parsed.showExternalStorage !== undefined) root.showExternalStorage = parsed.showExternalStorage === true
        if (parsed.showNet !== undefined) root.showNet = parsed.showNet === true
        if (parsed.showNetUpload !== undefined) root.showNetUpload = parsed.showNetUpload === true
        if (parsed.showIcons !== undefined) root.showIcons = parsed.showIcons === true
        if (parsed.refreshInterval !== undefined) root.refreshInterval = Math.max(500, parseInt(parsed.refreshInterval) || 2000)
      }
    } catch (e) {
      applySettingsFromHost()
    }
  }

  function saveSettings() {
    var data = {
      showMainIcon: root.showMainIcon,
      iconOnly: root.iconOnly,
      barIcon: root.barIcon,
      showCpu: root.showCpu,
      showRam: root.showRam,
      showStorage: root.showStorage,
      showExternalStorage: root.showExternalStorage,
      showNet: root.showNet,
      showNetUpload: root.showNetUpload,
      showIcons: root.showIcons,
      refreshInterval: root.refreshInterval
    }
    settingsFile.setText(JSON.stringify(data, null, 2) + "\n")

    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
      var entry = { id: root.moduleName }
      for (var k in data) entry[k] = data[k]
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    }
  }

  function resetDefaults() {
    var def = Model.defaultSettings()
    root.showMainIcon = def.showMainIcon
    root.iconOnly = def.iconOnly
    root.barIcon = def.barIcon
    root.showCpu = def.showCpu
    root.showRam = def.showRam
    root.showStorage = def.showStorage
    root.showExternalStorage = def.showExternalStorage
    root.showNet = def.showNet
    root.showNetUpload = def.showNetUpload
    root.showIcons = def.showIcons
    root.refreshInterval = def.refreshInterval
    root.saveSettings()
  }

  onSettingsChanged: applySettingsFromHost()
  Component.onCompleted: {
    applySettingsFromHost()
    settingsFile.reload()
    refresh()
  }

  // Geometry
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  visible: hasAnyMetricVisible

  // Bar Button Component
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: root.hasAnyMetricVisible
    tooltipText: root.tooltipString
    horizontalMargin: root.isIconOnlyMode ? 0 : 8
    verticalPadding: root.isIconOnlyMode ? 0 : 6

    fixedWidth: root.vertical ? -1 : (root.isIconOnlyMode ? Style.bar.iconSlot : (barContentRow.implicitWidth + button.scaledHorizontalMargin * 2))
    fixedHeight: root.vertical ? (root.isIconOnlyMode ? Style.bar.iconSlot : (barContentCol.implicitHeight + button.scaledVerticalPadding * 2)) : -1

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.openTaskManager()
      } else if (b === Qt.MiddleButton) {
        root.refresh()
      } else {
        root.toggle()
      }
    }

    // Icon-Only Container (Active in Icon-Only Mode OR when all stats are removed)
    Item {
      id: iconOnlyContainer
      visible: root.isIconOnlyMode
      anchors.centerIn: parent
      width: Style.bar.iconSlot
      height: Style.bar.iconSlot

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.barIcon && root.barIcon.length > 0 ? root.barIcon : ""
        font.family: Style.font.family
        font.pixelSize: Style.bar.iconFont
        color: root.anyUrgent ? root.activeUrgentColor : Color.accent
        renderType: Text.NativeRendering
      }
    }

    // Horizontal Layout (Standard Bar)
    Row {
      id: barContentRow
      visible: !root.vertical && !root.isIconOnlyMode
      anchors.centerIn: parent
      spacing: Style.space(9)

      // Main Widget Icon (When showMainIcon is enabled alongside stats)
      Row {
        visible: root.showMainIcon
        anchors.verticalCenter: parent.verticalCenter

        Text {
          textFormat: Text.PlainText
          text: root.barIcon && root.barIcon.length > 0 ? root.barIcon : ""
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: root.anyUrgent ? root.activeUrgentColor : Color.accent
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // CPU Metric
      Row {
        visible: root.showCpu
        spacing: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          visible: root.showIcons
          text: ""
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: root.cpuUrgent ? root.activeUrgentColor : Color.accent
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          textFormat: Text.PlainText
          text: root.cpuPercent + "%"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: root.cpuUrgent ? root.activeUrgentColor : root.barForeground
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // RAM Metric
      Row {
        visible: root.showRam
        spacing: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          visible: root.showIcons
          text: ""
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: root.ramUrgent ? root.activeUrgentColor : Color.accent
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          textFormat: Text.PlainText
          text: root.ramPercent + "%"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: root.ramUrgent ? root.activeUrgentColor : root.barForeground
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // Internal Storage Metric
      Row {
        visible: root.showStorage
        spacing: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          visible: root.showIcons
          text: "󰋊"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: root.storageUrgent ? root.activeUrgentColor : Color.accent
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          textFormat: Text.PlainText
          text: root.storagePercent + "%"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: root.storageUrgent ? root.activeUrgentColor : root.barForeground
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // External Storage Metric (Dynamic: appears when attached!)
      Row {
        visible: root.showExternalStorage && root.hasExternalStorage
        spacing: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          visible: root.showIcons
          text: "󱛟"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.accent
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          textFormat: Text.PlainText
          text: root.externalBarText
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: root.barForeground
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // Net Download Metric
      Row {
        visible: root.showNet
        spacing: Style.space(3)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          visible: root.showIcons
          text: "↓"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.accent
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          textFormat: Text.PlainText
          text: root.netDownSpeed
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: root.barForeground
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // Net Upload Metric
      Row {
        visible: root.showNetUpload
        spacing: Style.space(3)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          visible: root.showIcons
          text: "↑"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.accent
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          textFormat: Text.PlainText
          text: root.netUpSpeed
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: root.barForeground
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    // Vertical Layout (Vertical Bar)
    Column {
      id: barContentCol
      visible: root.vertical && !root.isIconOnlyMode
      anchors.centerIn: parent
      spacing: Style.space(4)

      // Main Widget Icon (When showMainIcon is enabled alongside stats)
      Row {
        visible: root.showMainIcon
        anchors.horizontalCenter: parent.horizontalCenter

        Text {
          textFormat: Text.PlainText
          text: root.barIcon && root.barIcon.length > 0 ? root.barIcon : ""
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: root.anyUrgent ? root.activeUrgentColor : Color.accent
        }
      }

      Row {
        visible: root.showCpu
        spacing: Style.space(2)
        anchors.horizontalCenter: parent.horizontalCenter
        Text {
          visible: root.showIcons
          text: ""
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: root.cpuUrgent ? root.activeUrgentColor : Color.accent
        }
        Text {
          text: root.cpuPercent + "%"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: root.cpuUrgent ? root.activeUrgentColor : root.barForeground
        }
      }

      Row {
        visible: root.showRam
        spacing: Style.space(2)
        anchors.horizontalCenter: parent.horizontalCenter
        Text {
          visible: root.showIcons
          text: ""
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: root.ramUrgent ? root.activeUrgentColor : Color.accent
        }
        Text {
          text: root.ramPercent + "%"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: root.ramUrgent ? root.activeUrgentColor : root.barForeground
        }
      }

      Row {
        visible: root.showStorage
        spacing: Style.space(2)
        anchors.horizontalCenter: parent.horizontalCenter
        Text {
          visible: root.showIcons
          text: "󰋊"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: root.storageUrgent ? root.activeUrgentColor : Color.accent
        }
        Text {
          text: root.storagePercent + "%"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: root.storageUrgent ? root.activeUrgentColor : root.barForeground
        }
      }

      Row {
        visible: root.showExternalStorage && root.hasExternalStorage
        spacing: Style.space(2)
        anchors.horizontalCenter: parent.horizontalCenter
        Text {
          visible: root.showIcons
          text: "󱛟"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.accent
        }
        Text {
          text: root.externalBarText
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: root.barForeground
        }
      }

      Row {
        visible: root.showNet
        spacing: Style.space(2)
        anchors.horizontalCenter: parent.horizontalCenter
        Text {
          text: "↓" + root.netDownSpeed
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: root.barForeground
        }
      }
    }

    // Popup Open Marker at the Bar Edge
    Rectangle {
      id: openIndicator
      visible: root.previewOpen
      readonly property bool isVert: !!root.bar && root.bar.vertical
      color: Color.accent
      anchors.bottom: isVert ? undefined : parent.bottom
      anchors.right: isVert ? parent.right : undefined
      anchors.horizontalCenter: isVert ? undefined : parent.horizontalCenter
      anchors.verticalCenter: isVert ? parent.verticalCenter : undefined
      width: isVert ? Style.space(2) : (root.isIconOnlyMode ? Style.space(14) : Math.max(Style.space(18), barContentRow.implicitWidth * 0.4))
      height: isVert ? (root.isIconOnlyMode ? Style.space(14) : Math.max(Style.space(18), barContentCol.implicitHeight * 0.4)) : Style.space(2)
      radius: Style.cornerRadius > 0 ? 1 : 0
    }
  }

  // Popup Window
  KeyboardPanel {
    id: previewPanel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.previewOpen
    focusTarget: keyCatcher
    contentWidth: previewPanel.fittedContentWidth(Style.space(390))
    contentHeight: previewPanel.fittedContentHeight(scrollContent.implicitHeight, Style.space(660))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Flickable {
        id: flickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: scrollContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: scrollContent
          width: flickable.width
          spacing: Style.space(14)
          topPadding: Style.space(4)
          bottomPadding: Style.space(8)

          // 1. Header Card
          Item {
            width: parent.width
            implicitHeight: Style.space(42)

            Rectangle {
              id: heroIconBox
              width: Style.space(38)
              height: Style.space(38)
              radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(6)
              color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
              border.width: 1
              border.color: Color.accent
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter

              Text {
                anchors.centerIn: parent
                text: root.barIcon && root.barIcon.length > 0 ? root.barIcon : ""
                font.family: Style.font.family
                font.pixelSize: Style.font.display
                color: Color.accent
              }
            }

            Column {
              anchors.left: heroIconBox.right
              anchors.leftMargin: Style.space(10)
              anchors.right: btopBtn.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: "System Monitor"
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
                color: Color.popups.text
              }

              Text {
                textFormat: Text.PlainText
                text: root.cpuModel + " • Up " + root.uptime
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Qt.darker(Color.popups.text, 1.4)
                elide: Text.ElideRight
                width: parent.width
              }
            }

            Button {
              id: btopBtn
              text: "btop"
              iconText: "󰄛"
              bordered: true
              fontSize: Style.font.caption
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(5)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.openTaskManager()
            }
          }

          PanelSeparator {}

          // 2. Live Metrics Cards
          PanelSectionHeader {
            text: "LIVE METRICS"
          }

          // CPU Card
          Rectangle {
            width: parent.width
            implicitHeight: cpuCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Qt.rgba(Color.popups.border.r, Color.popups.border.g, Color.popups.border.b, 0.08)
            border.width: 1
            border.color: Qt.rgba(Color.popups.border.r, Color.popups.border.g, Color.popups.border.b, 0.2)

            Column {
              id: cpuCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              Item {
                width: parent.width
                implicitHeight: Math.max(cpuTitle.implicitHeight, cpuVal.implicitHeight)

                Text {
                  id: cpuTitle
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: " CPU Utilization"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: Color.popups.text
                }

                Text {
                  id: cpuVal
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.cpuPercent + "%"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  color: root.cpuUrgent ? root.activeUrgentColor : Color.accent
                }
              }

              // CPU Progress Bar
              Rectangle {
                width: parent.width
                height: Style.space(6)
                radius: Style.space(3)
                color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.12)

                Rectangle {
                  height: parent.height
                  width: Math.max(0, Math.min(parent.width, parent.width * (root.cpuPercent / 100.0)))
                  radius: Style.space(3)
                  color: root.cpuUrgent ? root.activeUrgentColor : Color.accent

                  Behavior on width {
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                  }
                }
              }

              Row {
                width: parent.width
                Text {
                  text: "Load Average: " + root.loadAvg.join(", ")
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(Color.popups.text, 1.4)
                }
              }

              // Per-Core Mini Bars (if available)
              Item {
                visible: root.cpuData && root.cpuData.cores && root.cpuData.cores.length > 0
                width: parent.width
                implicitHeight: coreGrid.implicitHeight

                Flow {
                  id: coreGrid
                  width: parent.width
                  spacing: Style.space(4)

                  Repeater {
                    model: root.cpuData ? root.cpuData.cores : []

                    Rectangle {
                      required property int modelData
                      required property int index
                      width: Math.floor((coreGrid.width - (Math.min(root.cpuData.cores.length, 8) - 1) * Style.space(4)) / Math.min(root.cpuData.cores.length, 8))
                      height: Style.space(16)
                      radius: Style.space(2)
                      color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.08)

                      Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.max(1, Math.min(parent.height, parent.height * (modelData / 100.0)))
                        radius: Style.space(2)
                        color: modelData >= 85 ? root.activeUrgentColor : Color.accent
                        opacity: 0.8
                      }

                      Text {
                        anchors.centerIn: parent
                        text: String(index)
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption * 0.75
                        color: Color.popups.text
                        opacity: 0.6
                      }
                    }
                  }
                }
              }
            }
          }

          // RAM Card
          Rectangle {
            width: parent.width
            implicitHeight: ramCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Qt.rgba(Color.popups.border.r, Color.popups.border.g, Color.popups.border.b, 0.08)
            border.width: 1
            border.color: Qt.rgba(Color.popups.border.r, Color.popups.border.g, Color.popups.border.b, 0.2)

            Column {
              id: ramCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              Item {
                width: parent.width
                implicitHeight: Math.max(ramTitle.implicitHeight, ramVal.implicitHeight)

                Text {
                  id: ramTitle
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: " Memory (RAM)"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: Color.popups.text
                }

                Text {
                  id: ramVal
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.ramPercent + "%"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  color: root.ramUrgent ? root.activeUrgentColor : Color.accent
                }
              }

              // RAM Progress Bar
              Rectangle {
                width: parent.width
                height: Style.space(6)
                radius: Style.space(3)
                color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.12)

                Rectangle {
                  height: parent.height
                  width: Math.max(0, Math.min(parent.width, parent.width * (root.ramPercent / 100.0)))
                  radius: Style.space(3)
                  color: root.ramUrgent ? root.activeUrgentColor : Color.accent

                  Behavior on width {
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                  }
                }
              }

              Row {
                width: parent.width
                Text {
                  text: root.memData.usedGB + " GB used of " + root.memData.totalGB + " GB (" + root.memData.availableGB + " GB available)"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(Color.popups.text, 1.4)
                }
              }

              Row {
                visible: root.memData.swapTotalGB !== "0.0"
                width: parent.width
                Text {
                  text: "Swap: " + root.memData.swapUsedGB + " GB / " + root.memData.swapTotalGB + " GB (" + root.memData.swapPercent + "%)"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(Color.popups.text, 1.5)
                }
              }
            }
          }

          // Internal Storage Card
          Rectangle {
            width: parent.width
            implicitHeight: storageCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Qt.rgba(Color.popups.border.r, Color.popups.border.g, Color.popups.border.b, 0.08)
            border.width: 1
            border.color: Qt.rgba(Color.popups.border.r, Color.popups.border.g, Color.popups.border.b, 0.2)

            Column {
              id: storageCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              Item {
                width: parent.width
                implicitHeight: Math.max(storageTitle.implicitHeight, storageVal.implicitHeight)

                Text {
                  id: storageTitle
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰋊 Internal Storage"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: Color.popups.text
                }

                Text {
                  id: storageVal
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.storagePercent + "%"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  color: root.storageUrgent ? root.activeUrgentColor : Color.accent
                }
              }

              // Storage Progress Bar
              Rectangle {
                width: parent.width
                height: Style.space(6)
                radius: Style.space(3)
                color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.12)

                Rectangle {
                  height: parent.height
                  width: Math.max(0, Math.min(parent.width, parent.width * (root.storagePercent / 100.0)))
                  radius: Style.space(3)
                  color: root.storageUrgent ? root.activeUrgentColor : Color.accent

                  Behavior on width {
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                  }
                }
              }

              Row {
                width: parent.width
                Text {
                  text: ((root.storageData && root.storageData.internal) ? root.storageData.internal.usedFormatted : "0 GB") +
                        " used of " +
                        ((root.storageData && root.storageData.internal) ? root.storageData.internal.totalFormatted : "0 GB") +
                        " (" +
                        ((root.storageData && root.storageData.internal) ? root.storageData.internal.availFormatted : "0 GB") +
                        " available)"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(Color.popups.text, 1.4)
                }
              }

              Row {
                width: parent.width
                Text {
                  text: "Mount: " +
                        (((root.storageData && root.storageData.internal) && root.storageData.internal.mountpoint) ? root.storageData.internal.mountpoint : "/") +
                        (((root.storageData && root.storageData.internal) && root.storageData.internal.fstype) ? (" • " + root.storageData.internal.fstype.toUpperCase()) : "") +
                        (((root.storageData && root.storageData.internal) && root.storageData.internal.model) ? (" • " + root.storageData.internal.model) : "")
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(Color.popups.text, 1.6)
                  elide: Text.ElideRight
                  width: parent.width
                }
              }

              // Secondary internal partitions if any (e.g. /boot, separate /home)
              Repeater {
                model: (root.storageData && root.storageData.internal && root.storageData.internal.partitions) ? root.storageData.internal.partitions : []

                Row {
                  id: partRow
                  required property var modelData
                  width: storageCol.width
                  spacing: Style.space(6)

                  Text {
                    text: partRow.modelData.mountpoint + ":"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    color: Qt.darker(Color.popups.text, 1.3)
                  }

                  Text {
                    text: partRow.modelData.usedFormatted + " / " + partRow.modelData.sizeFormatted + " (" + partRow.modelData.percent + "%)"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Qt.darker(Color.popups.text, 1.5)
                  }
                }
              }
            }
          }

          // External Storage Card (Shown dynamically when external storage is attached!)
          Rectangle {
            visible: root.hasExternalStorage
            width: parent.width
            implicitHeight: extCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Qt.rgba(Color.popups.border.r, Color.popups.border.g, Color.popups.border.b, 0.08)
            border.width: 1
            border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)

            Column {
              id: extCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(10)

              Item {
                width: parent.width
                implicitHeight: Math.max(extTitle.implicitHeight, extBadge.implicitHeight)

                Row {
                  id: extTitle
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(6)

                  Text {
                    text: "󱛟"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    color: Color.accent
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: "External Storage"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    color: Color.popups.text
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Rectangle {
                  id: extBadge
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(20)
                  width: extBadgeText.implicitWidth + Style.space(12)
                  radius: Style.space(10)
                  color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)

                  Text {
                    id: extBadgeText
                    anchors.centerIn: parent
                    text: root.externalDrives.length + (root.externalDrives.length === 1 ? " device" : " devices")
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    color: Color.accent
                  }
                }
              }

              Repeater {
                model: root.externalDrives

                Column {
                  id: driveItem
                  required property var modelData
                  required property int index
                  width: extCol.width
                  spacing: Style.space(6)

                  Rectangle {
                    visible: driveItem.index > 0
                    width: parent.width
                    height: 1
                    color: Qt.rgba(Color.popups.border.r, Color.popups.border.g, Color.popups.border.b, 0.15)
                  }

                  Item {
                    width: parent.width
                    implicitHeight: Math.max(driveNameCol.implicitHeight, driveActionsRow.implicitHeight)

                    Column {
                      id: driveNameCol
                      anchors.left: parent.left
                      anchors.right: driveActionsRow.left
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(2)

                      Text {
                        text: driveItem.modelData.displayName || driveItem.modelData.name
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: true
                        color: Color.popups.text
                        elide: Text.ElideRight
                        width: parent.width
                      }

                      Text {
                        text: driveItem.modelData.isMounted
                          ? (driveItem.modelData.mountpoint + (driveItem.modelData.fstype ? " • " + driveItem.modelData.fstype.toUpperCase() : ""))
                          : ("Attached (" + (driveItem.modelData.fstype ? driveItem.modelData.fstype.toUpperCase() + " • " : "") + "Unmounted)")
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        color: Qt.darker(Color.popups.text, 1.5)
                        elide: Text.ElideRight
                        width: parent.width
                      }
                    }

                    Row {
                      id: driveActionsRow
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(6)

                      Text {
                        visible: driveItem.modelData.isMounted
                        text: driveItem.modelData.percent + "%"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: true
                        color: driveItem.modelData.percent >= 90 ? root.activeUrgentColor : Color.accent
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      Button {
                        visible: driveItem.modelData.isMounted && driveItem.modelData.mountpoint.length > 0
                        text: "Open"
                        iconText: "󰉉"
                        bordered: true
                        fontSize: Style.font.caption
                        horizontalPadding: Style.space(8)
                        verticalPadding: Style.space(3)
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: root.openMountPath(driveItem.modelData.mountpoint)
                      }
                    }
                  }

                  // Progress bar (if mounted)
                  Rectangle {
                    visible: driveItem.modelData.isMounted
                    width: parent.width
                    height: Style.space(5)
                    radius: Style.space(2.5)
                    color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.12)

                    Rectangle {
                      height: parent.height
                      width: Math.max(0, Math.min(parent.width, parent.width * (driveItem.modelData.percent / 100.0)))
                      radius: Style.space(2.5)
                      color: driveItem.modelData.percent >= 90 ? root.activeUrgentColor : Color.accent

                      Behavior on width {
                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                      }
                    }
                  }

                  // Size details
                  Row {
                    width: parent.width
                    Text {
                      text: driveItem.modelData.isMounted
                        ? (driveItem.modelData.usedFormatted + " used of " + driveItem.modelData.sizeFormatted + " (" + driveItem.modelData.availFormatted + " available)")
                        : ("Capacity: " + driveItem.modelData.sizeFormatted)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      color: Qt.darker(Color.popups.text, 1.4)
                    }
                  }
                }
              }
            }
          }

          // Network Card
          Rectangle {
            width: parent.width
            implicitHeight: netCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Qt.rgba(Color.popups.border.r, Color.popups.border.g, Color.popups.border.b, 0.08)
            border.width: 1
            border.color: Qt.rgba(Color.popups.border.r, Color.popups.border.g, Color.popups.border.b, 0.2)

            Column {
              id: netCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              Item {
                width: parent.width
                implicitHeight: Math.max(netTitle.implicitHeight, netIface.implicitHeight)

                Text {
                  id: netTitle
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰛳 Network Traffic"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: Color.popups.text
                }

                Text {
                  id: netIface
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.activeIface
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(Color.popups.text, 1.4)
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(12)

                // Download Stat
                Rectangle {
                  width: (parent.width - Style.space(12)) / 2
                  height: Style.space(44)
                  radius: Style.space(4)
                  color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.05)

                  Column {
                    anchors.centerIn: parent
                    spacing: Style.space(2)
                    Row {
                      anchors.horizontalCenter: parent.horizontalCenter
                      spacing: Style.space(4)
                      Text { text: "↓"; font.bold: true; color: Color.accent; font.pixelSize: Style.font.body }
                      Text { text: "Download"; color: Qt.darker(Color.popups.text, 1.4); font.pixelSize: Style.font.caption }
                    }
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: root.netDownSpeed
                      font.bold: true
                      color: Color.popups.text
                      font.pixelSize: Style.font.body
                    }
                  }
                }

                // Upload Stat
                Rectangle {
                  width: (parent.width - Style.space(12)) / 2
                  height: Style.space(44)
                  radius: Style.space(4)
                  color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.05)

                  Column {
                    anchors.centerIn: parent
                    spacing: Style.space(2)
                    Row {
                      anchors.horizontalCenter: parent.horizontalCenter
                      spacing: Style.space(4)
                      Text { text: "↑"; font.bold: true; color: Color.accent; font.pixelSize: Style.font.body }
                      Text { text: "Upload"; color: Qt.darker(Color.popups.text, 1.4); font.pixelSize: Style.font.caption }
                    }
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: root.netUpSpeed
                      font.bold: true
                      color: Color.popups.text
                      font.pixelSize: Style.font.body
                    }
                  }
                }
              }
            }
          }

          PanelSeparator {}

          // 3. Configuration Section (Configurable in popup window!)
          PanelSectionHeader {
            text: "TOPBAR CONFIGURATION"
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Toggle {
              width: parent.width
              label: "Show System Monitor Icon"
              description: "Display the main system icon on the topbar"
              checked: root.showMainIcon
              onClicked: {
                root.showMainIcon = !root.showMainIcon
                root.saveSettings()
              }
            }

            Toggle {
              width: parent.width
              label: "Icon-Only Mode"
              description: "Keep only 1 icon on the bar (clicking opens the stats popup)"
              checked: root.isIconOnlyMode
              onClicked: {
                root.iconOnly = !root.isIconOnlyMode
                root.saveSettings()
              }
            }

            // Topbar Icon Selector
            Column {
              width: parent.width
              spacing: Style.space(5)
              visible: root.showMainIcon || root.isIconOnlyMode

              Text {
                text: "Select Topbar Icon:"
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Qt.darker(Color.popups.text, 1.4)
              }

              Row {
                width: parent.width
                spacing: Style.space(5)

                Repeater {
                  model: [
                    { icon: "", name: "CPU" },
                    { icon: "󰻠", name: "Gauge" },
                    { icon: "", name: "Activity" },
                    { icon: "󰍛", name: "Chip" },
                    { icon: "󰋊", name: "Storage" },
                    { icon: "󰾆", name: "Dashboard" }
                  ]

                  Button {
                    required property var modelData
                    text: modelData.icon
                    tooltipText: modelData.name
                    selected: root.barIcon === modelData.icon
                    bordered: true
                    fontSize: Style.font.body
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(4)
                    onClicked: {
                      root.barIcon = modelData.icon
                      root.saveSettings()
                    }
                  }
                }

                TextField {
                  width: Style.space(48)
                  text: root.barIcon
                  placeholderText: ""
                  horizontalAlignment: TextInput.AlignHCenter
                  onEditingFinished: {
                    if (text.trim().length > 0) {
                      root.barIcon = text.trim()
                      root.saveSettings()
                    }
                  }
                }
              }
            }

            PanelSeparator {}

            Toggle {
              width: parent.width
              label: "Show CPU Usage"
              description: "Show CPU % (e.g.  " + root.cpuPercent + "%) on the topbar"
              checked: root.showCpu
              onClicked: {
                root.showCpu = !root.showCpu
                root.saveSettings()
              }
            }

            Toggle {
              width: parent.width
              label: "Show RAM Usage"
              description: "Show Memory % (e.g.  " + root.ramPercent + "%) on the topbar"
              checked: root.showRam
              onClicked: {
                root.showRam = !root.showRam
                root.saveSettings()
              }
            }

            Toggle {
              width: parent.width
              label: "Show Internal Storage"
              description: "Show Storage % (e.g. 󰋊 " + root.storagePercent + "%) on the topbar"
              checked: root.showStorage
              onClicked: {
                root.showStorage = !root.showStorage
                root.saveSettings()
              }
            }

            Toggle {
              width: parent.width
              label: "Show External Storage"
              description: "Show external drive (e.g. 󱛟 " + (root.hasExternalStorage ? root.externalBarText : "USB") + ") on topbar when attached"
              checked: root.showExternalStorage
              onClicked: {
                root.showExternalStorage = !root.showExternalStorage
                root.saveSettings()
              }
            }

            Toggle {
              width: parent.width
              label: "Show Download Speed"
              description: "Show Network download (e.g. ↓ " + root.netDownSpeed + ") on the topbar"
              checked: root.showNet
              onClicked: {
                root.showNet = !root.showNet
                root.saveSettings()
              }
            }

            Toggle {
              width: parent.width
              label: "Show Upload Speed"
              description: "Show Network upload (e.g. ↑ " + root.netUpSpeed + ") on the topbar"
              checked: root.showNetUpload
              onClicked: {
                root.showNetUpload = !root.showNetUpload
                root.saveSettings()
              }
            }

            Toggle {
              width: parent.width
              label: "Show Metric Icons"
              description: "Display icons (, , 󰋊, 󱛟, ↓, ↑) beside percentage values"
              checked: root.showIcons
              onClicked: {
                root.showIcons = !root.showIcons
                root.saveSettings()
              }
            }
          }

          // Refresh Interval Selector
          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "Refresh Rate:"
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              color: Color.popups.text
              anchors.verticalCenter: parent.verticalCenter
            }

            Row {
              spacing: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter

              Repeater {
                model: [
                  { label: "1s", val: 1000 },
                  { label: "2s", val: 2000 },
                  { label: "3s", val: 3000 },
                  { label: "5s", val: 5000 }
                ]

                Button {
                  required property var modelData
                  text: modelData.label
                  selected: root.refreshInterval === modelData.val
                  bordered: true
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(4)
                  onClicked: {
                    root.refreshInterval = modelData.val
                    root.saveSettings()
                  }
                }
              }
            }
          }

          PanelSeparator {}

          // 4. Footer Actions
          Item {
            width: parent.width
            implicitHeight: Math.max(resetBtn.implicitHeight, doneBtn.implicitHeight)

            Button {
              id: resetBtn
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Reset Defaults"
              bordered: true
              fontSize: Style.font.caption
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(5)
              onClicked: root.resetDefaults()
            }

            Button {
              id: doneBtn
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "Done"
              selected: true
              bordered: true
              fontSize: Style.font.caption
              horizontalPadding: Style.space(16)
              verticalPadding: Style.space(5)
              onClicked: root.close()
            }
          }
        }
      }
    }
  }
}
