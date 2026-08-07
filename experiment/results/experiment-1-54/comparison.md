# Exp154 Comparison

This artifact reports test-only Base64 decode measurements.

| concurrency | Cell A p95 (ns) | Cell B p95 (ns) | Cell A throughput | Cell B throughput |
|---:|---:|---:|---:|---:|
| 1 | 2273617 | 763564 | 56.522 | 82.142 |
| 2 | 2285137 | 7184456 | 126.089 | 162.975 |
| 4 | 1872045 | 1181532 | 295.800 | 337.959 |
| 8 | 2288858 | 1331253 | 627.048 | 680.854 |

Checksum validation is required for every operation; no production claim is made.
