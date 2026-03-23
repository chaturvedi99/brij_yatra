use redis::aio::ConnectionManager;
use sqlx::PgPool;
use std::sync::Arc;

use crate::auth::firebase::FirebaseJwksCache;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub redis: Option<ConnectionManager>,
    pub firebase_project_id: Arc<String>,
    pub dev_bypass_auth: bool,
    pub public_api_base_url: Arc<String>,
    pub jwks: Arc<tokio::sync::RwLock<FirebaseJwksCache>>,
    pub cors_allowed_origins: Vec<String>,
}
