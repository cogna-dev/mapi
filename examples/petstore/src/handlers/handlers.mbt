// User-owned file. Safe from regeneration.

///|
pub fn list_pets(
  _ctx : @lib.RequestContext,
  _input : @generated.ListPetsInput,
) -> Result[@generated.ListPetsResponse, @lib.AppError] {
  Ok(
    @generated.ListPetsResponse::Ok([
      { id: 1, name: "fubao" },
      { id: 2, name: "huahua" },
    ]),
  )
}

///|
pub fn create_pet(
  _ctx : @lib.RequestContext,
  input : @generated.CreatePetInput,
) -> Result[@generated.CreatePetResponse, @lib.AppError] {
  Ok(@generated.CreatePetResponse::Ok({ id: 42, name: input.body.name }))
}

///|
pub fn get_pet_by_id(
  _ctx : @lib.RequestContext,
  input : @generated.GetPetByIdInput,
) -> Result[@generated.GetPetByIdResponse, @lib.AppError] {
  if input.id == 1 {
    Ok(@generated.GetPetByIdResponse::Ok({ id: 1, name: "fubao" }))
  } else {
    Err(@lib.AppError::NotFound("pet not found: " + input.id.to_string()))
  }
}
