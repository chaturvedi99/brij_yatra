use axum::{
    extract::{Path, State},
    routing::post,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

use crate::group_access::ensure_group_member;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/media/presign", post(presign))
        .route("/media/assets", post(register_asset))
        .route("/groups/:id/memory/compile", post(queue_memory_compile))
}

#[derive(Deserialize)]
struct PresignBody {
    filename: String,
    #[serde(default)]
    content_type: String,
}

#[derive(Serialize)]
struct PresignResponse {
    asset_id: Uuid,
    upload_url: String,
    public_url: String,
}

async fn presign(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<PresignBody>,
) -> ApiResult<Json<PresignResponse>> {
    let id = Uuid::new_v4();
    let base = state.public_api_base_url.as_str().trim_end_matches('/');
    let upload_url = format!("{base}/media/upload/{id}?token=stub");
    let public_url = format!("{base}/media/public/{id}");
    let _ = (user.id, body.filename, body.content_type);
    Ok(Json(PresignResponse {
        asset_id: id,
        upload_url,
        public_url,
    }))
}

#[derive(Deserialize)]
struct RegisterAssetBody {
    group_id: Uuid,
    #[serde(default)]
    kind: String,
    storage_url: String,
    #[serde(default)]
    theme_itinerary_id: Option<Uuid>,
    #[serde(default)]
    meta_json: Value,
}

async fn register_asset(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<RegisterAssetBody>,
) -> ApiResult<Json<Value>> {
    let _ = ensure_group_member(&state.pool, body.group_id, user.id).await?;

    let kind = if body.kind.is_empty() {
        "image"
    } else {
        body.kind.as_str()
    };

    let aid = sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO media_assets (group_id, uploaded_by, kind, storage_url, theme_itinerary_id, meta_json)
        VALUES ($1, $2, $3::media_kind, $4, $5, $6)
        RETURNING id
        "#,
    )
    .bind(body.group_id)
    .bind(user.id)
    .bind(kind)
    .bind(&body.storage_url)
    .bind(body.theme_itinerary_id)
    .bind(&body.meta_json)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(json!({ "id": aid })))
}

async fn queue_memory_compile(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Value>> {
    let _ = ensure_group_member(&state.pool, id, user.id).await?;

    sqlx::query(
        r#"
        INSERT INTO memory_albums (group_id, status, summary_json)
        VALUES ($1, 'pending', '{}'::jsonb)
        ON CONFLICT (group_id) DO UPDATE SET status = 'pending', updated_at = now()
        "#,
    )
    .bind(id)
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    sqlx::query(
        r#"
        INSERT INTO trip_events (group_id, event_type, payload_json, created_by)
        VALUES ($1, 'memory_job_queued', '{}'::jsonb, $2)
        "#,
    )
    .bind(id)
    .bind(user.id)
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(json!({ "status": "queued" })))
}
