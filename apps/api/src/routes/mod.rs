mod admin;
mod analytics;
mod auth;
mod bookings;
mod guide;
mod health;
mod media;
mod themes;
mod trips;

use axum::Router;
use tower_http::cors::{AllowOrigin, Any, CorsLayer};
use tower_http::trace::TraceLayer;

use crate::state::AppState;

fn build_cors(origins: &[String]) -> CorsLayer {
    if origins.is_empty() {
        CorsLayer::new()
            .allow_origin(Any)
            .allow_methods(Any)
            .allow_headers(Any)
    } else {
        let allowed: Vec<http::HeaderValue> = origins
            .iter()
            .filter_map(|o| http::HeaderValue::from_str(o).ok())
            .collect();
        if allowed.is_empty() {
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any)
        } else {
            CorsLayer::new()
                .allow_origin(AllowOrigin::list(allowed))
                .allow_methods(Any)
                .allow_headers(Any)
        }
    }
}

pub fn api_router(state: AppState) -> Router {
    let cors = build_cors(&state.cors_allowed_origins);
    Router::new()
        .merge(health::routes())
        .merge(auth::routes())
        .merge(themes::routes())
        .merge(bookings::routes())
        .merge(guide::routes())
        .merge(trips::routes())
        .merge(admin::routes())
        .merge(media::routes())
        .merge(analytics::routes())
        .layer(cors)
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}
