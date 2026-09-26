import QtQuick
import Quickshell
import Quickshell.Io
import "FcitxController.js" as Fcitx
import "BloomController.js" as Bloom
import "i18n.js" as I18n

// The single owner of every backend process for Input Fusion. Callers read
// typed state properties and call the select* / refresh() verbs; they never
// touch a Process or parse raw output. See ADR 0004.
//
// Today the only engine is fcitx5 (over D-Bus via `busctl --json`), read and
// written through the pure helpers in FcitxController.js. Bloom joins later
// through the same seam.
Item {
    id: backend

    // A QtObject cannot host child objects (no default property), so this is a
    // zero-size invisible Item purely to own the backend processes.
    visible: false
    width: 0
    height: 0

    // --- inputs from the host widget ----------------------------------------
    // Whether picking a Schema should also move to the Rime Input Method.
    property bool autoSwitchToRime: true
    // Set while the control panel is open: its keyboard focus shadows the
    // application's fcitx5 input context, so reads taken then are wrong.
    property bool suspendReads: false

    // --- observable state ---------------------------------------------------
    property int state: -1          // 0 closed, 1 Direct Mode, 2 active
    property string imName: ""
    property string imDisplay: ""
    property string imSymbol: ""
    property string schema: ""
    property string groupName: ""
    property var groupMembers: []
    property var allSchemas: []
    property bool daemonRunning: false
    property string lastError: ""
    property var configData: ({})

    // --- Bloom bridge -------------------------------------------------------
    // Bloom is an optional external engine. Reads run on a slow cadence and on
    // demand, not on the fcitx5 poll, because `bloom list` may touch the
    // network. The only writes here are the fast, safe ones (enable, disable,
    // deploy); install/upgrade/remove are launched in a terminal by the UI.
    property bool bloomAvailable: false
    // True once `bloom --json list` has succeeded; drives bloom-preferred mode.
    property bool bloomListReady: false
    property bool bloomChecking: false
    // Set when a registry/update read is asked for before Bloom detection has
    // finished; replayed once the binary is confirmed present.
    property bool bloomRegistryPending: false
    property bool bloomUpdatesPending: false
    property var bloomEnabledSchemas: []
    // Every *.schema.yaml on disk, Enabled or not; keeps disabled schemas listed.
    property var bloomInstalledSchemas: []
    property var bloomPackages: []
    property var bloomUpdates: []
    property var bloomRegistry: []
    property int bloomUpdatesAvailable: -1  // -1 until a check has run
    property double bloomCheckedAt: 0
    property double bloomUpdatesAt: 0
    property string bloomError: ""
    property bool bloomWriteRunning: false
    property string bloomWriteError: ""

    readonly property bool unavailable: backend.state === 0
    readonly property bool direct: backend.state === 1
    readonly property bool active: backend.state === 2
    readonly property bool isRime: backend.active && backend.imName === "rime"

    function schemaDisplay(schema) {
        return Fcitx.schemaDisplay(backend.configData, schema);
    }

    // --- reads --------------------------------------------------------------
    function refresh() {
        if (!pState.running) pState.running = true;
        if (!pInfo.running) pInfo.running = true;
        if (!pGroup.running) pGroup.running = true;
        if (!pSchema.running) pSchema.running = true;
        if (!pSchemas.running) pSchemas.running = true;
        if (!pDaemon.running) pDaemon.running = true;
    }

    // --- Bloom reads --------------------------------------------------------
    // Detection is separate from reading so the section can appear only when
    // the binary exists; a missing `bloom` leaves the panel a two-section one.
    function detectBloom() {
        if (!pBloomWhich.running) pBloomWhich.running = true;
    }

    function refreshBloom() {
        if (!backend.bloomAvailable) { backend.detectBloom(); return; }
        if (!pBloomList.running) {
            backend.bloomChecking = true;
            pBloomList.running = true;
        }
    }

    // Remote update checks hit `git ls-remote`, so they run strictly on demand
    // or on a long timer, never on every panel open.
    function refreshBloomUpdates() {
        if (!backend.bloomAvailable) {
            backend.bloomUpdatesPending = true;
            backend.detectBloom();
            return;
        }
        backend.bloomUpdatesPending = false;
        if (!pBloomUpdate.running) pBloomUpdate.running = true;
    }

    function refreshBloomRegistry() {
        if (!backend.bloomAvailable) {
            backend.bloomRegistryPending = true;
            backend.detectBloom();
            return;
        }
        backend.bloomRegistryPending = false;
        if (!pBloomRegistry.running) pBloomRegistry.running = true;
    }

    // The unified Schema List: every Installed Schema (on disk), plus the
    // Enabled Schemas, plus the Active Schema, plus Owner Packages when Bloom
    // is available. See ADR 0006.
    readonly property var schemaRows: backend.buildSchemaRows()

    function buildSchemaRows() {
        var withBloom = backend.bloomAvailable && backend.bloomListReady;
        var enabled = withBloom ? backend.bloomEnabledSchemas : backend.allSchemas;
        // Active only exists while Rime is the current Input Method; otherwise
        // the last schema would linger as Active.
        var activeId = backend.isRime ? backend.schema : "";
        var packages = withBloom ? backend.bloomPackages : [];
        var installed = withBloom ? backend.bloomInstalledSchemas : [];
        return Bloom.schemas(enabled, packages, installed, activeId, backend.schemaDisplay);
    }

    // Enable/disable patch default.custom.yaml and redeploy: fast and safe
    // enough to run in the shell process.
    function setSchemaEnabled(schema, enabled) {
        backend.runBloomWrite(enabled ? Bloom.enableCommand(schema) : Bloom.disableCommand(schema));
    }

    // A plain redeploy, for applying changes made outside the plugin.
    function redeployBloom() {
        backend.runBloomWrite(Bloom.deployCommand());
    }

    // install/upgrade/remove never reach here; the UI launches them in a
    // terminal. This is the shared path for the fast in-process writes.
    function runBloomWrite(command) {
        if (!backend.bloomAvailable || !command || command.length === 0) return;
        backend.bloomWriteRunning = true;
        backend.bloomWriteError = "";
        pBloomWrite.command = command;
        pBloomWrite.running = true;
    }

    readonly property bool planActive: backend.opPlan !== null

    // Reads are dropped while the panel is open (SHADOWED context) and while a
    // switch plan runs (a poll issued before the plan can land during it and
    // overwrite the value the plan's verify step is about to read).
    readonly property bool readAllowed: !backend.suspendReads && !backend.planActive

    Process {
        id: pState
        command: Fcitx.controller("State")
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (backend.readAllowed) backend.state = Fcitx.integer(text)
        }
    }

    Process {
        id: pInfo
        command: Fcitx.controller("CurrentInputMethodInfo")
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (!backend.readAllowed) return;
                var info = Fcitx.inputMethodInfo(text);
                if (info) {
                    backend.imName = info.name;
                    backend.imDisplay = info.display;
                    backend.imSymbol = info.symbol;
                }
            }
        }
    }

    Process {
        id: pGroup
        command: Fcitx.controller("CurrentInputMethodGroup")
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (!backend.readAllowed) return;
                var group = Fcitx.firstString(text);
                backend.groupName = group;
                if (group !== "") {
                    pGroupInfo.command = Fcitx.controller("FullInputMethodGroupInfo", ["s", group]);
                    pGroupInfo.running = true;
                }
            }
        }
    }

    Process {
        id: pGroupInfo
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (backend.readAllowed) backend.groupMembers = Fcitx.fullGroup(text).members
        }
    }

    Process {
        id: pSchema
        command: Fcitx.rime("GetCurrentSchema")
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (backend.readAllowed) backend.schema = Fcitx.firstString(text)
        }
    }

    Process {
        id: pSchemas
        command: Fcitx.rime("ListAllSchemas")
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: backend.allSchemas = Fcitx.stringArray(text)
        }
    }

    Process {
        id: pDaemon
        command: ["pgrep", "-f", "hypr-input-switcher"]
        onExited: (code, status) => { backend.daemonRunning = (code === 0); }
    }

    Process {
        id: pBloomWhich
        command: Bloom.whichCommand()
        onExited: (code, status) => {
            backend.bloomAvailable = (code === 0);
            if (!backend.bloomAvailable) return;
            // Replay any read that was asked for before detection finished.
            backend.refreshBloom();
            if (backend.bloomRegistryPending) backend.refreshBloomRegistry();
            if (backend.bloomUpdatesPending) backend.refreshBloomUpdates();
        }
    }

    Process {
        id: pBloomList
        command: Bloom.listCommand()
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var data = Bloom.list(text);
                if (data) {
                    backend.bloomEnabledSchemas = data.enabledSchemas;
                    backend.bloomInstalledSchemas = data.installedSchemas;
                    backend.bloomPackages = data.packages;
                    if (data.updatesAvailable >= 0) backend.bloomUpdatesAvailable = data.updatesAvailable;
                    backend.bloomError = "";
                    backend.bloomListReady = true;
                } else {
                    backend.bloomError = Bloom.errorMessage(text) || I18n.t("bloom_unreadable");
                    backend.bloomListReady = false;
                }
            }
        }
        onExited: (code, status) => {
            backend.bloomChecking = false;
            backend.bloomCheckedAt = Date.now();
        }
    }

    Process {
        id: pBloomRegistry
        command: Bloom.listRegistryCommand()
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var data = Bloom.registry(text);
                if (data) {
                    backend.bloomRegistry = data.registry;
                } else {
                    backend.bloomError = Bloom.errorMessage(text) || I18n.t("bloom_unreadable");
                }
            }
        }
    }

    Process {
        id: pBloomWrite
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var obj = Bloom.parse(text);
                if (!obj || obj.ok !== true)
                    backend.bloomWriteError = Bloom.errorMessage(text) || I18n.t("bloom_write_failed");
            }
        }
        onExited: (code, status) => {
            backend.bloomWriteRunning = false;
            if (code !== 0 && backend.bloomWriteError === "")
                backend.bloomWriteError = I18n.t("bloom_write_failed");
            backend.refreshBloom();
        }
    }

    Process {
        id: pBloomUpdate
        command: Bloom.updateCommand()
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var data = Bloom.updates(text);
                if (data) {
                    backend.bloomUpdates = data.updates;
                    backend.bloomUpdatesAvailable = data.updatesAvailable;
                    backend.bloomError = "";
                } else {
                    backend.bloomError = Bloom.errorMessage(text) || I18n.t("bloom_unreadable");
                }
            }
        }
        onExited: (code, status) => { backend.bloomUpdatesAt = Date.now(); }
    }

    // --- config labels ------------------------------------------------------
    // Only the two flat sections the panel needs to label schemas: the
    // Input Method / schema relationship and the human names. The Overlay
    // remains the editor; this reader is deliberately minimal.
    FileView {
        id: configFileView
        path: Quickshell.env("HOME") + "/.config/hypr-input-switcher/config.yaml"
        watchChanges: true
        printErrors: false
        onLoaded: backend.configData = backend.parseLabelConfig(text())
        onLoadFailed: backend.configData = ({})
    }

    function parseLabelConfig(rawText) {
        var data = { rime_schemas: {}, display_names: {} };
        if (!rawText) return data;
        var section = "";
        var lines = rawText.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            if (/^\S/.test(line)) {
                var header = line.replace(/:.*$/, "").trim();
                section = (header === "rime_schemas" || header === "display_names") ? header : "";
                continue;
            }
            if (section === "") continue;
            var match = line.match(/^\s+([^:#]+):\s*(.*)$/);
            if (!match) continue;
            var key = match[1].trim().replace(/^["']|["']$/g, "");
            var value = match[2].trim().replace(/\s+#.*$/, "").replace(/^["']|["']$/g, "");
            if (key !== "") data[section][key] = value;
        }
        return data;
    }

    // --- snapshot for the control panel -------------------------------------
    // An immutable view taken while the panel is still closed, so it reflects
    // the real application context rather than the panel's shadowed one.
    function snapshot() {
        var inputRows = [{ kind: "input", global: 0, value: "__direct__", label: I18n.t("direct_label"),
                           sub: I18n.t("direct_sub"), badge: "A",
                           selected: backend.state !== 2, enabled: true }];
        for (var i = 0; i < backend.groupMembers.length; i++) {
            var member = backend.groupMembers[i];
            // A plain keyboard layout is reported as State "inactive", the same
            // as Direct Mode; the Direct row already represents it.
            if (Fcitx.isKeyboardInputMethod(member)) continue;
            var name = member.display || member.name;
            inputRows.push({ kind: "input", global: inputRows.length, value: member.name, label: name, sub: member.name,
                             badge: member.symbol || name.charAt(0),
                             selected: backend.state === 2 && backend.imName === member.name,
                             enabled: true });
        }
        // The Schema list is not part of the snapshot: it is not shadowed by
        // the panel's focus and is exposed as `schemaRows` instead.
        return {
            state: backend.state,
            imName: backend.imName,
            imDisplay: backend.imDisplay,
            schema: backend.schema,
            isRime: backend.isRime,
            unavailable: backend.unavailable,
            inputRows: inputRows,
            daemonRunning: backend.daemonRunning,
            error: backend.lastError
        };
    }

    // --- switching ----------------------------------------------------------
    // A plan is a queue of steps run one at a time by `opProc`. A step either
    // writes (no verify) or reads and verifies. A failed verify replays the
    // whole plan, because fcitx5 accepts invalid names silently and a re-read
    // alone could never observe the change. Plans run only while the panel is
    // closed, when writes are not deferred by its keyboard focus.
    property var opPlan: null
    property int opIndex: 0
    property int opAttempts: 0

    Timer { id: opStart; interval: 160; repeat: false; onTriggered: backend.runStep() }
    Timer { id: opDelay; interval: 100; repeat: false; onTriggered: backend.runStep() }

    Process {
        id: opProc
        command: []
        property var step: null
        property string raw: ""
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: opProc.raw = text }
        onExited: function(code, status) { backend.finishStep(opProc.step, opProc.raw); }
    }

    function startPlan(steps) {
        backend.lastError = "";
        backend.opPlan = steps;
        backend.opIndex = 0;
        backend.opAttempts = 0;
        opStart.restart();
    }

    function runStep() {
        if (!backend.opPlan) return;
        if (backend.opIndex >= backend.opPlan.length) { backend.opPlan = null; backend.refresh(); return; }
        var step = backend.opPlan[backend.opIndex];
        if (step.kind === "check") { backend.finishStep(step, ""); return; }
        opProc.command = step.cmd;
        opProc.raw = "";
        opProc.step = step;
        opProc.running = true;
    }

    // fcitx5 acks a switch before its input context has committed the new
    // value, so a read issued in the same tick can still see the old one. Let
    // the bus settle between steps instead of running write and verify back to
    // back.
    function finishStep(step, raw) {
        if (step) {
            if (step.kind === "read" && step.apply) step.apply(raw);
            if (step.verify && !step.verify(raw)) { backend.retryPlan(); return; }
        }
        backend.opIndex += 1;
        opDelay.restart();
    }

    function retryPlan() {
        backend.opAttempts += 1;
        if (backend.opAttempts > 5) {
            backend.opPlan = null;
            backend.lastError = I18n.t("switch_failed");
            backend.refresh();
            return;
        }
        backend.opIndex = 0;
        opDelay.restart();
    }

    function readStateStep() {
        return { kind: "read", cmd: Fcitx.controller("State"),
                 apply: function(raw) { backend.state = Fcitx.integer(raw); } };
    }

    function readInfoStep() {
        return { kind: "read", cmd: Fcitx.controller("CurrentInputMethodInfo"),
                 apply: function(raw) {
                     var info = Fcitx.inputMethodInfo(raw);
                     if (info) { backend.imName = info.name; backend.imDisplay = info.display; backend.imSymbol = info.symbol; }
                 } };
    }

    function readSchemaStep() {
        return { kind: "read", cmd: Fcitx.rime("GetCurrentSchema"),
                 apply: function(raw) { backend.schema = Fcitx.firstString(raw); } };
    }

    function selectDirect() {
        if (backend.state === 1) return;
        backend.startPlan([
            { kind: "write", cmd: Fcitx.controller("Deactivate") },
            backend.readStateStep(),
            { kind: "check", verify: function() { return backend.state === 1; } }
        ]);
    }

    function selectInputMethod(name) {
        if (!name) return;
        if (backend.state === 2 && backend.imName === name) return;
        backend.startPlan([
            { kind: "write", cmd: Fcitx.controller("Activate") },
            { kind: "write", cmd: Fcitx.controller("SetCurrentIM", ["s", name]) },
            backend.readStateStep(),
            backend.readInfoStep(),
            { kind: "check", verify: function() { return backend.state === 2 && backend.imName === name; } }
        ]);
    }

    // A Schema applies immediately even while Rime is not the active Input
    // Method, so the schema goes first and the move to Rime follows.
    function selectSchema(name) {
        if (!name) return;
        if (backend.isRime && backend.schema === name) return;
        var steps = [
            { kind: "write", cmd: Fcitx.rime("SetSchema", ["s", name]) },
            backend.readSchemaStep(),
            { kind: "check", verify: function() { return backend.schema === name; } }
        ];
        if (backend.autoSwitchToRime && backend.imName !== "rime") {
            steps.push({ kind: "write", cmd: Fcitx.controller("Activate") });
            steps.push({ kind: "write", cmd: Fcitx.controller("SetCurrentIM", ["s", "rime"]) });
            steps.push(backend.readStateStep());
            steps.push(backend.readInfoStep());
            steps.push({ kind: "check", verify: function() { return backend.state === 2 && backend.imName === "rime"; } });
        }
        backend.startPlan(steps);
    }
}
