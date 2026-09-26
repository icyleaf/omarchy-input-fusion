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
        "\nmodule.exports = { whichCommand, listCommand, updateCommand, parse, errorMessage, list, updates, packageLabel, stringArray, updateArray };",
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
        installed_packages: [
            { repo: "local/py", version: "local", installed_at: "2026-01-02T03:04:05Z", schemas: ["py", ""] },
        ],
        updates_available: 3,
    });
    const data = Bloom.list(raw);
    assert.equal(data.rimeDir, "/rime");
    assert.deepEqual([...data.enabledSchemas], ["luna_pinyin", "cangjie"]);
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

console.log(`${passed} checks passed`);
