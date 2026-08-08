-- Miles initial schema.
-- Rates are stored as decimal cents per mile (the IRS uses half-cent rates, e.g. 72.5¢).

create table if not exists drives (
  id uuid primary key,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  distance_miles double precision not null default 0,
  start_lat double precision,
  start_lng double precision,
  end_lat double precision,
  end_lng double precision,
  start_address text not null default '',
  end_address text not null default '',
  category text not null default 'unclassified'
    check (category in ('unclassified', 'business', 'personal')),
  purpose_note text not null default '',
  rate_cents_per_mile numeric(6, 2) not null default 0,
  polyline text not null default '',
  source text not null default 'auto'
    check (source in ('auto', 'manual', 'merged')),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists drives_started_at_idx on drives (started_at desc);
create index if not exists drives_updated_at_idx on drives (updated_at);
create index if not exists drives_category_idx on drives (category) where deleted_at is null;

create table if not exists rates (
  year integer primary key,
  cents_per_mile numeric(6, 2) not null
);

-- IRS standard business mileage rates. 2026 started at 72.5¢ and the IRS
-- raised it to 76¢ effective July 1, 2026 — the per-year model keeps one
-- effective rate per year, so override the 2026 value to whatever your CPA
-- wants applied (or keep 72.5 and adjust in the export).
insert into rates (year, cents_per_mile) values
  (2023, 65.5),
  (2024, 67.0),
  (2025, 70.0),
  (2026, 72.5)
on conflict (year) do nothing;

create table if not exists locations (
  id uuid primary key,
  name text not null,
  lat double precision not null,
  lng double precision not null,
  radius_meters double precision not null default 150,
  category text
    check (category is null or category in ('business', 'personal')),
  updated_at timestamptz not null default now()
);

create table if not exists settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);
