use axum::{
    extract::{Path, State},
    routing::{get, patch, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::auth::{require_role, AuthUser, UserRole};
use crate::error::{ApiError, ApiResult};
use crate::notifications::enqueue_notification;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/admin/themes", post(create_theme))
        .route("/admin/themes/:id", patch(update_theme))
        .route("/admin/themes/:id/publish", post(publish_theme_version))
        .route("/admin/groups/:id/assign-guide", post(assign_guide))
        .route("/admin/guides/:id/verify", patch(verify_guide))
        .route("/admin/bookings", get(list_bookings))
        .route("/admin/incidents", get(list_incidents))
}

fn admin_only(user: &AuthUser) -> ApiResult<()> {
    require_role(user, &[UserRole::Admin])?;
    Ok(())
}

#[derive(Deserialize)]
struct CreateThemeBody {
    slug: String,
    name: String,
    kind: String,
    #[serde(default)]
    summary: String,
    #[serde(default)]
    hero_media: Value,
    #[serde(default)]
    config_json: Value,
}

async fn create_theme(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<CreateThemeBody>,
) -> ApiResult<Json<Value>> {
    admin_only(&user)?;
    let id = sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO themes (slug, name, kind, summary, hero_media, config_json)
        VALUES ($1, $2, $3::theme_kind, $4, $5, $6)
        RETURNING id
        "#,
    )
    .bind(&body.slug)
    .bind(&body.name)
    .bind(&body.kind)
    .bind(&body.summary)
    .bind(&body.hero_media)
    .bind(&body.config_json)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        if let sqlx::Error::Database(dbe) = &e {
            if dbe.is_unique_violation() {
                return ApiError::Conflict("slug already exists".into());
            }
        }
        ApiError::Internal(e.into())
    })?;

    sqlx::query(
        r#"
        INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, payload_json)
        VALUES ($1, 'theme.create', 'theme', $2, '{}'::jsonb)
        "#,
    )
    .bind(user.id)
    .bind(id)
    .execute(&state.pool)
    .await
    .ok();

    Ok(Json(json!({ "id": id })))
}

#[derive(Deserialize)]
struct UpdateThemeBody {
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    summary: Option<String>,
    #[serde(default)]
    active: Option<bool>,
    #[serde(default)]
    hero_media: Option<Value>,
    #[serde(default)]
    config_json: Option<Value>,
}

async fn update_theme(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<UpdateThemeBody>,
) -> ApiResult<Json<Value>> {
    admin_only(&user)?;
    sqlx::query(
        r#"
        UPDATE themes SET
            name = COALESCE($2, name),
            summary = COALESCE($3, summary),
            active = COALESCE($4, active),
            hero_media = COALESCE($5, hero_media),
            config_json = COALESCE($6, config_json),
            updated_at = now()
        WHERE id = $1 AND deleted_at IS NULL
        "#,
    )
    .bind(id)
    .bind(body.name.as_deref())
    .bind(body.summary.as_deref())
    .bind(body.active)
    .bind(body.hero_media.as_ref())
    .bind(body.config_json.as_ref())
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(json!({ "ok": true })))
}

async fn publish_theme_version(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Value>> {
    admin_only(&user)?;
    let config: Value = sqlx::query_scalar(r#"SELECT config_json FROM themes WHERE id = $1"#)
        .bind(id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?
        .ok_or(ApiError::NotFound)?;

    let next_v: i32 = sqlx::query_scalar(r#"SELECT COALESCE(MAX(version), 0) + 1 FROM theme_versions WHERE theme_id = $1"#)
        .bind(id)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    sqlx::query(
        r#"
        INSERT INTO theme_versions (theme_id, version, config_json, published_by)
        VALUES ($1, $2, $3, $4)
        "#,
    )
    .bind(id)
    .bind(next_v)
    .bind(&config)
    .bind(user.id)
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(json!({ "version": next_v })))
}

#[derive(Deserialize)]
struct AssignGuideBody {
    guide_user_id: Uuid,
}

async fn assign_guide(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<AssignGuideBody>,
) -> ApiResult<Json<Value>> {
    admin_only(&user)?;
    sqlx::query(
        r#"
        UPDATE groups SET guide_id = $2, status = CASE WHEN status = 'confirmed' THEN 'assigned'::group_status ELSE status END, updated_at = now()
        WHERE id = $1
        "#,
    )
    .bind(id)
    .bind(body.guide_user_id)
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    enqueue_notification(
        &state.pool,
        Some(body.guide_user_id),
        "New group assignment",
        "You have been assigned to a yatra group.",
        json!({ "group_id": id }),
    )
    .await
    .ok();

    sqlx::query(
        r#"
        INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, payload_json)
        VALUES ($1, 'group.assign_guide', 'group', $2, $3::jsonb)
        "#,
    )
    .bind(user.id)
    .bind(id)
    .bind(json!({ "guide_user_id": body.guide_user_id }))
    .execute(&state.pool)
    .await
    .ok();

    Ok(Json(json!({ "ok": true })))
}

#[derive(Deserialize)]
struct VerifyGuideBody {
    verified: bool,
}

async fn verify_guide(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<VerifyGuideBody>,
) -> ApiResult<Json<Value>> {
    admin_only(&user)?;
    sqlx::query(
        r#"
        UPDATE guide_profiles SET
            kyc_status = CASE WHEN $2 THEN 'approved' ELSE 'pending' END,
            verified_badge = $2,
            updated_at = now()
        WHERE user_id = $1
        "#,
    )
    .bind(id)
    .bind(body.verified)
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(json!({ "ok": true })))
}

#[derive(Serialize, sqlx::FromRow)]
struct AdminBookingRow {
    id: Uuid,
    theme_slug: String,
    status: String,
    payment_status: String,
    date_start: chrono::NaiveDate,
}

async fn list_bookings(
    State(state): State<AppState>,
    user: AuthUser,
) -> ApiResult<Json<Vec<AdminBookingRow>>> {
    admin_only(&user)?;
    let rows = sqlx::query_as::<_, AdminBookingRow>(
        r#"
        SELECT b.id, t.slug as theme_slug, b.status::text, b.payment_status::text, b.date_start
        FROM bookings b
        JOIN themes t ON t.id = b.theme_id
        ORDER BY b.created_at DESC
        LIMIT 100
        "#,
    )
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;
    Ok(Json(rows))
}

#[derive(Serialize, sqlx::FromRow)]
struct IncidentRow {
    id: Uuid,
    group_id: Uuid,
    incident_type: String,
    severity: String,
    status: String,
    notes: String,
    created_at: chrono::DateTime<chrono::Utc>,
}

async fn list_incidents(
    State(state): State<AppState>,
    user: AuthUser,
) -> ApiResult<Json<Vec<IncidentRow>>> {
    admin_only(&user)?;
    let rows = sqlx::query_as::<_, IncidentRow>(
        r#"
        SELECT id, group_id, incident_type, severity, status::text, notes, created_at
        FROM incidents
        WHERE status != 'resolved'
        ORDER BY created_at DESC
        LIMIT 100
        "#,
    )
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;
    Ok(Json(rows))
}
