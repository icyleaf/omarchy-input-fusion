import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "i18n.js" as I18n
import "BloomController.js" as Bloom

// Control panel for the Input Fusion bar widget: the fcitx5 Input Method and
// Rime Schema sections, plus the Bloom bridge (schemas, packages, updates).
//
// This panel holds no processes and reads no live fcitx5 state of its own.
// A focused layer-shell surface makes fcitx5 report and switch its own
// transient input context instead of the focused application's, so anything
// read here while open would be the panel's context, not the app's. The bar
// widget owns all state and switching; the panel renders the widget's
// snapshot and, on selection, closes first (releasing focus) and asks the
// widget to apply the choice. Bloom is not shadowed, so its rows bind live to
// the widget and call back through it to toggle a schema or open a terminal.
Panel {
    id: root

    moduleName: "icyleaf.input-fusion"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null

    property string lang: {
        var envLang = Quickshell.env("LANG") || "";
        return envLang.toLowerCase().indexOf("zh") !== -1 ? "zh" : "en";
    }

    function tr(key) {
        var dummy = root.lang;
        return I18n.t(key);
    }

    onLangChanged: I18n.setLanguage(root.lang)
    Component.onCompleted: I18n.setLanguage(root.lang)

    readonly property color panelForeground: Color.popups.text
    readonly property color panelBackground: Color.popups.background
    readonly property color panelAccent: Color.accent

    // --- snapshot from the widget -------------------------------------------
    property var snapshot: ({ error: "", imDisplay: "", schema: "", state: -1,
                              isRime: false, unavailable: false, daemonRunning: false })
    property var inputRows: []
    property var rimeRows: []
    property int cursor: 0

    // --- Bloom bridge (read-only) -------------------------------------------
    // Unlike fcitx5, Bloom is not shadowed by the panel's keyboard focus, so
    // these bind live to the widget and may update while the panel is open.
    readonly property bool bloomVisible: root.hostWidget ? root.hostWidget.bloomAvailable : false
    readonly property bool bloomChecking: root.hostWidget ? root.hostWidget.bloomChecking : false
    readonly property var bloomEnabledSchemas: root.hostWidget ? root.hostWidget.bloomEnabledSchemas : []
    readonly property var bloomPackages: root.hostWidget ? root.hostWidget.bloomPackages : []
    readonly property var bloomUpdates: root.hostWidget ? root.hostWidget.bloomUpdates : []
    readonly property var bloomSchemas: root.hostWidget ? root.hostWidget.bloomSchemas : []
    readonly property int bloomUpdatesAvailable: root.hostWidget ? root.hostWidget.bloomUpdatesAvailable : -1
    readonly property double bloomUpdatesAt: root.hostWidget ? root.hostWidget.bloomUpdatesAt : 0
    readonly property string bloomError: root.hostWidget ? root.hostWidget.bloomError : ""
    readonly property bool bloomWriteRunning: root.hostWidget ? root.hostWidget.bloomWriteRunning : false
    readonly property string bloomWriteError: root.hostWidget ? root.hostWidget.bloomWriteError : ""

    function bloomRefresh() {
        if (!root.hostWidget) return;
        root.hostWidget.refreshBloom();
        root.hostWidget.refreshBloomUpdates();
    }

    // Enable/disable run in-process through the widget's Backend.
    function bloomToggle(schema, enabled) {
        if (root.hostWidget) root.hostWidget.bloomToggleSchema(schema, enabled);
    }

    // Upgrade opens a floating terminal via the widget (the panel holds no
    // processes of its own).
    function bloomUpgrade(repo) {
        if (root.hostWidget) root.hostWidget.bloomUpgrade(repo);
    }

    function takeSnapshot() {
        if (!root.hostWidget) return;
        var snap = root.hostWidget.snapshot();
        root.snapshot = snap;
        root.inputRows = snap.inputRows;
        root.rimeRows = snap.rimeRows;
        root.cursor = root.selectedGlobalIndex();
    }

    function allRows() {
        return root.inputRows.concat(root.rimeRows);
    }

    function currentRow() {
        var rows = root.allRows();
        if (root.cursor < 0 || root.cursor >= rows.length) return null;
        return rows[root.cursor];
    }

    function selectedGlobalIndex() {
        var rows = root.allRows();
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].selected) return i;
        }
        return rows.length > 0 ? 0 : -1;
    }

    function moveCursor(dy) {
        var rows = root.allRows();
        if (rows.length === 0) return;
        var next = root.cursor + dy;
        if (next < 0) next = 0;
        if (next >= rows.length) next = rows.length - 1;
        root.cursor = next;
    }

    function switchSection(direction) {
        if (direction > 0) root.cursor = root.inputRows.length;
        else root.cursor = 0;
    }

    function activate(row) {
        if (!row || !row.enabled || !root.hostWidget) return;
        var value = row.value;
        var isInputMethod = value !== "__direct__" && root.inputRows.indexOf(row) !== -1;
        root.close();
        root.hostWidget.applySelection(value, isInputMethod);
    }

    function open() {
        root.takeSnapshot();
        root.controller.show();
    }

    function close() { root.controller.hide(); }

    // Refresh the frozen snapshot only while closed, so the panel never
    // samples the shadowed context it would see while focused.
    onOpenedChanged: if (!root.opened) root.takeSnapshot()

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(360))
        contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(520))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onMoveRequested: function(dx, dy) { root.moveCursor(dy) }
            onActivateRequested: root.activate(root.currentRow())
            onTabRequested: function(direction) { root.switchSection(direction) }
            onCloseRequested: root.close()

            Item {
                id: content
                anchors.fill: parent
                implicitWidth: contentScroller.contentWidth
                implicitHeight: contentColumn.implicitHeight

                Flickable {
                    id: contentScroller
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: contentColumn.implicitHeight
                    clip: true
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: contentColumn
                        width: contentScroller.width
                        spacing: Style.space(10)

                        PanelSectionHeader {
                            width: parent.width
                            foreground: root.panelForeground
                            text: root.tr("section_input_method")
                        }

                        Repeater {
                            model: root.inputRows
                            delegate: rowDelegate
                        }

                        PanelSectionHeader {
                            width: parent.width
                            foreground: root.panelForeground
                            text: root.tr("section_rime_schema")
                        }

                        Text {
                            width: parent.width
                            visible: !root.snapshot.isRime
                            text: root.tr("rime_inactive_hint")
                            color: root.panelForeground
                            opacity: 0.58
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: root.rimeRows
                            delegate: rowDelegate
                        }

                        // --- Bloom (read + write) -------------------------------
                        // Schemas toggle in-process; packages and updates run
                        // their heavy writes in a terminal (see Widget.launchBloom).
                        Column {
                            width: parent.width
                            visible: root.bloomVisible
                            spacing: Style.space(6)

                            PanelSectionHeader {
                                width: parent.width
                                foreground: root.panelForeground
                                text: root.tr("section_bloom")
                            }

                            Text {
                                width: parent.width
                                text: root.tr("bloom_schemas")
                                color: root.panelForeground
                                opacity: 0.58
                                font.family: Style.font.family
                                font.pixelSize: Style.font.caption
                                font.bold: true
                            }

                            Text {
                                width: parent.width
                                visible: root.bloomSchemas.length === 0
                                text: root.tr("bloom_no_enabled")
                                color: root.panelForeground
                                opacity: 0.42
                                font.family: Style.font.family
                                font.pixelSize: Style.font.caption
                            }

                            Repeater {
                                model: root.bloomSchemas
                                delegate: bloomSchemaDelegate
                            }

                            Text {
                                width: parent.width
                                text: root.tr("bloom_packages")
                                color: root.panelForeground
                                opacity: 0.58
                                font.family: Style.font.family
                                font.pixelSize: Style.font.caption
                                font.bold: true
                            }

                            Text {
                                width: parent.width
                                visible: root.bloomPackages.length === 0
                                text: root.tr("bloom_no_packages")
                                color: root.panelForeground
                                opacity: 0.42
                                font.family: Style.font.family
                                font.pixelSize: Style.font.caption
                            }

                            Repeater {
                                model: root.bloomPackages
                                delegate: bloomPackageDelegate
                            }

                            Text {
                                width: parent.width
                                text: root.tr("bloom_updates")
                                color: root.panelForeground
                                opacity: 0.58
                                font.family: Style.font.family
                                font.pixelSize: Style.font.caption
                                font.bold: true
                            }

                            Repeater {
                                model: root.bloomUpdates
                                delegate: bloomUpdateDelegate
                            }

                            Text {
                                width: parent.width
                                text: {
                                    if (root.bloomWriteError !== "") return root.bloomWriteError;
                                    if (root.bloomWriteRunning) return root.tr("bloom_working");
                                    if (root.bloomError !== "") return root.bloomError;
                                    if (root.bloomChecking) return root.tr("bloom_checking");
                                    if (root.bloomUpdatesAvailable < 0) return root.tr("bloom_not_checked");
                                    if (root.bloomUpdatesAvailable === 0) return root.tr("bloom_up_to_date");
                                    return I18n.t("bloom_updates_available", root.bloomUpdatesAvailable);
                                }
                                color: (root.bloomError !== "" || root.bloomWriteError !== "") ? Color.accent : root.panelForeground
                                opacity: (root.bloomError !== "" || root.bloomWriteError !== "") ? 1.0 : 0.58
                                font.family: Style.font.family
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                id: bloomRefreshLabel
                                width: parent.width
                                text: "↻ " + root.tr("bloom_refresh")
                                color: root.panelAccent
                                font.family: Style.font.family
                                font.pixelSize: Style.font.caption
                                opacity: bloomRefreshMouse.containsMouse ? 1.0 : 0.75

                                MouseArea {
                                    id: bloomRefreshMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.bloomRefresh()
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: Style.spacing.hairline
                            color: Util.alpha(root.panelForeground, 0.16)
                        }

                        Text {
                            width: parent.width
                            text: {
                                if (root.snapshot.error !== "") return root.snapshot.error;
                                if (root.snapshot.daemonRunning) return root.tr("daemon_hint");
                                if (root.snapshot.unavailable) return root.tr("fcitx_unavailable");
                                if (root.snapshot.state === 1) return root.tr("state_direct");
                                if (root.snapshot.isRime) return root.snapshot.imDisplay + " · " + root.snapshot.schema;
                                return root.snapshot.imDisplay;
                            }
                            color: root.snapshot.error !== "" ? Color.accent : root.panelForeground
                            opacity: root.snapshot.error !== "" ? 1.0 : 0.58
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }

    Component {
        id: rowDelegate

        Rectangle {
            id: row
            required property var modelData

            width: contentColumn.width
            height: Style.space(38)
            radius: Style.cornerRadius
            color: {
                if (modelData.selected) return Style.selectedFillFor(root.panelForeground, root.panelAccent);
                if (mouse.containsMouse || modelData.global === root.cursor)
                    return Style.hoverFillFor(root.panelForeground, root.panelAccent);
                return "transparent";
            }
            // `muted` greys a Rime Schema row while Rime is inactive, but the
            // row stays clickable: selecting it switches to Rime first.
            opacity: modelData.muted ? 0.5 : 1.0

            Row {
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.rightMargin: Style.spacing.rowPaddingX
                spacing: Style.spacing.controlGap

                Text {
                    width: Style.space(26)
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.badge
                    color: root.panelForeground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    horizontalAlignment: Text.AlignHCenter
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(26) - check.width - Style.spacing.controlGap * 2
                    spacing: 0

                    Text {
                        width: parent.width
                        text: row.modelData.label
                        color: root.panelForeground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: row.modelData.selected
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        visible: row.modelData.sub !== "" && row.modelData.sub !== row.modelData.label
                        text: row.modelData.sub
                        color: root.panelForeground
                        opacity: 0.58
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                    }
                }

                Text {
                    id: check
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.selected ? "✓" : ""
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: row.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    root.cursor = row.modelData.global;
                    root.activate(row.modelData);
                }
            }
        }
    }

    // Bloom schema row: click toggles enable/disable (in-process).
    Component {
        id: bloomSchemaDelegate

        Rectangle {
            id: schemaRow
            required property var modelData

            width: parent.width
            height: Style.space(30)
            radius: Style.cornerRadius
            color: schemaMouse.containsMouse ? Style.hoverFillFor(root.panelForeground, root.panelAccent) : "transparent"
            opacity: root.bloomWriteRunning ? 0.55 : 1.0

            Row {
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.rightMargin: Style.spacing.rowPaddingX
                spacing: Style.spacing.controlGap

                Text {
                    width: Style.space(20)
                    anchors.verticalCenter: parent.verticalCenter
                    text: schemaRow.modelData.enabled ? "✓" : "○"
                    color: schemaRow.modelData.enabled ? Color.accent : root.panelForeground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(20) - Style.spacing.controlGap
                    text: schemaRow.modelData.id
                    color: root.panelForeground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                id: schemaMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !root.bloomWriteRunning
                cursorShape: Qt.PointingHandCursor
                onClicked: root.bloomToggle(schemaRow.modelData.id, !schemaRow.modelData.enabled)
            }
        }
    }

    // Bloom package row: click upgrades it in a floating terminal.
    Component {
        id: bloomPackageDelegate

        Rectangle {
            id: packageRow
            required property var modelData

            width: parent.width
            height: Style.space(34)
            radius: Style.cornerRadius
            color: packageMouse.containsMouse ? Style.hoverFillFor(root.panelForeground, root.panelAccent) : "transparent"

            Column {
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.rightMargin: Style.spacing.rowPaddingX
                spacing: 0

                Text {
                    width: parent.width
                    text: "• " + Bloom.packageLabel(packageRow.modelData.repo)
                    color: root.panelForeground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: sub !== ""
                    text: sub
                    color: root.panelForeground
                    opacity: 0.58
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight

                    readonly property string sub: {
                        var schemas = (packageRow.modelData.schemas || []).join(", ");
                        if (schemas !== "" && packageRow.modelData.version !== "") return schemas + " · " + packageRow.modelData.version;
                        return schemas !== "" ? schemas : packageRow.modelData.version;
                    }
                }
            }

            MouseArea {
                id: packageMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.bloomUpgrade(packageRow.modelData.repo)
            }
        }
    }

    // Bloom update row: click upgrades it in a floating terminal.
    Component {
        id: bloomUpdateDelegate

        Rectangle {
            id: updateRow
            required property var modelData

            width: parent.width
            height: Style.space(30)
            radius: Style.cornerRadius
            visible: modelData.updateAvailable
            color: updateMouse.containsMouse ? Style.hoverFillFor(root.panelForeground, root.panelAccent) : "transparent"

            Text {
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.rightMargin: Style.spacing.rowPaddingX
                verticalAlignment: Text.AlignVCenter
                text: "↑ " + Bloom.packageLabel(updateRow.modelData.repo) + ": " + updateRow.modelData.local + " → " + updateRow.modelData.remote
                color: root.panelForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
            }

            MouseArea {
                id: updateMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.bloomUpgrade(updateRow.modelData.repo)
            }
        }
    }
}
