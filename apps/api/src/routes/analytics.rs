use axum::{extract::State, routing::get, Json, Router};
use serde::Serialize;
use serde_json::json;

use crate::auth::{require_role, AuthUser, UserRole};
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new().route("/admin/analytics/summary", get(summary))
}

#[derive(Serialize)]
struct AnalyticsSummary {
    themes_active: i64,
    bookings_total: i64,
    bookings_confirmed: i64,
    groups_in_progress: i64,
    open_requests: i64,
    open_incidents: i64,
}

async fn summary(State(state): State<AppState>, user: AuthUser) -> ApiResult<Json<serde_json::Value>> {
    require_role(&user, &[UserRole::Admin])?;

    let themes_active: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM themes WHERE active = true AND deleted_at IS NULL"#,
    )
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let bookings_total: i64 = sqlx::query_scalar(r#"SELECT COUNT(*) FROM bookings"#)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    let bookings_confirmed: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM bookings WHERE status = 'confirmed'"#,
    )
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let groups_in_progress: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM groups WHERE status = 'in_progress'"#,
    )
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let open_requests: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM service_requests WHERE status = 'open'"#,
    )
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let open_incidents: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM incidents WHERE status != 'resolved'"#,
    )
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let s = AnalyticsSummary {
        themes_active,
        bookings_total,
        bookings_confirmed,
        groups_in_progress,
        open_requests,
        open_incidents,
    };

    Ok(Json(json!(s)))
}
