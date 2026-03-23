pub mod auth;
pub mod config;
pub mod error;
pub mod group_access;
pub mod jobs;
pub mod notifications;
pub mod routes;
pub mod state;

pub use error::ApiError;

use anyhow::Result;
use sqlx::postgres::PgPoolOptions;
use std::sync::Arc;
use tokio::net::TcpListener;
use tower_governor::{governor::GovernorConfigBuilder, GovernorLayer};

use crate::auth::firebase::FirebaseJwksCache;
use crate::state::AppState;

pub async fn run_server() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let cfg = config::Config::from_env()?;
    let pool = PgPoolOptions::new()
        .max_connections(15)
        .connect(&cfg.database_url)
        .await?;
    sqlx::migrate!("./migrations").run(&pool).await?;

    let redis = if let Some(ref u) = cfg.redis_url {
        match redis::Client::open(u.as_str()) {
            Ok(client) => match redis::aio::ConnectionManager::new(client).await {
                Ok(cm) => Some(cm),
                Err(e) => {
                    tracing::warn!(error = %e, "redis unavailable; theme cache disabled");
                    None
                }
            },
            Err(e) => {
                tracing::warn!(error = %e, "invalid REDIS_URL; theme cache disabled");
                None
            }
        }
    } else {
        None
    };

    let jwks = Arc::new(tokio::sync::RwLock::new(FirebaseJwksCache::new()));

    let state = AppState {
        pool,
        redis,
        firebase_project_id: Arc::new(cfg.firebase_project_id),
        dev_bypass_auth: cfg.dev_bypass_auth,
        public_api_base_url: Arc::new(cfg.public_api_base_url),
        jwks,
        cors_allowed_origins: cfg.cors_allowed_origins.clone(),
    };

    let mut app = routes::api_router(state);
    if let Some(per_sec) = cfg.rate_limit_per_second {
        let burst: u32 = (per_sec.saturating_mul(2).max(10)).min(u32::MAX as u64) as u32;
        let governor_conf = Arc::new(
            GovernorConfigBuilder::default()
                .per_second(per_sec)
                .burst_size(burst)
                .finish()
                .expect("valid governor config"),
        );
        app = app.layer(GovernorLayer {
            config: governor_conf,
        });
    }
    let addr = format!("{}:{}", cfg.host, cfg.port);
    let listener = TcpListener::bind(&addr).await?;
    tracing::info!(%addr, "BrijYatra API listening");
    axum::serve(listener, app).await?;
    Ok(())
}

pub async fn run_worker() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();
    let cfg = config::Config::from_env()?;
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&cfg.database_url)
        .await?;
    sqlx::migrate!("./migrations").run(&pool).await?;
    jobs::worker_loop(pool).await
}
