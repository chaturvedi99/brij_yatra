use axum::{
    extract::{Path, State},
    routing::get,
    Json, Router,
};
use redis::AsyncCommands;
use serde::Serialize;
use serde_json::Value;
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/themes", get(list_themes))
        .route("/themes/:slug", get(theme_detail))
        .route("/themes/:slug/itinerary", get(theme_itinerary))
}

#[derive(Serialize, sqlx::FromRow)]
struct ThemeRow {
    id: Uuid,
    slug: String,
    name: String,
    #[sqlx(rename = "kind")]
    kind: String,
    summary: String,
    hero_media: Value,
    config_version: i32,
    config_json: Value,
}

#[derive(Serialize)]
struct ThemeListItem {
    id: Uuid,
    slug: String,
    name: String,
    kind: String,
    summary: String,
    hero_media: Value,
    config_version: i32,
}

async fn list_themes(State(state): State<AppState>, _user: AuthUser) -> ApiResult<Json<Vec<ThemeListItem>>> {
    let rows = sqlx::query_as::<_, ThemeRow>(
        r#"
        SELECT id, slug, name, kind::text as kind, summary, hero_media, config_version, config_json
        FROM themes
        WHERE active = true AND deleted_at IS NULL
        ORDER BY name
        "#,
    )
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let out = rows
        .into_iter()
        .map(|r| ThemeListItem {
            id: r.id,
            slug: r.slug,
            name: r.name,
            kind: r.kind,
            summary: r.summary,
            hero_media: r.hero_media,
            config_version: r.config_version,
        })
        .collect();
    Ok(Json(out))
}

async fn theme_detail(
    State(state): State<AppState>,
    Path(slug): Path<String>,
    _user: AuthUser,
) -> ApiResult<Json<Value>> {
    let cache_key = format!("theme:{slug}");
    if let Some(ref redis) = state.redis {
        let mut conn = redis.clone();
        if let Ok(Some(cached)) = conn.get::<_, Option<String>>(&cache_key).await {
            if let Ok(v) = serde_json::from_str::<Value>(&cached) {
                return Ok(Json(v));
            }
        }
    }

    let row = sqlx::query_as::<_, ThemeRow>(
        r#"
        SELECT id, slug, name, kind::text as kind, summary, hero_media, config_version, config_json
        FROM themes
        WHERE slug = $1 AND active = true AND deleted_at IS NULL
        "#,
    )
    .bind(&slug)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?
    .ok_or(ApiError::NotFound)?;

    let v = serde_json::to_value(&row).map_err(|e| ApiError::Internal(e.into()))?;

    if let Some(ref redis) = state.redis {
        let mut conn = redis.clone();
        if let Ok(s) = serde_json::to_string(&v) {
            let _: Result<(), _> = conn.set_ex(&cache_key, s, 300).await;
        }
    }

    Ok(Json(v))
}

#[derive(Serialize, sqlx::FromRow)]
struct ItineraryRow {
    id: Uuid,
    day_no: i32,
    sequence: i32,
    stop_name: String,
    stop_type: String,
    description: String,
    ritual_info: Value,
    media_refs: Value,
    geo_location: Option<Value>,
    estimated_minutes: Option<i32>,
    place_id: Option<Uuid>,
}

async fn theme_itinerary(
    State(state): State<AppState>,
    Path(slug): Path<String>,
    _user: AuthUser,
) -> ApiResult<Json<Vec<ItineraryRow>>> {
    let theme_id: Uuid = sqlx::query_scalar(
        r#"SELECT id FROM themes WHERE slug = $1 AND active = true AND deleted_at IS NULL"#,
    )
    .bind(&slug)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?
    .ok_or(ApiError::NotFound)?;

    let steps = sqlx::query_as::<_, ItineraryRow>(
        r#"
        SELECT id, day_no, sequence, stop_name, stop_type, description, ritual_info, media_refs,
               geo_location, estimated_minutes, place_id
        FROM theme_itineraries
        WHERE theme_id = $1
        ORDER BY day_no, sequence
        "#,
    )
    .bind(theme_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(steps))
}
