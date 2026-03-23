use axum::{
    extract::{Path, State},
    routing::{get, patch, post},
    Json, Router,
};
use chrono::NaiveDate;
use rand::Rng;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::notifications::enqueue_notification;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/bookings", post(create_booking))
        .route("/bookings/mine", get(my_bookings))
        .route("/bookings/:id", patch(update_booking))
        .route("/bookings/:id/pay", post(pay_booking))
}

#[derive(Deserialize)]
struct CreateBookingBody {
    theme_slug: String,
    date_start: NaiveDate,
    date_end: NaiveDate,
    #[serde(default)]
    booking_metadata_json: Value,
    #[serde(default)]
    needs_json: Value,
    #[serde(default)]
    traveler_ids: Vec<Uuid>,
}

#[derive(Serialize)]
struct BookingCreated {
    id: Uuid,
    status: String,
}

fn validate_against_theme_config(config: &Value, meta: &Value, needs: &Value) -> Result<(), ApiError> {
    let schema = config.get("booking_field_schema").cloned().unwrap_or(json!({}));
    if let Some(arr) = schema.get("required_metadata_keys").and_then(|v| v.as_array()) {
        for k in arr {
            if let Some(key) = k.as_str() {
                if meta.get(key).is_none() {
                    return Err(ApiError::BadRequest(format!("missing booking_metadata_json.{key}")));
                }
            }
        }
    }
    if let Some(arr) = schema.get("required_needs_keys").and_then(|v| v.as_array()) {
        for k in arr {
            if let Some(key) = k.as_str() {
                if needs.get(key).is_none() {
                    return Err(ApiError::BadRequest(format!("missing needs_json.{key}")));
                }
            }
        }
    }
    Ok(())
}

fn estimate_price_cents(config: &Value, _meta: &Value, _needs: &Value) -> i64 {
    config
        .pointer("/pricing/base_price_cents")
        .and_then(|v| v.as_i64())
        .unwrap_or(49_900)
}

async fn create_booking(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<CreateBookingBody>,
) -> ApiResult<Json<BookingCreated>> {
    let theme = sqlx::query_as::<_, (Uuid, Value, i32)>(
        r#"SELECT id, config_json, config_version FROM themes WHERE slug = $1 AND active = true AND deleted_at IS NULL"#,
    )
    .bind(&body.theme_slug)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?
    .ok_or(ApiError::NotFound)?;

    let (theme_id, config_json, _cv) = theme;
    validate_against_theme_config(&config_json, &body.booking_metadata_json, &body.needs_json)?;

    let min_group = config_json
        .pointer("/group/min_size")
        .and_then(|v| v.as_i64())
        .unwrap_or(5) as i32;

    let total = estimate_price_cents(&config_json, &body.booking_metadata_json, &body.needs_json);
    let booking_amount = (total / 5).max(1);

    let mut tx = state.pool.begin().await.map_err(|e| ApiError::Internal(e.into()))?;

    let booking_id = sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO bookings (
            theme_id, creator_user_id, date_start, date_end, status,
            total_amount_cents, booking_amount_cents, payment_status,
            booking_metadata_json, needs_json, join_code
        )
        VALUES (
            $1, $2, $3, $4, 'draft',
            $5, $6, 'pending',
            $7, $8, encode(gen_random_bytes(4), 'hex')
        )
        RETURNING id
        "#,
    )
    .bind(theme_id)
    .bind(user.id)
    .bind(body.date_start)
    .bind(body.date_end)
    .bind(total)
    .bind(booking_amount)
    .bind(&body.booking_metadata_json)
    .bind(&body.needs_json)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    sqlx::query(
        r#"
        INSERT INTO booking_travelers (booking_id, user_id, is_group_leader, traveler_input_json)
        VALUES ($1, $2, true, '{}'::jsonb)
        ON CONFLICT (booking_id, user_id) DO NOTHING
        "#,
    )
    .bind(booking_id)
    .bind(user.id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    for tid in &body.traveler_ids {
        if *tid == user.id {
            continue;
        }
        sqlx::query(
            r#"
            INSERT INTO booking_travelers (booking_id, user_id, is_group_leader, traveler_input_json)
            VALUES ($1, $2, false, '{}'::jsonb)
            ON CONFLICT (booking_id, user_id) DO NOTHING
            "#,
        )
        .bind(booking_id)
        .bind(tid)
        .execute(&mut *tx)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;
    }

    let count: i64 = sqlx::query_scalar(r#"SELECT COUNT(*) FROM booking_travelers WHERE booking_id = $1"#)
        .bind(booking_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    if (count as i32) < min_group {
        // allow draft with fewer — user can invite; pay endpoint will enforce
    }

    tx.commit().await.map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(BookingCreated {
        id: booking_id,
        status: "draft".into(),
    }))
}

#[derive(Deserialize)]
struct PatchBookingBody {
    #[serde(default)]
    booking_metadata_json: Option<Value>,
    #[serde(default)]
    needs_json: Option<Value>,
    #[serde(default)]
    date_start: Option<NaiveDate>,
    #[serde(default)]
    date_end: Option<NaiveDate>,
}

async fn update_booking(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<PatchBookingBody>,
) -> ApiResult<Json<Value>> {
    let owner = sqlx::query_scalar::<_, bool>(
        r#"SELECT EXISTS(SELECT 1 FROM bookings WHERE id = $1 AND creator_user_id = $2)"#,
    )
    .bind(id)
    .bind(user.id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;
    if !owner {
        return Err(ApiError::Forbidden);
    }

    let (theme_id, status): (Uuid, String) = sqlx::query_as::<_, (Uuid, String)>(
        r#"SELECT theme_id, status::text FROM bookings WHERE id = $1"#,
    )
    .bind(id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?
    .ok_or(ApiError::NotFound)?;

    if status != "draft" && status != "pending_payment" {
        return Err(ApiError::BadRequest("booking not editable".into()));
    }

    let config: Value = sqlx::query_scalar(r#"SELECT config_json FROM themes WHERE id = $1"#)
        .bind(theme_id)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    let meta = body
        .booking_metadata_json
        .clone()
        .unwrap_or_else(|| json!({}));
    let needs = body.needs_json.clone().unwrap_or_else(|| json!({}));

    let merged_meta = if body.booking_metadata_json.is_some() {
        meta
    } else {
        sqlx::query_scalar::<_, Value>(r#"SELECT booking_metadata_json FROM bookings WHERE id = $1"#)
            .bind(id)
            .fetch_one(&state.pool)
            .await
            .map_err(|e| ApiError::Internal(e.into()))?
    };
    let merged_needs = if body.needs_json.is_some() {
        needs
    } else {
        sqlx::query_scalar::<_, Value>(r#"SELECT needs_json FROM bookings WHERE id = $1"#)
            .bind(id)
            .fetch_one(&state.pool)
            .await
            .map_err(|e| ApiError::Internal(e.into()))?
    };

    validate_against_theme_config(&config, &merged_meta, &merged_needs)?;

    sqlx::query(
        r#"
        UPDATE bookings SET
            booking_metadata_json = COALESCE($2, booking_metadata_json),
            needs_json = COALESCE($3, needs_json),
            date_start = COALESCE($4, date_start),
            date_end = COALESCE($5, date_end),
            updated_at = now()
        WHERE id = $1
        "#,
    )
    .bind(id)
    .bind(body.booking_metadata_json.as_ref())
    .bind(body.needs_json.as_ref())
    .bind(body.date_start)
    .bind(body.date_end)
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(json!({ "ok": true })))
}

#[derive(Serialize, sqlx::FromRow)]
struct BookingMineRow {
    id: Uuid,
    theme_slug: String,
    theme_name: String,
    date_start: NaiveDate,
    date_end: NaiveDate,
    status: String,
    payment_status: String,
}

async fn my_bookings(State(state): State<AppState>, user: AuthUser) -> ApiResult<Json<Vec<BookingMineRow>>> {
    let rows = sqlx::query_as::<_, BookingMineRow>(
        r#"
        SELECT b.id, t.slug as theme_slug, t.name as theme_name, b.date_start, b.date_end,
               b.status::text, b.payment_status::text
        FROM bookings b
        JOIN themes t ON t.id = b.theme_id
        JOIN booking_travelers bt ON bt.booking_id = b.id AND bt.user_id = $1
        ORDER BY b.created_at DESC
        "#,
    )
    .bind(user.id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;
    Ok(Json(rows))
}

#[derive(Deserialize)]
struct PayBody {
    #[serde(default)]
    idempotency_key: Option<String>,
}

async fn pay_booking(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<PayBody>,
) -> ApiResult<Json<Value>> {
    let rec = sqlx::query_as::<_, (Uuid, Uuid, String, i64, i64)>(
        r#"
        SELECT id, creator_user_id, status::text, total_amount_cents, booking_amount_cents
        FROM bookings WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?
    .ok_or(ApiError::NotFound)?;

    let (booking_id, creator, status, total_cents, booking_amt) = rec;
    if creator != user.id {
        return Err(ApiError::Forbidden);
    }
    if status == "confirmed" {
        return Ok(Json(json!({ "status": "already_confirmed" })));
    }

    let min_group: i32 = sqlx::query_scalar(
        r#"
        SELECT COALESCE((t.config_json->'group'->>'min_size')::int, 5)
        FROM bookings b JOIN themes t ON t.id = b.theme_id WHERE b.id = $1
        "#,
    )
    .bind(booking_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let cnt: i64 = sqlx::query_scalar(r#"SELECT COUNT(*) FROM booking_travelers WHERE booking_id = $1"#)
        .bind(booking_id)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;
    if (cnt as i32) < min_group {
        return Err(ApiError::BadRequest(format!(
            "minimum group size is {min_group}"
        )));
    }

    let mut tx = state.pool.begin().await.map_err(|e| ApiError::Internal(e.into()))?;

    if let Some(ref key) = body.idempotency_key {
        if let Some(_) = sqlx::query_scalar::<_, Uuid>(
            r#"SELECT id FROM payments WHERE idempotency_key = $1 AND status = 'succeeded'"#,
        )
        .bind(key)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?
        {
            tx.commit().await.map_err(|e| ApiError::Internal(e.into()))?;
            return Ok(Json(json!({ "status": "idempotent_replay" })));
        }
    }

    sqlx::query(
        r#"
        INSERT INTO payments (booking_id, payer_id, amount_cents, method, status, idempotency_key)
        VALUES ($1, $2, $3, 'stub', 'succeeded', $4)
        "#,
    )
    .bind(booking_id)
    .bind(user.id)
    .bind(booking_amt)
    .bind(body.idempotency_key.as_deref())
    .execute(&mut *tx)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    sqlx::query(
        r#"
        UPDATE bookings SET status = 'confirmed', payment_status = 'succeeded', updated_at = now()
        WHERE id = $1
        "#,
    )
    .bind(booking_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let otp: String = (0..6)
        .map(|_| rand::thread_rng().gen_range(0..10).to_string())
        .collect();

    let group_id = sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO groups (booking_id, leader_user_id, min_size, current_size, status, otp_start_code)
        VALUES ($1, $2, $3, $4, 'confirmed', $5)
        ON CONFLICT (booking_id) DO UPDATE SET
            leader_user_id = EXCLUDED.leader_user_id,
            current_size = EXCLUDED.current_size,
            status = 'confirmed',
            otp_start_code = EXCLUDED.otp_start_code,
            updated_at = now()
        RETURNING id
        "#,
    )
    .bind(booking_id)
    .bind(user.id)
    .bind(min_group)
    .bind(cnt as i32)
    .bind(&otp)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    sqlx::query(
        r#"
        INSERT INTO chat_threads (group_id, title)
        SELECT $1, 'Group chat'
        WHERE NOT EXISTS (SELECT 1 FROM chat_threads WHERE group_id = $1)
        "#,
    )
    .bind(group_id)
    .execute(&mut *tx)
    .await
    .ok();

    tx.commit().await.map_err(|e| ApiError::Internal(e.into()))?;

    enqueue_notification(
        &state.pool,
        Some(user.id),
        "Booking confirmed",
        "Your yatra is confirmed. Share the join code with your group.",
        json!({ "booking_id": booking_id, "group_id": group_id }),
    )
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(json!({
        "status": "confirmed",
        "group_id": group_id,
        "trip_start_otp": otp,
        "total_cents": total_cents
    })))
}
