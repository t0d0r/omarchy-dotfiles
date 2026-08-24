import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "todor.zabbix-status"
  ipcTarget: "todor.zabbix-status"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property string state: "LOADING"
  property string statusText: "Checking…"
  property bool promptedForKey: false
  property var events: []
  property string selectedGroup: "All"
  property string selectedSeverity: "All"
  property int problemCount: 0
  property int acknowledgedCount: 0
  property string highestSeverity: "INFO"
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color muted: Qt.darker(foreground, 1.45)
  readonly property var groups: {
    var result = ["All"]
    for (var i = 0; i < events.length; i++) {
      if (result.indexOf(events[i].group) < 0)
        result.push(events[i].group)
    }
    return result
  }
  readonly property var visibleEvents: {
    return events.filter(function(event) {
      var groupMatches = selectedGroup === "All" || event.group === selectedGroup
      var severityMatches = selectedSeverity === "All"
        || normalizeSeverity(event.severity) === selectedSeverity
      return groupMatches && severityMatches
    })
  }
  readonly property string severitySummary: formatSeverityCounts(events)
  readonly property var severityCounts: buildSeverityCounts(events)

  function normalizeSeverity(severity) {
    var normalized = String(severity || "INFO").toUpperCase()
    if (normalized === "WARNING") return "WARN"
    if (normalized === "AVERAGE") return "AVG"
    return normalized
  }

  function buildSeverityCounts(eventList) {
    var counts = {}
    for (var i = 0; i < eventList.length; i++) {
      var severity = normalizeSeverity(eventList[i].severity)
      counts[severity] = (counts[severity] || 0) + 1
    }

    var order = ["DISASTER", "HIGH", "AVG", "WARN", "INFO"]
    var result = []
    for (var j = 0; j < order.length; j++) {
      if (counts[order[j]])
        result.push({ severity: order[j], count: counts[order[j]] })
    }
    return result
  }

  function formatSeverityCounts(eventList) {
    var severityItems = buildSeverityCounts(eventList)
    var parts = []
    for (var i = 0; i < severityItems.length; i++)
      parts.push(severityItems[i].severity + " " + severityItems[i].count)
    return parts.join(" · ")
  }

  function open() { controller.show(); refresh() }
  function toggle() { opened ? close() : open() }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function refresh() {
    if (statusProcess.running) return
    state = "LOADING"
    statusText = "Checking…"
    statusProcess.running = true
  }

  function severityRank(severity) {
    var ranks = {
      "INFO": 1,
      "WARN": 2,
      "WARNING": 2,
      "AVG": 3,
      "AVERAGE": 3,
      "HIGH": 4,
      "DISASTER": 5
    }
    return ranks[String(severity || "").toUpperCase()] || 0
  }

  function severityColor(severity) {
    var rank = severityRank(severity)
    if (rank >= 4) return urgent
    if (rank === 3) return "#e5a84b"
    if (rank === 2) return "#d7bd55"
    return muted
  }

  function consume(raw) {
    var normalized = String(raw || "").replace(/\r/g, "")
    var lines = normalized.split("\n")
    var protocol = lines.length > 0 ? lines.shift() : ""
    var separator = protocol.indexOf("\t")
    var protocolState = separator < 0 ? protocol.trim() : protocol.slice(0, separator).trim()
    var protocolMessage = separator < 0 ? "" : protocol.slice(separator + 1).trim()

    if (protocolState !== "OK") {
      state = protocolState || "ERROR"
      statusText = protocolMessage || "Unknown error"
      events = []
      problemCount = 0
      acknowledgedCount = 0
      highestSeverity = "INFO"
    } else {
      var parsed = []
      var group = "Zabbix"
      var acked = 0
      var highest = "INFO"

      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (line === "") continue

        // zabbix.status emits group headers, then one event per line:
        // HH:MM:SS SEVERITY STATE ACK/NACK SOURCE message...
        var match = line.match(/^(\d{2}:\d{2}:\d{2})\s+(\S+)\s+(\S+)\s+(ACK|NACK)\s+(\S+)\s+(.+)$/)
        if (!match) {
          group = line
          continue
        }

        var event = {
          group: group,
          time: match[1],
          severity: match[2].toUpperCase(),
          condition: match[3].toUpperCase(),
          acknowledged: match[4].toUpperCase() === "ACK",
          source: match[5],
          message: match[6]
        }
        parsed.push(event)
        if (event.acknowledged) acked++
        if (severityRank(event.severity) > severityRank(highest)) highest = event.severity
      }

      events = parsed
      if (groups.indexOf(selectedGroup) < 0)
        selectedGroup = "All"
      if (selectedSeverity !== "All"
          && !parsed.some(function(event) { return normalizeSeverity(event.severity) === selectedSeverity }))
        selectedSeverity = "All"
      problemCount = parsed.length
      acknowledgedCount = acked
      highestSeverity = highest
      state = parsed.length > 0 ? "PROBLEM" : "OK"
      statusText = parsed.length > 0
        ? parsed.length + " problem" + (parsed.length === 1 ? "" : "s")
          + " · " + formatSeverityCounts(parsed)
        : "No active problems"
    }

    if (state === "NEEDS_KEY" && !promptedForKey) {
      promptedForKey = true
      unlockProcess.running = true
    } else if (state !== "NEEDS_KEY") {
      promptedForKey = false
    }
  }

  Component.onCompleted: refresh()

  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProcess
    command: [Qt.resolvedUrl("status.sh").toString().replace("file://", "")]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.consume(text) }
    stderr: StdioCollector { waitForEnd: true }
  }

  Process {
    id: unlockProcess
    command: [
      "xdg-terminal-exec", "bash", "-lc",
      "ssh-add \"$HOME/.ssh/id_ed25519\"; rc=$?; if (( rc != 0 )); then echo; read -rp 'Press Enter to close…'; fi; exit $rc"
    ]
    onExited: function(exitCode) { keyPoll.restart() }
  }

  Timer { id: keyPoll; interval: 1500; onTriggered: root.refresh() }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  PopupCard {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    contentWidth: panel.fittedContentWidth(Style.space(640))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    Item {
      anchors.fill: parent

      Column {
        id: content
        width: parent.width
        spacing: Style.space(16)

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(12)

          Text {
            text: "󰒋"
            color: root.state === "ERROR" || root.state === "NEEDS_KEY" ? root.urgent : root.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.icon
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)
            Text {
              text: "ZABBIX STATUS"
              color: root.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              font.letterSpacing: 1
            }
            Text {
              text: "do · ~/bin/zabbix.status"
              color: root.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)

          Rectangle {
            readonly property bool selected: root.selectedSeverity === "All"
            width: allSeverityLabel.implicitWidth + Style.space(16)
            height: Style.space(26)
            radius: height / 2
            color: selected
              ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
              : "transparent"

            Text {
              id: allSeverityLabel
              anchors.centerIn: parent
              text: root.state === "LOADING" ? "Checking…" : root.problemCount + " active"
              color: root.problemCount > 0 ? root.severityColor(root.highestSeverity) : root.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: parent.selected
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectedSeverity = "All"
            }
          }

          Row {
            visible: root.problemCount > 0
            spacing: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
              model: root.severityCounts

              Rectangle {
                required property var modelData
                readonly property bool selected: root.selectedSeverity === modelData.severity
                width: severityLabel.implicitWidth + Style.space(16)
                height: Style.space(26)
                radius: height / 2
                color: selected
                  ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
                  : "transparent"

                Text {
                  id: severityLabel
                  anchors.centerIn: parent
                  text: parent.modelData.severity + " " + parent.modelData.count
                  color: root.severityColor(parent.modelData.severity)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: parent.selected
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectedSeverity = parent.selected
                    ? "All" : parent.modelData.severity
                }
              }
            }
          }
        }

        Flickable {
          width: parent.width
          height: Style.space(30)
          contentWidth: categoryTabs.implicitWidth
          contentHeight: height
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Row {
            id: categoryTabs
            spacing: Style.space(8)

            Repeater {
              model: root.groups

              Rectangle {
                required property string modelData
                readonly property bool selected: root.selectedGroup === modelData
                width: tabLabel.implicitWidth + Style.space(24)
                height: Style.space(30)
                radius: height / 2
                color: selected
                  ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
                  : Style.hoverFillFor(root.foreground, Color.accent)

                Text {
                  id: tabLabel
                  anchors.centerIn: parent
                  text: parent.modelData
                  color: parent.selected ? root.foreground : root.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: parent.selected
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectedGroup = parent.modelData
                }
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Style.space(380)
          radius: Style.cornerRadius
          color: Style.hoverFillFor(root.foreground, Color.accent)
          clip: true

          Text {
            anchors.centerIn: parent
            width: parent.width - Style.space(40)
            visible: root.visibleEvents.length === 0
            text: root.state === "LOADING" ? "Checking do…"
              : root.events.length > 0 ? "No problems match these filters" : root.statusText
            color: root.state === "ERROR" || root.state === "NEEDS_KEY" ? root.urgent : root.muted
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
          }

          ListView {
            id: problemList
            anchors.fill: parent
            anchors.margins: Style.space(10)
            visible: root.visibleEvents.length > 0
            model: root.visibleEvents
            spacing: Style.space(8)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Item {
              required property int index
              required property var modelData
              width: problemList.width - (problemList.ScrollBar.vertical.visible ? Style.space(10) : 0)
              height: groupLabel.height + eventCard.height + (groupLabel.visible ? Style.space(7) : 0)

              readonly property bool firstInGroup: index === 0
                || root.visibleEvents[index - 1].group !== modelData.group

              Text {
                id: groupLabel
                visible: parent.firstInGroup && root.selectedGroup === "All"
                width: parent.width
                height: visible ? implicitHeight : 0
                text: parent.modelData.group
                color: root.muted
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideMiddle
              }

              Rectangle {
                id: eventCard
                y: groupLabel.height + (groupLabel.visible ? Style.space(7) : 0)
                width: parent.width
                height: eventContent.implicitHeight + Style.space(18)
                radius: Style.cornerRadius
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.055)

                Column {
                  id: eventContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.margins: Style.space(9)
                  spacing: Style.space(5)

                  Row {
                    spacing: Style.space(9)

                    Text {
                      text: modelData.severity
                      color: root.severityColor(modelData.severity)
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    Text {
                      text: modelData.time
                      color: root.muted
                      font.family: "monospace"
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      text: modelData.acknowledged ? "ACK" : "NACK"
                      color: modelData.acknowledged ? root.muted : root.foreground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      text: modelData.source
                      color: root.foreground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  Text {
                    width: parent.width
                    text: modelData.message
                    color: root.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.Wrap
                  }
                }
              }
            }
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(10)
          Button {
            text: root.state === "LOADING" ? "Refreshing…" : "Refresh"
            enabled: root.state !== "LOADING"
            foreground: root.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            fontSize: Style.font.bodySmall
            bordered: true
            onClicked: root.refresh()
          }
          Button {
            text: "Open SSH"
            foreground: root.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            fontSize: Style.font.bodySmall
            bordered: true
            onClicked: if (root.bar) root.bar.run("xdg-terminal-exec ssh do")
          }
        }
      }
    }
  }
}
