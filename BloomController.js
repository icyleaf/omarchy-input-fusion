.pragma library

// Pure argv builders and parsers for the `bloom` CLI's `--json` contract.
//
// Like FcitxController.js this file is stateless: it either builds an argv for
// Quickshell's Process or parses one of bloom's JSON objects. Keeping the shape
// here lets Backend.qml own the processes and call sites deal only in typed
// values. See ADR 0004 and ADR 0005.

// `bloom` is not bundled; the plugin detects it on PATH and hides the Bloom
// section when absent.
function whichCommand() {
    return ["sh", "-c", "command -v bloom"];
}

function listCommand() {
    return ["bloom", "--json", "list"];
}

function updateCommand() {
    return ["bloom", "--json", "update"];
}

// parse returns the decoded JSON object, or null when the output is not JSON.
function parse(raw) {
    if (!raw) return null;
    try {
        var obj = JSON.parse(raw);
        if (!obj || typeof obj !== "object" || Array.isArray(obj)) return null;
        return obj;
    } catch (e) {
        return null;
    }
}

// errorMessage extracts the `error` field from a failed envelope, or "".
function errorMessage(raw) {
    var obj = parse(raw);
    if (!obj || obj.ok === true) return "";
    return String(obj.error || "");
}

// list shapes `bloom --json list`. Returns null on a failed or malformed reply.
function list(raw) {
    var obj = parse(raw);
    if (!obj || obj.ok !== true) return null;
    return {
        rimeDir: String(obj.rime_dir || ""),
        enabledSchemas: stringArray(obj.enabled_schemas),
        packages: packageArray(obj.installed_packages),
        updatesAvailable: numberOr(obj.updates_available, -1)
    };
}

// updates shapes `bloom --json update`. Returns null on a failed reply.
function updates(raw) {
    var obj = parse(raw);
    if (!obj || obj.ok !== true) return null;
    return {
        updates: updateArray(obj.updates),
        updatesAvailable: numberOr(obj.updates_available, 0)
    };
}

function stringArray(value) {
    var out = [];
    if (!Array.isArray(value)) return out;
    for (var i = 0; i < value.length; i++) {
        var text = String(value[i] === undefined || value[i] === null ? "" : value[i]);
        if (text !== "") out.push(text);
    }
    return out;
}

function packageArray(value) {
    var out = [];
    if (!Array.isArray(value)) return out;
    for (var i = 0; i < value.length; i++) {
        var item = value[i] || {};
        out.push({
            repo: String(item.repo || ""),
            version: String(item.version || ""),
            installedAt: String(item.installed_at || ""),
            schemas: stringArray(item.schemas)
        });
    }
    return out;
}

function updateArray(value) {
    var out = [];
    if (!Array.isArray(value)) return out;
    for (var i = 0; i < value.length; i++) {
        var item = value[i] || {};
        out.push({
            repo: String(item.repo || ""),
            local: String(item.local || ""),
            remote: String(item.remote || ""),
            updateAvailable: item.update_available === true,
            error: String(item.error || "")
        });
    }
    return out;
}

// packageLabel mirrors bloom's own text output: a locally scanned package's
// tracking key is "local/<schema>" but only "<schema>" is worth showing.
function packageLabel(repo) {
    var text = String(repo || "");
    if (text.indexOf("local/") === 0) return text.slice("local/".length);
    return text;
}

function numberOr(value, fallback) {
    var n = Number(value);
    if (value === null || value === undefined || isNaN(n)) return fallback;
    return n;
}
