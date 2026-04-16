///|
suberror WriteError {
  FileSystem(String)
} derive(Debug, Eq)

///|
fn fs_error_message(err : &@debug.Debug) -> String {
  @debug.render(@debug.to_repr(err))
}

///|
fn write_project(
  files : Map[String, String],
  out_dir : String,
  overwrite_generated : Bool,
) -> Unit raise WriteError {
  ensure_dir(out_dir)
  for entry in files {
    let relative_path = entry.0
    let content = entry.1
    let absolute_path = join_path(out_dir, relative_path)
    let is_generated_file = is_generated_path(relative_path)
    let is_user_owned = is_user_owned_path(relative_path)
    ensure_parent_dirs(absolute_path)
    if @fs.path_exists(absolute_path) {
      if is_generated_file && overwrite_generated {
        write_file(absolute_path, content)
      } else if !is_user_owned {
        write_file(absolute_path, content)
      }
    } else {
      write_file(absolute_path, content)
    }
  }
}

///|
fn write_state(
  ir : ApiIR,
  spec_path : String,
  out_dir : String,
) -> Unit raise WriteError {
  let state_dir = join_path(out_dir, ".mapi")
  ensure_dir(state_dir)
  let operation_ids = ir.operations.map(fn(op) { "\"" + op.operation_id + "\"" })
  let ops_json = "[" + operation_ids.join(", ") + "]"
  let builder = StringBuilder::new()
  builder.write_string("{\n")
  builder.write_string("  \"cli_version\": \"0.1.0\",\n")
  builder.write_string("  \"codegen_schema_version\": \"1\",\n")
  builder.write_string("  \"spec_path\": \"")
  builder.write_string(spec_path)
  builder.write_string("\",\n")
  builder.write_string("  \"operations\": ")
  builder.write_string(ops_json)
  builder.write_string("\n}\n")
  write_file(join_path(state_dir, "state.json"), builder.to_string())
}

///|
fn ensure_parent_dirs(path : String) -> Unit raise WriteError {
  let segments = path.split("/").to_array()
  if segments.length() <= 1 {
    ()
  } else {
    let current = StringBuilder::new()
    for i in 0..<(segments.length() - 1) {
      let segment = segments[i]
      if !segment.is_empty() {
        if current.to_string().is_empty() {
          current.write_string(segment.to_string())
        } else {
          current.write_char('/')
          current.write_string(segment.to_string())
        }
        ensure_dir(current.to_string())
      }
    }
  }
}

///|
fn ensure_dir(path : String) -> Unit raise WriteError {
  if !@fs.path_exists(path) {
    @fs.create_dir(path) catch {
      err => raise FileSystem(fs_error_message(err))
    }
  }
}

///|
fn write_file(path : String, content : String) -> Unit raise WriteError {
  @fs.write_string_to_file(path, content) catch {
    err => raise FileSystem(fs_error_message(err))
  }
}

///|
fn join_path(base : String, relative : String) -> String {
  if base.is_empty() {
    relative
  } else if relative.is_empty() {
    base
  } else if base.has_suffix("/") {
    base + relative
  } else {
    base + "/" + relative
  }
}

///|
fn is_generated_path(relative_path : String) -> Bool {
  relative_path == "moon.mod.json" || relative_path.has_prefix("src/generated/")
}

///|
fn is_user_owned_path(relative_path : String) -> Bool {
  relative_path.has_prefix("src/handlers/") ||
  relative_path.has_prefix("src/bootstrap/")
}
