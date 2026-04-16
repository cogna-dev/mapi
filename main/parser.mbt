///|
suberror ParseError {
  InvalidSpec(String)
} derive(Debug, Eq)

///|
fn parse_openapi(json_str : String) -> ApiIR raise ParseError {
  let doc = @openapi.parse(json_str) catch {
    err => raise InvalidSpec(err.to_string())
  }
  {
    title: doc.info.title,
    version: doc.info.version,
    schemas: translate_schemas(doc),
    operations: translate_operations(doc),
  }
}

///|
fn translate_schemas(
  doc : @openapi.OpenApiDocument,
) -> Array[SchemaIR] raise ParseError {
  match doc.components {
    None => []
    Some(components) =>
      match components.schemas {
        None => []
        Some(schemas_map) => {
          let schemas : Array[SchemaIR] = []
          for name, schema_or_ref in schemas_map {
            schemas.push(translate_schema(name, schema_or_ref))
          }
          schemas
        }
      }
  }
}

///|
fn translate_schema(
  name : String,
  schema_or_ref : @openapi.SchemaOrRef,
) -> SchemaIR raise ParseError {
  let pascal_name = pascal_case(name)
  match schema_or_ref {
    Ref(r) =>
      {
        name: pascal_name,
        kind: Primitive(ref_name_from_ref(r.ref_)),
        fields: [],
      }
    SchemaValue(schema) =>
      match schema.enum_ {
        Some(enum_values) => {
          let variants : Array[String] = []
          for value in enum_values {
            match value {
              String(s) => variants.push(s)
              _ => ()
            }
          }
          { name: pascal_name, kind: StringEnum(variants), fields: [] }
        }
        None => {
          let type_str = match schema.type_ {
            Some(Single(t)) => t
            _ => "object"
          }
          match type_str {
            "object" => {
              let required_set = match schema.required {
                Some(r) => r
                None => []
              }
              let fields = translate_schema_fields(schema, required_set)
              { name: pascal_name, kind: Object, fields }
            }
            _ => {
              let moonbit_type = schema_type_to_moonbit(schema, pascal_name)
              { name: pascal_name, kind: Primitive(moonbit_type), fields: [] }
            }
          }
        }
      }
  }
}

///|
fn translate_schema_fields(
  schema : @openapi.Schema,
  required_set : Array[String],
) -> Array[FieldIR] raise ParseError {
  match schema.properties {
    None => []
    Some(properties) => {
      let fields : Array[FieldIR] = []
      for field_name, field_schema_or_ref in properties {
        let field : FieldIR = {
          name: camel_case(field_name),
          moonbit_type: schema_or_ref_to_type(
            field_schema_or_ref,
            pascal_case(field_name),
          ),
          required: required_set.contains(field_name),
        }
        fields.push(field)
      }
      fields
    }
  }
}

///|
fn translate_operations(
  doc : @openapi.OpenApiDocument,
) -> Array[OperationIR] raise ParseError {
  let operations : Array[OperationIR] = []
  for path, path_item in doc.paths {
    if path_item.get is Some(op) {
      operations.push(translate_operation(path, "get", op))
    }
    if path_item.put is Some(op) {
      operations.push(translate_operation(path, "put", op))
    }
    if path_item.post is Some(op) {
      operations.push(translate_operation(path, "post", op))
    }
    if path_item.delete is Some(op) {
      operations.push(translate_operation(path, "delete", op))
    }
    if path_item.options is Some(op) {
      operations.push(translate_operation(path, "options", op))
    }
    if path_item.head is Some(op) {
      operations.push(translate_operation(path, "head", op))
    }
    if path_item.patch is Some(op) {
      operations.push(translate_operation(path, "patch", op))
    }
  }
  operations
}

///|
fn translate_operation(
  path : String,
  http_method_str : String,
  op : @openapi.Operation,
) -> OperationIR raise ParseError {
  let operation_id = match op.operation_id {
    Some(id) => id
    None =>
      raise InvalidSpec(
        "operation at " + http_method_str + " " + path + " missing operationId",
      )
  }
  let (path_params, query_params) = translate_parameters(
    match op.parameters {
      Some(p) => p
      None => []
    },
  )
  let (response_type, success_status) = translate_response(op.responses)
  {
    operation_id,
    snake_id: snake_case(operation_id),
    http_method: http_method_variant(http_method_str),
    path,
    path_params,
    query_params,
    request_body_type: translate_request_body(op.request_body),
    response_type,
    success_status,
  }
}

///|
fn translate_parameters(
  params : Array[@openapi.ParameterOrRef],
) -> (Array[ParamIR], Array[ParamIR]) raise ParseError {
  let path_params : Array[ParamIR] = []
  let query_params : Array[ParamIR] = []
  for param_or_ref in params {
    match param_or_ref {
      Ref(_) => ()
      ParameterValue(p) => {
        let moonbit_type = match p.schema {
          Some(s) => schema_or_ref_to_type(s, pascal_case(p.name))
          None => "String"
        }
        let param : ParamIR = {
          name: camel_case(p.name),
          moonbit_type,
          required: match p.required {
            Some(r) => r
            None => false
          },
        }
        match p.in_ {
          Path => path_params.push(param)
          Query => query_params.push(param)
          _ => ()
        }
      }
    }
  }
  (path_params, query_params)
}

///|
fn translate_request_body(
  rb_or_ref : @openapi.RequestBodyOrRef?,
) -> String? raise ParseError {
  match rb_or_ref {
    None => None
    Some(Ref(_)) => None
    Some(RequestBodyValue(rb)) =>
      match rb.content.get("application/json") {
        None => None
        Some(media) =>
          match media.schema {
            None => None
            Some(s) => Some(schema_or_ref_to_type(s, "Json"))
          }
      }
  }
}

///|
fn translate_response(
  responses : @openapi.Responses,
) -> (String, String?) raise ParseError {
  let preferred_statuses = ["200", "201", "202", "203", "204", "205", "206"]
  for status in preferred_statuses {
    match responses.by_status.get(status) {
      Some(response_or_ref) => {
        let response_type = response_type_from_response(response_or_ref)
        return (response_type, Some(status))
      }
      None => ()
    }
  }
  for status, response_or_ref in responses.by_status {
    if status.has_prefix("2") {
      let response_type = response_type_from_response(response_or_ref)
      return (response_type, Some(status))
    }
  }
  match responses.default {
    Some(response_or_ref) =>
      (response_type_from_response(response_or_ref), None)
    None => ("Unit", None)
  }
}

///|
fn response_type_from_response(
  response_or_ref : @openapi.ResponseOrRef,
) -> String raise ParseError {
  match response_or_ref {
    Ref(_) => "Unit"
    ResponseValue(r) =>
      match r.content {
        None => "Unit"
        Some(content) =>
          match content.get("application/json") {
            None => "Unit"
            Some(media) =>
              match media.schema {
                None => "Unit"
                Some(s) => schema_or_ref_to_type(s, "Json")
              }
          }
      }
  }
}

///|
fn schema_or_ref_to_type(
  schema_or_ref : @openapi.SchemaOrRef,
  fallback_name : String,
) -> String raise ParseError {
  match schema_or_ref {
    Ref(r) => ref_name_from_ref(r.ref_)
    SchemaValue(schema) => schema_type_to_moonbit(schema, fallback_name)
  }
}

///|
fn schema_type_to_moonbit(
  schema : @openapi.Schema,
  fallback_name : String,
) -> String raise ParseError {
  let type_str = match schema.type_ {
    Some(Single(t)) => t
    _ => "object"
  }
  match type_str {
    "string" => "String"
    "integer" => "Int"
    "number" => "Double"
    "boolean" => "Bool"
    "array" =>
      match schema.items {
        Some(items) =>
          "Array[" + schema_or_ref_to_type(items, fallback_name) + "]"
        None => "Array[Json]"
      }
    "object" => fallback_name
    _ => "Json"
  }
}

///|
fn ref_name_from_ref(ref_path : String) -> String raise ParseError {
  let segments = ref_path.split("/").to_array()
  match segments.last() {
    Some(name) => pascal_case(name.to_string())
    None => raise InvalidSpec("invalid $ref: " + ref_path)
  }
}

///|
fn http_method_variant(method_name : String) -> String raise ParseError {
  match method_name {
    "get" => "Get"
    "post" => "Post"
    "put" => "Put"
    "patch" => "Patch"
    "delete" => "Delete"
    "head" => "Head"
    "options" => "Options"
    _ => raise InvalidSpec("unsupported HTTP method: " + method_name)
  }
}

///|
fn pascal_case(value : String) -> String {
  join_pascal_words(split_words(value))
}

///|
fn camel_case(value : String) -> String {
  let words = split_words(value)
  match words {
    [] => ""
    [first, .. rest] => {
      let builder = StringBuilder::new()
      builder.write_string(first.to_lower())
      for word in rest {
        builder.write_string(capitalize_word(word))
      }
      builder.to_string()
    }
  }
}

///|
fn snake_case(value : String) -> String {
  let normalized = split_words(value).map(word => word.to_lower())
  normalized.join("_")
}

///|
fn split_words(value : String) -> Array[String] {
  let words : Array[String] = []
  let current = StringBuilder::new()
  let mut previous_is_lower = false
  for ch in value {
    if is_separator(ch) {
      flush_word(words, current)
      previous_is_lower = false
    } else if ch.is_ascii_uppercase() && previous_is_lower {
      flush_word(words, current)
      current.write_char(ch)
      previous_is_lower = false
    } else {
      current.write_char(ch)
      previous_is_lower = ch.is_ascii_lowercase()
    }
  }
  flush_word(words, current)
  words
}

///|
fn is_separator(ch : Char) -> Bool {
  ch == '_' || ch == '-' || ch == ' ' || ch == '/'
}

///|
fn flush_word(words : Array[String], current : StringBuilder) -> Unit {
  let word = current.to_string()
  if !word.is_empty() {
    words.push(word)
  }
  current.reset()
}

///|
fn join_pascal_words(words : Array[String]) -> String {
  let builder = StringBuilder::new()
  for word in words {
    builder.write_string(capitalize_word(word))
  }
  builder.to_string()
}

///|
fn capitalize_word(word : String) -> String {
  if word.is_empty() {
    word
  } else {
    let lower = word.to_lower()
    let builder = StringBuilder::new()
    let mut first = true
    for ch in lower {
      if first {
        builder.write_char(ch.to_ascii_uppercase())
        first = false
      } else {
        builder.write_char(ch)
      }
    }
    builder.to_string()
  }
}
