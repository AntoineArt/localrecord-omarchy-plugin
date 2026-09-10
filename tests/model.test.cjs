const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const model = {};
vm.createContext(model);
vm.runInContext(fs.readFileSync(require("node:path").join(__dirname, "../Model.js"), "utf8").replace(/^\.pragma library\s*/, ""), model);

assert.equal(model.isLocalRecordProcess("localrecord", ""), true);
assert.equal(model.isLocalRecordProcess("localrecord", "1.3.2"), true);
assert.equal(model.isLocalRecordProcess("localrec-1.3.3", "1.3.3"), true);
assert.equal(model.isLocalRecordProcess("localrec-1.3.2", "1.3.3"), false);
assert.equal(model.isLocalRecordProcess("localrec-1.3.3", ""), false);
assert.equal(model.isLocalRecordProcess("bash", "1.3.3"), false);
assert.equal(model.isLocalRecordProcess("", "1.3.3"), false);
for (const version of ["", "0.1.16", "1.3.2", "bad"]) {
  assert.equal(model.desktopOnlyAgc(version), false);
}
for (const version of ["1.3.3", "1.3.10", "1.4.0", "2.0.0"]) {
  assert.equal(model.desktopOnlyAgc(version), true);
}
console.log("Plugin process detection and AGC compatibility tests passed");
