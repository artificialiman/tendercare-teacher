-- ============================================================================
-- Feed as a real notification board (Lane 2, September rollover handoff).
--
-- Deliberately NEW tables, not a repurpose of feed_comments/feed_likes
-- (0001). Those tables are load-bearing for a DIFFERENT feature: student-
-- authored comments/likes, with feed_comments.author_student_id feeding
-- 0008's alumni graduation snapshot (a graduating student's own feed
-- activity gets archived before their id is freed for recycling). This
-- spec is not that feature wearing a different UI -- it's admin/result
-- activity only (upload dates, class averages, media changes, staff
-- role/arrival changes), reactions-only with no comments at all, and on
-- a completely different retention rhythm (weekly deletion + a full
-- yearly wipe, vs. feed_comments/feed_likes which currently have no
-- retention policy of their own). Repurposing the existing tables would
-- either break 0008's snapshot (if student authorship were dropped) or
-- force this feature to carry a column set it doesn't need. Building
-- alongside is strictly additive and reversible if this turns out wrong
-- -- gutting a table another migration already depends on is not.
--
-- feed_comments/feed_likes are UNTOUCHED by this migration. If they're
-- ever formally retired, that's its own deliberate migration once
-- there's an actual plan for whatever they were originally meant to
-- serve -- not a side effect of this one.
-- ============================================================================

-- One row per notification-board entry. `kind` is a closed set matching
-- the spec's content list exactly (result uploads, class averages, media
-- changes, new teacher roles, part-time/corps-member arrivals) --
-- deliberately NOT open text, so this can never silently become a
-- student-commenting surface by another column just being free-form.
-- `payload` carries whatever structured detail each kind needs (e.g.
-- which class, which average, whose role changed) so the web display
-- can render a real sentence per kind rather than a stored pre-rendered
-- string that goes stale if the rendering rules change later.
create table feed_posts (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in (
    'result_upload',
    'class_average',
    'media_change',
    'staff_role_change',
    'staff_arrival'
  )),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Reactions only, no comment body at all -- the spec is explicit that
-- this is not open student commentary. One row per (post, student)
-- reaction, same shape as feed_likes' primary key for a reason: a
-- student can react to a given post once, not stack reactions.
-- Anonymous/visitor reactions are NOT supported here (unlike
-- feed_comments.author_student_id being nullable for exactly that) --
-- the spec's "3x count inflation" only makes sense as a real per-
-- student count being multiplied for display, not a free-for-all
-- counter open visitors could inflate arbitrarily by re-reacting.
create table feed_reactions (
  post_id uuid not null references feed_posts(id) on delete cascade,
  student_id text not null references students(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, student_id)
);

create index idx_feed_posts_created on feed_posts(created_at desc);
create index idx_feed_reactions_post on feed_reactions(post_id);

alter table feed_posts enable row level security;
alter table feed_reactions enable row level security;

-- Same read/write shape as feed_comments/feed_likes (0002): anyone
-- authenticated can read, a student can only act as themselves. Posts
-- themselves are never student-writable -- they're created by staff-
-- side activity (result uploads, staff-roster changes, etc.), so the
-- only student-facing write surface here is reacting, not posting.
create policy "feed posts are publicly readable"
  on feed_posts for select using (true);

create policy "feed posts are staff-written only"
  on feed_posts for insert
  with check (coalesce(auth.jwt() ->> 'role', '') in ('staff', 'admin'));

create policy "feed reactions are publicly readable"
  on feed_reactions for select using (true);

create policy "a student can only react as themselves"
  on feed_reactions for all
  using (student_id = auth.jwt() ->> 'student_id')
  with check (student_id = auth.jwt() ->> 'student_id');

comment on table feed_posts is
  'Admin/result activity notification board (Lane 2, Sept 2026 handoff). '
  'NOT student commentary -- see feed_comments for that separate, older '
  'feature. kind is a closed set on purpose; do not add a free-text post '
  'type without also updating the spec this table was built against.';

comment on column feed_posts.payload is
  'Structured detail specific to each kind -- e.g. {"class_id": "SS2 '
  'Science", "average": 68.4} for class_average, {"staff_name": ..., '
  '"new_role": ...} for staff_role_change. Rendering into a display '
  'sentence happens in tendercare-web, not here, so wording changes '
  'never require a migration.';

comment on table feed_reactions is
  'Reactions only -- no comment body exists on this table by design. '
  'The web display multiplies the raw count by 3 for the shown number '
  '(inflated by design, not a bug) -- that multiplication happens in '
  'display code, not stored here, so the true per-student count stays '
  'auditable.';

-- ----------------------------------------------------------------------------
-- Retention: two distinct, non-contradictory jobs per the spec --
--   1. Weekly deletion of feed activity, feed-specific, runs regardless
--      of the yearly reset.
--   2. Full wipe on the Sept 1 rollover, tied to the same event as
--      student promotion (0012/0014/0015's run_promotion()), not a
--      separate schedule of its own.
-- Both are exposed here as callable functions; NEITHER is wired to a
-- schedule by this migration. No cron exists anywhere in this suite as
-- of the September 2026 reconciliation (INVARIANTS.md) -- job 1 needs a
-- pg_cron schedule or an external scheduled trigger (GitHub Actions,
-- Supabase's scheduled Edge Functions, etc., whichever this project
-- ends up using elsewhere), which is an infrastructure decision, not
-- this migration's to make unilaterally. Job 2 is folded into
-- run_promotion() itself below, since that's staff-triggered already
-- and the spec ties this wipe to that exact event, not an independent
-- yearly date check that could drift out of sync with when promotion
-- actually runs.
-- ----------------------------------------------------------------------------

create or replace function public.delete_old_feed_activity(older_than_days int default 7)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count int;
begin
  if coalesce(auth.jwt() ->> 'role', '') not in ('staff', 'admin') then
    raise exception 'only staff may delete feed activity';
  end if;

  delete from feed_posts
  where created_at < now() - (older_than_days || ' days')::interval;
  get diagnostics deleted_count = row_count;

  return deleted_count;
end;
$$;

revoke all on function public.delete_old_feed_activity(int) from public;
grant execute on function public.delete_old_feed_activity(int) to authenticated;

comment on function delete_old_feed_activity is
  'Weekly deletion leg of the feed retention spec -- feed-specific, runs '
  'regardless of the yearly Sept 1 reset (see run_promotion() for that '
  'separate wipe). NOT scheduled by this migration -- no cron exists in '
  'this suite yet; wiring a weekly trigger (pg_cron, GitHub Actions, '
  'Supabase scheduled function) is a deliberate follow-up, not bundled '
  'here so this migration stays reviewable as schema-only.';

-- run_promotion() (0015) is extended, not replaced wholesale a fourth
-- time for an unrelated reason -- the Sept 1 feed wipe is tied to this
-- exact event per the spec, and duplicating its staff-role guard and
-- already-run guard in a second function would be two places that can
-- drift out of sync on what "the Sept 1 rollover" means. One new line
-- at the end, inside the existing will_roll_term guard, so the feed
-- only clears when promotion genuinely runs (not on a rejected/guarded
-- call that raises before reaching this point).
create or replace function public.run_promotion()
returns table(promoted_count int, graduated_count int, pending_assignment_count int)
language plpgsql
security definer
set search_path = public
as $$
declare
  s record;
  target_id text;
  promoted int := 0;
  graduated int := 0;
  pending int := 0;
  cur_term record;
  cur_year_start int;
  new_academic_year text;
  new_term_id text;
  will_roll_term boolean := false;
begin
  if coalesce(auth.jwt() ->> 'role', '') not in ('staff', 'admin') then
    raise exception 'only staff may run promotion';
  end if;

  select * into cur_term from terms where is_current = true order by id desc limit 1;
  if found then
    will_roll_term := true;
    cur_year_start := split_part(cur_term.academic_year, '/', 1)::int;
    new_academic_year := (cur_year_start + 1) || '/' || (cur_year_start + 2);
    new_term_id := replace(new_academic_year, '/', '-') || '-T1';

    if exists (select 1 from terms where id = new_term_id) then
      raise exception 'promotion has already been run for % -- % already exists', new_academic_year, new_term_id;
    end if;
  end if;

  if not exists (select 1 from classes where id = 'SS1 Unassigned') then
    perform add_class('SS', 1, 'Unassigned', 'SS1 New');
  end if;

  for s in
    select st.id, c.stage, c.level, c.arm
    from students st
    join classes c on c.id = st.class_id
    where st.active = true and st.repeating = false and c.arm <> 'Unassigned'
    order by st.id
  loop
    if s.stage = 'JSS' and s.level < 3 then
      target_id := 'JSS' || (s.level + 1) || s.arm;
      if not exists (select 1 from classes where id = target_id) then
        perform add_class('JSS', s.level + 1, s.arm);
      end if;
      update students set class_id = target_id where id = s.id;
      promoted := promoted + 1;

    elsif s.stage = 'JSS' and s.level = 3 then
      update students set class_id = 'SS1 Unassigned' where id = s.id;
      pending := pending + 1;

    elsif s.stage = 'SS' and s.level < 3 then
      target_id := 'SS' || (s.level + 1) || ' ' || s.arm;
      if not exists (select 1 from classes where id = target_id) then
        perform add_class('SS', s.level + 1, s.arm);
      end if;
      update students set class_id = target_id where id = s.id;
      promoted := promoted + 1;

    elsif s.stage = 'SS' and s.level = 3 then
      perform mark_student_graduated(s.id);
      graduated := graduated + 1;
    end if;
  end loop;

  if will_roll_term then
    insert into terms (id, academic_year, term_number, is_current)
    values (new_term_id, new_academic_year, 1, true)
    on conflict (id) do nothing;

    update terms set is_current = false where id = cur_term.id;
    update terms set is_current = true where id = new_term_id;

    -- Full feed wipe, tied to this exact rollover event per the spec --
    -- only reached once promotion has genuinely committed to running
    -- (past both the role guard and the already-run guard above), never
    -- on a rejected call. feed_comments/feed_likes are untouched here;
    -- this is the new admin-activity board only.
    delete from feed_reactions;
    delete from feed_posts;
  end if;

  return query select promoted, graduated, pending;
end;
$$;

revoke all on function public.run_promotion() from public;
grant execute on function public.run_promotion() to authenticated;
