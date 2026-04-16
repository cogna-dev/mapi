///|
pub(all) enum HttpMethod {
  Get
  Post
  Put
  Patch
  Delete
  Head
  Options
} derive(Eq, Debug)

///|
pub(all) suberror DecodeError {
  MissingRequiredParam(String)
  InvalidParamType(String, String)
  InvalidBody(String)
} derive(Eq, Debug)

///|
pub(all) suberror AppError {
  NotFound(String)
  BadRequest(String)
  Unauthorized
  Forbidden
  Internal(String)
} derive(Eq, Debug)

///|
pub(all) suberror InternalError {
  RouterError(String)
  EncodingError(String)
} derive(Eq, Debug)
