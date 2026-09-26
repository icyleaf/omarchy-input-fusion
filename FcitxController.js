.pragma library

// D-Bus bridge to fcitx5 and its Rime addon, via `busctl --json=short`.
//
// Every function here is pure: it either builds an argv for Quickshell's
// Process or parses one of busctl's JSON replies. No state, no shell.

var SERVICE = "org.fcitx.Fcitx5";
var CONTROLLER_PATH = "/controller";
var CONTROLLER_IFACE = "org.fcitx.Fcitx.Controller1";
var RIME_PATH = "/rime";
var RIME_IFACE = "org.fcitx.Fcitx.Rime1";

function call(path, iface, method, args) {
    var cmd = ["busctl", "--json=short", "--user", "call", SERVICE, path, iface, method];
    if (args) {
        for (var i = 0; i < args.length; i++) cmd.push(String(args[i]));
    }
    return cmd;
}

function stringArg(value) {
    return ["s", String(value)];
}

function controller(method, args) {
    return call(CONTROLLER_PATH, CONTROLLER_IFACE, method, args);
}

function rime(method, args) {
    return call(RIME_PATH, RIME_IFACE, method, args);
}

// busctl --json=short wraps the reply as { "type": "<signature>", "data": [..] }.
// Return only the data array, or null when the call failed / printed nothing.
function parse(raw) {
    if (!raw) return null;
    try {
        var reply = JSON.parse(raw);
        if (reply && reply.data !== undefined) return reply.data;
        return null;
    } catch (e) {
        return null;
    }
}

function firstString(raw) {
    var data = parse(raw);
    return (data && data.length > 0) ? String(data[0]) : "";
}

function integer(raw) {
    var data = parse(raw);
    return (data && data.length > 0) ? Number(data[0]) : 0;
}

function stringArray(raw) {
    var data = parse(raw);
    if (!data) return [];
    var list = Array.isArray(data[0]) ? data[0] : data;
    var out = [];
    for (var i = 0; i < list.length; i++) out.push(String(list[i]));
    return out;
}

// CurrentInputMethodInfo  ->  sssssssbsa{sv}
// [uniqueName, displayName, "", icon, symbol, language, addon, enabled, "", {}]
function inputMethodInfo(raw) {
    var data = parse(raw);
    if (!data || data.length < 1) return null;
    return {
        name: String(data[0] || ""),
        display: String(data[1] || ""),
        icon: String(data[3] || ""),
        symbol: String(data[4] || ""),
        language: String(data[5] || ""),
        addon: String(data[6] || "")
    };
}

// InputMethodGroupInfo  ->  sa(ss)
// ["us", [[uniqueName, layout], ...]]
function groupMembers(raw) {
    var data = parse(raw);
    if (!data || !Array.isArray(data[1])) return [];
    var out = [];
    for (var i = 0; i < data[1].length; i++) {
        var member = data[1][i];
        var name = String(member[0] || "");
        out.push({ name: name, display: name, symbol: "" });
    }
    return out;
}

// FullInputMethodGroupInfo  ->  sssa{sv}a(sssssssbsa{sv})
// [group, currentIM, layout, {}, [memberStruct, ...]]
function fullGroup(raw) {
    var data = parse(raw);
    if (!data) return { name: "", members: [] };
    var members = [];
    for (var i = 0; i < data.length; i++) {
        if (Array.isArray(data[i])) members = data[i];
    }
    var out = [];
    for (var j = 0; j < members.length; j++) {
        var member = members[j];
        out.push({
            name: String(member[0] || ""),
            display: String(member[1] || member[0] || ""),
            symbol: String(member[4] || ""),
            addon: String(member[6] || "")
        });
    }
    return { name: String(data[0] || ""), members: out };
}

// A plain keyboard layout. fcitx5 reports one as the current Input Method
// while State is "inactive", which is exactly the Direct Mode state, so the
// panel must not list it beside the Direct row as a second, identical target.
function isKeyboardInputMethod(member) {
    return member && member.addon === "keyboard";
}

// Config.yaml helpers: resolve a Schema id back to its label / display name.

function rimeSchemas(data) {
    return (data && data.rime_schemas) || {};
}

function displayNames(data) {
    return (data && data.display_names) || {};
}

function schemaLabel(data, schema) {
    var map = rimeSchemas(data);
    for (var label in map) {
        if (String(map[label]) === String(schema)) return String(label);
    }
    return "";
}

function schemaDisplay(data, schema) {
    var label = schemaLabel(data, schema);
    if (!label) return String(schema);
    return displayNames(data)[label] || label;
}
