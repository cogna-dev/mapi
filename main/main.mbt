///|
enum CommandMode {
  Init
  Generate
} derive(Eq)

///|
fn fail_with_message(prefix : String, detail : String) -> Unit {
  println(prefix + detail)
  @sys.exit(1)
}

///|
fn debug_string(value : &@debug.Debug) -> String {
  @debug.render(@debug.to_repr(value))
}

///|
fn main {
  match @sys.get_cli_args() {
    [_, "init", .. rest] => run_command(rest.to_array(), Init)
    [_, "generate", .. rest] => run_command(rest.to_array(), Generate)
    [_, "check", .. rest] => run_check(rest.to_array())
    [_, "diff", .. rest] => run_diff(rest.to_array())
    [_, "doctor", .. rest] => run_doctor(rest.to_array())
    _ => print_usage()
  }
}

///|
fn run_command(args : Array[String], mode : CommandMode) -> Unit {
  match parse_cli_options(args, mode) {
    Ok(config) => {
      let spec = @fs.read_file_to_string(config.spec_path) catch {
        err => {
          fail_with_message("Failed to read spec: ", debug_string(err))
          ""
        }
      }
      let ir = parse_openapi(spec) catch {
        err => {
          fail_with_message("Failed to parse spec: ", debug_string(err))
          { title: "", version: "", schemas: [], operations: [] }
        }
      }
      let module_name = infer_module_name(config.output_dir)
      let files = generate_project(ir, module_name)
      write_project(files, config.output_dir, mode == Generate) catch {
        err => fail_with_message("Failed to write project: ", debug_string(err))
      }
      write_state(ir, config.spec_path, config.output_dir) catch {
        err => fail_with_message("Failed to write state: ", debug_string(err))
      }
      println(success_message(mode, config.output_dir))
    }
    Err(message) => {
      println(message)
      print_usage()
      @sys.exit(1)
    }
  }
}

///|
struct CliConfig {
  spec_path : String
  output_dir : String
}

///|
fn parse_cli_options(
  args : Array[String],
  mode : CommandMode,
) -> Result[CliConfig, String] {
  let mut spec_path : String? = None
  let mut output_dir : String? = None
  let mut index = 0
  while index < args.length() {
    let current = args[index]
    if index + 1 >= args.length() {
      return Err("Missing value for option: " + current)
    }
    let value = args[index + 1]
    match current {
      "--spec" => spec_path = Some(value)
      "--out" if mode == Init => output_dir = Some(value)
      "--project" if mode == Generate => output_dir = Some(value)
      _ => return Err("Unknown option: " + current)
    }
    index += 2
  }
  match (spec_path, output_dir) {
    (Some(spec_path), Some(output_dir)) => Ok({ spec_path, output_dir })
    (None, _) => Err("Missing required option: --spec")
    (_, None) =>
      Err(
        match mode {
          Init => "Missing required option: --out"
          Generate => "Missing required option: --project"
        },
      )
  }
}

///|
fn parse_project_flag(args : Array[String]) -> Result[String, String] {
  let mut index = 0
  while index < args.length() {
    let current = args[index]
    if index + 1 >= args.length() {
      return Err("Missing value for option: " + current)
    }
    let value = args[index + 1]
    if current == "--project" {
      return Ok(value)
    }
    index += 2
  }
  Err("Missing required option: --project")
}

///|
fn parse_spec_and_project(
  args : Array[String],
) -> Result[(String, String), String] {
  let mut spec_path : String? = None
  let mut project_dir : String? = None
  let mut index = 0
  while index < args.length() {
    let current = args[index]
    if index + 1 >= args.length() {
      return Err("Missing value for option: " + current)
    }
    let value = args[index + 1]
    match current {
      "--spec" => spec_path = Some(value)
      "--project" => project_dir = Some(value)
      _ => return Err("Unknown option: " + current)
    }
    index += 2
  }
  match (spec_path, project_dir) {
    (Some(s), Some(p)) => Ok((s, p))
    (None, _) => Err("Missing required option: --spec")
    (_, None) => Err("Missing required option: --project")
  }
}

///|
fn infer_module_name(output_dir : String) -> String {
  let parts = output_dir.split("/").to_array().filter(part => !part.is_empty())
  match parts.last() {
    Some(last) => last.to_string()
    None => "generated-api"
  }
}

///|
fn success_message(mode : CommandMode, output_dir : String) -> String {
  match mode {
    Init => "Initialized project in " + output_dir
    Generate => "Regenerated generated layer in " + output_dir
  }
}

///|
fn print_usage() -> Unit {
  println("Usage:")
  println("  mapi init     --spec <path> --out <dir>")
  println("  mapi generate --spec <path> --project <dir>")
  println("  mapi check    --project <dir>")
  println("  mapi diff     --spec <path> --project <dir>")
  println("  mapi doctor   --project <dir>")
}

///|
fn run_check(args : Array[String]) -> Unit {
  let project_dir = match parse_project_flag(args) {
    Ok(dir) => dir
    Err(msg) => {
      println(msg)
      @sys.exit(1)
      ""
    }
  }
  let state_path = project_dir + "/.mapi/state.json"
  if !@fs.path_exists(state_path) {
    println(
      "Error: .mapi/state.json not found in " +
      project_dir +
      ". Run `mapi init` or `mapi generate` first.",
    )
    @sys.exit(1)
    return
  }
  let state_raw = @fs.read_file_to_string(state_path) catch {
    err => {
      fail_with_message("Failed to read state: ", debug_string(err))
      ""
    }
  }
  let operations = parse_state_operations(state_raw)
  let mut missing = 0
  let mut ok = 0
  for op_id in operations {
    let snake = to_snake_case(op_id)
    let handler_path = project_dir + "/src/handlers/" + snake + ".mbt"
    if @fs.path_exists(handler_path) {
      ok += 1
    } else {
      println(
        "  missing handler: src/handlers/" +
        snake +
        ".mbt  (operation: " +
        op_id +
        ")",
      )
      missing += 1
    }
  }
  if missing > 0 {
    println(
      "check: " +
      missing.to_string() +
      " missing handler(s), " +
      ok.to_string() +
      " ok",
    )
    @sys.exit(1)
  } else {
    println("check: all " + ok.to_string() + " handlers present \u2713")
  }
}

///|
fn run_diff(args : Array[String]) -> Unit {
  let (spec_path, project_dir) = match parse_spec_and_project(args) {
    Ok(pair) => pair
    Err(msg) => {
      println(msg)
      @sys.exit(1)
      ("", "")
    }
  }
  let spec_raw = @fs.read_file_to_string(spec_path) catch {
    err => {
      fail_with_message("Failed to read spec: ", debug_string(err))
      ""
    }
  }
  let ir = parse_openapi(spec_raw) catch {
    err => {
      fail_with_message("Failed to parse spec: ", debug_string(err))
      { title: "", version: "", schemas: [], operations: [] }
    }
  }
  let current_ops : Array[String] = ir.operations.map(fn(op) { op.operation_id })
  let state_path = project_dir + "/.mapi/state.json"
  let previous_ops : Array[String] = if @fs.path_exists(state_path) {
    let raw = @fs.read_file_to_string(state_path) catch { _err => "{}" }
    parse_state_operations(raw)
  } else {
    []
  }
  let added = current_ops.filter(fn(op) { !previous_ops.contains(op) })
  let removed = previous_ops.filter(fn(op) { !current_ops.contains(op) })
  let unchanged = current_ops.filter(fn(op) { previous_ops.contains(op) })
  if added.is_empty() && removed.is_empty() {
    println(
      "diff: no changes detected (" +
      unchanged.length().to_string() +
      " operations unchanged)",
    )
    return
  }
  for op in added {
    println(
      "  + " + op + "  (new handler stub will be created on next generate)",
    )
  }
  for op in removed {
    println(
      "  - " + op + "  (orphaned handler \u2014 run generate to see warning)",
    )
  }
  for op in unchanged {
    println("    " + op)
  }
  println(
    "diff: +" +
    added.length().to_string() +
    " -" +
    removed.length().to_string() +
    " =" +
    unchanged.length().to_string(),
  )
}

///|
fn run_doctor(args : Array[String]) -> Unit {
  let mut project_dir : String? = None
  let mut spec_path : String? = None
  let mut index = 0
  while index < args.length() {
    let current = args[index]
    if index + 1 >= args.length() {
      println("Missing value for option: " + current)
      @sys.exit(1)
      return
    }
    let value = args[index + 1]
    match current {
      "--project" => project_dir = Some(value)
      "--spec" => spec_path = Some(value)
      _ => {
        println("Unknown option: " + current)
        @sys.exit(1)
        return
      }
    }
    index += 2
  }
  let mut all_ok = true
  let moon_ok = @fs.path_exists("/usr/local/bin/moon") ||
    @fs.path_exists("/usr/bin/moon") ||
    @fs.path_exists("/opt/homebrew/bin/moon")
  if moon_ok {
    println("  [ok]   moon CLI found")
  } else {
    println(
      "  [warn] moon CLI not found in common paths \u2014 make sure it is on PATH",
    )
    all_ok = false
  }
  match project_dir {
    Some(dir) => {
      let mod_path = dir + "/moon.mod.json"
      if @fs.path_exists(mod_path) {
        println("  [ok]   moon.mod.json found in " + dir)
      } else {
        println("  [error] moon.mod.json not found in " + dir)
        all_ok = false
      }
      let state_path = dir + "/.mapi/state.json"
      if @fs.path_exists(state_path) {
        println("  [ok]   .mapi/state.json found in " + dir)
      } else {
        println(
          "  [warn] .mapi/state.json not found \u2014 run `mapi init` or `mapi generate` first",
        )
        all_ok = false
      }
    }
    None => ()
  }
  match spec_path {
    Some(path) =>
      if !@fs.path_exists(path) {
        println("  [error] Spec file not found: " + path)
        all_ok = false
      } else {
        let raw = @fs.read_file_to_string(path) catch {
          _err => {
            println("  [error] Cannot read spec: " + path)
            all_ok = false
            ""
          }
        }
        if !raw.is_empty() {
          let result = try {
            let parsed = parse_openapi(raw)
            Ok(parsed)
          } catch {
            _err => Err(())
          }
          match result {
            Ok(_) => println("  [ok]   spec parsed successfully: " + path)
            Err(_) => {
              println("  [error] spec is not valid OpenAPI 3.0 JSON: " + path)
              all_ok = false
            }
          }
        }
      }
    None => ()
  }
  if all_ok {
    println("doctor: all checks passed \u2713")
  } else {
    println("doctor: some checks failed \u2014 see above")
    @sys.exit(1)
  }
}

///|
fn parse_state_operations(raw : String) -> Array[String] {
  let ops : Array[String] = []
  let marker = "\"operations\": ["
  match raw.find(marker) {
    None => ops
    Some(start) => {
      let after = start + marker.length()
      match raw[after:].find("]") {
        None => ops
        Some(end_rel) => {
          let array_content = raw[after:after + end_rel]
          for part in array_content.split(",") {
            let s = part
              .to_string()
              .trim()
              .trim_start(chars="\"")
              .trim_end(chars="\"")
              .to_string()
            if !s.is_empty() {
              ops.push(s)
            }
          }
          ops
        }
      }
    }
  }
}

///|
fn to_snake_case(s : String) -> String {
  let builder = StringBuilder::new()
  let chars = s.to_array()
  for i, ch in chars {
    if ch >= 'A' && ch <= 'Z' {
      if i > 0 {
        builder.write_char('_')
      }
      builder.write_char(
        (ch.to_int() + ('a'.to_int() - 'A'.to_int())).unsafe_to_char(),
      )
    } else {
      builder.write_char(ch)
    }
  }
  builder.to_string()
}
