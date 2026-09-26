import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";
import assert from "node:assert/strict";

// BloomController.js is a QML library (.pragma library); strip the pragma and
// evaluate it in a bare context so the pure functions can be tested in Node.
const here = dirname(fileURLToPath(import.meta.url));
let source = readFileSync(join(here, "..", "BloomController.js"), "utf8");
source = source.replace(/^\.pragma library\s*/, "");

const context = { module: { exports: {} }, console, JSON, Array, Number, String, isNaN };
vm.createContext(context);
vm.runInContext(
    source +
        "\nmodule.exports = { whichCommand, listCommand, listRegistryCommand, updateCommand, deployCommand, launchCommand, " +
        "enableCommand, disableCommand, installArgs, removeArgs, upgradeArgs, upgradeAllArgs, " +
        "parse, errorMessage, list, registry, updates, schemas, packageLabel, stringArray, updateArray };",
    context,
);
const Bloom = context.module.exports;

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

test("command builders", () => {
    assert.deepEqual([...Bloom.whichCommand()], ["sh", "-c", "command -v bloom"]);
    assert.deepEqual([...Bloom.listCommand()], ["bloom", "--json", "list"]);
    assert.deepEqual([...Bloom.updateCommand()], ["bloom", "--json", "update"]);
});

test("parse rejects malformed and non-object payloads", () => {
    assert.equal(Bloom.parse(""), null);
    assert.equal(Bloom.parse("not json"), null);
    assert.equal(Bloom.parse("[1,2,3]"), null);
    assert.deepEqual(Bloom.parse('{"ok":true}'), { ok: true });
});

test("errorMessage reads a failed envelope", () => {
    assert.equal(Bloom.errorMessage('{"ok":false,"error":"boom"}'), "boom");
    assert.equal(Bloom.errorMessage('{"ok":true}'), "");
    assert.equal(Bloom.errorMessage("garbage"), "");
});

test("list shapes a good payload and filters empty schemas", () => {
    const raw = JSON.stringify({
        ok: true,
        rime_dir: "/rime",
        enabled_schemas: ["luna_pinyin", "", "cangjie"],
        installed_schemas: ["luna_pinyin", "sno_ch_jp"],
        installed_packages: [
            { repo: "local/py", version: "local", installed_at: "2026-01-02T03:04:05Z", schemas: ["py", ""] },
        ],
        updates_available: 3,
    });
    const data = Bloom.list(raw);
    assert.equal(data.rimeDir, "/rime");
    assert.deepEqual([...data.enabledSchemas], ["luna_pinyin", "cangjie"]);
    assert.deepEqual([...data.installedSchemas], ["luna_pinyin", "sno_ch_jp"]);
    assert.equal(data.packages.length, 1);
    assert.deepEqual([...data.packages[0].schemas], ["py"]);
    assert.equal(data.updatesAvailable, 3);
});

test("list returns null on failure and on garbage", () => {
    assert.equal(Bloom.list('{"ok":false,"error":"nope"}'), null);
    assert.equal(Bloom.list("garbage"), null);
});

test("list tolerates missing arrays", () => {
    const data = Bloom.list('{"ok":true}');
    assert.deepEqual([...data.enabledSchemas], []);
    assert.deepEqual([...data.packages], []);
    assert.equal(data.updatesAvailable, -1);
});

test("updates shapes update_available and errors", () => {
    const raw = JSON.stringify({
        ok: true,
        updates: [
            { repo: "a", local: "1", remote: "1", update_available: false },
            { repo: "b", local: "1", remote: "2", update_available: true },
            { repo: "c", local: "1", remote: "", update_available: false, error: "offline" },
        ],
        updates_available: 1,
    });
    const data = Bloom.updates(raw);
    assert.equal(data.updatesAvailable, 1);
    assert.equal(data.updates.length, 3);
    assert.equal(data.updates[1].updateAvailable, true);
    assert.equal(data.updates[2].error, "offline");
});

test("packageLabel strips the local/ scan prefix", () => {
    assert.equal(Bloom.packageLabel("local/py"), "py");
    assert.equal(Bloom.packageLabel("rime/rime-luna-pinyin"), "rime/rime-luna-pinyin");
    assert.equal(Bloom.packageLabel(""), "");
});

test("registry and write command builders", () => {
    assert.deepEqual([...Bloom.listRegistryCommand()], ["bloom", "--json", "list", "-r"]);
    assert.deepEqual([...Bloom.enableCommand("py")], ["bloom", "--json", "enable", "py"]);
    assert.deepEqual([...Bloom.disableCommand("py")], ["bloom", "--json", "disable", "py"]);
    assert.deepEqual([...Bloom.installArgs("rime/py")], ["bloom", "install", "rime/py"]);
    assert.deepEqual([...Bloom.removeArgs("rime/py")], ["bloom", "remove", "rime/py"]);
    assert.deepEqual([...Bloom.upgradeArgs("rime/py")], ["bloom", "upgrade", "rime/py"]);
    assert.deepEqual([...Bloom.upgradeAllArgs()], ["bloom", "upgrade"]);
    assert.deepEqual([...Bloom.deployCommand()], ["bloom", "--json", "deploy"]);
});

test("launchCommand wraps a bloom argv in the floating-terminal launcher", () => {
    assert.deepEqual(
        [...Bloom.launchCommand(Bloom.upgradeArgs("rime/py"))],
        ["omarchy-launch-floating-terminal-with-presentation", "bloom", "upgrade", "rime/py"],
    );
});

test("registry shapes entries and marks installed", () => {
    const raw = JSON.stringify({
        ok: true,
        registry: [
            { name: "luna-pinyin", repo: "rime/rime-luna-pinyin", description: "Luna", installed: true },
            { name: "cangjie", repo: "rime/rime-cangjie", description: "Cangjie", installed: false },
        ],
    });
    const data = Bloom.registry(raw);
    assert.equal(data.registry.length, 2);
    assert.equal(data.registry[0].installed, true);
    assert.equal(data.registry[1].installed, false);
    assert.equal(data.registry[1].repo, "rime/rime-cangjie");
});

test("registry returns null on failure and tolerates a missing list", () => {
    assert.equal(Bloom.registry('{"ok":false,"error":"nope"}'), null);
    assert.deepEqual([...Bloom.registry('{"ok":true}').registry], []);
});

test("schemas builds the unified list: active, then enabled, then installed-disabled", () => {
    const packages = [
        { repo: "local/py", schemas: ["py"] },
        { repo: "rime/rime-luna-pinyin", schemas: ["sno_ch_jp", "luna_pinyin"] },
    ];
    const labels = { sno_ch_jp: "中文", japanese: "日本語", py: "拼音", luna_pinyin: "朙月拼音" };
    const rows = Bloom.schemas(["sno_ch_jp", "japanese"], packages, [], "sno_ch_jp", (id) => labels[id] || id);
    assert.deepEqual(
        [...rows.map((r) => [r.id, r.enabled, r.installed, r.owner, r.active])],
        [
            ["sno_ch_jp", true, true, "rime/rime-luna-pinyin", true],
            ["japanese", true, false, "", false],
            ["py", false, true, "local/py", false],
            ["luna_pinyin", false, true, "rime/rime-luna-pinyin", false],
        ],
    );
});

test("schemas keeps an Active-but-not-Enabled schema and marks it not installed", () => {
    const rows = Bloom.schemas(["a"], [], [], "ghost", (id) => id);
    assert.deepEqual([...rows.map((r) => r.id)], ["ghost", "a"]);
    assert.equal(rows[0].active, true);
    assert.equal(rows[0].enabled, false);
    assert.equal(rows[0].installed, false);
});

test("schemas lists on-disk schemas as installed even without an owner", () => {
    const rows = Bloom.schemas(["a"], [], ["a", "py"], "", (id) => id);
    assert.deepEqual(
        [...rows.map((r) => [r.id, r.enabled, r.installed, r.owner])],
        [
            ["a", true, true, ""],
            ["py", false, true, ""],
        ],
    );
});

test("schemas: first owner wins and label falls back to the id", () => {
    const rows = Bloom.schemas([], [{ repo: "a", schemas: ["x"] }, { repo: "b", schemas: ["x"] }], [], "", null);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].owner, "a");
    assert.equal(rows[0].label, "x");
});

test("schemas is empty-safe", () => {
    assert.deepEqual([...Bloom.schemas([], [], [], "", null)], []);
    assert.deepEqual([...Bloom.schemas(null, null, null, "", null)], []);
});

console.log(`${passed} checks passed`);
