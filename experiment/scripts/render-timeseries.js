const fs = require("fs")
const path = require("path")

const runDirectory = requiredArgument("--run-directory")
const applicationRows = readJsonLines("application-metrics.jsonl")
  .sort(byCapturedAt)
const clientRows = readJsonLines("client-progress.jsonl")
  .filter((row) => row.capturedAt)
  .sort(byCapturedAt)
const databaseRows = readJsonLines("database-metrics.jsonl")
  .sort(byCapturedAt)
const containerRows = readJsonLines("container-stats.jsonl")
  .sort(byCapturedAt)
const summary = readJson("container-monitor-summary.json")

if (applicationRows.length === 0) {
  throw new Error("application-metrics.jsonl has no rows")
}

const implementation =
  applicationRows[0]?.application?.body?.implementation ||
  applicationRows[0]?.service ||
  "unknown"
const startedAt = Date.parse(applicationRows[0].capturedAt)
let clientIndex = 0
let databaseIndex = 0
let latestClient = null
let latestDatabase = null
const containerByService = new Map()
for (const row of containerRows) {
  if (!containerByService.has(row.service)) {
    containerByService.set(row.service, [])
  }
  containerByService.get(row.service).push(row)
}
const containerIndexes = new Map()
const latestContainers = new Map()
let initialGcPauseTotalMs = null

const csvRows = applicationRows.map((row) => {
  const capturedAtMs = Date.parse(row.capturedAt)
  const body = row.application?.body || {}
  const client = latestAt(
    clientRows,
    capturedAtMs,
    () => clientIndex,
    (value) => { clientIndex = value },
    () => latestClient,
    (value) => { latestClient = value },
  )
  const database = latestAt(
    databaseRows,
    capturedAtMs,
    () => databaseIndex,
    (value) => { databaseIndex = value },
    () => latestDatabase,
    (value) => { latestDatabase = value },
  )
  const appContainer = latestContainerAt(
    row.service,
    capturedAtMs,
  )
  const mock = row.mock?.body || {}
  const gcPauseTotalMs = numberAt(body, "jvm.gcPauseTotalMs")
  if (initialGcPauseTotalMs == null && gcPauseTotalMs != null) {
    initialGcPauseTotalMs = gcPauseTotalMs
  }

  return {
    elapsedSeconds: ((capturedAtMs - startedAt) / 1000).toFixed(3),
    clientInFlight: finiteOrNull(client?.inFlight),
    mockAiInFlight: finiteOrNull(mock.aiInFlight),
    mockStorageInFlight: finiteOrNull(mock.storageInFlight),
    mvcBusy: numberAt(body, "requestRuntime.busy"),
    mvcMax: numberAt(body, "requestRuntime.max"),
    mvcQueue: numberAt(body, "requestRuntime.queue"),
    fluxEventLoopPendingSum: numberAt(body, "requestRuntime.pendingSum"),
    fluxEventLoopPendingMax: numberAt(body, "requestRuntime.pendingMax"),
    outboundActive: numberAt(body, "outboundHttp.active"),
    outboundPending: numberAt(body, "outboundHttp.pending"),
    outboundMax: numberAt(body, "outboundHttp.max"),
    databasePoolActive: numberAt(body, "databasePool.active"),
    databasePoolPending: numberAt(body, "databasePool.pending"),
    databasePoolMax: numberAt(body, "databasePool.max"),
    databaseThreadsConnected: finiteOrNull(database?.threadsConnected),
    databaseThreadsRunning: finiteOrNull(database?.threadsRunning),
    processCpuPercent: multiply(
      numberAt(body, "jvm.processCpuUsage"),
      100,
    ),
    containerCpuPercent: parsePercent(appContainer?.stats?.CPUPerc),
    heapUsedMiB: divide(
      numberAt(body, "jvm.heapUsedBytes"),
      1024 * 1024,
    ),
    containerMemoryUsedMiB: parseMemoryMiB(
      appContainer?.stats?.MemUsage,
    ),
    liveThreads: numberAt(body, "jvm.liveThreads"),
    gcPauseDeltaMs:
      gcPauseTotalMs == null || initialGcPauseTotalMs == null
        ? null
        : gcPauseTotalMs - initialGcPauseTotalMs,
    gcPauseMaxMs: numberAt(body, "jvm.gcPauseMaxMs"),
  }
})

writeCsv(csvRows)
writeSvg(csvRows)

function requiredArgument(name) {
  const index = process.argv.indexOf(name)
  if (index < 0 || !process.argv[index + 1]) {
    throw new Error(`${name} is required`)
  }
  return path.resolve(process.argv[index + 1])
}

function readJson(name) {
  return JSON.parse(fs.readFileSync(path.join(runDirectory, name), "utf8"))
}

function readJsonLines(name) {
  const file = path.join(runDirectory, name)
  if (!fs.existsSync(file)) return []
  return fs
    .readFileSync(file, "utf8")
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => JSON.parse(line))
}

function byCapturedAt(left, right) {
  return Date.parse(left.capturedAt) - Date.parse(right.capturedAt)
}

function numberAt(object, propertyPath) {
  const value = propertyPath
    .split(".")
    .reduce((current, key) => current == null ? null : current[key], object)
  return finiteOrNull(value)
}

function finiteOrNull(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null
}

function multiply(value, factor) {
  return value == null ? null : value * factor
}

function divide(value, divisor) {
  return value == null ? null : value / divisor
}

function latestAt(
  rows,
  capturedAtMs,
  getIndex,
  setIndex,
  getLatest,
  setLatest,
) {
  let index = getIndex()
  let latest = getLatest()
  while (
    index < rows.length &&
    Date.parse(rows[index].capturedAt) <= capturedAtMs
  ) {
    latest = rows[index]
    index += 1
  }
  setIndex(index)
  setLatest(latest)
  return latest
}

function latestContainerAt(service, capturedAtMs) {
  const rows = containerByService.get(service) || []
  let index = containerIndexes.get(service) || 0
  let latest = latestContainers.get(service) || null
  while (
    index < rows.length &&
    Date.parse(rows[index].capturedAt) <= capturedAtMs
  ) {
    latest = rows[index]
    index += 1
  }
  containerIndexes.set(service, index)
  latestContainers.set(service, latest)
  return latest
}

function parsePercent(value) {
  const parsed = Number(String(value || "").replace("%", ""))
  return Number.isFinite(parsed) ? parsed : null
}

function parseMemoryMiB(value) {
  const used = String(value || "").split("/")[0].trim()
  const match = used.match(/^([\d.]+)([KMG]iB|B)$/)
  if (!match) return null
  const amount = Number(match[1])
  const factors = {
    B: 1 / (1024 * 1024),
    KiB: 1 / 1024,
    MiB: 1,
    GiB: 1024,
  }
  return Number.isFinite(amount) ? amount * factors[match[2]] : null
}

function writeCsv(rows) {
  const columns = Object.keys(rows[0])
  const output = [columns.join(",")]
  for (const row of rows) {
    output.push(columns.map((column) => row[column] ?? "").join(","))
  }
  fs.writeFileSync(
    path.join(runDirectory, "timeseries.csv"),
    `${output.join("\n")}\n`,
  )
}

function writeSvg(rows) {
  const width = 1280
  const panels = [
    {
      title: "요청 겹침과 외부 stage 체류량",
      series: [
        series("clientInFlight", "client in-flight", "#0f766e"),
        series("mockAiInFlight", "AI in-flight", "#2563eb"),
        series("mockStorageInFlight", "storage in-flight", "#7c3aed"),
      ],
    },
    implementation === "mvc"
      ? {
          title: "MVC Tomcat 요청 executor",
          series: [
            series("mvcBusy", "busy", "#dc2626"),
            series("mvcMax", "max", "#6b7280"),
            series("mvcQueue", "queue", "#f59e0b"),
          ],
        }
      : {
          title: "WebFlux Netty event loop",
          series: [
            series(
              "fluxEventLoopPendingSum",
              "pending sum",
              "#dc2626",
            ),
            series(
              "fluxEventLoopPendingMax",
              "pending max",
              "#f59e0b",
            ),
          ],
        },
    {
      title: "외부 HTTP connection pool",
      series: [
        series("outboundActive", "active", "#2563eb"),
        series("outboundPending", "pending", "#dc2626"),
        series("outboundMax", "max", "#6b7280"),
      ],
    },
    {
      title: "DB pool과 MariaDB 상태",
      series: [
        series("databasePoolActive", "pool active", "#2563eb"),
        series("databasePoolPending", "pool pending", "#dc2626"),
        series("databaseThreadsRunning", "DB running", "#7c3aed"),
        series("databaseThreadsConnected", "DB connected", "#059669"),
      ],
    },
    {
      title: "앱 CPU (%)",
      series: [
        series("processCpuPercent", "JVM process", "#dc2626"),
        series("containerCpuPercent", "container", "#2563eb"),
      ],
    },
    {
      title: "앱 메모리 (MiB)",
      series: [
        series("heapUsedMiB", "JVM heap", "#7c3aed"),
        series("containerMemoryUsedMiB", "container", "#059669"),
      ],
    },
    {
      title: "JVM thread와 GC pause (보조)",
      series: [
        series("liveThreads", "live threads", "#2563eb"),
        series("gcPauseDeltaMs", "GC cumulative ms", "#dc2626"),
        series("gcPauseMaxMs", "GC max ms", "#f59e0b"),
      ],
    },
  ]
  const panelHeight = 135
  const panelGap = 70
  const height = 100 + panels.length * (panelHeight + panelGap)
  const left = 130
  const plotWidth = 1080
  const fragments = [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">`,
    "<style>text{font-family:Arial,sans-serif;fill:#111827}.title{font-size:19px;font-weight:700}.label{font-size:12px}.axis{stroke:#d1d5db}.grid{stroke:#e5e7eb;stroke-dasharray:3 4}</style>",
    `<rect width="100%" height="100%" fill="#ffffff"/>`,
    `<text x="40" y="34" class="title">${escapeXml(summary.runId)} · ${escapeXml(implementation)} · lightweight observability</text>`,
    `<text x="40" y="56" class="label">1초 단일 앱 snapshot · 1초 mock · 2초 DB · Docker stats. 각 panel y축은 독립적이다.</text>`,
  ]
  panels.forEach((panel, index) => {
    const top = 95 + index * (panelHeight + panelGap)
    fragments.push(...renderPanel(
      panel,
      rows,
      left,
      top,
      plotWidth,
      panelHeight,
    ))
  })
  fragments.push("</svg>")
  fs.writeFileSync(
    path.join(runDirectory, "timeseries.svg"),
    fragments.join("\n"),
  )
}

function series(key, label, color) {
  return { key, label, color }
}

function renderPanel(panel, rows, left, top, width, height) {
  const values = panel.series.flatMap((item) =>
    rows
      .map((row) => row[item.key])
      .filter((value) => value != null),
  )
  const maximum = Math.max(1, ...values)
  const output = [
    `<text x="${left}" y="${top - 14}" class="title">${escapeXml(panel.title)}</text>`,
    `<line x1="${left}" y1="${top}" x2="${left}" y2="${top + height}" class="axis"/>`,
    `<line x1="${left}" y1="${top + height}" x2="${left + width}" y2="${top + height}" class="axis"/>`,
    `<text x="${left - 65}" y="${top + 5}" class="label">${maximum.toFixed(1)}</text>`,
    `<text x="${left - 20}" y="${top + height + 5}" class="label">0</text>`,
  ]
  for (let grid = 1; grid < 4; grid += 1) {
    const y = top + (height * grid) / 4
    output.push(
      `<line x1="${left}" y1="${y}" x2="${left + width}" y2="${y}" class="grid"/>`,
    )
  }
  panel.series.forEach((item, index) => {
    const points = rows
      .map((row, rowIndex) => {
        const value = row[item.key]
        if (value == null) return null
        const x =
          left +
          (rows.length <= 1
            ? 0
            : (rowIndex / (rows.length - 1)) * width)
        const y = top + height - (value / maximum) * height
        return `${x.toFixed(1)},${y.toFixed(1)}`
      })
      .filter(Boolean)
      .join(" ")
    if (points) {
      output.push(
        `<polyline fill="none" stroke="${item.color}" stroke-width="2.2" points="${points}"/>`,
      )
    }
    const legendX = left + 520 + index * 145
    output.push(
      `<rect x="${legendX}" y="${top - 27}" width="10" height="10" fill="${item.color}"/>`,
      `<text x="${legendX + 15}" y="${top - 17}" class="label">${escapeXml(item.label)}</text>`,
    )
  })
  return output
}

function escapeXml(value) {
  return String(value).replace(/[<>&'"]/g, (character) => ({
    "<": "&lt;",
    ">": "&gt;",
    "&": "&amp;",
    "'": "&apos;",
    '"': "&quot;",
  }[character]))
}
