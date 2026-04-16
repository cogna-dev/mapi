use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    routing::get,
    Router,
};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};
use tokio::net::TcpListener;

#[derive(Clone, Serialize)]
struct Pet {
    id: u64,
    name: String,
}

#[derive(Deserialize)]
struct CreatePet {
    name: String,
}

#[derive(Clone)]
struct AppState {
    pets: Arc<Mutex<HashMap<u64, Pet>>>,
    next_id: Arc<Mutex<u64>>,
}

impl AppState {
    fn new() -> Self {
        let mut pets = HashMap::new();
        pets.insert(1, Pet { id: 1, name: "initial-pet".into() });
        Self {
            pets: Arc::new(Mutex::new(pets)),
            next_id: Arc::new(Mutex::new(2)),
        }
    }
}

async fn list_pets(State(state): State<AppState>) -> Json<Vec<Pet>> {
    let pets = state.pets.lock().unwrap();
    Json(pets.values().cloned().collect())
}

async fn create_pet(
    State(state): State<AppState>,
    Json(body): Json<CreatePet>,
) -> (StatusCode, Json<Pet>) {
    let mut next = state.next_id.lock().unwrap();
    let id = *next;
    *next += 1;
    drop(next);

    let pet = Pet { id, name: body.name };
    state.pets.lock().unwrap().insert(id, pet.clone());
    (StatusCode::CREATED, Json(pet))
}

async fn get_pet(
    State(state): State<AppState>,
    Path(id): Path<u64>,
) -> Result<Json<Pet>, StatusCode> {
    let pets = state.pets.lock().unwrap();
    pets.get(&id).cloned().map(Json).ok_or(StatusCode::NOT_FOUND)
}

#[tokio::main]
async fn main() {
    let state = AppState::new();
    let app = Router::new()
        .route("/pets", get(list_pets).post(create_pet))
        .route("/pets/:id", get(get_pet))
        .with_state(state);

    let listener = TcpListener::bind("0.0.0.0:8082").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
