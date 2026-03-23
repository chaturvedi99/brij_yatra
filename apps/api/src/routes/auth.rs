use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    routing::post,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;

use crate::auth::firebase::{dev_firebase_uid_from_token, parse_bearer, verify_firebase_id_token};
use crate::auth::UserRole;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new().route("/auth/bootstrap", post(bootstrap))
}

#[derive(Debug, Deserialize)]
struct BootstrapBody {
    name: Option<String>,
    #[serde(default)]
    role: Option<UserRoleWire>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "lowercase")]
enum UserRoleWire {
    Traveler,
    Guide,
    Admin,
    Vendor,
}

impl From<UserRoleWire> for UserRole {
    fn from(r: UserRoleWire) -> Self {
        match r {
            UserRoleWire::Traveler => UserRole::Traveler,
            UserRoleWire::Guide => UserRole::Guide,
            UserRoleWire::Admin => UserRole::Admin,
            UserRoleWire::Vendor => UserRole::Vendor,
        }
    }
}

#[derive(Serialize)]
struct BootstrapResponse {
    user_id: Uuid,
    firebase_uid: String,
    #[serde(rename = "token")]
    bearer_token: String,
    role: &'static str,
}

async fn bootstrap(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<BootstrapBody>,
) -> ApiResult<(StatusCode, Json<serde_json::Value>)> {
    let name = body.name.unwrap_or_else(|| "Yatri".to_string());
    let role: UserRole = body
        .role
        .map(Into::into)
        .unwrap_or(UserRole::Traveler);

    if state.dev_bypass_auth {
        let firebase_uid = format!("dev_{}", Uuid::new_v4());
        let rec = sqlx::query_scalar::<_, Uuid>(
            r#"
            INSERT INTO users (firebase_uid, name, role)
            VALUES ($1, $2, $3::user_role)
            RETURNING id
            "#,
        )
        .bind(&firebase_uid)
        .bind(&name)
        .bind(role)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

        ensure_profile(&state.pool, rec, role).await?;

        return Ok((
            StatusCode::CREATED,
            Json(json!(BootstrapResponse {
                user_id: rec,
                firebase_uid: firebase_uid.clone(),
                bearer_token: firebase_uid.clone(),
                role: role.as_str(),
            })),
        ));
    }

    let auth = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .ok_or(ApiError::Unauthorized)?;
    let token = parse_bearer(auth).ok_or(ApiError::Unauthorized)?;

    let firebase_uid = if let Some(uid) = dev_firebase_uid_from_token(token) {
        uid
    } else {
        let claims = verify_firebase_id_token(&state.jwks, token, &state.firebase_project_id)
            .await
            .map_err(|_| ApiError::Unauthorized)?;
        claims.sub
    };

    let id = sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO users (firebase_uid, name, role)
        VALUES ($1, $2, $3::user_role)
        ON CONFLICT (firebase_uid) DO UPDATE SET name = EXCLUDED.name, updated_at = now()
        RETURNING id
        "#,
    )
    .bind(&firebase_uid)
    .bind(&name)
    .bind(role)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    ensure_profile(&state.pool, id, role).await?;

    Ok((
        StatusCode::OK,
        Json(json!(BootstrapResponse {
            user_id: id,
            firebase_uid: firebase_uid.clone(),
            bearer_token: token.to_string(),
            role: role.as_str(),
        })),
    ))
}

async fn ensure_profile(
    pool: &sqlx::PgPool,
    user_id: Uuid,
    role: UserRole,
) -> Result<(), ApiError> {
    match role {
        UserRole::Traveler => {
            sqlx::query(r#"INSERT INTO traveler_profiles (user_id) VALUES ($1) ON CONFLICT DO NOTHING"#)
                .bind(user_id)
                .execute(pool)
                .await
                .map_err(|e| ApiError::Internal(e.into()))?;
        }
        UserRole::Guide => {
            sqlx::query(r#"INSERT INTO guide_profiles (user_id) VALUES ($1) ON CONFLICT DO NOTHING"#)
                .bind(user_id)
                .execute(pool)
                .await
                .map_err(|e| ApiError::Internal(e.into()))?;
        }
        _ => {}
    }
    Ok(())
}
