use uuid::Uuid;

use crate::error::ApiError;

pub async fn ensure_group_member(
    pool: &sqlx::PgPool,
    group_id: Uuid,
    user_id: Uuid,
) -> Result<Uuid, ApiError> {
    let booking_id: Uuid = sqlx::query_scalar(r#"SELECT booking_id FROM groups WHERE id = $1"#)
        .bind(group_id)
        .fetch_optional(pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?
        .ok_or(ApiError::NotFound)?;

    let ok: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(SELECT 1 FROM booking_travelers WHERE booking_id = $1 AND user_id = $2)"#,
    )
    .bind(booking_id)
    .bind(user_id)
    .fetch_one(pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;
    if !ok {
        let is_guide: bool = sqlx::query_scalar(
            r#"SELECT COALESCE(guide_id = $2, false) FROM groups WHERE id = $1"#,
        )
        .bind(group_id)
        .bind(user_id)
        .fetch_one(pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;
        if !is_guide {
            return Err(ApiError::Forbidden);
        }
    }
    Ok(booking_id)
}
