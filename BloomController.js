.pragma library

// Pure argv builders and parsers for the `bloom` CLI's `--json` contract.
//
// Like FcitxController.js this file is stateless: it either builds an argv for
// Quickshell's Process or parses one of bloom's JSON objects. Keeping the shape
// here lets Backend.qml own the processes and call sites deal only in typed
// values. See ADR 0004 and ADR 0005.

// Remote update checks run `git ls-remote`; both surfaces reuse a cached
// result for this long before checking again.
var staleAfterMs = 5 * 60 * 1000;

// `bloom` is not bundled; the plugin detects it on PATH and hides the Bloom
// section when absent.
function whichCommand() {
    return ["sh", "-c", "command -v bloom"];
}

function listCommand() {
    return ["bloom", "--json", "list"];
}

function listRegistryCommand() {
    return ["bloom", "--json", "list", "-r"];
}

function updateCommand() {
    return ["bloom", "--json", "update"];
}

function deployCommand() {
    return ["bloom", "--json", "deploy"];
}

// Heavy writes are handed to Omarchy's floating-terminal launcher. The launcher
// joins its arguments and runs them under `bash -c`, so every argument is
// passed through untouched as a single argv element.
function launchCommand(args) {
    return ["omarchy-launch-floating-terminal-with-presentation"].concat(args);
}

// In-process writes: enable/disable are fast and safe to run inside the shell
// (they patch default.custom.yaml and redeploy). Heavy writes (install,
// upgrade, remove) build their argv here but are launched in a terminal.
function enableCommand(schema) {
    return ["bloom", "--json", "enable", String(schema)];
}

function disableCommand(schema) {
    return ["bloom", "--json", "disable", String(schema)];
}

function installArgs(repo) {
    return ["bloom", "install", String(repo)];
}

function removeArgs(repo) {
    return ["bloom", "remove", String(repo)];
}

function upgradeArgs(repo) {
    return ["bloom", "upgrade", String(repo)];
}

function upgradeAllArgs() {
    return ["bloom", "upgrade"];
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
        installedSchemas: stringArray(obj.installed_schemas),
        packages: packageArray(obj.installed_packages),
        updatesAvailable: numberOr(obj.updates_available, -1)
    };
}

// registry shapes `bloom --json list -r`. Returns null on a failed reply.
function registry(raw) {
    var obj = parse(raw);
    if (!obj || obj.ok !== true) return null;
    var out = [];
    if (Array.isArray(obj.registry)) {
        for (var i = 0; i < obj.registry.length; i++) {
            var item = obj.registry[i] || {};
            out.push({
                name: String(item.name || ""),
                repo: String(item.repo || ""),
                description: String(item.description || ""),
                installed: item.installed === true
            });
        }
    }
    return { registry: out };
}

// schemas builds the unified Schema List: every Installed Schema (present on
// disk), plus the Enabled Schemas, plus every Schema owned by an Installed
// Package, plus the Active Schema if it is none of those (Active can outlive
// Enabled until a redeploy). Each row carries its Enabled flag, its Owner
// Package (empty when ownerless), whether it is installed, and whether it is
// Active.
//
// The Installed set is what keeps a disabled Schema from vanishing: fcitx5
// exposes only the Enabled set, so without it an installed-but-disabled Schema
// would be unreachable.
//
// Sort: Active first, then the Enabled group, then the Installed-but-disabled
// group; within a group by display name (labelOf), then by id as a tiebreak.
function schemas(enabled, packages, installed, activeId, labelOf) {
    var enabledSet = {};
    var installedSet = {};
    var i, j;
    if (Array.isArray(enabled)) {
        for (i = 0; i < enabled.length; i++) {
            var id = idOf(enabled[i]);
            if (id !== "") enabledSet[id] = true;
        }
    }
    if (Array.isArray(installed)) {
        for (i = 0; i < installed.length; i++) {
            var onDisk = idOf(installed[i]);
            if (onDisk !== "") installedSet[onDisk] = true;
        }
    }

    var owners = {};
    if (Array.isArray(packages)) {
        for (i = 0; i < packages.length; i++) {
            var pkg = packages[i] || {};
            var repo = idOf(pkg.repo);
            var list = pkg.schemas;
            if (!Array.isArray(list)) continue;
            for (j = 0; j < list.length; j++) {
                var owned = idOf(list[j]);
                if (owned !== "" && owners[owned] === undefined) owners[owned] = repo;
            }
        }
    }

    var seen = {};
    var ids = [];
    function add(value) {
        if (value !== "" && seen[value] === undefined) {
            seen[value] = true;
            ids.push(value);
        }
    }
    for (var enabledId in enabledSet) add(enabledId);
    for (var installedId in installedSet) add(installedId);
    for (var ownerId in owners) add(ownerId);
    var active = idOf(activeId);
    add(active);

    var label = (typeof labelOf === "function") ? labelOf : function(value) { return String(value); };
    var rows = [];
    for (i = 0; i < ids.length; i++) {
        var rowId = ids[i];
        var hasOwner = owners[rowId] !== undefined;
        var text = String(label(rowId));
        rows.push({
            id: rowId,
            label: text !== "" ? text : rowId,
            owner: hasOwner ? owners[rowId] : "",
            installed: hasOwner || installedSet[rowId] === true,
            enabled: enabledSet[rowId] === true,
            active: rowId === active
        });
    }

    rows.sort(function(a, b) {
        var ra = schemaGroup(a);
        var rb = schemaGroup(b);
        if (ra !== rb) return ra - rb;
        if (a.label < b.label) return -1;
        if (a.label > b.label) return 1;
        if (a.id < b.id) return -1;
        if (a.id > b.id) return 1;
        return 0;
    });
    return rows;
}

// schemaGroup ranks a row: Active first, then Enabled, then Installed-disabled.
function schemaGroup(row) {
    if (row.active) return 0;
    if (row.enabled) return 1;
    return 2;
}

function idOf(value) {
    return String(value === undefined || value === null ? "" : value);
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
