use axum::{
    extract::{Path, State},
    routing::{get, post},
    Json, Router,
};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::auth::{require_role, AuthUser, UserRole};
use crate::error::{ApiError, ApiResult};
use crate::notifications::enqueue_notification;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/guide/groups", get(list_groups))
        .route("/guide/groups/:id", get(group_detail))
        .route("/guide/groups/:id/trip/start", post(trip_start))
        .route(
            "/guide/groups/:gid/stops/:sid/complete",
            post(complete_stop),
        )
        .route("/guide/groups/:id/announce", post(announce))
}

#[derive(Serialize, sqlx::FromRow)]
struct GuideGroupRow {
    group_id: Uuid,
    booking_id: Uuid,
    status: String,
    current_size: i32,
    trip_start_at: Option<chrono::DateTime<Utc>>,
}

async fn list_groups(State(state): State<AppState>, user: AuthUser) -> ApiResult<Json<Vec<GuideGroupRow>>> {
    require_role(&user, &[UserRole::Guide, UserRole::Admin])?;
    let rows = if matches!(user.role, UserRole::Admin) {
        sqlx::query_as::<_, GuideGroupRow>(
            r#"
            SELECT g.id as group_id, g.booking_id, g.status::text, g.current_size, g.trip_start_at
            FROM groups g
            ORDER BY g.updated_at DESC
            LIMIT 50
            "#,
        )
        .fetch_all(&state.pool)
        .await
    } else {
        sqlx::query_as::<_, GuideGroupRow>(
            r#"
            SELECT g.id as group_id, g.booking_id, g.status::text, g.current_size, g.trip_start_at
            FROM groups g
            WHERE g.guide_id = $1
            ORDER BY g.updated_at DESC
            "#,
        )
        .bind(user.id)
        .fetch_all(&state.pool)
        .await
    }
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(rows))
}

#[derive(Serialize)]
struct GroupDetail {
    group: Value,
    travelers: Vec<Value>,
    needs_summary: Value,
    pending_requests: i64,
}

async fn group_detail(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<GroupDetail>> {
    require_role(&user, &[UserRole::Guide, UserRole::Admin])?;

    let mut g: Value = sqlx::query_scalar(r#"SELECT to_jsonb(g) FROM groups g WHERE g.id = $1"#)
        .bind(id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?
        .ok_or(ApiError::NotFound)?;
    if let Some(obj) = g.as_object_mut() {
        obj.remove("otp_start_code");
    }

    if matches!(user.role, UserRole::Guide) {
        let gid: Option<Uuid> = sqlx::query_scalar(r#"SELECT guide_id FROM groups WHERE id = $1"#)
            .bind(id)
            .fetch_optional(&state.pool)
            .await
            .map_err(|e| ApiError::Internal(e.into()))?;
        if gid != Some(user.id) {
            return Err(ApiError::Forbidden);
        }
    }

    let booking_id: Uuid = sqlx::query_scalar(r#"SELECT booking_id FROM groups WHERE id = $1"#)
        .bind(id)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    let travelers = sqlx::query_scalar::<_, Value>(
        r#"
        SELECT COALESCE(
            (SELECT jsonb_agg(jsonb_build_object(
                'user_id', u.id,
                'name', u.name,
                'is_leader', bt.is_group_leader,
                'input', bt.traveler_input_json
            ))
            FROM booking_travelers bt
            JOIN users u ON u.id = bt.user_id
            WHERE bt.booking_id = $1),
            '[]'::jsonb
        )
        "#,
    )
    .bind(booking_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let needs_summary: Value = sqlx::query_scalar(r#"SELECT needs_json FROM bookings WHERE id = $1"#)
        .bind(booking_id)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    let pending: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM service_requests WHERE group_id = $1 AND status = 'open'"#,
    )
    .bind(id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let arr: Vec<Value> = travelers
        .as_array()
        .cloned()
        .unwrap_or_default();

    Ok(Json(GroupDetail {
        group: g,
        travelers: arr,
        needs_summary,
        pending_requests: pending,
    }))
}

#[derive(Deserialize)]
struct TripStartBody {
    otp: String,
}

async fn trip_start(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<TripStartBody>,
) -> ApiResult<Json<Value>> {
    require_role(&user, &[UserRole::Guide, UserRole::Admin])?;

    let (stored, guide_id): (Option<String>, Option<Uuid>) = sqlx::query_as(
        r#"SELECT otp_start_code, guide_id FROM groups WHERE id = $1"#,
    )
    .bind(id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?
    .ok_or(ApiError::NotFound)?;

    if matches!(user.role, UserRole::Guide) {
        if guide_id != Some(user.id) {
            return Err(ApiError::Forbidden);
        }
    }

    let stored = stored.ok_or(ApiError::BadRequest("otp not set".into()))?;
    if stored != body.otp.trim() {
        return Err(ApiError::BadRequest("invalid otp".into()));
    }

    sqlx::query(
        r#"
        UPDATE groups SET status = 'in_progress', trip_start_at = now(), updated_at = now()
        WHERE id = $1
        "#,
    )
    .bind(id)
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    sqlx::query(
        r#"
        INSERT INTO trip_events (group_id, event_type, payload_json, created_by)
        VALUES ($1, 'trip_started', '{}'::jsonb, $2)
        "#,
    )
    .bind(id)
    .bind(user.id)
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(json!({ "ok": true })))
}

#[derive(Deserialize)]
struct CompleteStopBody {
    #[serde(default)]
    notes: Option<String>,
}

async fn complete_stop(
    State(state): State<AppState>,
    user: AuthUser,
    Path((gid, sid)): Path<(Uuid, Uuid)>,
    Json(body): Json<CompleteStopBody>,
) -> ApiResult<Json<Value>> {
    require_role(&user, &[UserRole::Guide, UserRole::Admin])?;

    if matches!(user.role, UserRole::Guide) {
        let ok: bool = sqlx::query_scalar(
            r#"SELECT COALESCE(guide_id = $2, false) FROM groups WHERE id = $1"#,
        )
        .bind(gid)
        .bind(user.id)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;
        if !ok {
            return Err(ApiError::Forbidden);
        }
    }

    sqlx::query(
        r#"
        INSERT INTO group_itinerary_progress (group_id, theme_itinerary_id, status, completed_at, notes)
        VALUES ($1, $2, 'completed', now(), $3)
        ON CONFLICT (group_id, theme_itinerary_id) DO UPDATE SET
            status = 'completed', completed_at = now(), notes = EXCLUDED.notes, updated_at = now()
        "#,
    )
    .bind(gid)
    .bind(sid)
    .bind(body.notes.as_deref().unwrap_or(""))
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    sqlx::query(
        r#"
        INSERT INTO trip_events (group_id, event_type, payload_json, created_by)
        VALUES ($1, 'stop_completed', $2::jsonb, $3)
        "#,
    )
    .bind(gid)
    .bind(json!({ "theme_itinerary_id": sid }))
    .bind(user.id)
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(json!({ "ok": true })))
}

#[derive(Deserialize)]
struct AnnounceBody {
    message: String,
}

async fn announce(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<AnnounceBody>,
) -> ApiResult<Json<Value>> {
    require_role(&user, &[UserRole::Guide, UserRole::Admin])?;

    sqlx::query(
        r#"
        INSERT INTO trip_events (group_id, event_type, payload_json, created_by)
        VALUES ($1, 'announcement', $2::jsonb, $3)
        "#,
    )
    .bind(id)
    .bind(json!({ "message": body.message }))
    .bind(user.id)
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let users: Vec<Uuid> = sqlx::query_scalar(
        r#"
        SELECT u.id FROM users u
        JOIN booking_travelers bt ON bt.user_id = u.id
        JOIN groups g ON g.booking_id = bt.booking_id
        WHERE g.id = $1
        "#,
    )
    .bind(id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    for uid in users {
        enqueue_notification(
            &state.pool,
            Some(uid),
            "Guide update",
            &body.message,
            json!({ "group_id": id }),
        )
        .await
        .ok();
    }

    Ok(Json(json!({ "ok": true })))
}
