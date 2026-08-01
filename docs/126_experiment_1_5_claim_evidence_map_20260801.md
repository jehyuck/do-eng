# Experiment 1-5 Claim/Evidence Map

| Claim | Evidence | Boundary |
|---|---|---|
| Full-path budget 352 was executed | run-config, admission endpoint, three core raw runs | fixed synthetic VU200 contract |
| Budget remained bounded and leak-free | admission JSONL, max 352, leak 0 | observed runs only |
| 352 met the preregistered capacity target | **Not supported**; successful-RPS median 108.7429 < 124.0172 | target missed |
| 503 target was met | **Not supported**; median 40.331% > 37.689% | target missed |
| Safety was preserved | **Not supported**; HTTP500=2 in run 002 | other safety artifacts passed |
| 352 is optimal | **Not tested** | no sweep authorized |
| WebFlux is superior to MVC | **Not tested** | MVC comparison gate not opened |
