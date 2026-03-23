pub mod firebase;

use axum::{
    async_trait,
    extract::FromRequestParts,
    http::{header::AUTHORIZATION, request::Parts, HeaderMap},
};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

use crate::auth::firebase::{dev_firebase_uid_from_token, parse_bearer, verify_firebase_id_token};
use crate::error::ApiError;
use crate::state::AppState;

#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "user_role", rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
pub enum UserRole {
    Traveler,
    Guide,
    Admin,
    Vendor,
}

impl UserRole {
    pub fn as_str(&self) -> &'static str {
        match self {
            UserRole::Traveler => "traveler",
            UserRole::Guide => "guide",
            UserRole::Admin => "admin",
            UserRole::Vendor => "vendor",
        }
    }
}

#[derive(Debug, Clone)]
pub struct AuthUser {
    pub id: Uuid,
    pub role: UserRole,
    pub firebase_uid: Option<String>,
}

#[async_trait]
impl FromRequestParts<AppState> for AuthUser {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self, Self::Rejection> {
        if state.dev_bypass_auth {
            if let Some(u) = dev_headers_user(&parts.headers, &state.pool).await? {
                return Ok(u);
            }
        }

        let auth = parts
            .headers
            .get(AUTHORIZATION)
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

        let user = sqlx::query_as::<_, UserRow>(
            r#"SELECT id, role as "role: UserRole", firebase_uid FROM users WHERE firebase_uid = $1"#,
        )
        .bind(&firebase_uid)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?
        .ok_or(ApiError::Unauthorized)?;

        Ok(AuthUser {
            id: user.id,
            role: user.role,
            firebase_uid: user.firebase_uid,
        })
    }
}

#[derive(sqlx::FromRow)]
struct UserRow {
    id: Uuid,
    role: UserRole,
    firebase_uid: Option<String>,
}

async fn dev_headers_user(headers: &HeaderMap, pool: &PgPool) -> Result<Option<AuthUser>, ApiError> {
    let uid_hdr = headers.get("x-dev-user-id").and_then(|v| v.to_str().ok());
    let role_hdr = headers
        .get("x-dev-role")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("traveler");
    let Some(uid_str) = uid_hdr else {
        return Ok(None);
    };
    let id: Uuid = uid_str.parse().map_err(|_| ApiError::BadRequest("invalid X-Dev-User-Id".into()))?;
    let _role = match role_hdr.to_lowercase().as_str() {
        "guide" => UserRole::Guide,
        "admin" => UserRole::Admin,
        "vendor" => UserRole::Vendor,
        _ => UserRole::Traveler,
    };

    let user = sqlx::query_as::<_, UserRow>(
        r#"SELECT id, role as "role: UserRole", firebase_uid FROM users WHERE id = $1"#,
    )
    .bind(id)
    .fetch_optional(pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(user.map(|u| AuthUser {
        id: u.id,
        role: u.role,
        firebase_uid: u.firebase_uid,
    }))
}

pub fn require_role(user: &AuthUser, allowed: &[UserRole]) -> Result<(), ApiError> {
    if allowed.contains(&user.role) {
        Ok(())
    } else {
        Err(ApiError::Forbidden)
    }
}
