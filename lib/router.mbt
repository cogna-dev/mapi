///|
pub(all) struct Route {
  http_method : HttpMethod
  pattern : String
  handler : (RequestContext, RequestEnvelope, Map[String, String]) -> ResponseEnvelope
}

///|
pub(all) struct Router {
  routes : Array[Route]
}

///|
priv struct RouteMatch {
  route : Route
  params : Map[String, String]
}

///|
fn split_path_segments(path : String) -> Array[String] {
  path
  .split("/")
  .filter_map(segment => {
    if segment.is_empty() {
      None
    } else {
      Some(segment.to_string())
    }
  })
  .to_array()
}

///|
fn is_path_param_segment(segment : String) -> Bool {
  segment.has_prefix("{") && segment.has_suffix("}") && segment.length() >= 2
}

///|
fn path_param_name(segment : String) -> String {
  segment.sub(start=1, end=segment.length() - 1).to_string()
}

///|
fn match_route_pattern(pattern : String, path : String) -> Map[String, String]? {
  let pattern_segments = split_path_segments(pattern)
  let path_segments = split_path_segments(path)
  if pattern_segments.length() != path_segments.length() {
    None
  } else {
    let params = Map::new()
    for i in 0..<pattern_segments.length() {
      let pattern_segment = pattern_segments[i]
      let path_segment = path_segments[i]
      if is_path_param_segment(pattern_segment) {
        params[path_param_name(pattern_segment)] = path_segment
      } else if pattern_segment != path_segment {
        return None
      }
    }
    Some(params)
  }
}

///|
fn find_route_match(router : Router, req : RequestEnvelope) -> RouteMatch? {
  for route in router.routes {
    match match_route_pattern(route.pattern, req.path) {
      Some(params) if route.http_method == req.http_method =>
        return Some({ route, params })
      _ => ()
    }
  }
  None
}

///|
fn has_path_match(router : Router, path : String) -> Bool {
  router.routes.any(route => match_route_pattern(route.pattern, path) is Some(_))
}

///|
fn request_id_from_headers(headers : Map[String, String]) -> String {
  headers.get("x-request-id").unwrap_or("")
}

///|
fn not_found_response(path : String) -> ResponseEnvelope {
  {
    status: 404,
    headers: Map::new(),
    body: Some(@utf8.encode("Not found: " + path)),
  }
}

///|
fn method_not_allowed_response() -> ResponseEnvelope {
  { status: 405, headers: Map::new(), body: None }
}

///|
pub fn Router::new() -> Router {
  { routes: [] }
}

///|
pub fn Router::add(self : Router, route : Route) -> Unit {
  self.routes.push(route)
}

///|
pub fn Router::dispatch(
  self : Router,
  req : RequestEnvelope,
) -> ResponseEnvelope {
  match find_route_match(self, req) {
    Some(route_match) => {
      let ctx : RequestContext = {
        request_id: request_id_from_headers(req.headers),
        matched_operation: route_match.route.pattern,
      }
      (route_match.route.handler)(ctx, req, route_match.params)
    }
    None =>
      if has_path_match(self, req.path) {
        method_not_allowed_response()
      } else {
        not_found_response(req.path)
      }
  }
}
