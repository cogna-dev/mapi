///|
pub(all) struct InMemoryHost {
  app : App
}

///|
pub fn InMemoryHost::new(app : App) -> InMemoryHost {
  { app, }
}

///|
pub fn InMemoryHost::request(
  self : InMemoryHost,
  http_method : HttpMethod,
  path : String,
  body : Bytes?,
  headers : Map[String, String]?,
  query : Map[String, Array[String]]?,
) -> ResponseEnvelope {
  let req : RequestEnvelope = {
    http_method,
    path,
    query: query.unwrap_or_default(),
    headers: headers.unwrap_or_default(),
    body,
  }
  self.app.serve(req)
}
