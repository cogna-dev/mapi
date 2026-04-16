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
| **go-gin**    | **3 431** | **3.97** | **0.69** |    14.22 |    20.39 |    57.77 | 100 %  |
| rust-axum     |   3 268   |     5.46 |     1.34 |    18.03 |    24.97 |    68.72 | 100 %  |
| mbt-mapi      |     504   |   173.17 |     2.04 |   806.06 | 1 124.09 | 1 528.30 | 100 %  |

Latency figures cover **all four endpoints** (incl. the intentional 404).
Go-gin still leads on throughput and median latency; rust-axum remains close.
The native `mbt-mapi` benchmark server now runs the real mapi pipeline on the
MoonBit native backend, but under this 100-VU workload it shows much heavier
tail latency than the Go and Rust servers.

## mbt-mapi architecture note

The `mbt-mapi` server runs the actual mapi runtime:

1. `examples/petstore/src/benchmark_native_host` is compiled with `moon build src/benchmark_native_host --target native --release`
2. The native host uses `moonbitlang/async/http` to accept HTTP requests on port 8083
3. Each request is converted into a `RequestEnvelope` and dispatched through MoonBit `App::serve()`
4. `examples/petstore/src/benchmark_handlers` provides a benchmark-only in-memory pet store with semantics aligned to the Go/Rust servers

This benchmark now measures the MoonBit **native** backend plus the `moonbitlang/async/http` host layer, not the old Bun/JS path.
