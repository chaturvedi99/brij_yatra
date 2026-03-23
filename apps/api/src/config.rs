use anyhow::{Context, Result};
use std::env;

#[derive(Clone, Debug)]
pub struct Config {
    pub database_url: String,
    pub redis_url: Option<String>,
    pub host: String,
    pub port: u16,
    pub firebase_project_id: String,
    pub dev_bypass_auth: bool,
    pub public_api_base_url: String,
    /// Empty = mirror previous permissive CORS (any origin). Set in production.
    pub cors_allowed_origins: Vec<String>,
    /// None or Some(0) = disabled
    pub rate_limit_per_second: Option<u64>,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        dotenvy::dotenv().ok();
        let database_url = env::var("DATABASE_URL").context("DATABASE_URL must be set")?;
        let redis_url = env::var("REDIS_URL").ok().filter(|s| !s.is_empty());
        let host = env::var("HOST").unwrap_or_else(|_| "0.0.0.0".into());
        let port = env::var("PORT")
            .unwrap_or_else(|_| "8080".into())
            .parse()
            .context("PORT must be a number")?;
        let firebase_project_id =
            env::var("FIREBASE_PROJECT_ID").unwrap_or_else(|_| "dev-project".into());
        let dev_bypass_auth = env::var("DEV_BYPASS_AUTH")
            .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
            .unwrap_or(false);
        let public_api_base_url =
            env::var("PUBLIC_API_BASE_URL").unwrap_or_else(|_| "http://127.0.0.1:8080".into());
        let cors_allowed_origins = env::var("ALLOWED_ORIGINS")
            .map(|s| {
                s.split(',')
                    .map(|x| x.trim().to_string())
                    .filter(|x| !x.is_empty())
                    .collect()
            })
            .unwrap_or_default();
        let rate_limit_per_second = env::var("RATE_LIMIT_PER_SECOND")
            .ok()
            .and_then(|s| s.parse().ok())
            .and_then(|n: u64| if n > 0 { Some(n) } else { None });
        Ok(Self {
            database_url,
            redis_url,
            host,
            port,
            firebase_project_id,
            dev_bypass_auth,
            public_api_base_url,
            cors_allowed_origins,
            rate_limit_per_second,
        })
    }
}
