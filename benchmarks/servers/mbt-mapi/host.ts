// Bun HTTP host adapter — now powered by real mapi MoonBit code.
//
// This file is intentionally thin: the actual HTTP routing and handler
// logic lives in examples/petstore (MoonBit), compiled to JS via
// `moon build --target js`. The compiled output is run directly.
//
// Build step is handled by benchmarks/run.ts before starting this server.
import { join } from "path";

const compiled = join(
  import.meta.dir,
  "../../../examples/petstore/_build/js/release/build/src/http_host/http_host.js"
);

await import(compiled);
