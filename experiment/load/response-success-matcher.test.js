const assert = require("node:assert/strict")
const test = require("node:test")

const { responseMatchesSuccess } = require("./response-success-matcher")

test("legacy literal true matching remains strict", () => {
  assert.equal(responseMatchesSuccess("true"), true)
  assert.equal(responseMatchesSuccess(" TRUE "), true)
  assert.equal(responseMatchesSuccess("false"), false)
  assert.equal(responseMatchesSuccess('{"ai":{"result":true}}'), false)
})

test("JSON path matches boolean true only", () => {
  assert.equal(responseMatchesSuccess('{"ai":{"result":true}}', "ai.result"), true)
  assert.equal(responseMatchesSuccess('{"ai":{"result":false}}', "ai.result"), false)
  assert.equal(responseMatchesSuccess('{"ai":{"result":"true"}}', "ai.result"), false)
  assert.equal(responseMatchesSuccess('{"other":true}', "ai.result"), false)
  assert.equal(responseMatchesSuccess("not-json", "ai.result"), false)
  assert.equal(responseMatchesSuccess('{"ai":{"result":1}}', "ai.result"), false)
  assert.equal(responseMatchesSuccess('{"ai":{"result":null}}', "ai.result"), false)
})
