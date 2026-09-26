import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "i18n.js" as I18n

// Omarchy bar widget for Input Fusion: the live fcitx5 Input Method / Rime
// Schema indicator. Left click opens the control panel; middle click opens the
// Overlay.
//
// All fcitx5 access lives in Backend, which this widget owns. The widget never
// holds keyboard focus, which matters: a focused layer-shell surface (the
// panel) makes fcitx5 report and switch its own transient input context instead
// of the focused application's. The panel therefore only renders a snapshot
// taken here and hands selections back after it closes.
BarWidget {
    id: root

    moduleName: "icyleaf.input-fusion"

    Backend {
        id: backend
        autoSwitchToRime: root.autoSwitchToRime
        // Freeze reads while the panel holds focus, so its shadowed fcitx5
        // context cannot overwrite the real state; and while a switch plan runs.
        suspendReads: root.panelOpen
    }

    readonly property string lang: {
        var envLang = Quickshell.env("LANG") || "";
        return envLang.toLowerCase().indexOf("zh") !== -1 ? "zh" : "en";
    }

    readonly property bool autoSwitchToRime: {
        var value = root.setting("autoSwitchToRime", true);
        return value === true || String(value).toLowerCase() === "true";
    }

    readonly property bool showSchema: {
        var value = root.setting("showSchemaOnBar", true);
        return value === true || String(value).toLowerCase() === "true";
    }

    // Set by the panel while it is open.
    readonly property bool panelOpen: panelLoader.item ? panelLoader.item.opened === true : false

    // Bloom is read-only here; the panel binds to these and never writes.
    readonly property bool bloomAvailable: backend.bloomAvailable
    readonly property bool bloomChecking: backend.bloomChecking
    readonly property var bloomEnabledSchemas: backend.bloomEnabledSchemas
    readonly property var bloomPackages: backend.bloomPackages
    readonly property var bloomUpdates: backend.bloomUpdates
    readonly property int bloomUpdatesAvailable: backend.bloomUpdatesAvailable
    readonly property double bloomUpdatesAt: backend.bloomUpdatesAt
    readonly property string bloomError: backend.bloomError

    readonly property string label: {
        if (backend.active) {
            var base = backend.imSymbol || (backend.imDisplay ? backend.imDisplay.charAt(0) : "󰌌");
            if (backend.imName === "rime" && root.showSchema && backend.schema !== "")
                return base + " " + backend.schema;
            return base;
        }
        if (backend.direct) return "A";
        return "󰌌";
    }

    readonly property string tooltip: {
        var base;
        if (backend.unavailable) base = I18n.t("fcitx_unavailable");
        else if (backend.direct) base = I18n.t("direct_label");
        else {
            base = backend.isRime ? backend.imDisplay + " · " + backend.schema : backend.imDisplay;
            if (backend.lastError !== "") base += " — " + backend.lastError;
        }
        // Bloom only touches the tooltip: a pending update is worth a glance
        // without spending bar space on it.
        if (backend.bloomAvailable && backend.bloomUpdatesAvailable > 0)
            base += " · " + I18n.t("bloom_updates_available", backend.bloomUpdatesAvailable);
        return base;
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

    function injectPanel() {
        if (!panelLoader.item) return;
        panelLoader.item.bar = root.bar;
        panelLoader.item.anchorItem = button;
        panelLoader.item.hostWidget = root;
    }

    function open() {
        if (panelLoader.item) { panelLoader.item.open(); refreshBloomIfStale(); return; }
        panelLoader.active = true;
        Qt.callLater(function() {
            if (panelLoader.item) panelLoader.item.open();
            refreshBloomIfStale();
        });
    }

    // A cached update check is reused until it is five minutes old, so opening
    // the panel does not hammer `git ls-remote`.
    readonly property double bloomStaleAfter: 5 * 60 * 1000

    function refreshBloomIfStale() {
        backend.refreshBloom();
        if (backend.bloomUpdatesAt === 0 || (Date.now() - backend.bloomUpdatesAt) > root.bloomStaleAfter)
            backend.refreshBloomUpdates();
    }

    function refreshBloom() { backend.refreshBloom(); }
    function refreshBloomUpdates() { backend.refreshBloomUpdates(); }

    function close() {
        if (panelLoader.item) panelLoader.item.close();
    }

    function toggle() {
        if (root.opened) root.close();
        else root.open();
    }

    // The panel's view of the backend. A snapshot taken before it takes focus.
    function snapshot() { return backend.snapshot(); }

    // Called by the panel after it closes, so writes are not deferred by the
    // panel's keyboard focus.
    function applySelection(value, isInputMethod) {
        if (value === "__direct__") backend.selectDirect();
        else if (isInputMethod) backend.selectInputMethod(value);
        else backend.selectSchema(value);
    }

    onBarChanged: injectPanel()

    Component.onCompleted: {
        // I18n is a shared-library singleton; seed the language once here.
        I18n.setLanguage(root.lang);
        backend.refresh();
        backend.detectBloom();
    }

    Timer {
        interval: 1000
        repeat: true
        running: !root.panelOpen && !backend.planActive
        onTriggered: backend.refresh()
    }

    // Bloom reads are deliberately off the one-second fcitx5 poll: the list is
    // a forked process and updates hit the network. This timer always runs so
    // a Bloom installed after startup is still picked up (refreshBloom
    // re-detects when it is unavailable).
    Timer {
        interval: root.bloomStaleAfter
        repeat: true
        running: true
        onTriggered: {
            backend.refreshBloom();
            backend.refreshBloomUpdates();
        }
    }

    Loader {
        id: panelLoader
        active: false
        source: Qt.resolvedUrl("ControlPanel.qml")
        visible: false
        onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel); }
    }

    WidgetButton {
        id: button
        bar: root.bar
        text: root.label
        dimmed: !backend.active
        tooltipText: root.tooltip
        onPressed: function(mouseButton) {
            if (mouseButton === Qt.LeftButton) root.toggle();
            else if (mouseButton === Qt.MiddleButton && root.bar)
                root.bar.run("omarchy-shell shell toggle icyleaf.input-fusion");
        }
    }
}
