///|
pub type Middleware = (
  (RequestContext, RequestEnvelope, Map[String, String]) -> ResponseEnvelope,
) -> (RequestContext, RequestEnvelope, Map[String, String]) -> ResponseEnvelope

///|
pub(all) struct App {
  router : Router
  middlewares : Array[Middleware]
}

///|
fn build_request_context(
  req : RequestEnvelope,
  route : Route,
) -> RequestContext {
  {
    request_id: request_id_from_headers(req.headers),
    matched_operation: route.pattern,
  }
}

///|
fn compose_middlewares(
  middlewares : Array[Middleware],
  handler : (RequestContext, RequestEnvelope, Map[String, String]) -> ResponseEnvelope,
) -> (RequestContext, RequestEnvelope, Map[String, String]) -> ResponseEnvelope {
  let mut pipeline = handler
  let total = middlewares.length()
  for i in 0..<total {
    pipeline = middlewares[total - i - 1](pipeline)
  }
  pipeline
}

///|
pub fn App::new(router : Router) -> App {
  { router, middlewares: [] }
}

///|
pub fn App::use_middleware(self : App, m : Middleware) -> Unit {
  self.middlewares.push(m)
}

///|
pub fn App::serve(self : App, req : RequestEnvelope) -> ResponseEnvelope {
  match find_route_match(self.router, req) {
    Some(route_match) => {
      let ctx = build_request_context(req, route_match.route)
      let pipeline = compose_middlewares(
        self.middlewares,
        route_match.route.handler,
      )
      pipeline(ctx, req, route_match.params)
    }
    None =>
      if has_path_match(self.router, req.path) {
        method_not_allowed_response()
      } else {
        not_found_response(req.path)
      }
  }
}
