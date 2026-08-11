function responseMatchesSuccess(body, jsonPath) {
  if (typeof jsonPath !== "string" || jsonPath.trim() === "") {
    return typeof body === "string" && body.trim().toLowerCase() === "true"
  }

  let parsed
  try {
    parsed = typeof body === "string" ? JSON.parse(body) : body
  } catch (_) {
    return false
  }

  const pathParts = jsonPath.trim().split(".")
  let value = parsed
  for (const part of pathParts) {
    if (!part || value === null || value === undefined) return false
    if (typeof value !== "object" || !Object.prototype.hasOwnProperty.call(value, part)) {
      return false
    }
    value = value[part]
  }
  return value === true
}

module.exports = { responseMatchesSuccess }
