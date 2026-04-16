///|
pub(all) struct ApiIR {
  title : String
  version : String
  schemas : Array[SchemaIR]
  operations : Array[OperationIR]
}

///|
pub(all) struct SchemaIR {
  name : String
  kind : SchemaKind
  fields : Array[FieldIR]
}

///|
pub(all) struct FieldIR {
  name : String
  moonbit_type : String
  required : Bool
}

///|
pub(all) enum SchemaKind {
  Object
  StringEnum(Array[String])
  Primitive(String)
}

///|
pub(all) struct OperationIR {
  operation_id : String
  snake_id : String
  http_method : String
  path : String
  path_params : Array[ParamIR]
  query_params : Array[ParamIR]
  request_body_type : String?
  response_type : String
  success_status : String?
}

///|
pub(all) struct ParamIR {
  name : String
  moonbit_type : String
  required : Bool
}
