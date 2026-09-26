import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "yaml.js" as Yaml
import "i18n.js" as I18n

Item {
    id: root

    property var shell: null
    property var manifest: null
    property bool opened: false

    property string pluginId: (root.manifest && root.manifest.id) || "icyleaf.input-fusion"
    property var configData: ({})
    property string defaultInputMethod: "english"
    property string statusMessage: ""
    property bool isSaving: false
    property bool isPicking: false
    property int currentTab: 0 // 0: Rules, 1: Input Methods

    // Internationalization (i18n)
    property string lang: {
        var envLang = Quickshell.env("LANG") || "";
        return envLang.toLowerCase().indexOf("zh") !== -1 ? "zh" : "en";
    }

    function tr(key, arg0) {
        // Evaluate root.lang so that QML property binding tracks language switch
        var dummy = root.lang;
        return I18n.t(key, arg0);
    }

    onLangChanged: {
        I18n.setLanguage(root.lang);
    }

    Component.onCompleted: {
        I18n.setLanguage(root.lang);
    }

    // System Status Properties (Explicit reactive properties for reliable QML bindings)
    property bool isInstalled: false
    property bool isRunning: false
    property int runningPid: 0
    property string binaryVersion: ""
    property bool configExists: false
    property bool hasSlurp: false

    // Version feature check: keep setting supported since 0.4.0
    function isVersionAtLeast(currentVer, requiredVer) {
        if (!currentVer) return false;
        var curParts = currentVer.replace(/^v/, "").split(".").map(function(x) { return parseInt(x) || 0; });
        var reqParts = requiredVer.replace(/^v/, "").split(".").map(function(x) { return parseInt(x) || 0; });
        for (var i = 0; i < Math.max(curParts.length, reqParts.length); i++) {
            var c = curParts[i] || 0;
            var r = reqParts[i] || 0;
            if (c > r) return true;
            if (c < r) return false;
        }
        return true;
    }

    readonly property bool supportsKeep: isVersionAtLeast(root.binaryVersion, "0.4.0")

    // Rule dialog state
    property int editingRuleIndex: -1
    property string selectedRuleIm: "chinese"

    // Input Method dialog state
    property int editingImIndex: -1

    property var pickPoint: null

    readonly property color background: Color.menu.background
    readonly property color foreground: Color.menu.text
    readonly property color border: Color.menu.border
    readonly property color scrim: Color.menu.scrim
    readonly property color accent: Color.menu.selectedText
    readonly property color selectedBackground: Color.menu.selectedBackground
    readonly property string fontFamily: Style.font.menuFamily
    readonly property int cornerRadius: Style.cornerRadius

    function open(payloadJson) {
        root.opened = true;
        configFileView.reload();
        root.loadStatus();
        Qt.callLater(function() { keyCatcher.forceActiveFocus() });
    }

    function close() {
        ruleDialog.visible = false;
        imDialog.visible = false;
        root.opened = false;
    }

    function dismiss() {
        root.close();
        if (root.shell && typeof root.shell.hide === "function") {
            root.shell.hide(root.pluginId);
        }
    }

    function toggle() {
        if (root.opened) root.dismiss();
        else root.open("{}");
    }

    function getDefaultConfig() {
        return {
            "version": 2,
            "description": "Hyprland Input Method Switcher Configuration",
            "input_methods": {
                "english": "keyboard-us",
                "chinese": "rime",
                "japanese": "rime"
            },
            "default_input_method": "english",
            "client_rules": [
                {"class": "firefox", "title": "", "input_method": "chinese"},
                {"class": "google-chrome", "title": "", "input_method": "chinese"},
                {"class": "chromium", "title": "", "input_method": "chinese"},
                {"class": "wechat", "title": "", "input_method": "chinese"},
                {"class": "code", "title": "", "input_method": "english"},
                {"class": "n(?)vim", "title": "", "input_method": "english"},
                {"class": "kitty", "title": "", "input_method": "english"},
                {"class": "org.wezfurlong.wezterm", "title": "", "input_method": "english"}
            ],
            "fcitx5": {
                "enabled": true,
                "rime_input_method": "rime"
            },
            "rime_schemas": {
                "chinese": "rime_frost",
                "japanese": "jaroomaji"
            },
            "display_names": {
                "english": "English",
                "chinese": "中文",
                "japanese": "日本語"
            }
        };
    }

    function parseYamlConfig(rawText) {
        if (!rawText || rawText.trim() === "") {
            loadDefaultConfig();
            return;
        }
        try {
            var data = Yaml.parse(rawText);
            if (!data || typeof data !== "object") {
                loadDefaultConfig();
                return;
            }
            root.configData = data;
            root.defaultInputMethod = data.default_input_method || "english";

            // Sync Input Methods Model
            imModel.clear();
            var ims = data.input_methods || {};
            var names = data.display_names || {};
            var rimeSchemas = data.rime_schemas || {};
            for (var key in ims) {
                imModel.append({
                    imKey: key,
                    imEngine: String(ims[key]),
                    imDisplayName: names[key] || key,
                    imRimeSchema: rimeSchemas[key] || ""
                });
            }

            // Sync Rules Model
            rulesModel.clear();
            if (data.client_rules) {
                for (var i = 0; i < data.client_rules.length; i++) {
                    rulesModel.append({
                        ruleClass: data.client_rules[i].class || "",
                        ruleTitle: data.client_rules[i].title || "",
                        ruleInputMethod: data.client_rules[i].input_method || "english"
                    });
                }
            }
            root.configExists = true;
            root.statusMessage = root.tr("config_synced");
        } catch(e) {
            root.statusMessage = e.message;
        }
    }

    function loadDefaultConfig() {
        var def = getDefaultConfig();
        parseYamlConfig(Yaml.dump(def));
        root.statusMessage = root.tr("default_template_loaded");
    }

    // Quickshell FileView: Direct YAML Read & Atomic Write
    FileView {
        id: configFileView
        path: Quickshell.env("HOME") + "/.config/hypr-input-switcher/config.yaml"
        watchChanges: true
        printErrors: false
        onLoaded: root.parseYamlConfig(text())
        onLoadFailed: root.loadDefaultConfig()
    }

    // Diagnostics: CLI Version Probe
    Process {
        id: versionProcess
        command: ["hypr-input-switcher", "version"]
        property string outputBuffer: ""

        stdout: SplitParser {
            onRead: data => { versionProcess.outputBuffer += data }
        }

        onExited: (code, status) => {
            if (code === 0 && outputBuffer.trim().length > 0) {
                root.isInstalled = true;
                var match = outputBuffer.match(/(\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z.-]+)?)/);
                if (match) {
                    root.binaryVersion = match[1];
                } else {
                    root.binaryVersion = "0.0.0";
                }
            } else {
                root.isInstalled = false;
                root.binaryVersion = "";
            }
            outputBuffer = "";
        }
    }

    // Diagnostics: Daemon Process Probe
    Process {
        id: pgrepProcess
        command: ["pgrep", "-f", "hypr-input-switcher"]
        property string outputBuffer: ""

        stdout: SplitParser {
            onRead: data => { pgrepProcess.outputBuffer += data }
        }

        onExited: (code, status) => {
            if (code === 0 && outputBuffer.trim().length > 0) {
                var pids = outputBuffer.trim().split("\n");
                var validPid = parseInt(pids[0]);
                if (!isNaN(validPid) && validPid > 0) {
                    root.isRunning = true;
                    root.runningPid = validPid;
                } else {
                    root.isRunning = false;
                    root.runningPid = 0;
                }
            } else {
                root.isRunning = false;
                root.runningPid = 0;
            }
            outputBuffer = "";
        }
    }

    // Diagnostics: Slurp Availability Probe
    Process {
        id: slurpCheckProcess
        command: ["which", "slurp"]
        property string outputBuffer: ""

        stdout: SplitParser {
            onRead: data => { slurpCheckProcess.outputBuffer += data }
        }

        onExited: (code, status) => {
            root.hasSlurp = (code === 0 && outputBuffer.trim().length > 0);
            outputBuffer = "";
        }
    }

    Timer {
        id: statusDelayTimer
        interval: 600
        repeat: false
        onTriggered: root.loadStatus()
    }

    // Pure Native Window Picker Processes
    Process {
        id: slurpProcess
        command: ["slurp", "-p", "-b", "00000060", "-c", "89b4faff"]
        property string outputBuffer: ""

        stdout: SplitParser {
            onRead: data => { slurpProcess.outputBuffer += data }
        }

        onExited: (code, status) => {
            if (code === 0 && outputBuffer.length > 0) {
                var parts = outputBuffer.trim().split(" ")[0].split(",");
                if (parts.length >= 2) {
                    root.pickPoint = { x: parseInt(parts[0]), y: parseInt(parts[1]) };
                    clientsProcess.outputBuffer = "";
                    clientsProcess.running = true;
                    outputBuffer = "";
                    return;
                }
            }
            root.isPicking = false;
            root.opened = true;
            root.statusMessage = root.tr("screen_pick_cancel");
            outputBuffer = "";
            Qt.callLater(function() { keyCatcher.forceActiveFocus() });
        }
    }

    Process {
        id: clientsProcess
        command: ["hyprctl", "clients", "-j"]
        property string outputBuffer: ""

        stdout: SplitParser {
            onRead: data => { clientsProcess.outputBuffer += data }
        }

        onExited: (code, status) => {
            root.isPicking = false;
            root.opened = true;
            if (code === 0 && outputBuffer.length > 0 && root.pickPoint) {
                try {
                    var clients = JSON.parse(outputBuffer);
                    var px = root.pickPoint.x;
                    var py = root.pickPoint.y;
                    var matched = null;
                    for (var i = 0; i < clients.length; i++) {
                        var c = clients[i];
                        var at = c.at || [0, 0];
                        var size = c.size || [0, 0];
                        if (px >= at[0] && px <= at[0] + size[0] && py >= at[1] && py <= at[1] + size[1]) {
                            matched = c;
                            break;
                        }
                    }
                    if (matched) {
                        dialogClassInput.text = matched.class || matched.initialClass || "";
                        if (matched.title && dialogTitleInput.text === "") {
                            dialogTitleInput.text = matched.title;
                        }
                        root.statusMessage = root.tr("screen_picked", matched.class || matched.initialClass);
                    } else {
                        root.statusMessage = root.tr("screen_pick_not_found");
                    }
                } catch(e) {
                    root.statusMessage = e.message;
                }
            }
            outputBuffer = "";
            root.pickPoint = null;
            Qt.callLater(function() { keyCatcher.forceActiveFocus() });
        }
    }

    ListModel { id: rulesModel }
    ListModel { id: imModel }

    function getImDisplayName(key) {
        if (key === "keep") {
            return root.tr("keep_current");
        }
        for (var i = 0; i < imModel.count; i++) {
            if (imModel.get(i).imKey === key) {
                return imModel.get(i).imDisplayName;
            }
        }
        return key;
    }

    function loadStatus() {
        versionProcess.outputBuffer = "";
        versionProcess.running = true;
        pgrepProcess.outputBuffer = "";
        pgrepProcess.running = true;
        slurpCheckProcess.outputBuffer = "";
        slurpCheckProcess.running = true;
    }

    function launchDaemon() {
        Quickshell.execDetached(["uwsm", "app", "--", "hypr-input-switcher", "-w"]);
        root.statusMessage = "Starting hypr-input-switcher...";
        statusDelayTimer.start();
    }

    function saveConfig() {
        root.isSaving = true;
        root.statusMessage = root.tr("saving");

        var rulesList = [];
        for (var i = 0; i < rulesModel.count; i++) {
            var item = rulesModel.get(i);
            var entry = {
                "class": item.ruleClass,
                "input_method": item.ruleInputMethod
            };
            if (item.ruleTitle && item.ruleTitle.trim() !== "") {
                entry.title = item.ruleTitle;
            }
            rulesList.push(entry);
        }

        var imDict = {};
        var nameDict = {};
        var rimeDict = (root.configData && root.configData.rime_schemas) || {};
        for (var j = 0; j < imModel.count; j++) {
            var imItem = imModel.get(j);
            imDict[imItem.imKey] = imItem.imEngine;
            nameDict[imItem.imKey] = imItem.imDisplayName;
            if (imItem.imEngine.toLowerCase().indexOf("rime") !== -1) {
                if (imItem.imRimeSchema && imItem.imRimeSchema.trim() !== "") {
                    rimeDict[imItem.imKey] = imItem.imRimeSchema.trim();
                }
            } else {
                delete rimeDict[imItem.imKey];
            }
        }

        var payload = root.configData || {};
        payload.client_rules = rulesList;
        payload.input_methods = imDict;
        payload.display_names = nameDict;
        payload.rime_schemas = rimeDict;
        payload.default_input_method = root.defaultInputMethod;

        try {
            var yamlText = Yaml.dump(payload);
            configFileView.setText(yamlText);
            root.isSaving = false;
            root.statusMessage = root.tr("save_success");
            root.loadStatus();
        } catch(e) {
            root.isSaving = false;
            root.statusMessage = root.tr("save_failed") + e.message;
        }
    }

    function startPickWindow() {
        root.isPicking = true;
        root.statusMessage = root.tr("screen_picking_hint");
        root.opened = false;
        slurpProcess.outputBuffer = "";
        slurpProcess.running = true;
    }

    // --- Rules Dialog ---
    function openRuleDialog(index) {
        root.editingRuleIndex = index;
        if (index >= 0 && index < rulesModel.count) {
            var item = rulesModel.get(index);
            dialogClassInput.text = item.ruleClass;
            dialogTitleInput.text = item.ruleTitle;
            root.selectedRuleIm = item.ruleInputMethod;
            ruleDialogTitle.text = root.tr("rule_dialog_edit", (index + 1));
        } else {
            dialogClassInput.text = "";
            dialogTitleInput.text = "";
            root.selectedRuleIm = (imModel.count > 0 ? imModel.get(0).imKey : "english");
            ruleDialogTitle.text = root.tr("rule_dialog_add");
        }
        ruleDialog.visible = true;
        Qt.callLater(function() { dialogClassInput.forceActiveFocus() });
    }

    function applyRuleDialog() {
        var cls = dialogClassInput.text.trim();
        if (!cls) {
            root.statusMessage = root.tr("class_required");
            return;
        }

        var im = root.selectedRuleIm || "english";
        var title = dialogTitleInput.text.trim();

        if (root.editingRuleIndex >= 0 && root.editingRuleIndex < rulesModel.count) {
            rulesModel.set(root.editingRuleIndex, {
                ruleClass: cls,
                ruleTitle: title,
                ruleInputMethod: im
            });
        } else {
            rulesModel.append({
                ruleClass: cls,
                ruleTitle: title,
                ruleInputMethod: im
            });
        }
        ruleDialog.visible = false;
        saveConfig();
    }

    function moveRule(fromIndex, toIndex) {
        if (fromIndex < 0 || fromIndex >= rulesModel.count || toIndex < 0 || toIndex >= rulesModel.count) return;
        rulesModel.move(fromIndex, toIndex, 1);
        saveConfig();
    }

    function deleteRule(index) {
        if (index >= 0 && index < rulesModel.count) {
            rulesModel.remove(index);
            saveConfig();
        }
    }

    // --- Input Methods Dialog ---
    function openImDialog(index) {
        root.editingImIndex = index;
        if (index >= 0 && index < imModel.count) {
            var item = imModel.get(index);
            dialogImKeyInput.text = item.imKey;
            dialogImEngineInput.text = item.imEngine;
            dialogImNameInput.text = item.imDisplayName;
            dialogImRimeSchemaInput.text = item.imRimeSchema || "";
            imDialogTitle.text = root.tr("im_dialog_edit");
        } else {
            dialogImKeyInput.text = "";
            dialogImEngineInput.text = "rime";
            dialogImNameInput.text = "";
            dialogImRimeSchemaInput.text = "";
            imDialogTitle.text = root.tr("im_dialog_add");
        }
        imDialog.visible = true;
        Qt.callLater(function() { dialogImKeyInput.forceActiveFocus() });
    }

    function applyImDialog() {
        var key = dialogImKeyInput.text.trim().toLowerCase();
        var engine = dialogImEngineInput.text.trim();
        var name = dialogImNameInput.text.trim() || key;
        var rimeSchema = dialogImRimeSchemaInput.text.trim();

        if (!key || !engine) {
            root.statusMessage = root.tr("im_key_engine_required");
            return;
        }

        if (root.editingImIndex >= 0 && root.editingImIndex < imModel.count) {
            var oldKey = imModel.get(root.editingImIndex).imKey;
            imModel.set(root.editingImIndex, {
                imKey: key,
                imEngine: engine,
                imDisplayName: name,
                imRimeSchema: rimeSchema
            });
            if (oldKey !== key) {
                for (var i = 0; i < rulesModel.count; i++) {
                    if (rulesModel.get(i).ruleInputMethod === oldKey) {
                        rulesModel.setProperty(i, "ruleInputMethod", key);
                    }
                }
                if (root.defaultInputMethod === oldKey) {
                    root.defaultInputMethod = key;
                }
            }
        } else {
            imModel.append({
                imKey: key,
                imEngine: engine,
                imDisplayName: name,
                imRimeSchema: rimeSchema
            });
        }
        imDialog.visible = false;
        saveConfig();
    }

    function deleteIm(index) {
        if (index >= 0 && index < imModel.count) {
            imModel.remove(index);
            saveConfig();
        }
    }

    PanelWindow {
        id: panel
        visible: root.opened
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        WlrLayershell.namespace: "omarchy-hypr-input-switcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        // 1. Backdrop Scrim
        Rectangle {
            anchors.fill: parent
            color: root.scrim
        }

        // 2. Click outside card to dismiss
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (ruleDialog.visible) {
                    ruleDialog.visible = false;
                } else if (imDialog.visible) {
                    imDialog.visible = false;
                } else {
                    root.dismiss();
                }
            }
        }

        // 3. Center Main Card with Generous Padding
        BorderSurface {
            id: card
            width: Math.min(880, panel.width - 60)
            height: Math.min(700, panel.height - 60)
            radius: root.cornerRadius || 16
            anchors.centerIn: parent
            color: root.background
            borderSpec: Border.surfaceSpec("menu", "border", root.border, Math.max(1, Style.space(2)))

            // Prevent clicks inside card from bubbling to scrim
            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            // Keyboard Focus Scope
            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: true

                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                        if (ruleDialog.visible) {
                            ruleDialog.visible = false;
                        } else if (imDialog.visible) {
                            imDialog.visible = false;
                        } else {
                            root.dismiss();
                        }
                        event.accepted = true;
                    }
                }

                // Generous Inner Layout with 24px Padding
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 14

                    // Header Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        Image {
                            width: 38
                            height: 38
                            source: Qt.resolvedUrl("assets/logo.svg")
                            sourceSize.width: 38
                            sourceSize.height: 38
                            fillMode: Image.PreserveAspectFit
                        }

                        ColumnLayout {
                            spacing: 3

                            Text {
                                text: root.tr("title")
                                font.family: root.fontFamily
                                font.pixelSize: 18
                                font.bold: true
                                color: root.foreground
                            }
                            Text {
                                text: root.tr("subtitle")
                                font.family: root.fontFamily
                                font.pixelSize: 12
                                color: Qt.darker(root.foreground, 1.4)
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Tabs Switcher
                        RowLayout {
                            spacing: 8

                            Button {
                                text: root.tr("tab_rules")
                                selected: root.currentTab === 0
                                onClicked: root.currentTab = 0
                            }

                            Button {
                                text: root.tr("tab_input_methods")
                                selected: root.currentTab === 1
                                onClicked: root.currentTab = 1
                            }
                        }

                        // Language Switcher Toggle
                        Button {
                            text: root.lang === "zh" ? "🇨🇳 中文" : "🇺🇸 EN"
                            bordered: true
                            onClicked: {
                                root.lang = (root.lang === "zh" ? "en" : "zh");
                            }
                        }

                        // Close Button
                        Button {
                            text: "✕"
                            onClicked: root.dismiss()
                        }
                    }

                    // System Diagnostics / Status Strip
                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        radius: 8
                        color: root.selectedBackground
                        border.color: root.border
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 12

                            // Binary Installed Status
                            RowLayout {
                                spacing: 5
                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: root.isInstalled ? "#a6e3a1" : "#f38ba8"
                                }
                                Text {
                                    text: root.isInstalled ? root.tr("installed") : root.tr("not_installed")
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: root.isInstalled ? root.foreground : "#f38ba8"
                                }
                            }

                            // Version Badge
                            Rectangle {
                                visible: root.binaryVersion !== ""
                                height: 20
                                radius: 4
                                color: root.background
                                border.color: root.border
                                border.width: 1
                                Layout.preferredWidth: versionText.implicitWidth + 12

                                Text {
                                    id: versionText
                                    anchors.centerIn: parent
                                    text: "v" + root.binaryVersion
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: root.accent
                                }
                            }

                            // Running / Daemon Status
                            RowLayout {
                                spacing: 5
                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: root.isRunning ? "#a6e3a1" : "#fab387"
                                }
                                Text {
                                    text: root.isRunning ? (root.tr("running") + " (PID " + root.runningPid + ")") : root.tr("not_running")
                                    font.pixelSize: 11
                                    color: root.isRunning ? root.foreground : "#fab387"
                                }
                            }

                            // Quick Launch Daemon Button if not running
                            Button {
                                visible: !root.isRunning && root.isInstalled
                                text: root.tr("start_service")
                                bordered: true
                                onClicked: launchDaemon()
                            }

                            Item { Layout.fillWidth: true }

                            // Config Status
                            RowLayout {
                                spacing: 5
                                Text {
                                    text: root.configExists ? root.tr("config_ready", rulesModel.count) : root.tr("config_missing")
                                    font.pixelSize: 11
                                    color: root.configExists ? Qt.darker(root.foreground, 1.3) : "#f9e2af"
                                }
                            }
                        }
                    }

                    // TAB 0: RULES MANAGEMENT
                    ColumnLayout {
                        visible: root.currentTab === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 12

                        // Global Default Setting & Action Bar
                        Rectangle {
                            Layout.fillWidth: true
                            height: 50
                            radius: 8
                            color: root.selectedBackground
                            border.color: root.border
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 12

                                Text {
                                    text: root.tr("default_im")
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                }

                                RowLayout {
                                    spacing: 6

                                    Repeater {
                                        model: imModel
                                        delegate: Button {
                                            text: model.imDisplayName
                                            selected: root.defaultInputMethod === model.imKey
                                            onClicked: {
                                                root.defaultInputMethod = model.imKey;
                                                saveConfig();
                                            }
                                        }
                                    }

                                    Button {
                                        text: root.tr("keep_current")
                                        enabled: root.supportsKeep
                                        selected: root.defaultInputMethod === "keep"
                                        onClicked: {
                                            if (root.supportsKeep) {
                                                root.defaultInputMethod = "keep";
                                                saveConfig();
                                            }
                                        }
                                    }

                                    Text {
                                        visible: !root.supportsKeep
                                        text: root.tr("keep_version_hint")
                                        font.pixelSize: 10
                                        color: "#fab387"
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Button {
                                    text: root.tr("add_rule")
                                    bordered: true
                                    accent: root.accent
                                    onClicked: openRuleDialog(-1)
                                }
                            }
                        }

                        // Table Header
                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: 6
                            color: root.selectedBackground
                            border.color: root.border
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 10

                                Text {
                                    text: root.tr("col_index")
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Qt.darker(root.foreground, 1.4)
                                    Layout.preferredWidth: 32
                                }

                                Text {
                                    text: root.tr("col_class")
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Qt.darker(root.foreground, 1.4)
                                    Layout.preferredWidth: 220
                                }

                                Text {
                                    text: root.tr("col_title")
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Qt.darker(root.foreground, 1.4)
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: root.tr("col_target_im")
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Qt.darker(root.foreground, 1.4)
                                    Layout.preferredWidth: 140
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Text {
                                    text: root.tr("col_actions")
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Qt.darker(root.foreground, 1.4)
                                    Layout.preferredWidth: 130
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }

                        // Rules Table List
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 8
                            color: root.background
                            border.color: root.border
                            border.width: 1
                            clip: true

                            ListView {
                                id: rulesListView
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 6
                                model: rulesModel

                                delegate: Rectangle {
                                    width: rulesListView.width
                                    height: 46
                                    radius: 6
                                    color: mouseAreaRule.containsMouse ? root.selectedBackground : "transparent"
                                    border.color: root.border
                                    border.width: 1

                                    MouseArea {
                                        id: mouseAreaRule
                                        anchors.fill: parent
                                        hoverEnabled: true
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 16
                                        anchors.rightMargin: 16
                                        spacing: 10

                                        // Col 1: Index
                                        Text {
                                            text: (index + 1).toString()
                                            font.pixelSize: 11
                                            color: Qt.darker(root.foreground, 1.4)
                                            Layout.preferredWidth: 32
                                        }

                                        // Col 2: Class
                                        RowLayout {
                                            Layout.preferredWidth: 220
                                            spacing: 6

                                            Text {
                                                text: model.ruleClass
                                                font.family: root.fontFamily
                                                font.pixelSize: 13
                                                font.bold: true
                                                color: root.foreground
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Rectangle {
                                                visible: model.ruleClass.indexOf("^") !== -1 || model.ruleClass.indexOf("?") !== -1 || model.ruleClass.indexOf("$") !== -1
                                                width: 38
                                                height: 16
                                                radius: 4
                                                color: root.selectedBackground
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: root.tr("regex_badge")
                                                    font.pixelSize: 8
                                                    font.bold: true
                                                    color: root.accent
                                                }
                                            }
                                        }

                                        // Col 3: Title
                                        Text {
                                            text: model.ruleTitle && model.ruleTitle.trim() !== "" ? model.ruleTitle : root.tr("all_windows")
                                            font.pixelSize: 12
                                            color: model.ruleTitle && model.ruleTitle.trim() !== "" ? root.foreground : Qt.darker(root.foreground, 2.0)
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        // Col 4: Target IM Badge
                                        Rectangle {
                                            Layout.preferredWidth: 140
                                            height: 28
                                            radius: 6
                                            color: model.ruleInputMethod === "keep" ? "#313244" : root.selectedBackground
                                            border.color: model.ruleInputMethod === "keep" ? "#fab387" : root.border
                                            border.width: 1

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.getImDisplayName(model.ruleInputMethod)
                                                font.pixelSize: 11
                                                font.bold: true
                                                color: model.ruleInputMethod === "keep" ? "#fab387" : root.accent
                                            }
                                        }

                                        // Col 5: Actions
                                        RowLayout {
                                            Layout.preferredWidth: 130
                                            spacing: 4

                                            Button {
                                                text: "▲"
                                                enabled: index > 0
                                                bordered: true
                                                onClicked: moveRule(index, index - 1)
                                            }

                                            Button {
                                                text: "▼"
                                                enabled: index < rulesModel.count - 1
                                                bordered: true
                                                onClicked: moveRule(index, index + 1)
                                            }

                                            Button {
                                                text: "✎"
                                                bordered: true
                                                onClicked: openRuleDialog(index)
                                            }

                                            Button {
                                                text: "🗑"
                                                bordered: true
                                                foreground: "#f38ba8"
                                                onClicked: deleteRule(index)
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: rulesModel.count === 0
                                text: root.tr("no_rules_hint")
                                color: Qt.darker(root.foreground, 1.6)
                                font.pixelSize: 13
                            }
                        }
                    }

                    // TAB 1: INPUT METHODS CONFIGURATION
                    ColumnLayout {
                        visible: root.currentTab === 1
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 12

                        // Action Bar
                        Rectangle {
                            Layout.fillWidth: true
                            height: 50
                            radius: 8
                            color: root.selectedBackground
                            border.color: root.border
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 12

                                Text {
                                    text: root.tr("im_table_title")
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                }

                                Item { Layout.fillWidth: true }

                                Button {
                                    text: root.tr("add_im")
                                    bordered: true
                                    accent: root.accent
                                    onClicked: openImDialog(-1)
                                }
                            }
                        }

                        // Input Methods Table Header
                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: 6
                            color: root.selectedBackground
                            border.color: root.border
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 10

                                Text {
                                    text: root.tr("col_im_key")
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Qt.darker(root.foreground, 1.4)
                                    Layout.preferredWidth: 150
                                }

                                Text {
                                    text: root.tr("col_im_name")
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Qt.darker(root.foreground, 1.4)
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: root.tr("col_im_engine")
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Qt.darker(root.foreground, 1.4)
                                    Layout.preferredWidth: 190
                                }

                                Text {
                                    text: root.tr("col_actions")
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Qt.darker(root.foreground, 1.4)
                                    Layout.preferredWidth: 100
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }

                        // Input Methods List
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 8
                            color: root.background
                            border.color: root.border
                            border.width: 1
                            clip: true

                            ListView {
                                id: imListView
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 6
                                model: imModel

                                delegate: Rectangle {
                                    width: imListView.width
                                    height: 46
                                    radius: 6
                                    color: mouseAreaIm.containsMouse ? root.selectedBackground : "transparent"
                                    border.color: root.border
                                    border.width: 1

                                    MouseArea {
                                        id: mouseAreaIm
                                        anchors.fill: parent
                                        hoverEnabled: true
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 16
                                        anchors.rightMargin: 16
                                        spacing: 10

                                        Text {
                                            text: model.imKey
                                            font.pixelSize: 13
                                            font.bold: true
                                            color: root.accent
                                            Layout.preferredWidth: 150
                                        }

                                        Text {
                                            text: model.imDisplayName
                                            font.pixelSize: 13
                                            color: root.foreground
                                            Layout.fillWidth: true
                                        }

                                        // Natural inline text for engine + (schema)
                                        Text {
                                            text: model.imRimeSchema && model.imRimeSchema.trim() !== "" ? (model.imEngine + " (" + model.imRimeSchema + ")") : model.imEngine
                                            font.pixelSize: 12
                                            color: model.imRimeSchema && model.imRimeSchema.trim() !== "" ? "#89dceb" : Qt.darker(root.foreground, 1.3)
                                            Layout.preferredWidth: 190
                                        }

                                        RowLayout {
                                            Layout.preferredWidth: 100
                                            spacing: 4

                                            Button {
                                                text: "✎"
                                                bordered: true
                                                onClicked: openImDialog(index)
                                            }

                                            Button {
                                                text: "🗑"
                                                bordered: true
                                                foreground: "#f38ba8"
                                                onClicked: deleteIm(index)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Footer Status & Controls
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        Text {
                            Layout.fillWidth: true
                            text: root.statusMessage
                            color: Qt.darker(root.foreground, 1.3)
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Button {
                            text: root.tr("reload")
                            bordered: true
                            onClicked: {
                                configFileView.reload();
                                loadStatus();
                            }
                        }

                        Button {
                            text: root.tr("save_config")
                            bordered: true
                            selected: true
                            accent: root.accent
                            onClicked: saveConfig()
                        }
                    }
                }
            }

            // Edit / Add Rule Modal Popover
            Rectangle {
                id: ruleDialog
                visible: false
                anchors.fill: parent
                radius: root.cornerRadius || 16
                color: root.scrim

                Rectangle {
                    width: 560
                    height: 420
                    anchors.centerIn: parent
                    radius: 12
                    color: root.background
                    border.color: root.border
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 14

                        Text {
                            id: ruleDialogTitle
                            text: root.tr("rule_dialog_add")
                            font.pixelSize: 15
                            font.bold: true
                            color: root.foreground
                        }

                        // Window Class input
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: root.tr("rule_class_label")
                                font.pixelSize: 12
                                color: Qt.darker(root.foreground, 1.4)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                TextField {
                                    id: dialogClassInput
                                    Layout.fillWidth: true
                                    placeholderText: root.tr("rule_class_placeholder")
                                }

                                Button {
                                    visible: root.hasSlurp
                                    text: root.tr("screen_pick")
                                    bordered: true
                                    accent: root.accent
                                    onClicked: startPickWindow()
                                }
                            }
                        }

                        // Window Title input (Optional)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: root.tr("rule_title_label")
                                font.pixelSize: 12
                                color: Qt.darker(root.foreground, 1.4)
                            }

                            TextField {
                                id: dialogTitleInput
                                Layout.fillWidth: true
                                placeholderText: root.tr("rule_title_placeholder")
                            }
                        }

                        // Target Input Method (Dynamic list + keep support)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: root.tr("rule_target_im_label")
                                    font.pixelSize: 12
                                    color: Qt.darker(root.foreground, 1.4)
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    visible: !root.supportsKeep
                                    text: root.tr("rule_keep_version_hint", (root.binaryVersion || "0.0.0"))
                                    font.pixelSize: 11
                                    color: "#fab387"
                                }
                            }

                            RowLayout {
                                spacing: 6

                                Repeater {
                                    model: imModel
                                    delegate: Button {
                                        text: model.imDisplayName
                                        selected: root.selectedRuleIm === model.imKey
                                        onClicked: root.selectedRuleIm = model.imKey
                                    }
                                }

                                Button {
                                    text: root.tr("keep_current")
                                    enabled: root.supportsKeep
                                    selected: root.selectedRuleIm === "keep"
                                    onClicked: {
                                        if (root.supportsKeep) {
                                            root.selectedRuleIm = "keep";
                                        }
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        // Dialog Buttons
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Item { Layout.fillWidth: true }

                            Button {
                                text: root.tr("cancel")
                                bordered: true
                                onClicked: ruleDialog.visible = false
                            }

                            Button {
                                text: root.tr("confirm_save")
                                bordered: true
                                selected: true
                                onClicked: applyRuleDialog()
                            }
                        }
                    }
                }
            }

            // Edit / Add Input Method Modal Popover
            Rectangle {
                id: imDialog
                visible: false
                anchors.fill: parent
                radius: root.cornerRadius || 16
                color: root.scrim

                Rectangle {
                    width: 500
                    height: dialogImEngineInput.text.toLowerCase().indexOf("rime") !== -1 ? 430 : 360
                    anchors.centerIn: parent
                    radius: 12
                    color: root.background
                    border.color: root.border
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 14

                        Text {
                            id: imDialogTitle
                            text: root.tr("im_dialog_add")
                            font.pixelSize: 15
                            font.bold: true
                            color: root.foreground
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: root.tr("im_key_label")
                                font.pixelSize: 12
                                color: Qt.darker(root.foreground, 1.4)
                            }

                            TextField {
                                id: dialogImKeyInput
                                Layout.fillWidth: true
                                placeholderText: root.tr("im_key_placeholder")
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: root.tr("im_name_label")
                                font.pixelSize: 12
                                color: Qt.darker(root.foreground, 1.4)
                            }

                            TextField {
                                id: dialogImNameInput
                                Layout.fillWidth: true
                                placeholderText: root.tr("im_name_placeholder")
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: root.tr("im_engine_label")
                                font.pixelSize: 12
                                color: Qt.darker(root.foreground, 1.4)
                            }

                            TextField {
                                id: dialogImEngineInput
                                Layout.fillWidth: true
                                placeholderText: root.tr("im_engine_placeholder")
                            }
                        }

                        // Rime Schema Field (only if engine is rime)
                        ColumnLayout {
                            visible: dialogImEngineInput.text.toLowerCase().indexOf("rime") !== -1
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: root.tr("im_rime_schema_label")
                                font.pixelSize: 12
                                color: "#89dceb"
                            }

                            TextField {
                                id: dialogImRimeSchemaInput
                                Layout.fillWidth: true
                                placeholderText: root.tr("im_rime_schema_placeholder")
                            }
                        }

                        Item { Layout.fillHeight: true }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Item { Layout.fillWidth: true }

                            Button {
                                text: root.tr("cancel")
                                bordered: true
                                onClicked: imDialog.visible = false
                            }

                            Button {
                                text: root.tr("confirm_save")
                                bordered: true
                                selected: true
                                onClicked: applyImDialog()
                            }
                        }
                    }
                }
            }
        }
    }
}
