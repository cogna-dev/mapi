///|
struct Pet {
  id : Int
  name : String
} derive(ToJson, FromJson)

///|
struct CreatePetBody {
  name : String
} derive(ToJson, FromJson)

///|
let pets_store : Ref[Map[Int, Pet]] = Ref::new({
  1: { id: 1, name: "initial-pet" },
})

///|
let next_id : Ref[Int] = Ref::new(2)

///|
let listen_addr : String = "0.0.0.0:8083"

///|
fn json_response(status : Int, body : Json) -> @lib.ResponseEnvelope {
  {
    status,
    headers: { "content-type": "application/json" },
    body: Some(@utf8.encode(body.stringify())),
  }
}

///|
fn error_response(status : Int, message : String) -> @lib.ResponseEnvelope {
  json_response(status, { "error": message.to_json() })
}

///|
fn reason_phrase(status : Int) -> String {
  match status {
    200 => "OK"
    201 => "Created"
    400 => "Bad Request"
    404 => "Not Found"
    405 => "Method Not Allowed"
    _ => "OK"
  }
}

///|
fn list_handler(
  _ctx : @lib.RequestContext,
  _req : @lib.RequestEnvelope,
  _params : Map[String, String],
) -> @lib.ResponseEnvelope {
  json_response(200, pets_store.val.values().to_array().to_json())
}

///|
fn create_handler(
  _ctx : @lib.RequestContext,
  req : @lib.RequestEnvelope,
  _params : Map[String, String],
) -> @lib.ResponseEnvelope {
  let raw_body = match req.body {
    Some(body) => @utf8.decode_lossy(body.view())
    None => ""
  }
  let payload : CreatePetBody = @json.from_json(@json.parse(raw_body)) catch {
    _ => return error_response(400, "invalid body")
  }
  if payload.name.trim().is_empty() {
    return error_response(400, "name is required")
  }
  let id = next_id.val
  next_id.val = id + 1
  let pet : Pet = { id, name: payload.name }
  pets_store.val[id] = pet
  json_response(201, pet.to_json())
}

///|
fn get_handler(
  _ctx : @lib.RequestContext,
  _req : @lib.RequestEnvelope,
  params : Map[String, String],
) -> @lib.ResponseEnvelope {
  let id_str = match params.get("id") {
    Some(id) => id
    None => return error_response(400, "missing id")
  }
  let id : Int = @strconv.from_str(id_str) catch {
    _ => return error_response(400, "invalid id")
  }
  match pets_store.val.get(id) {
    Some(pet) => json_response(200, pet.to_json())
    None => error_response(404, "not found")
  }
}

///|
fn build_app() -> @lib.App {
  let router = @lib.Router::new()
  router.add({
    http_method: @lib.HttpMethod::Get,
    pattern: "/pets",
    handler: list_handler,
  })
  router.add({
    http_method: @lib.HttpMethod::Post,
    pattern: "/pets",
    handler: create_handler,
  })
  router.add({
    http_method: @lib.HttpMethod::Get,
    pattern: "/pets/{id}",
    handler: get_handler,
  })
  @lib.App::new(router)
}

///|
async fn write_response(
  conn : @http.ServerConnection,
  resp : @lib.ResponseEnvelope,
) -> Unit {
  conn.send_response(
    resp.status,
    reason_phrase(resp.status),
    extra_headers=resp.headers,
  )
  match resp.body {
    Some(body) => conn.write(@utf8.decode_lossy(body.view()))
    None => ()
  }
  conn.end_response()
}

///|
async fn main {
  let app = build_app()
  let server = @http.Server(@socket.Addr::parse(listen_addr), reuse_addr=true)
  println("mbt-mapi benchmark server listening on http://\{listen_addr}")
  server.run_forever((request, body, conn) => {
    let raw_body = body.read_all().text() catch { _ => "" }
    let http_method = match request.meth {
      Get => @lib.HttpMethod::Get
      Post => @lib.HttpMethod::Post
      Put => @lib.HttpMethod::Put
      Patch => @lib.HttpMethod::Patch
      Delete => @lib.HttpMethod::Delete
      Head => @lib.HttpMethod::Head
      Options => @lib.HttpMethod::Options
      _ => @lib.HttpMethod::Get
    }
    let req : @lib.RequestEnvelope = {
      http_method,
      path: request.path,
      query: Map::new(),
      headers: request.headers,
      body: if raw_body.is_empty() {
        None
      } else {
        Some(@utf8.encode(raw_body))
      },
    }
    write_response(conn, app.serve(req))
  }) catch {
    err => println("mbt-mapi benchmark server terminated: \{err}")
  }
}
