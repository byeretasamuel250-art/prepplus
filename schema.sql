-- ============================================================
-- prep+ database schema
-- Run this in Supabase: Dashboard -> SQL Editor -> New query -> Run
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- SUBJECTS ----------
create table if not exists subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  level text not null check (level in ('UCE','UACE')),
  is_free boolean not null default false,   -- free subjects are visible to everyone, no subscription needed
  created_at timestamptz not null default now()
);

-- ---------- TOPICS (within a subject) ----------
create table if not exists topics (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

-- ---------- QUESTIONS ----------
create table if not exists questions (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  topic_id uuid references topics(id) on delete set null,
  year int,
  paper text,                              -- e.g. "Paper 1"
  question_text text not null,
  options jsonb not null,                  -- array of 4 strings, e.g. ["mn","n^m","2^(mn)-1","2^(mn)"]
  correct_index int not null check (correct_index between 0 and 3),
  explanation text,
  created_at timestamptz not null default now()
);
create index if not exists idx_questions_subject on questions(subject_id);
create index if not exists idx_questions_topic on questions(topic_id);

-- ---------- PROFILES (students) ----------
create table if not exists profiles (
  id uuid primary key default gen_random_uuid(),
  auth_uid uuid unique,
  phone text unique not null,
  pin_hash text not null,
  name text,
  school text,
  level text check (level in ('UCE','UACE')),
  subscription_status text not null default 'inactive'
      check (subscription_status in ('inactive','pending','active','expired')),
  subscription_expires_at timestamptz,
  created_at timestamptz not null default now()
);

-- ---------- SUBSCRIPTION REQUESTS (manual mobile-money payments) ----------
create table if not exists subscription_requests (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  network text not null check (network in ('MTN','Airtel')),
  transaction_ref text,
  amount integer not null default 3000,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);

-- ---------- QUIZ ATTEMPTS ----------
create table if not exists quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  subject_id uuid not null references subjects(id) on delete cascade,
  mode text not null check (mode in ('topic','paper','timed')),
  score int not null default 0,
  total int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists attempt_answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references quiz_attempts(id) on delete cascade,
  question_id uuid not null references questions(id) on delete cascade,
  topic_id uuid references topics(id) on delete set null,
  selected_index int,
  is_correct boolean not null
);
create index if not exists idx_answers_attempt on attempt_answers(attempt_id);

-- ---------- ADMIN ALLOWLIST ----------
create table if not exists admin_allowlist (
  email text primary key
);

-- ---------- PAPER FILES (scanned past papers uploaded by admin) ----------
create table if not exists paper_files (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  title text not null,
  year int,
  paper text,
  storage_path text not null,      -- path inside the 'papers' storage bucket
  file_type text,                  -- 'pdf' or 'image', just for showing the right icon
  uploaded_at timestamptz not null default now()
);
create index if not exists idx_paper_files_subject on paper_files(subject_id);

-- Prevent a student from ever having more than one pending payment
-- request at a time. This is a hard database guard, so it holds even
-- if someone taps "I've paid" many times fast, has two tabs open, or
-- retries after a network blip — the DB itself rejects the duplicate.
create unique index if not exists idx_one_pending_request_per_profile
  on subscription_requests (profile_id)
  where (status = 'pending');

-- storage bucket for uploaded scanned papers — NOT public; access is
-- controlled entirely by the RLS policies below (same subscription
-- gate as the questions table), so a locked subject's papers are
-- unreachable even with a guessed or shared link.
insert into storage.buckets (id, name, public)
values ('papers', 'papers', false)
on conflict (id) do nothing;

-- ---------- STORAGE (avatars, if this project also runs new+, is handled by that app's own schema) ----------

-- ============================================================
-- Helper: is the currently-logged-in Supabase Auth user an admin?
-- ============================================================
create or replace function is_admin()
returns boolean
language sql security definer stable
as $$
  select exists (
    select 1 from admin_allowlist a
    where a.email = (auth.jwt() ->> 'email')
  );
$$;
grant execute on function is_admin() to anon, authenticated;

-- Helper: does the current session belong to an active subscriber?
create or replace function is_active_subscriber()
returns boolean
language sql security definer stable
as $$
  select exists (
    select 1 from profiles p
    where p.auth_uid = auth.uid()
      and p.subscription_status = 'active'
      and (p.subscription_expires_at is null or p.subscription_expires_at > now())
  );
$$;
grant execute on function is_active_subscriber() to anon, authenticated;

-- ============================================================
-- Registration and login (same pattern as new+)
-- ============================================================
create or replace function register_with_pin(
  p_phone text, p_pin text, p_name text, p_school text, p_level text
)
returns profiles
language plpgsql security definer
as $$
declare
  new_row profiles;
begin
  if auth.uid() is null then
    raise exception 'no active session';
  end if;
  if exists (select 1 from profiles where phone = p_phone) then
    raise exception 'phone_taken';
  end if;
  insert into profiles (auth_uid, phone, pin_hash, name, school, level)
  values (auth.uid(), p_phone, encode(digest(p_pin, 'sha256'), 'hex'), p_name, p_school, p_level)
  returning * into new_row;
  return new_row;
end;
$$;
grant execute on function register_with_pin(text, text, text, text, text) to anon, authenticated;

create or replace function login_with_pin(p_phone text, p_pin text)
returns profiles
language plpgsql security definer
as $$
declare
  match_row profiles;
begin
  if auth.uid() is null then
    raise exception 'no active session';
  end if;
  select * into match_row from profiles where phone = p_phone;
  if match_row is null or match_row.pin_hash <> encode(digest(p_pin, 'sha256'), 'hex') then
    raise exception 'invalid_credentials';
  end if;
  update profiles set auth_uid = auth.uid() where id = match_row.id returning * into match_row;
  return match_row;
end;
$$;
grant execute on function login_with_pin(text, text) to anon, authenticated;

-- ============================================================
-- Submit a completed quiz attempt in one call (attempt + all its
-- answers together), so the client never writes attempt_answers
-- directly, and RLS on that table can stay simple.
-- p_answers is a jsonb array like:
-- [{"question_id": "...", "topic_id": "...", "selected_index": 2, "is_correct": true}, ...]
-- ============================================================
create or replace function submit_quiz_attempt(
  p_subject_id uuid, p_mode text, p_score int, p_total int, p_answers jsonb
)
returns quiz_attempts
language plpgsql security definer
as $$
declare
  my_profile_id uuid;
  new_attempt quiz_attempts;
  ans jsonb;
begin
  select id into my_profile_id from profiles where auth_uid = auth.uid();
  if my_profile_id is null then
    raise exception 'no matching profile';
  end if;

  insert into quiz_attempts (profile_id, subject_id, mode, score, total)
  values (my_profile_id, p_subject_id, p_mode, p_score, p_total)
  returning * into new_attempt;

  for ans in select * from jsonb_array_elements(p_answers) loop
    insert into attempt_answers (attempt_id, question_id, topic_id, selected_index, is_correct)
    values (
      new_attempt.id,
      (ans->>'question_id')::uuid,
      nullif(ans->>'topic_id','')::uuid,
      (ans->>'selected_index')::int,
      (ans->>'is_correct')::boolean
    );
  end loop;

  return new_attempt;
end;
$$;
grant execute on function submit_quiz_attempt(uuid, text, int, int, jsonb) to anon, authenticated;

-- ============================================================
-- Row Level Security
-- ============================================================

alter table subjects enable row level security;
alter table topics enable row level security;
alter table questions enable row level security;
alter table profiles enable row level security;
alter table subscription_requests enable row level security;
alter table quiz_attempts enable row level security;
alter table attempt_answers enable row level security;
alter table admin_allowlist enable row level security;

-- subjects & topics: everyone can browse the catalog (titles only reveal
-- what exists, not the actual question content)
drop policy if exists "subjects_read_all" on subjects;
create policy "subjects_read_all" on subjects for select using (true);
drop policy if exists "subjects_write_admin" on subjects;
create policy "subjects_write_admin" on subjects for all using (is_admin()) with check (is_admin());

drop policy if exists "topics_read_all" on topics;
create policy "topics_read_all" on topics for select using (true);
drop policy if exists "topics_write_admin" on topics;
create policy "topics_write_admin" on topics for all using (is_admin()) with check (is_admin());

-- questions: only readable if the subject is free, the requester is an
-- active subscriber, or an admin. This is the actual paywall.
drop policy if exists "questions_read_gated" on questions;
create policy "questions_read_gated" on questions for select
  using (
    is_admin()
    or is_active_subscriber()
    or exists (select 1 from subjects s where s.id = subject_id and s.is_free)
  );
drop policy if exists "questions_write_admin" on questions;
create policy "questions_write_admin" on questions for all using (is_admin()) with check (is_admin());

-- paper_files: same gating as questions — free subject, active
-- subscriber, or admin. This is the metadata (title/year); the
-- actual file bytes are separately gated below via storage policies.
alter table paper_files enable row level security;
drop policy if exists "paper_files_read_gated" on paper_files;
create policy "paper_files_read_gated" on paper_files for select
  using (
    is_admin()
    or is_active_subscriber()
    or exists (select 1 from subjects s where s.id = subject_id and s.is_free)
  );
drop policy if exists "paper_files_write_admin" on paper_files;
create policy "paper_files_write_admin" on paper_files for all using (is_admin()) with check (is_admin());

-- storage.objects for the 'papers' bucket: files are uploaded under
-- a path like {subject_id}/{filename}, so the same subject-level gate
-- applies directly to the file bytes, not just the metadata row above.
drop policy if exists "papers_read_gated" on storage.objects;
create policy "papers_read_gated" on storage.objects for select
  using (
    bucket_id = 'papers'
    and (
      is_admin()
      or is_active_subscriber()
      or exists (select 1 from subjects s where s.id::text = (storage.foldername(name))[1] and s.is_free)
    )
  );
drop policy if exists "papers_write_admin" on storage.objects;
create policy "papers_write_admin" on storage.objects for insert to authenticated
  with check (bucket_id = 'papers' and is_admin());
drop policy if exists "papers_delete_admin" on storage.objects;
create policy "papers_delete_admin" on storage.objects for delete
  using (bucket_id = 'papers' and is_admin());

-- profiles: same ownership pattern as new+
drop policy if exists "profiles_select_own_or_admin" on profiles;
create policy "profiles_select_own_or_admin" on profiles for select
  using (auth_uid = auth.uid() or is_admin());
drop policy if exists "profiles_insert_own" on profiles;
create policy "profiles_insert_own" on profiles for insert
  with check (auth_uid = auth.uid());
drop policy if exists "profiles_update_own_or_admin" on profiles;
create policy "profiles_update_own_or_admin" on profiles for update
  using (auth_uid = auth.uid() or is_admin())
  with check (auth_uid = auth.uid() or is_admin());
drop policy if exists "profiles_delete_admin" on profiles;
create policy "profiles_delete_admin" on profiles for delete using (is_admin());

create or replace function protect_subscription_fields()
returns trigger language plpgsql as $$
begin
  if not is_admin() then
    new.subscription_status := old.subscription_status;
    new.subscription_expires_at := old.subscription_expires_at;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_protect_subscription on profiles;
create trigger trg_protect_subscription before update on profiles
  for each row execute function protect_subscription_fields();

-- subscription_requests: same pattern as new+
drop policy if exists "requests_insert_own" on subscription_requests;
create policy "requests_insert_own" on subscription_requests for insert
  with check (exists (select 1 from profiles p where p.id = profile_id and p.auth_uid = auth.uid()));
drop policy if exists "requests_select_own_or_admin" on subscription_requests;
create policy "requests_select_own_or_admin" on subscription_requests for select
  using (exists (select 1 from profiles p where p.id = profile_id and p.auth_uid = auth.uid()) or is_admin());
drop policy if exists "requests_update_admin" on subscription_requests;
create policy "requests_update_admin" on subscription_requests for update using (is_admin());

-- quiz_attempts / attempt_answers: only readable by their owner or admin.
-- Writes only happen via submit_quiz_attempt() above (security definer),
-- so no client-facing insert policy is needed for either table.
drop policy if exists "attempts_select_own_or_admin" on quiz_attempts;
create policy "attempts_select_own_or_admin" on quiz_attempts for select
  using (exists (select 1 from profiles p where p.id = profile_id and p.auth_uid = auth.uid()) or is_admin());

drop policy if exists "answers_select_own_or_admin" on attempt_answers;
create policy "answers_select_own_or_admin" on attempt_answers for select
  using (
    exists (
      select 1 from quiz_attempts qa join profiles p on p.id = qa.profile_id
      where qa.id = attempt_id and p.auth_uid = auth.uid()
    ) or is_admin()
  );

-- admin_allowlist: no direct client access; only is_admin() reads it (bypasses RLS via security definer)

-- ============================================================
-- Realtime: let the admin dashboard and the student app hear
-- about changes instantly instead of needing a manual refresh.
-- (If this errors saying the table is already a member, that's
-- fine — it just means it's already on; ignore that error.)
-- ============================================================
alter publication supabase_realtime add table subscription_requests;
alter publication supabase_realtime add table profiles;
