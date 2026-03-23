use anyhow::Result;
use serde_json::Value;
use sqlx::PgPool;
use uuid::Uuid;

pub async fn enqueue_notification(
    pool: &PgPool,
    user_id: Option<Uuid>,
    title: &str,
    body: &str,
    data: Value,
) -> Result<()> {
    sqlx::query(
        r#"
        INSERT INTO notification_outbox (user_id, channel, title, body, data_json)
        VALUES ($1, 'fcm', $2, $3, $4)
        "#,
    )
    .bind(user_id)
    .bind(title)
    .bind(body)
    .bind(data)
    .execute(pool)
    .await?;
    Ok(())
}
