const http = require("http")
const crypto = require("crypto")

const port = Number(process.env.MOCK_PORT || 9100)
const defaultMemberId = Number(process.env.MOCK_MEMBER_ID || 15)

const defaultAiState = {
  result: String(process.env.MOCK_AI_RESULT || "false").toLowerCase() === "true",
  delayMs: Number(process.env.MOCK_AI_DELAY_MS || 0),
  status: Number(process.env.MOCK_AI_STATUS || 200),
  closeBeforeResponse: false,
}

let aiState = { ...defaultAiState }
const defaultStorageState = {
  delayMs: Number(process.env.MOCK_STORAGE_DELAY_MS || 0),
  status: Number(process.env.MOCK_STORAGE_STATUS || 200),
}
let storageState = { ...defaultStorageState }
const storedObjects = new Map()
let requestSequence = 0
let observedRequests = []
let aiLifecycleEvents = []
let socketSequence = 0
const socketIds = new WeakMap()
const socketMetadata = new WeakMap()
let aiInFlight = 0
let aiMaxInFlight = 0
let aiCompleted = 0
let storageInFlight = 0
let storageMaxInFlight = 0
let storageCompleted = 0
let resetGeneration = 0
let strictAuth = false
let authLoginCompleted = 0
let authLoginFailures = 0
const authUsers = new Map()
const issuedTokens = new Map()

function observeRequest(request, pathname) {
  requestSequence += 1
  observedRequests.push({
    sequence: requestSequence,
    observedAt: new Date().toISOString(),
    method: request.method,
    path: pathname,
    contentLength: Number(request.headers["content-length"] || 0),
    experimentRunId: request.headers["x-experiment-run-id"] || null,
    experimentRequestId: request.headers["x-experiment-request-id"] || null,
  })
}

function getSocketId(socket) {
  if (!socket) return null
  if (!socketIds.has(socket)) {
    socketSequence += 1
    socketIds.set(socket, `socket-${socketSequence}`)
  }
  return socketIds.get(socket)
}

function snapshotSocket(socket) {
  if (!socket) return {
    mockChannelId: null,
    localAddress: null,
    localPort: null,
    remoteAddress: null,
    remotePort: null,
  }
  if (!socketMetadata.has(socket)) {
    socketMetadata.set(socket, {
      mockChannelId: getSocketId(socket),
      localAddress: socket.localAddress || null,
      localPort: socket.localPort || null,
      remoteAddress: socket.remoteAddress || null,
      remotePort: socket.remotePort || null,
    })
  }
  return socketMetadata.get(socket)
}

function observeConnection(event, socket, extra = {}) {
  aiLifecycleEvents.push({
    event,
    observedAt: new Date().toISOString(),
    requestId: null,
    experimentRunId: null,
    missionRunId: null,
    connectionLevel: true,
    ...snapshotSocket(socket),
    ...extra,
  })
}

function observeAiLifecycle(event, request, state, extra = {}) {
  const { socket: connectionSocket, ...details } = extra
  const socket = request?.socket || connectionSocket
  aiLifecycleEvents.push({
    event,
    observedAt: new Date().toISOString(),
    requestId: request?.headers?.["x-experiment-request-id"] || null,
    experimentRunId: request?.headers?.["x-experiment-run-id"] || null,
    missionRunId: request?.headers?.["x-mission-run-id"] || null,
    socketId: getSocketId(socket),
    ...snapshotSocket(socket),
    responseFinished: state?.responseFinished ?? null,
    responseWriteStarted: state?.writeStarted ?? null,
    requestAborted: state?.requestAborted ?? null,
    ...details,
  })
}

function requestCounts() {
  return observedRequests.reduce((counts, request) => {
    const key = `${request.method} ${request.path}`
    counts[key] = (counts[key] || 0) + 1
    return counts
  }, {})
}

function readBuffer(request) {
  return new Promise((resolve, reject) => {
    const chunks = []

    request.on("data", (chunk) => chunks.push(chunk))
    request.on("end", () => resolve(Buffer.concat(chunks)))
    request.on("error", reject)
  })
}

function readJson(request) {
  return new Promise((resolve, reject) => {
    let body = ""

    request.setEncoding("utf8")
    request.on("data", (chunk) => {
      body += chunk
    })
    request.on("end", () => {
      if (!body) {
        resolve({})
        return
      }

      try {
        resolve(JSON.parse(body))
      } catch (error) {
        reject(error)
      }
    })
    request.on("error", reject)
  })
}

function sendJson(response, status, body) {
  const serialized = JSON.stringify(body)
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(serialized),
  })
  response.end(serialized)
}

function parseMemberId(authorization) {
  if (strictAuth) {
    return issuedTokens.get(String(authorization || "")) ?? null
  }

  const match = String(authorization || "").match(/experiment-member-(\d+)$/)
  return match ? Number(match[1]) : defaultMemberId
}

function resetAuthState() {
  strictAuth = false
  authLoginCompleted = 0
  authLoginFailures = 0
  authUsers.clear()
  issuedTokens.clear()
}

function normalizeBase64(image) {
  const value = String(image || "")
  const separatorIndex = value.indexOf(",")
  return separatorIndex >= 0 ? value.slice(separatorIndex + 1) : value
}

function isAnalyzePath(pathname) {
  return ["/analyze/face", "/analyze/object", "/analyze/doodle"].includes(pathname)
}

const server = http.createServer(async (request, response) => {
  const url = new URL(request.url, `http://${request.headers.host}`)

  if (request.method === "GET" && url.pathname === "/health") {
    sendJson(response, 200, {
      status: "ok",
      ai: aiState,
      storage: storageState,
      storedObjectCount: storedObjects.size,
      strictAuth,
      authRegisteredUsers: authUsers.size,
      requestCounts: requestCounts(),
    })
    return
  }

  if (request.method === "GET" && url.pathname === "/api/member/ai") {
    observeRequest(request, url.pathname)
    const memberId = parseMemberId(request.headers.authorization)
    if (memberId === null) {
      sendJson(response, 401, { error: "mock token is not issued" })
      return
    }
    sendJson(response, 200, {
      id: memberId,
    })
    return
  }

  if (request.method === "POST" && url.pathname === "/__auth/users") {
    try {
      const body = await readJson(request)
      const users = Array.isArray(body.users) ? body.users : null
      if (!users || users.length === 0) {
        sendJson(response, 400, { error: "users must be a non-empty array" })
        return
      }

      const nextUsers = new Map()
      for (const user of users) {
        const login = String(user.login || "")
        const memberId = Number(user.memberId)
        if (!login || !Number.isSafeInteger(memberId) || memberId <= 0) {
          sendJson(response, 400, { error: "invalid auth user" })
          return
        }
        if (nextUsers.has(login)) {
          sendJson(response, 400, { error: "duplicate auth login" })
          return
        }
        nextUsers.set(login, memberId)
      }

      strictAuth = true
      authLoginCompleted = 0
      authLoginFailures = 0
      authUsers.clear()
      issuedTokens.clear()
      for (const [login, memberId] of nextUsers) {
        authUsers.set(login, memberId)
      }
      sendJson(response, 200, {
        strictAuth,
        registeredUsers: authUsers.size,
      })
    } catch (error) {
      sendJson(response, 400, { error: "invalid auth user payload" })
    }
    return
  }

  if (request.method === "POST" && url.pathname === "/__auth/login") {
    try {
      const body = await readJson(request)
      const login = String(body.login || "")
      const memberId = authUsers.get(login)
      if (!strictAuth || memberId === undefined) {
        authLoginFailures += 1
        sendJson(response, 401, { error: "mock login rejected" })
        return
      }

      const authorization = `Bearer experiment-session-${crypto.randomUUID()}`
      issuedTokens.set(authorization, memberId)
      authLoginCompleted += 1
      sendJson(response, 200, { authorization, memberId })
    } catch (error) {
      authLoginFailures += 1
      sendJson(response, 400, { error: "invalid mock login payload" })
    }
    return
  }

  if (request.method === "POST" && url.pathname === "/__control") {
    try {
      const body = await readJson(request)
      aiState = {
        result: body.result === undefined ? aiState.result : Boolean(body.result),
        delayMs: body.delayMs === undefined ? aiState.delayMs : Number(body.delayMs),
        status: body.status === undefined ? aiState.status : Number(body.status),
        closeBeforeResponse:
          body.closeBeforeResponse === undefined
            ? aiState.closeBeforeResponse
            : Boolean(body.closeBeforeResponse),
      }
      storageState = {
        delayMs:
          body.storageDelayMs === undefined
            ? storageState.delayMs
            : Number(body.storageDelayMs),
        status:
          body.storageStatus === undefined
            ? storageState.status
            : Number(body.storageStatus),
      }
      sendJson(response, 200, { ai: aiState, storage: storageState })
    } catch (error) {
      sendJson(response, 400, { error: "invalid control payload" })
    }
    return
  }

  if (request.method === "POST" && url.pathname === "/__reset") {
    resetGeneration += 1
    aiState = { ...defaultAiState }
    storageState = { ...defaultStorageState }
    storedObjects.clear()
    requestSequence = 0
    observedRequests = []
    aiLifecycleEvents = []
    aiInFlight = 0
    aiMaxInFlight = 0
    aiCompleted = 0
    storageInFlight = 0
    storageMaxInFlight = 0
    storageCompleted = 0
    resetAuthState()
    sendJson(response, 200, {
      ai: aiState,
      storage: storageState,
      storedObjectCount: 0,
    })
    return
  }

  if (request.method === "GET" && url.pathname === "/__requests") {
    sendJson(response, 200, {
      counts: requestCounts(),
      requests: observedRequests,
      aiLifecycleEvents,
    })
    return
  }

  if (request.method === "GET" && url.pathname === "/__metrics") {
    sendJson(response, 200, {
      aiInFlight,
      aiMaxInFlight,
      aiCompleted,
      storageInFlight,
      storageMaxInFlight,
      storageCompleted,
      strictAuth,
      authRegisteredUsers: authUsers.size,
      authIssuedTokens: issuedTokens.size,
      authLoginCompleted,
      authLoginFailures,
      resetGeneration,
      aiLifecycleEventCount: aiLifecycleEvents.length,
      requestCounts: requestCounts(),
    })
    return
  }

  if (request.method === "GET" && url.pathname === "/__storage") {
    sendJson(response, 200, {
      objectCount: storedObjects.size,
      objects: Array.from(storedObjects.values()),
    })
    return
  }

  if (request.method === "PUT" && url.pathname === "/storage/object") {
    observeRequest(request, url.pathname)
    try {
      const objectKey = url.searchParams.get("key")
      if (!objectKey) {
        sendJson(response, 400, { error: "key is required" })
        return
      }

      const body = await readBuffer(request)
      const snapshot = { ...storageState }
      const requestGeneration = resetGeneration
      if (requestGeneration === resetGeneration) {
        storageInFlight += 1
        storageMaxInFlight = Math.max(storageMaxInFlight, storageInFlight)
      }

      setTimeout(() => {
        try {
          if (snapshot.status >= 400) {
            sendJson(response, snapshot.status, {
              error: "mock storage failure",
              status: snapshot.status,
            })
            return
          }

          const storedObject = {
            key: objectKey,
            bytes: body.length,
            sha256: crypto.createHash("sha256").update(body).digest("hex"),
          }
          storedObjects.set(objectKey, storedObject)
          sendJson(response, 200, storedObject)
        } finally {
          if (requestGeneration === resetGeneration) {
            storageInFlight -= 1
            storageCompleted += 1
          }
        }
      }, Math.max(0, snapshot.delayMs))
    } catch (error) {
      sendJson(response, 500, { error: "mock storage read failure" })
    }
    return
  }

  if (request.method === "POST" && isAnalyzePath(url.pathname)) {
    observeRequest(request, url.pathname)
    const requestGeneration = resetGeneration
    const lifecycle = {
      requestReceived: true,
      delayStarted: false,
      writeStarted: false,
      responseFinished: false,
      requestAborted: false,
      requestClosed: false,
      responseClosed: false,
    }
    observeAiLifecycle("MOCK_AI_REQUEST_RECEIVED", request, lifecycle)
    request.once("aborted", () => {
      lifecycle.requestAborted = true
      observeAiLifecycle("MOCK_AI_REQUEST_ABORTED", request, lifecycle)
    })
    request.once("close", () => {
      lifecycle.requestClosed = true
      observeAiLifecycle("MOCK_AI_REQUEST_CLOSED", request, lifecycle)
    })
    response.once("finish", () => {
      lifecycle.responseFinished = true
      observeAiLifecycle("MOCK_AI_RESPONSE_FINISHED", request, lifecycle)
    })
    response.once("close", () => {
      lifecycle.responseClosed = true
      observeAiLifecycle("MOCK_AI_RESPONSE_CLOSED", request, lifecycle, {
        incompleteResponse: !lifecycle.responseFinished,
      })
    })
    try {
      const body = await readJson(request)
      const snapshot = { ...aiState }
      if (requestGeneration === resetGeneration) {
        aiInFlight += 1
        aiMaxInFlight = Math.max(aiMaxInFlight, aiInFlight)
      }
      lifecycle.delayStarted = true
      observeAiLifecycle("MOCK_AI_DELAY_STARTED", request, lifecycle)

      setTimeout(() => {
        try {
          if (snapshot.closeBeforeResponse) {
            request.socket.destroy()
            return
          }
          lifecycle.writeStarted = true
          observeAiLifecycle("MOCK_AI_RESPONSE_WRITE_STARTED", request, lifecycle)
          if (snapshot.status >= 400) {
            sendJson(response, snapshot.status, {
              error: "mock AI failure",
              status: snapshot.status,
            })
            return
          }

          sendJson(response, 200, {
            result: snapshot.result,
            image: snapshot.result ? normalizeBase64(body.image) : null,
          })
        } finally {
          if (requestGeneration === resetGeneration) {
            aiInFlight -= 1
            aiCompleted += 1
          }
        }
      }, Math.max(0, snapshot.delayMs))
    } catch (error) {
      sendJson(response, 400, { error: "invalid AI request payload" })
    }
    return
  }

  sendJson(response, 404, { error: "not found" })
})

server.on("connection", (socket) => {
  snapshotSocket(socket)
  observeConnection("MOCK_CONNECTION_ACCEPTED", socket)
  observeConnection("MOCK_CONNECTION_ACTIVE", socket)
  socket.once("end", () => {
    observeConnection("MOCK_CONNECTION_INACTIVE", socket)
  })
  socket.once("close", (hadError) => {
    observeConnection("MOCK_CONNECTION_CLOSED", socket, {
      hadError: Boolean(hadError),
    })
    observeAiLifecycle("MOCK_AI_SOCKET_CLOSED", null, null, {
      socket,
      connectionLevel: true,
      hadError: Boolean(hadError),
    })
  })
  socket.once("error", (error) => {
    observeConnection("MOCK_CONNECTION_EXCEPTION", socket, {
      errorClass: error.name || null,
      errorMessage: error.message || null,
      errorCode: error.code || null,
    })
    observeAiLifecycle("MOCK_AI_SOCKET_ERROR", null, null, {
      socket,
      connectionLevel: true,
      errorClass: error.name || null,
      errorMessage: error.message || null,
      errorCode: error.code || null,
    })
  })
})

server.listen(port, "0.0.0.0", () => {
  process.stdout.write(`experiment mock listening on ${port}\n`)
})
