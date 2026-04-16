// User-owned file. Safe from regeneration.

///|
fn main {
  let api_handlers : @generated.ApiHandlers = {
    list_pets: @handlers.list_pets,
    create_pet: @handlers.create_pet,
    get_pet_by_id: @handlers.get_pet_by_id,
  }
  let app = @generated.make_app(api_handlers)
  let host = @lib.InMemoryHost::new(app)
  let resp = host.request(@lib.HttpMethod::Get, "/pets", None, None, None)
  println("GET /pets -> " + resp.status.to_string())
}
