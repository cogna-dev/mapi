///|
fn ok_response(status : Int, text : String) -> ResponseEnvelope {
  { status, headers: Map::new(), body: Some(@utf8.encode(text)) }
}

///|
fn make_request(http_method : HttpMethod, path : String) -> RequestEnvelope {
  { http_method, path, query: Map::new(), headers: Map::new(), body: None }
}

///|
test "http method enum variants exist" {
  let methods = [
    HttpMethod::Get,
    HttpMethod::Post,
    HttpMethod::Put,
    HttpMethod::Patch,
    HttpMethod::Delete,
    HttpMethod::Head,
    HttpMethod::Options,
  ]
  inspect(methods.length(), content="7")
}

///|
test "router dispatch returns 404 for unregistered path" {
  let router = Router::new()
  let response = router.dispatch(make_request(HttpMethod::Get, "/missing"))
  inspect(response.status, content="404")
}

///|
test "router dispatch returns 405 for wrong method" {
  let router = Router::new()
  router.add({
    http_method: HttpMethod::Get,
    pattern: "/pets",
    handler: (_, _, _) => ok_response(200, "pets"),
  })
  let response = router.dispatch(make_request(HttpMethod::Post, "/pets"))
  inspect(response.status, content="405")
}

///|
test "router dispatch returns handler response for correct route" {
  let router = Router::new()
  router.add({
    http_method: HttpMethod::Get,
    pattern: "/pets",
    handler: (_, _, _) => ok_response(200, "ok"),
  })
  let response = router.dispatch(make_request(HttpMethod::Get, "/pets"))
  inspect(response.status, content="200")
  inspect(response.body == Some(@utf8.encode("ok")), content="true")
}

///|
test "router extracts path params" {
  let router = Router::new()
  router.add({
    http_method: HttpMethod::Get,
    pattern: "/pets/{id}",
    handler: (_, _, params) => {
      ok_response(200, params.get("id").unwrap_or("missing"))
    },
  })
  let response = router.dispatch(make_request(HttpMethod::Get, "/pets/42"))
  inspect(response.status, content="200")
  inspect(response.body == Some(@utf8.encode("42")), content="true")
}

///|
test "in memory host request returns expected response" {
  let router = Router::new()
  router.add({
    http_method: HttpMethod::Post,
    pattern: "/echo",
    handler: (ctx, req, _) => {
      let prefix = if ctx.request_id.is_empty() {
        Bytes::default()
      } else {
        @utf8.encode(ctx.request_id + ":")
      }
      let body_bytes = req.body.unwrap_or_default()
      { status: 201, headers: Map::new(), body: Some(prefix + body_bytes) }
    },
  })
  let app = App::new(router)
  let host = InMemoryHost::new(app)
  let response = host.request(
    HttpMethod::Post,
    "/echo",
    Some(Bytes::from_array([b'h', b'i'])),
    Some({ "x-request-id": "req-123" }),
    None,
  )
  inspect(response.status, content="201")
  inspect(
    response.body ==
    Some(@utf8.encode("req-123:") + Bytes::from_array([b'h', b'i'])),
    content="true",
  )
}
