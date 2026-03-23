-- MVP themes: Vrindavan (route), Govardhan (route + story), Chunari Manorath (ritual)

INSERT INTO themes (slug, name, kind, summary, hero_media, config_version, config_json)
VALUES (
    'vrindavan_yatra',
    'Vrindavan Yatra',
    'route',
    'Curated darshan and parikrama across sacred Vrindavan with local Brij Sevak support.',
    '{"type":"image","url":"https://example.com/media/vrindavan_hero.jpg"}'::jsonb,
    1,
    '{
      "schema_version": 1,
      "group": { "min_size": 1, "max_size": 16 },
      "booking_field_schema": {
        "required_metadata_keys": ["party_name"],
        "required_needs_keys": ["food_preference", "mobility_support"]
      },
      "pricing": { "base_price_cents": 499900, "currency": "INR" },
      "ui": {
        "primary": "#2E5077",
        "accent": "#C9A227",
        "surface": "#F5F0E6",
        "typography": "serif_soft"
      },
      "story_cards": [
        { "title": "Why Vrindavan", "body": "The forest of grace where every lane remembers Krishna lila." }
      ],
      "memory_flow": { "enabled": true, "collect_photos_per_stop": true }
    }'::jsonb
),
(
    'govardhan_yatra',
    'Govardhan Yatra',
    'route',
    'Govardhan parikrama with narrative immersion: Krishna lifting the hill and the faith of Brijwasis.',
    '{"type":"image","url":"https://example.com/media/govardhan_hero.jpg"}'::jsonb,
    1,
    '{
      "schema_version": 1,
      "group": { "min_size": 1, "max_size": 14 },
      "booking_field_schema": {
        "required_metadata_keys": ["party_name"],
        "required_needs_keys": ["food_preference", "language"]
      },
      "pricing": { "base_price_cents": 389900, "currency": "INR" },
      "ui": {
        "primary": "#1B4D3E",
        "accent": "#D4AF37",
        "surface": "#F3E9D7",
        "typography": "serif_soft"
      },
      "story_cards": [
        { "title": "Giriraj seva", "body": "Walk with the hill that Krishna held for seven days." }
      ],
      "memory_flow": { "enabled": true }
    }'::jsonb
),
(
    'chunari_manorath',
    'Chunari Manorath',
    'ritual',
    'Offering-focused experience: chunari, flowers, and seva coordination with temple rhythms.',
    '{"type":"image","url":"https://example.com/media/chunari_hero.jpg"}'::jsonb,
    1,
    '{
      "schema_version": 1,
      "group": { "min_size": 1, "max_size": 12 },
      "booking_field_schema": {
        "required_metadata_keys": ["party_name", "deity_focus"],
        "required_needs_keys": ["offering_preferences", "pundit_needed"]
      },
      "pricing": { "base_price_cents": 429900, "currency": "INR" },
      "ui": {
        "primary": "#6B2D5C",
        "accent": "#E8C547",
        "surface": "#FAF3F0",
        "typography": "serif_soft"
      },
      "ritual_checklist_template": [
        { "key": "flowers", "label": "Flowers arranged" },
        { "key": "chunari", "label": "Chunari prepared" },
        { "key": "prasad", "label": "Prasad coordination" }
      ],
      "memory_flow": { "enabled": true }
    }'::jsonb
);

-- Itinerary steps (template)
INSERT INTO theme_itineraries (theme_id, day_no, sequence, stop_name, stop_type, description, ritual_info, estimated_minutes)
SELECT t.id, 1, 1, 'Banke Bihari Darshan', 'darshan', 'Gentle darshan with etiquette briefing.', '{}'::jsonb, 90
FROM themes t WHERE t.slug = 'vrindavan_yatra';

INSERT INTO theme_itineraries (theme_id, day_no, sequence, stop_name, stop_type, description, ritual_info, estimated_minutes)
SELECT t.id, 1, 2, 'Nidhivan & Seva orientation', 'story', 'Evening story walk and seva mindset.', '{}'::jsonb, 60
FROM themes t WHERE t.slug = 'vrindavan_yatra';

INSERT INTO theme_itineraries (theme_id, day_no, sequence, stop_name, stop_type, description, ritual_info, estimated_minutes)
SELECT t.id, 1, 1, 'Govardhan Parikrama start', 'walk', 'Begin parikrama with hydration and pacing plan.', '{}'::jsonb, 120
FROM themes t WHERE t.slug = 'govardhan_yatra';

INSERT INTO theme_itineraries (theme_id, day_no, sequence, stop_name, stop_type, description, ritual_info, estimated_minutes)
SELECT t.id, 1, 2, 'Kusum Sarovar', 'darshan', 'Sacred water and Radha-Krishna lila narrative.', '{}'::jsonb, 75
FROM themes t WHERE t.slug = 'govardhan_yatra';

INSERT INTO theme_itineraries (theme_id, day_no, sequence, stop_name, stop_type, description, ritual_info, estimated_minutes)
SELECT t.id, 1, 1, 'Temple coordination', 'seva', 'Meet local coordinator; confirm offering slots.', '{}'::jsonb, 45
FROM themes t WHERE t.slug = 'chunari_manorath';

INSERT INTO theme_itineraries (theme_id, day_no, sequence, stop_name, stop_type, description, ritual_info, estimated_minutes)
SELECT t.id, 1, 2, 'Offering fulfillment', 'ritual', 'Execute chunari/flower offerings with guide support.', '{}'::jsonb, 90
FROM themes t WHERE t.slug = 'chunari_manorath';

-- Sample offerings
INSERT INTO offerings (theme_id, offering_type, name, description, price_cents, config_json)
SELECT t.id, 'addon', 'Photography (memory)', 'Discreet photography for key moments.', 150000, '{}'::jsonb
FROM themes t WHERE t.slug = 'vrindavan_yatra';

INSERT INTO offerings (theme_id, offering_type, name, description, price_cents, config_json)
SELECT t.id, 'addon', 'Extra prasad boxes', 'Additional prasad for family.', 25000, '{}'::jsonb
FROM themes t WHERE t.slug = 'govardhan_yatra';

INSERT INTO offerings (theme_id, offering_type, name, description, price_cents, config_json)
SELECT t.id, 'seva', 'Flower basket upgrade', 'Premium flower arrangement for manorath.', 35000, '{}'::jsonb
FROM themes t WHERE t.slug = 'chunari_manorath';
