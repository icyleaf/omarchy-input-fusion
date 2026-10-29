import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";
import assert from "node:assert/strict";

// FcitxController.js is a QML library (.pragma library); strip the pragma and
// evaluate it in a bare context so the pure functions can be tested in Node.
const here = dirname(fileURLToPath(import.meta.url));
let source = readFileSync(join(here, "..", "FcitxController.js"), "utf8");
source = source.replace(/^\.pragma library\s*/, "");

const context = { module: { exports: {} }, console, JSON, Array, Number, String, isNaN };
vm.createContext(context);
vm.runInContext(
    source +
        "\nmodule.exports = { controller, rime, parse, firstString, integer, stringArray, " +
        "inputMethodInfo, groupMembers, fullGroup, isKeyboardInputMethod, directRowSelected, " +
        "schemaLabel, schemaDisplay, panelNavigableRows, settingsTarget };\n",
    context,
);
const Fcitx = context.module.exports;

let passed = 0;
function test(name, fn) {
    try {
        fn();
        passed++;
    } catch (error) {
        console.error(`FAIL: ${name}\n  ${error.message}`);
        process.exitCode = 1;
    }
}

test("argv builders", () => {
    assert.deepEqual([...Fcitx.controller("State")], [
        "busctl", "--json=short", "--user", "call", "org.fcitx.Fcitx5", "/controller",
        "org.fcitx.Fcitx.Controller1", "State",
    ]);
    assert.deepEqual([...Fcitx.rime("SetSchema", ["s", "rime_frost"])], [
        "busctl", "--json=short", "--user", "call", "org.fcitx.Fcitx5", "/rime",
        "org.fcitx.Fcitx.Rime1", "SetSchema", "s", "rime_frost",
    ]);
});

// Captured from a live session: the Default group holds Rime plus the English
// (UK) layout, and fcitx5 reports the layout as the group's current member.
const FULL_GROUP_INFO =
    '{"type":"sssa{sv}a(sssssssbsa{sv})","data":["Default","keyboard-gb","us",{},' +
    '[["rime","Rime","","fcitx-rime","ㄓ","zh","rime",true,"",{}],' +
    '["keyboard-gb","Keyboard - English (UK)","","input-keyboard","en","en","keyboard",true,"",{}]]]}';

test("fullGroup reads the members out of a real reply", () => {
    const group = Fcitx.fullGroup(FULL_GROUP_INFO);
    assert.equal(group.name, "Default");
    assert.deepEqual(
        [...group.members.map((m) => [m.name, m.display, m.addon])],
        [
            ["rime", "Rime", "rime"],
            ["keyboard-gb", "Keyboard - English (UK)", "keyboard"],
        ],
    );
});

test("getters parse the single-value replies", () => {
    assert.deepEqual([...Fcitx.parse('{"type":"s","data":["rime_frost"]}')], ["rime_frost"]);
    assert.equal(Fcitx.firstString('{"type":"s","data":["rime_frost"]}'), "rime_frost");
    assert.equal(Fcitx.integer('{"type":"i","data":[2]}'), 2);
    assert.equal(Fcitx.integer("garbage"), 0);
    assert.deepEqual([...Fcitx.stringArray('{"type":"as","data":[["rime_frost","jaroomaji"]]}')], [
        "rime_frost",
        "jaroomaji",
    ]);
});

test("isKeyboardInputMethod only matches the keyboard addon", () => {
    const members = Fcitx.fullGroup(FULL_GROUP_INFO).members;
    assert.equal(Fcitx.isKeyboardInputMethod(members[1]), true);
    assert.equal(Fcitx.isKeyboardInputMethod(members[0]), false);
    assert.equal(Fcitx.isKeyboardInputMethod(null), false);
});

test("directRowSelected covers Direct Mode and every active case", () => {
    const members = Fcitx.fullGroup(FULL_GROUP_INFO).members;
    // State 0 (fcitx5 unavailable) and 1 (deactivated) are Direct Mode.
    assert.equal(Fcitx.directRowSelected(0, members, ""), true);
    assert.equal(Fcitx.directRowSelected(1, members, "rime"), true);
    // Active on Rime: its own row is the selected one.
    assert.equal(Fcitx.directRowSelected(2, members, "rime"), false);
    // Active on a keyboard layout: it is folded into the Direct row, so that
    // row is the selected one instead of the panel showing no selection.
    assert.equal(Fcitx.directRowSelected(2, members, "keyboard-gb"), true);
    // An Input Method the panel does not know about is not silently Direct.
    assert.equal(Fcitx.directRowSelected(2, members, "mozc"), false);
    assert.equal(Fcitx.directRowSelected(2, members, "msime"), false);
    assert.equal(Fcitx.directRowSelected(2, [], "rime"), false);
    assert.equal(Fcitx.directRowSelected(2, null, "rime"), false);
});

test("schemaDisplay resolves a schema id to its configured name", () => {
    const data = { rime_schemas: { chinese: "rime_frost" }, display_names: { chinese: "中文" } };
    assert.equal(Fcitx.schemaLabel(data, "rime_frost"), "chinese");
    assert.equal(Fcitx.schemaDisplay(data, "rime_frost"), "中文");
    assert.equal(Fcitx.schemaDisplay(data, "jaroomaji"), "jaroomaji");
});

test("panelNavigableRows hides schemas when Rime is not active", () => {
    const inputRows = [{ kind: "input", value: "msime" }, { kind: "input", value: "__direct__" }];
    const schemaRows = [{ kind: "schema", value: "luna_pinyin" }];

    // Non-Rime (e.g. msime, Direct Mode): schemas must not be navigable
    assert.deepEqual([...Fcitx.panelNavigableRows(false, inputRows, schemaRows)], inputRows);
    assert.deepEqual([...Fcitx.panelNavigableRows(false, inputRows, [])], inputRows);
    assert.deepEqual([...Fcitx.panelNavigableRows(false, null, schemaRows)], []);

    // Rime active: inputRows and schemaRows concatenated
    assert.deepEqual([...Fcitx.panelNavigableRows(true, inputRows, schemaRows)], [
        { kind: "input", value: "msime" },
        { kind: "input", value: "__direct__" },
        { kind: "schema", value: "luna_pinyin" },
    ]);
});

test("settingsTarget resolves settings destination and labelKey per active method", () => {
    // Rime active -> Overlay Bloom tab
    assert.deepEqual({ ...Fcitx.settingsTarget(true, "rime") }, { id: "rime", labelKey: "settings_rime" });

    // msime active -> MSIME settings
    assert.deepEqual({ ...Fcitx.settingsTarget(false, "msime") }, { id: "msime", labelKey: "settings_msime" });

    // Direct mode or generic layout -> Fcitx5 configtool
    assert.deepEqual({ ...Fcitx.settingsTarget(false, "") }, { id: "fcitx5", labelKey: "settings_fcitx5" });
    assert.deepEqual({ ...Fcitx.settingsTarget(false, "keyboard-us") }, { id: "fcitx5", labelKey: "settings_fcitx5" });
    assert.deepEqual({ ...Fcitx.settingsTarget(false, "mozc") }, { id: "fcitx5", labelKey: "settings_fcitx5" });
});

console.log(`${passed} checks passed`);
