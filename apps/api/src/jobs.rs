use anyhow::Result;
use serde_json::json;
use sqlx::PgPool;

pub async fn worker_loop(pool: PgPool) -> Result<()> {
    loop {
        tokio::time::sleep(std::time::Duration::from_secs(3)).await;
        if let Err(e) = process_outbox(&pool).await {
            tracing::error!(error = %e, "outbox batch failed");
        }
        if let Err(e) = process_memory_jobs(&pool).await {
            tracing::error!(error = %e, "memory batch failed");
        }
    }
}

async fn process_outbox(pool: &PgPool) -> Result<()> {
    let mut tx = pool.begin().await?;
    let row: Option<(uuid::Uuid, Option<uuid::Uuid>, String, String, serde_json::Value)> =
        sqlx::query_as(
            r#"
            SELECT id, user_id, title, body, data_json
            FROM notification_outbox
            WHERE status = 'pending'
            ORDER BY created_at
            LIMIT 1
            FOR UPDATE SKIP LOCKED
            "#,
        )
        .fetch_optional(&mut *tx)
        .await?;

    let Some((id, user_id, title, body, _data)) = row else {
        tx.commit().await?;
        return Ok(());
    };

    sqlx::query("UPDATE notification_outbox SET status = 'processing' WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;

    tracing::info!(%id, ?user_id, %title, %body, "FCM stub: notification would be sent");

    sqlx::query(
        "UPDATE notification_outbox SET status = 'sent', processed_at = now() WHERE id = $1",
    )
    .bind(id)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(())
}

async fn process_memory_jobs(pool: &PgPool) -> Result<()> {
    let mut tx = pool.begin().await?;
    let row: Option<(uuid::Uuid, uuid::Uuid)> = sqlx::query_as(
        r#"
        SELECT id, group_id
        FROM memory_albums
        WHERE status = 'pending'
        ORDER BY updated_at
        LIMIT 1
        FOR UPDATE SKIP LOCKED
        "#,
    )
    .fetch_optional(&mut *tx)
    .await?;

    let Some((_album_id, group_id)) = row else {
        tx.commit().await?;
        return Ok(());
    };

    let media: serde_json::Value = sqlx::query_scalar(
        r#"
        SELECT COALESCE(
            (SELECT jsonb_agg(to_jsonb(m) ORDER BY m.created_at)
             FROM media_assets m WHERE m.group_id = $1),
            '[]'::jsonb
        )
        "#,
    )
    .bind(group_id)
    .fetch_one(&mut *tx)
    .await?;

    let summary = json!({ "assets": media, "group_id": group_id });

    sqlx::query(
        r#"
        UPDATE memory_albums SET status = 'ready', summary_json = $2, updated_at = now()
        WHERE group_id = $1 AND status = 'pending'
        "#,
    )
    .bind(group_id)
    .bind(&summary)
    .execute(&mut *tx)
    .await?;

    sqlx::query(
        r#"
        INSERT INTO trip_events (group_id, event_type, payload_json, created_by)
        VALUES ($1, 'memory_job_done', $2::jsonb, NULL)
        "#,
    )
    .bind(group_id)
    .bind(json!({ "compiled": true }))
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(())
}
