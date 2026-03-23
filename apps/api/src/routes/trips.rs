use axum::{
    extract::{Path, State},
    routing::{get, patch, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::group_access::ensure_group_member;
use crate::notifications::enqueue_notification;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/groups/:id/dashboard", get(group_dashboard))
        .route("/groups/:id/timeline", get(timeline))
        .route("/groups/:id/service-requests", post(create_request))
        .route("/service-requests/:id", patch(update_request_status))
        .route("/groups/:id/incidents", post(create_incident))
        .route("/groups/:id/location", post(location_ping))
        .route("/users/me/device-token", post(register_device_token))
}

async fn group_dashboard(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Value>> {
    let booking_id = ensure_group_member(&state.pool, id, user.id).await?;

    let mut group: Value = sqlx::query_scalar(r#"SELECT to_jsonb(g) FROM groups g WHERE g.id = $1"#)
        .bind(id)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;
    if let Some(obj) = group.as_object_mut() {
        obj.remove("otp_start_code");
    }

    let itinerary: Value = sqlx::query_scalar(
        r#"
        SELECT COALESCE(
            (SELECT jsonb_agg(
                jsonb_build_object(
                    'id', ti.id,
                    'day_no', ti.day_no,
                    'sequence', ti.sequence,
                    'stop_name', ti.stop_name,
                    'stop_type', ti.stop_type,
                    'progress', COALESCE(p.status, 'pending')
                ) ORDER BY ti.day_no, ti.sequence
            )
            FROM theme_itineraries ti
            JOIN bookings b ON b.theme_id = ti.theme_id AND b.id = $1
            LEFT JOIN group_itinerary_progress p ON p.theme_itinerary_id = ti.id AND p.group_id = $2),
            '[]'::jsonb
        )
        "#,
    )
    .bind(booking_id)
    .bind(id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(json!({
        "group": group,
        "itinerary": itinerary,
    })))
}

async fn timeline(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Value>> {
    let _ = ensure_group_member(&state.pool, id, user.id).await?;

    let events: Value = sqlx::query_scalar(
        r#"
        SELECT COALESCE(
            (SELECT jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC)
             FROM trip_events t
             WHERE t.group_id = $1),
            '[]'::jsonb
        )
        "#,
    )
    .bind(id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(json!({ "events": events })))
}

#[derive(Deserialize)]
struct ServiceRequestBody {
    category: String,
    #[serde(default)]
    request_text: String,
    #[serde(default)]
    priority: String,
}

async fn create_request(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<ServiceRequestBody>,
) -> ApiResult<Json<Value>> {
    let _ = ensure_group_member(&state.pool, id, user.id).await?;

    let rid = sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO service_requests (group_id, traveler_user_id, category, request_text, priority)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id
        "#,
    )
    .bind(id)
    .bind(user.id)
    .bind(&body.category)
    .bind(&body.request_text)
    .bind(if body.priority.is_empty() {
        "normal"
    } else {
        body.priority.as_str()
    })
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let guide: Option<Uuid> = sqlx::query_scalar(r#"SELECT guide_id FROM groups WHERE id = $1"#)
        .bind(id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    if let Some(g) = guide {
        enqueue_notification(
            &state.pool,
            Some(g),
            "New service request",
            &body.request_text,
            json!({ "group_id": id, "request_id": rid }),
        )
        .await
        .ok();
    }

    Ok(Json(json!({ "id": rid })))
}

#[derive(Deserialize)]
struct PatchRequestBody {
    status: String,
    #[serde(default)]
    fulfillment_notes: Option<String>,
}

async fn update_request_status(
    State(state): State<AppState>,
    user: AuthUser,
    Path(rid): Path<Uuid>,
    Json(body): Json<PatchRequestBody>,
) -> ApiResult<Json<Value>> {
    let group_id: Uuid = sqlx::query_scalar(r#"SELECT group_id FROM service_requests WHERE id = $1"#)
        .bind(rid)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?
        .ok_or(ApiError::NotFound)?;

    let is_guide: bool = sqlx::query_scalar(
        r#"SELECT COALESCE(guide_id = $2, false) FROM groups WHERE id = $1"#,
    )
    .bind(group_id)
    .bind(user.id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    if !is_guide {
        return Err(ApiError::Forbidden);
    }

    sqlx::query(
        r#"
        UPDATE service_requests
        SET status = $2::service_request_status, fulfillment_notes = COALESCE($3, fulfillment_notes), updated_at = now()
        WHERE id = $1
        "#,
    )
    .bind(rid)
    .bind(&body.status)
    .bind(body.fulfillment_notes.as_deref())
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(json!({ "ok": true })))
}

#[derive(Deserialize)]
struct IncidentBody {
    incident_type: String,
    #[serde(default)]
    severity: String,
    #[serde(default)]
    notes: String,
    #[serde(default)]
    payload_json: Value,
}

async fn create_incident(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<IncidentBody>,
) -> ApiResult<Json<Value>> {
    let _ = ensure_group_member(&state.pool, id, user.id).await?;

    let iid = sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO incidents (group_id, incident_type, severity, notes, payload_json)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id
        "#,
    )
    .bind(id)
    .bind(&body.incident_type)
    .bind(if body.severity.is_empty() {
        "medium"
    } else {
        body.severity.as_str()
    })
    .bind(&body.notes)
    .bind(&body.payload_json)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    sqlx::query(
        r#"
        INSERT INTO trip_events (group_id, event_type, payload_json, created_by)
        VALUES ($1, 'lost_traveler', $2::jsonb, $3)
        "#,
    )
    .bind(id)
    .bind(json!({ "incident_id": iid, "payload": body.payload_json }))
    .bind(user.id)
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let admins: Vec<Uuid> = sqlx::query_scalar(r#"SELECT id FROM users WHERE role = 'admin'::user_role"#)
        .fetch_all(&state.pool)
        .await
        .unwrap_or_default();

    for aid in admins {
        enqueue_notification(
            &state.pool,
            Some(aid),
            "Incident reported",
            &body.notes,
            json!({ "group_id": id, "incident_id": iid }),
        )
        .await
        .ok();
    }

    Ok(Json(json!({ "id": iid })))
}

#[derive(Deserialize)]
struct LocationBody {
    lat: f64,
    lng: f64,
    #[serde(default)]
    consent: bool,
}

async fn location_ping(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<LocationBody>,
) -> ApiResult<Json<Value>> {
    if !body.consent {
        return Err(ApiError::BadRequest("location consent required".into()));
    }
    let _ = ensure_group_member(&state.pool, id, user.id).await?;

    sqlx::query(
        r#"
        INSERT INTO trip_events (group_id, event_type, payload_json, created_by)
        VALUES ($1, 'location_ping', $2::jsonb, $3)
        "#,
    )
    .bind(id)
    .bind(json!({ "lat": body.lat, "lng": body.lng, "user_id": user.id }))
    .bind(user.id)
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(json!({ "ok": true })))
}

#[derive(Deserialize)]
struct DeviceTokenBody {
    token: String,
    #[serde(default)]
    platform: String,
}

#[derive(Serialize)]
struct OkMsg {
    ok: bool,
}

async fn register_device_token(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<DeviceTokenBody>,
) -> ApiResult<Json<OkMsg>> {
    let platform = if body.platform.is_empty() {
        "unknown"
    } else {
        body.platform.as_str()
    };
    sqlx::query(
        r#"
        INSERT INTO device_tokens (user_id, token, platform)
        VALUES ($1, $2, $3)
        ON CONFLICT (user_id, token) DO UPDATE SET platform = EXCLUDED.platform, updated_at = now()
        "#,
    )
    .bind(user.id)
    .bind(&body.token)
    .bind(platform)
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(OkMsg { ok: true }))
}
