# Multi-stage build: API + worker binaries (same image, different start command on Railway).
FROM rust:1.85-bookworm AS builder
WORKDIR /app

COPY Cargo.toml Cargo.lock ./
COPY migrations ./migrations
COPY src ./src

RUN cargo build --release --locked

FROM debian:bookworm-slim AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libssl3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/target/release/brijyatra_api /usr/local/bin/brijyatra_api
COPY --from=builder /app/target/release/worker /usr/local/bin/worker

ENV HOST=0.0.0.0
EXPOSE 8080
# Railway injects PORT; config reads it.
CMD ["/usr/local/bin/brijyatra_api"]
