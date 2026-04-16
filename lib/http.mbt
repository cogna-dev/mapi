///|
pub type PathParams = Map[String, String]

///|
pub type QueryParams = Map[String, Array[String]]

///|
pub type HeaderMap = Map[String, String]

///|
pub(all) struct RequestEnvelope {
  http_method : HttpMethod
  path : String
  query : Map[String, Array[String]]
  headers : Map[String, String]
  body : Bytes?
}

///|
pub(all) struct ResponseEnvelope {
  status : Int
  headers : Map[String, String]
  body : Bytes?
}

///|
pub(all) struct RequestContext {
  request_id : String
  matched_operation : String
}
