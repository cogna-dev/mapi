import { spawnSync, spawn } from "bun";
import { existsSync, mkdirSync, readFileSync } from "fs";
import { join } from "path";

const ROOT = import.meta.dir;

interface ServerConfig {
  name: string;
  port: number;
  dir: string;
  buildDir?: string;
  startDir?: string;
  buildCmd?: string[];
  startCmd: string[];
}

interface K6Summary {
  metrics: {
    http_req_duration: {
      avg: number;
      med: number;
      "p(90)": number;
      "p(95)": number;
      max: number;
    };
    http_reqs: { count: number; rate: number };
    http_req_failed: { value: number };
    checks: { value: number };
  };
}

const servers: ServerConfig[] = [
  {
    name: "go-gin",
    port: 8081,
    dir: join(ROOT, "servers/go-gin"),
    buildCmd: ["go", "build", "-o", "./bin/server", "."],
    startCmd: ["./bin/server"],
  },
  {
    name: "rust-axum",
    port: 8082,
    dir: join(ROOT, "servers/rust-axum"),
    buildCmd: ["cargo", "build", "--release"],
    startCmd: ["./target/release/rust-axum"],
  },
  {
    name: "mbt-mapi",
    port: 8083,
    dir: join(ROOT, "servers/mbt-mapi"),
    buildCmd: ["moon", "build", ".", "--target", "native", "--release"],
    startCmd: ["moon", "run", ".", "--target", "native", "--release"],
  },
];

const resultsDir = join(ROOT, "results");
if (!existsSync(resultsDir)) mkdirSync(resultsDir, { recursive: true });

async function waitForPort(port: number, timeoutMs = 10_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(`http://localhost:${port}/pets`);
      if (res.status < 500) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error(`Server on port ${port} did not become ready within ${timeoutMs}ms`);
}

function build(server: ServerConfig): void {
  if (!server.buildCmd) return;
  console.log(`  Building ${server.name}...`);
  const cwd = server.buildDir ?? server.dir;
  const result = spawnSync(server.buildCmd, { cwd, stdio: ["inherit", "inherit", "inherit"] });
  if (result.exitCode !== 0) throw new Error(`Build failed for ${server.name}`);
}

async function runBenchmark(server: ServerConfig): Promise<K6Summary> {
  console.log(`\n▶ ${server.name} (port ${server.port})`);

  build(server);

  const proc = spawn(server.startCmd, {
    cwd: server.startDir ?? server.dir,
    stdio: ["ignore", "ignore", "ignore"],
  });

  try {
    await waitForPort(server.port);

    const summaryPath = join(resultsDir, `${server.name}.json`);
    const k6 = spawnSync(
      [
        "k6",
        "run",
        "--summary-export",
        summaryPath,
        "--env",
        `PORT=${server.port}`,
        join(ROOT, "k6/petstore.js"),
      ],
      { stdio: ["inherit", "inherit", "inherit"] }
    );

    if (k6.exitCode !== 0) throw new Error(`k6 exited with code ${k6.exitCode} for ${server.name}`);

    return JSON.parse(readFileSync(summaryPath, "utf8")) as K6Summary;
  } finally {
    proc.kill();
    await proc.exited;
  }
}

function ms(val: number): string {
  return val.toFixed(2).padStart(8);
}

function printTable(results: Array<{ name: string; summary: K6Summary }>): void {
  const header = ["Server", "RPS", "avg(ms)", "p50(ms)", "p90(ms)", "p95(ms)", "max(ms)", "Checks"];
  const rows = results.map(({ name, summary }) => {
    const d = summary.metrics.http_req_duration;
    const reqs = summary.metrics.http_reqs;
    const checks = summary.metrics.checks;
    return [
      name,
      reqs.rate.toFixed(1),
      ms(d.avg),
      ms(d.med),
      ms(d["p(90)"]),
      ms(d["p(95)"]),
      ms(d.max),
      (checks.value * 100).toFixed(0) + "%",
    ];
  });

  const cols = header.length;
  const widths = Array.from({ length: cols }, (_, i) =>
    Math.max(header[i].length, ...rows.map((r) => r[i].length))
  );

  const sep = "+" + widths.map((w) => "-".repeat(w + 2)).join("+") + "+";
  const fmt = (cells: string[]) =>
    "| " + cells.map((c, i) => c.padEnd(widths[i])).join(" | ") + " |";

  console.log("\n" + sep);
  console.log(fmt(header));
  console.log(sep);
  for (const row of rows) {
    console.log(fmt(row));
  }
  console.log(sep + "\n");
}

const results: Array<{ name: string; summary: K6Summary }> = [];

for (const server of servers) {
  const summary = await runBenchmark(server);
  results.push({ name: server.name, summary });
}

printTable(results);
