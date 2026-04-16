# mapi benchmarks

Compares HTTP throughput across three petstore implementations:

| Server    | Language                 | Port |
|-----------|--------------------------|------|
| go-gin    | Go + Gin                 | 8081 |
| rust-axum | Rust + Axum              | 8082 |
| mbt-mapi  | MoonBit native + async/http | 8083 |

## Prerequisites

- [k6](https://k6.io/docs/get-started/installation/)
- [Go](https://go.dev/dl/) ≥ 1.21
- [Rust + Cargo](https://rustup.rs/)
- [Bun](https://bun.sh/) ≥ 1.0
- [MoonBit](https://www.moonbitlang.com/download/) toolchain

## Run

```sh
bun run bench
```

`run.ts` will:
1. Build each server (Go, Rust, and MoonBit native)
2. Start each server
3. Run a 30s k6 load test (100 VUs) against it
4. Stop the server
5. Print a comparison table

Results JSON files are saved to `results/`.

## Benchmark Results

### Hardware

| Item   | Detail                    |
|--------|---------------------------|
| CPU    | Apple M5                  |
| Memory | 32 GB                     |
| OS     | macOS 26.3 (darwin/arm64) |

### Test Parameters

| Parameter | Value                                                           |
|-----------|-----------------------------------------------------------------|
| Tool      | k6 v1.7.1                                                       |
| VUs       | 100                                                             |
| Duration  | 30 s                                                            |
| Endpoints | GET /pets · POST /pets · GET /pets/1 · GET /pets/999999 (404)   |

Each iteration makes 4 requests (one per endpoint). The 25 % `http_req_failed`
rate is expected — k6 counts HTTP 404 as a failure, and one of the four
endpoints is intentionally expected to return 404. All k6 `check()` assertions
passed at 100 % for the latest run.

### Results

| Server        |       RPS | avg (ms) | p50 (ms) | p90 (ms) | p95 (ms) | max (ms) | Checks |
|---------------|----------:|---------:|---------:|---------:|---------:|---------:|--------|
| **go-gin**    | **3 392** | **4.31** | **0.74** |    16.39 |    22.59 |    59.91 | 100 %  |
| rust-axum     |   3 213   |     6.01 |     1.52 |    19.03 |    25.67 |    94.23 | 100 %  |
| mbt-mapi      |     467   |   188.90 |     2.18 |   869.01 | 1 113.84 | 2 780.15 | 100 %  |

Latency figures cover **all four endpoints** (incl. the intentional 404).
Go-gin still leads on throughput and median latency; rust-axum remains close.
The standalone native `mbt-mapi` benchmark server now runs the real mapi
pipeline from its own benchmark project under `benchmarks/servers/mbt-mapi/`,
but under this 100-VU workload it still shows much heavier tail latency than
the Go and Rust servers.

## mbt-mapi architecture note

The `mbt-mapi` server runs the actual mapi runtime:

1. `benchmarks/servers/mbt-mapi/` is a standalone MoonBit module with its own `moon.mod.json`
2. It depends on the root `cogna-dev/mapi` module via a local path dependency
3. The native host uses `moonbitlang/async/http` to accept HTTP requests on port 8083
4. Each request is converted into a `RequestEnvelope` and dispatched through MoonBit `App::serve()`
5. The benchmark server keeps its own in-memory pet store so benchmark semantics stay aligned with the Go/Rust servers without coupling to `examples/`

This benchmark now measures the MoonBit **native** backend plus the `moonbitlang/async/http` host layer from a standalone benchmark project, not the old Bun/JS path and not the `examples/` tree.
