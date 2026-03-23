# BrijYatra

Monorepo for the BrijYatra spiritual journey platform.

## Layout

- `apps/mobile` — Flutter app (traveler + guide roles, single binary)
- `apps/api` — Rust Axum API + `worker` binary for outbox jobs
- `infra` — Docker Compose for PostgreSQL and Redis

## Local development

1. Start databases:

   ```bash
   docker compose -f infra/docker-compose.yml up -d
   ```

2. Copy environment:

   ```bash
   cp .env.example .env
   ```

3. Run migrations and API (from `apps/api`):

   ```bash
   export DATABASE_URL=postgres://brijyatra:brijyatra@127.0.0.1:5433/brijyatra
   cargo run -p brijyatra_api
   ```

4. Run notification worker (separate terminal):

   ```bash
   export DATABASE_URL=postgres://brijyatra:brijyatra@127.0.0.1:5433/brijyatra
   cargo run -p brijyatra_api --bin worker
   ```

5. Run Flutter:

   ```bash
   cd apps/mobile
   flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080
   ```

With `DEV_BYPASS_AUTH=1`, send headers `X-Dev-User-Id` (UUID) and `X-Dev-Role` (`traveler` | `guide` | `admin`) on API requests after first `POST /auth/bootstrap`.

## Deploy (Railway + Firebase)

See [docs/deploy-railway-firebase.md](docs/deploy-railway-firebase.md) for Postgres/Redis, API and worker services, env vars, and Flutter release `dart-define` values.

## CI

See `.github/workflows/brijyatra-ci.yml`.
# brij_yatra
