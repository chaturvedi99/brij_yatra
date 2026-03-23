use anyhow::{anyhow, Context, Result};
use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use serde::Deserialize;
use std::collections::HashMap;
use std::time::{Duration, Instant};

#[derive(Debug, Deserialize)]
pub struct FirebaseIdTokenClaims {
    pub sub: String,
    pub aud: String,
    pub iss: String,
}

pub struct FirebaseJwksCache {
    pem_by_kid: HashMap<String, String>,
    fetched_at: Option<Instant>,
}

impl FirebaseJwksCache {
    pub fn new() -> Self {
        Self {
            pem_by_kid: HashMap::new(),
            fetched_at: None,
        }
    }

    fn needs_refresh(&self) -> bool {
        match self.fetched_at {
            None => true,
            Some(t) => t.elapsed() > Duration::from_secs(60 * 60),
        }
    }

    pub async fn refresh_if_needed(&mut self) -> Result<()> {
        if !self.needs_refresh() && !self.pem_by_kid.is_empty() {
            return Ok(());
        }
        let client = reqwest::Client::new();
        let url = "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com";
        let resp = client.get(url).send().await?.error_for_status()?;
        let map: HashMap<String, String> = resp.json().await?;
        self.pem_by_kid = map;
        self.fetched_at = Some(Instant::now());
        Ok(())
    }

    pub fn decoding_key_for_kid(&self, kid: &str) -> Result<DecodingKey> {
        let pem = self
            .pem_by_kid
            .get(kid)
            .ok_or_else(|| anyhow!("unknown jwt kid"))?;
        DecodingKey::from_rsa_pem(pem.as_bytes())
            .with_context(|| format!("invalid rsa pem for kid {kid}"))
    }
}

pub fn firebase_validation(project_id: &str) -> Validation {
    let mut v = Validation::new(Algorithm::RS256);
    v.set_audience(&[project_id]);
    v.set_issuer(&[format!(
        "https://securetoken.google.com/{project_id}"
    )]);
    v.validate_exp = true;
    v
}

pub async fn verify_firebase_id_token(
    cache: &tokio::sync::RwLock<FirebaseJwksCache>,
    token: &str,
    project_id: &str,
) -> Result<FirebaseIdTokenClaims> {
    let header = decode_header(token).context("invalid jwt header")?;
    let kid = header
        .kid
        .ok_or_else(|| anyhow!("jwt missing kid"))?;

    {
        let mut guard = cache.write().await;
        guard.refresh_if_needed().await?;
    }

    let key = {
        let guard = cache.read().await;
        guard.decoding_key_for_kid(&kid)?
    };

    let validation = firebase_validation(project_id);
    let data = decode::<FirebaseIdTokenClaims>(token, &key, &validation)
        .map_err(|e| anyhow!("jwt verify failed: {e}"))?;
    Ok(data.claims)
}

/// Dev-only: treat raw token as firebase_uid when it is not a JWT (starts with "dev_").
pub fn dev_firebase_uid_from_token(token: &str) -> Option<String> {
    let t = token.trim();
    if t.starts_with("dev_") {
        Some(t.to_string())
    } else {
        None
    }
}

pub fn parse_bearer(auth_header: &str) -> Option<&str> {
    auth_header
        .strip_prefix("Bearer ")
        .or_else(|| auth_header.strip_prefix("bearer "))
        .map(str::trim)
}
