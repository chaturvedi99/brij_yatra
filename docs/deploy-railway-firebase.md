# Deploy BrijYatra on Railway + Firebase

This document matches the in-repo setup under `brijyatra/apps/api` (Dockerfile, `railway.toml`) and `brijyatra/apps/mobile` (Firebase-ready Flutter).

## 1. Firebase (console)

1. Create a project at [Firebase Console](https://console.firebase.google.com/).
2. **Authentication:** enable **Email/Password** (and any other providers you need).
3. **Cloud Messaging:** enable FCM (for device tokens; server push can stay stub until you wire Admin SDK).
4. Add **Android** app with package `com.brijyatra.brijyatra_mobile`.
5. Add **iOS** app with bundle id matching `ios/Runner` (update to your team id as needed).
6. Run from `apps/mobile`:

   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```

   This overwrites `lib/firebase_options.dart`, `android/app/google-services.json`, and `ios/Runner/GoogleService-Info.plist` with real values. Until then, placeholder files allow **builds** but Firebase calls will fail until you configure.

7. **Web (Firebase Hosting):** In the Firebase console, add a **Web** app to the same project (or select **Web** when `flutterfire configure` prompts for platforms). After configure, `firebase_options.dart` includes real `web` options.

8. **Authentication — authorized domains (required for web):** In Firebase Console → Authentication → Settings → Authorized domains, ensure these exist:
   - `localhost` (dev)
   - `YOUR_PROJECT.web.app`
   - `YOUR_PROJECT.firebaseapp.com`
   - Any custom domain you attach to Hosting

9. **Hosting:** In Firebase Console → Hosting, click **Get started** if you have not enabled Hosting yet.

10. Update [apps/mobile/.firebaserc](apps/mobile/.firebaserc): replace `demo-brijyatra-replace-me` with your real Firebase **project ID** (same as `FIREBASE_PROJECT_ID` on the API).

11. Set **`FIREBASE_PROJECT_ID`** on Railway to the same **Project ID** (used by the Rust API for JWT validation).

## 2. Railway layout

One Railway **Project** with:

| Resource   | Notes |
|-----------|--------|
| **PostgreSQL** | Plugin; exposes `DATABASE_URL` (append `?sslmode=require` if required). |
| **Redis**      | Plugin; exposes `REDIS_URL`. |
| **Service: API** | Root directory: `brijyatra/apps/api`. Uses Dockerfile + default start `brijyatra_api`. Public networking + domain. |
| **Service: Worker** | Same root + Dockerfile. **Start command:** `/usr/local/bin/worker`. No public port. |

Connect `DATABASE_URL` and `REDIS_URL` from plugins to **both** services (reference variables in Railway UI).

## 3. API environment variables

| Variable | Required | Example |
|----------|-----------|---------|
| `DATABASE_URL` | yes | From Railway Postgres |
| `REDIS_URL` | recommended | From Railway Redis |
| `PORT` | auto | Set by Railway |
| `HOST` | no | `0.0.0.0` (default in Docker image) |
| `FIREBASE_PROJECT_ID` | yes (prod) | e.g. `my-brijyatra` |
| `DEV_BYPASS_AUTH` | no | Omit or `0` in production |
| `PUBLIC_API_BASE_URL` | yes | `https://<your-api>.up.railway.app` |
| `ALLOWED_ORIGINS` | recommended | Comma-separated origins for CORS; **required for Flutter web** against a locked-down API. Include `https://YOUR_PROJECT.web.app` and `https://YOUR_PROJECT.firebaseapp.com` (no trailing slash). Empty = allow any (dev-style only) |
| `RATE_LIMIT_PER_SECOND` | no | e.g. `50`; unset or `0` disables governor |
| `RUST_LOG` | no | `brijyatra_api=info,tower_http=info` |

## 4. Worker environment variables

`DATABASE_URL`, `REDIS_URL` (optional if worker only touches DB), `RUST_LOG`. No `PORT`.

## 5. First deploy

1. Deploy **API**; open `GET /health` on the public URL.
2. Check logs for migration success (`sqlx::migrate`).
3. Deploy **Worker**; confirm outbox/memory logs.
4. Set `PUBLIC_API_BASE_URL` to the final public API URL if it changed.
5. Build Flutter with:

   ```bash
   flutter build apk --release \
     --dart-define=API_BASE_URL=https://YOUR_API_HOST \
     --dart-define=USE_FIREBASE_AUTH=true
   ```

   For local/dev without Firebase, omit `USE_FIREBASE_AUTH` (defaults to `false`) and use API `DEV_BYPASS_AUTH=1` with dev bootstrap.

## 5b. Flutter web + Firebase Hosting

From `brijyatra/apps/mobile` (after `firebase login` or CI service account):

1. Set **`ALLOWED_ORIGINS`** on the API to your Hosting URLs (see table above). Redeploy the API if it was already running.

2. Build the web app (use your real API host; must be **https** in production):

   ```bash
   cd apps/mobile
   flutter build web --release \
     --dart-define=API_BASE_URL=https://YOUR_API_HOST \
     --dart-define=USE_FIREBASE_AUTH=true
   ```

3. Deploy static files (uses [firebase.json](apps/mobile/firebase.json) → `public: build/web` and SPA rewrites):

   ```bash
   firebase deploy --only hosting
   ```

4. Open the Hosting URL from the CLI output; sign in with Firebase Auth and confirm API calls succeed (check browser devtools for CORS errors if not).

**Notes**

- [apps/mobile/.firebaserc](apps/mobile/.firebaserc) default project must match your Firebase project ID.
- Push notifications (FCM) on web are not wired in the app yet; the Profile screen shows a message on web when using Firebase auth.
- Optional: add a GitHub Actions job that runs `flutter build web` and `firebase deploy --only hosting` using a `FIREBASE_SERVICE_ACCOUNT` JSON secret.

## 6. CI deploy (optional)

Add `RAILWAY_TOKEN` and use [Railway CLI](https://docs.railway.app/develop/cli) or GitHub integration to deploy from `main`.

## 7. Security checklist

- [ ] `DEV_BYPASS_AUTH` disabled in production  
- [ ] `ALLOWED_ORIGINS` set to your real origins  
- [ ] Firebase **Authorized domains** configured for OAuth (if used)  
- [ ] Release signing for Android/iOS store builds  
