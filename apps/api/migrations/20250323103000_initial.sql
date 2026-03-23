-- BrijYatra core schema (v1)

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TYPE user_role AS ENUM ('traveler', 'guide', 'admin', 'vendor');
CREATE TYPE theme_kind AS ENUM ('route', 'story', 'ritual', 'support');
CREATE TYPE booking_status AS ENUM ('draft', 'pending_payment', 'confirmed', 'cancelled', 'completed');
CREATE TYPE payment_status AS ENUM ('pending', 'succeeded', 'failed', 'refunded');
CREATE TYPE group_status AS ENUM ('forming', 'confirmed', 'assigned', 'in_progress', 'completed', 'cancelled');
CREATE TYPE service_request_status AS ENUM ('open', 'in_progress', 'fulfilled', 'escalated', 'cancelled');
CREATE TYPE incident_status AS ENUM ('open', 'acknowledged', 'resolved');
CREATE TYPE trip_event_type AS ENUM (
    'trip_started',
    'trip_ended',
    'stop_completed',
    'delay_reported',
    'announcement',
    'location_ping',
    'lost_traveler',
    'memory_job_queued',
    'memory_job_done'
);
CREATE TYPE outbox_status AS ENUM ('pending', 'processing', 'sent', 'failed');
CREATE TYPE media_kind AS ENUM ('image', 'video', 'audio', 'document');

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    firebase_uid TEXT UNIQUE,
    role user_role NOT NULL DEFAULT 'traveler',
    name TEXT NOT NULL DEFAULT '',
    phone TEXT,
    email TEXT,
    profile_photo_url TEXT,
    language TEXT NOT NULL DEFAULT 'en',
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_role ON users (role);
CREATE INDEX idx_users_firebase_uid ON users (firebase_uid);

CREATE TABLE traveler_profiles (
    user_id UUID PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    age_band TEXT,
    gender TEXT,
    special_needs_json JSONB NOT NULL DEFAULT '{}',
    devotional_preferences_json JSONB NOT NULL DEFAULT '{}',
    emergency_contact JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE guide_profiles (
    user_id UUID PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    kyc_status TEXT NOT NULL DEFAULT 'pending',
    verified_badge BOOLEAN NOT NULL DEFAULT false,
    languages TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    service_areas TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    theme_expertise TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    rating NUMERIC(3, 2) NOT NULL DEFAULT 0,
    payout_info JSONB,
    availability_status TEXT NOT NULL DEFAULT 'offline',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE places (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    city TEXT NOT NULL DEFAULT 'Vrindavan',
    place_type TEXT NOT NULL DEFAULT 'temple',
    geo JSONB,
    crowd_metadata JSONB NOT NULL DEFAULT '{}',
    timing_metadata JSONB NOT NULL DEFAULT '{}',
    narrative_content JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_places_city ON places (city);

CREATE TABLE themes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    kind theme_kind NOT NULL,
    summary TEXT NOT NULL DEFAULT '',
    hero_media JSONB NOT NULL DEFAULT '{}',
    config_version INT NOT NULL DEFAULT 1,
    config_json JSONB NOT NULL DEFAULT '{}',
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_themes_kind_active ON themes (kind, active);

CREATE TABLE theme_itineraries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    theme_id UUID NOT NULL REFERENCES themes (id) ON DELETE CASCADE,
    day_no INT NOT NULL DEFAULT 1,
    sequence INT NOT NULL,
    stop_name TEXT NOT NULL,
    stop_type TEXT NOT NULL DEFAULT 'darshan',
    description TEXT NOT NULL DEFAULT '',
    ritual_info JSONB NOT NULL DEFAULT '{}',
    media_refs JSONB NOT NULL DEFAULT '[]',
    geo_location JSONB,
    estimated_minutes INT,
    place_id UUID REFERENCES places (id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_theme_itineraries_theme ON theme_itineraries (theme_id, day_no, sequence);

CREATE TABLE offerings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    theme_id UUID REFERENCES themes (id) ON DELETE SET NULL,
    offering_type TEXT NOT NULL DEFAULT 'addon',
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    price_cents BIGINT NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'INR',
    config_json JSONB NOT NULL DEFAULT '{}',
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_offerings_theme ON offerings (theme_id, active);

CREATE TABLE bookings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    theme_id UUID NOT NULL REFERENCES themes (id),
    creator_user_id UUID NOT NULL REFERENCES users (id),
    date_start DATE NOT NULL,
    date_end DATE NOT NULL,
    status booking_status NOT NULL DEFAULT 'draft',
    total_amount_cents BIGINT NOT NULL DEFAULT 0,
    booking_amount_cents BIGINT NOT NULL DEFAULT 0,
    payment_status payment_status NOT NULL DEFAULT 'pending',
    booking_metadata_json JSONB NOT NULL DEFAULT '{}',
    needs_json JSONB NOT NULL DEFAULT '{}',
    join_code TEXT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_bookings_status_dates ON bookings (status, date_start);
CREATE INDEX idx_bookings_creator ON bookings (creator_user_id);

CREATE TABLE booking_travelers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id UUID NOT NULL REFERENCES bookings (id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users (id),
    is_group_leader BOOLEAN NOT NULL DEFAULT false,
    traveler_input_json JSONB NOT NULL DEFAULT '{}',
    consent_flags JSONB NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'confirmed',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (booking_id, user_id)
);

CREATE INDEX idx_booking_travelers_booking ON booking_travelers (booking_id);

CREATE TABLE booking_offerings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id UUID NOT NULL REFERENCES bookings (id) ON DELETE CASCADE,
    offering_id UUID NOT NULL REFERENCES offerings (id),
    quantity INT NOT NULL DEFAULT 1,
    custom_input_json JSONB NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_booking_offerings_booking ON booking_offerings (booking_id);

CREATE TABLE groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id UUID NOT NULL UNIQUE REFERENCES bookings (id) ON DELETE CASCADE,
    guide_id UUID REFERENCES users (id),
    leader_user_id UUID REFERENCES users (id),
    min_size INT NOT NULL DEFAULT 5,
    current_size INT NOT NULL DEFAULT 0,
    status group_status NOT NULL DEFAULT 'forming',
    otp_start_code TEXT,
    otp_rotated_at TIMESTAMPTZ,
    trip_start_at TIMESTAMPTZ,
    trip_end_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_groups_guide_status ON groups (guide_id, status);

CREATE TABLE group_itinerary_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES groups (id) ON DELETE CASCADE,
    theme_itinerary_id UUID NOT NULL REFERENCES theme_itineraries (id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending',
    completed_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (group_id, theme_itinerary_id)
);

CREATE INDEX idx_group_itinerary_progress_group ON group_itinerary_progress (group_id);

CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id UUID NOT NULL REFERENCES bookings (id) ON DELETE CASCADE,
    payer_id UUID NOT NULL REFERENCES users (id),
    amount_cents BIGINT NOT NULL,
    currency TEXT NOT NULL DEFAULT 'INR',
    method TEXT NOT NULL DEFAULT 'stub',
    status payment_status NOT NULL DEFAULT 'pending',
    gateway_ref TEXT,
    idempotency_key TEXT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_payments_booking ON payments (booking_id);

CREATE TABLE service_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES groups (id) ON DELETE CASCADE,
    traveler_user_id UUID REFERENCES users (id),
    category TEXT NOT NULL,
    request_text TEXT NOT NULL DEFAULT '',
    priority TEXT NOT NULL DEFAULT 'normal',
    status service_request_status NOT NULL DEFAULT 'open',
    assigned_to UUID REFERENCES users (id),
    fulfillment_notes TEXT,
    proof_media JSONB NOT NULL DEFAULT '[]',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_service_requests_group_status ON service_requests (group_id, status);

CREATE TABLE trip_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES groups (id) ON DELETE CASCADE,
    event_type trip_event_type NOT NULL,
    payload_json JSONB NOT NULL DEFAULT '{}',
    created_by UUID REFERENCES users (id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_trip_events_group_created ON trip_events (group_id, created_at);

CREATE TABLE incidents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES groups (id) ON DELETE CASCADE,
    incident_type TEXT NOT NULL,
    severity TEXT NOT NULL DEFAULT 'medium',
    notes TEXT NOT NULL DEFAULT '',
    status incident_status NOT NULL DEFAULT 'open',
    payload_json JSONB NOT NULL DEFAULT '{}',
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_incidents_group_status ON incidents (group_id, status);

CREATE TABLE reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id UUID NOT NULL REFERENCES bookings (id) ON DELETE CASCADE,
    reviewer_id UUID NOT NULL REFERENCES users (id),
    target_guide_id UUID REFERENCES users (id),
    rating INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_reviews_booking ON reviews (booking_id);

CREATE TABLE notification_outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users (id),
    channel TEXT NOT NULL DEFAULT 'fcm',
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    data_json JSONB NOT NULL DEFAULT '{}',
    status outbox_status NOT NULL DEFAULT 'pending',
    attempts INT NOT NULL DEFAULT 0,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at TIMESTAMPTZ
);

CREATE INDEX idx_notification_outbox_pending ON notification_outbox (status, created_at);

CREATE TABLE device_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT 'unknown',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, token)
);

CREATE INDEX idx_device_tokens_user ON device_tokens (user_id);

CREATE TABLE chat_threads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES groups (id) ON DELETE CASCADE,
    title TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_chat_threads_group ON chat_threads (group_id);

CREATE TABLE chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id UUID NOT NULL REFERENCES chat_threads (id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users (id),
    body TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_chat_messages_thread ON chat_messages (thread_id, created_at);

CREATE TABLE media_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES groups (id) ON DELETE CASCADE,
    uploaded_by UUID NOT NULL REFERENCES users (id),
    kind media_kind NOT NULL DEFAULT 'image',
    storage_url TEXT NOT NULL,
    theme_itinerary_id UUID REFERENCES theme_itineraries (id),
    meta_json JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_media_assets_group ON media_assets (group_id);

CREATE TABLE memory_albums (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES groups (id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending',
    summary_json JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (group_id)
);

CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id UUID REFERENCES users (id),
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID,
    payload_json JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_logs_entity ON audit_logs (entity_type, entity_id);

CREATE TABLE theme_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    theme_id UUID NOT NULL REFERENCES themes (id) ON DELETE CASCADE,
    version INT NOT NULL,
    config_json JSONB NOT NULL,
    published_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_by UUID REFERENCES users (id),
    UNIQUE (theme_id, version)
);
