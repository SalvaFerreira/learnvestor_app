-- Learning content: tracks > units > lessons, versioned and translated.
--
-- Content is authored as code in packages/content and published with its build script.
-- Lesson versions are immutable: changing a lesson means publishing a new version, so
-- attempts always reference exactly what the learner saw.
-- Clients never read lesson_versions/lesson_translations directly; exercises are served
-- by start_lesson(), which enforces unlock order, premium access and regions.

create table public.tracks (
  id          text primary key check (id ~ '^[a-z0-9-]+$'),
  position    int not null unique,
  icon        text not null,
  color       text not null check (color ~ '^#[0-9A-Fa-f]{6}$'),
  is_premium  boolean not null default false,
  created_at  timestamptz not null default now()
);

create table public.track_translations (
  track_id    text not null references public.tracks (id) on delete cascade,
  locale      text not null check (locale in ('en', 'pt')),
  title       text not null,
  description text not null,
  primary key (track_id, locale)
);

create table public.units (
  id          text primary key check (id ~ '^[a-z0-9-]+$'),
  track_id    text not null references public.tracks (id) on delete cascade,
  position    int not null,
  unique (track_id, position)
);

create table public.unit_translations (
  unit_id     text not null references public.units (id) on delete cascade,
  locale      text not null check (locale in ('en', 'pt')),
  title       text not null,
  description text not null,
  primary key (unit_id, locale)
);

create table public.lessons (
  id                text primary key check (id ~ '^[a-z0-9-]+$'),
  unit_id           text not null references public.units (id) on delete cascade,
  position          int not null,
  xp_reward         int not null check (xp_reward between 1 and 200),
  coin_reward       numeric(12,2) not null check (coin_reward >= 0),
  is_premium        boolean not null default false,
  -- ISO country codes where the lesson applies (e.g. country-specific banking); null = global.
  regions           text[],
  published_version int,
  unique (unit_id, position)
);

create table public.lesson_versions (
  lesson_id      text not null references public.lessons (id) on delete cascade,
  version        int not null check (version > 0),
  -- { "<exercise id>": <expected response> } for every graded exercise.
  answer_key     jsonb not null check (jsonb_typeof(answer_key) = 'object'),
  exercise_count int not null,
  gradable_count int not null,
  content_hash   text not null,
  created_at     timestamptz not null default now(),
  primary key (lesson_id, version)
);

alter table public.lessons
  add constraint lessons_published_version_fkey
  foreign key (id, published_version) references public.lesson_versions (lesson_id, version)
  deferrable initially deferred;

create table public.lesson_translations (
  lesson_id   text not null,
  version     int not null,
  locale      text not null check (locale in ('en', 'pt')),
  title       text not null,
  description text not null,
  exercises   jsonb not null check (jsonb_typeof(exercises) = 'array'),
  primary key (lesson_id, version, locale),
  foreign key (lesson_id, version) references public.lesson_versions (lesson_id, version) on delete cascade
);

create index units_track_idx on public.units (track_id, position);
create index lessons_unit_idx on public.lessons (unit_id, position);

alter table public.tracks enable row level security;
alter table public.track_translations enable row level security;
alter table public.units enable row level security;
alter table public.unit_translations enable row level security;
alter table public.lessons enable row level security;
alter table public.lesson_versions enable row level security;
alter table public.lesson_translations enable row level security;

create policy "tracks: readable" on public.tracks for select to authenticated using (true);
create policy "track_translations: readable" on public.track_translations for select to authenticated using (true);
create policy "units: readable" on public.units for select to authenticated using (true);
create policy "unit_translations: readable" on public.unit_translations for select to authenticated using (true);
create policy "lessons: readable" on public.lessons for select to authenticated using (true);
-- lesson_versions / lesson_translations: no policies on purpose (served via start_lesson).
