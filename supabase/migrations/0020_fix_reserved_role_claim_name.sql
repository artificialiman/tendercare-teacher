-- ============================================================================
-- THE ACTUAL ROOT CAUSE, finally found after three failed attempts
-- (0018, 0019, and the sb_publishable_ key swap -- none of those were
-- wrong to try given the evidence at each point, but none of them were
-- the real bug either).
--
-- The smoking gun: after 0018/0019's hook correctly promoted
-- app_metadata.role onto the JWT as a top-level "role" claim, classes
-- started returning `{"code": "22023", "message": "role \"staff\" does
-- not exist"}` -- a genuine Postgres error, not an app-level one.
--
-- "role" is not an ordinary claim name to PostgREST. PostgREST reads a
-- top-level JWT claim literally named "role" and uses it to
-- `SET ROLE <that value>` on the actual database connection -- an
-- attempt to switch to a real Postgres database role, completely
-- separate from anything an RLS policy's `auth.jwt() ->> 'role'` check
-- was trying to do. This codebase never created a Postgres role named
-- `staff` or `admin` -- those were only ever meant to be string values
-- compared inside RLS policies, not Postgres roles to switch into. The
-- moment a claim named "role" existed with that value, PostgREST tried
-- to become that Postgres role and failed, because it doesn't exist.
--
-- This explains why it was invisible before 0018: with no Custom
-- Access Token Hook, "role" was never present as a *custom* top-level
-- claim in the first place (Supabase's own "authenticated"/"anon"
-- value occupied that slot instead, which IS a real Postgres role) --
-- so every auth.jwt() ->> 'role' check across 0002-0016 was quietly
-- reading the wrong thing and returning null/'authenticated', not
-- 'staff'/'admin', ever since 0003. That's a second, independent bug
-- that's been there since 0003 and was simply never caught, because
-- app_metadata being unset (the original, also-wrong hypothesis this
-- session started from) produced the identical symptom either error
-- happened to be reached by, for entirely different reasons.
--
-- Supabase's own documented RBAC pattern
-- (supabase.com/docs/guides/auth/custom-claims-and-role-based-access-
-- control-rbac) uses a claim named `user_role`, specifically to avoid
-- this exact collision -- never the bare word `role`. This migration
-- renames the custom claim to `app_role` throughout (matching that
-- guidance's intent while staying close to this codebase's existing
-- naming), and rewrites every RLS policy and function that checked
-- `auth.jwt() ->> 'role'` to check `auth.jwt() ->> 'app_role'` instead.
--
-- No RLS policy can be "or replace"d in Postgres -- each one below is
-- dropped and recreated. Every affected function uses `create or
-- replace`, which works. Every body below is the actual current live
-- version from its most recent defining migration (0002, 0007 -> 0008
-- for create_student, 0008 for mark_student_graduated/
-- recycle_alumni_id, 0011 for add_class, 0016 for run_promotion,
-- 0016 for the feed listener functions), with only the claim name
-- changed -- no other logic touched.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. The hook itself: emit app_role, not role.
-- ----------------------------------------------------------------------------

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
as $$
declare
  claims jsonb;
  user_role text;
begin
  claims := event -> 'claims';

  select raw_app_meta_data ->> 'role' into user_role
  from auth.users
  where id = (event ->> 'user_id')::uuid;

  if user_role is not null then
    -- app_role, not role -- "role" is reserved by PostgREST for
    -- SET ROLE and must never be used as a custom claim name. The
    -- source column (app_metadata.role) keeps its existing name; only
    -- the JWT claim this promotes it to is renamed.
    claims := jsonb_set(claims, '{app_role}', to_jsonb(user_role));
  end if;

  return jsonb_build_object('claims', claims);
end;
$$;

comment on function custom_access_token_hook is
  'Custom Access Token Hook -- promotes auth.users.raw_app_meta_data.role '
  'onto the JWT as a top-level "app_role" claim (NOT "role" -- that name '
  'is reserved by PostgREST for SET ROLE and caused '
  '''role "staff" does not exist'' errors when used, see 0020). MUST be '
  'enabled in Authentication > Hooks (Custom Access Token) for this to '
  'run at all -- if 0018/0019''s version was already selected there, no '
  'further dashboard action is needed, this migration replaces the '
  'function in place. Still requires one fresh login after this '
  'migration is applied.';


-- ----------------------------------------------------------------------------
-- 2. RLS policies (0002_rls_policies.sql) -- drop and recreate each,
--    same table/command/logic, app_role instead of role.
-- ----------------------------------------------------------------------------

drop policy if exists "staff can manage reference data" on classes;
create policy "staff can manage reference data"
  on classes for all using (auth.jwt() ->> 'app_role' = 'staff');

drop policy if exists "staff can manage reference data" on subjects;
create policy "staff can manage reference data"
  on subjects for all using (auth.jwt() ->> 'app_role' = 'staff');

drop policy if exists "staff can manage reference data" on terms;
create policy "staff can manage reference data"
  on terms for all using (auth.jwt() ->> 'app_role' = 'staff');

drop policy if exists "staff can do everything on students" on students;
create policy "staff can do everything on students"
  on students for all
  using (auth.jwt() ->> 'app_role' = 'staff')
  with check (auth.jwt() ->> 'app_role' = 'staff');

drop policy if exists "staff can manage scores" on scores;
create policy "staff can manage scores"
  on scores for all
  using (auth.jwt() ->> 'app_role' = 'staff')
  with check (auth.jwt() ->> 'app_role' = 'staff');

drop policy if exists "a student can read only their own scores" on scores;
create policy "a student can read only their own scores"
  on scores for select
  using (auth.jwt() ->> 'app_role' = 'staff' or student_id = auth.jwt() ->> 'student_id');

drop policy if exists "staff can manage remarks" on remarks;
create policy "staff can manage remarks"
  on remarks for all
  using (auth.jwt() ->> 'app_role' = 'staff')
  with check (auth.jwt() ->> 'app_role' = 'staff');

drop policy if exists "a student can read only their own remarks" on remarks;
create policy "a student can read only their own remarks"
  on remarks for select
  using (auth.jwt() ->> 'app_role' = 'staff' or student_id = auth.jwt() ->> 'student_id');

drop policy if exists "staff can manage credentials" on portal_credentials;
create policy "staff can manage credentials"
  on portal_credentials for all
  using (auth.jwt() ->> 'app_role' = 'staff')
  with check (auth.jwt() ->> 'app_role' = 'staff');

-- feed_comments/feed_likes (0002) -- these never checked role for
-- select/insert (only student_id self-checks, unaffected), so nothing
-- to change there. Listed here for completeness of the audit, not
-- touched.

-- alumni_archive (0009_alumni_archive_rls.sql)
drop policy if exists "admin can manage alumni archive" on alumni_archive;
create policy "admin can manage alumni archive"
  on alumni_archive for all
  using (auth.jwt() ->> 'app_role' = 'admin')
  with check (auth.jwt() ->> 'app_role' = 'admin');

-- staff table (0010_staff_table.sql)
drop policy if exists "admin manages staff" on staff;
create policy "admin manages staff"
  on staff for all
  using (auth.jwt() ->> 'app_role' = 'admin')
  with check (auth.jwt() ->> 'app_role' = 'admin');

drop policy if exists "staff can view the staff list" on staff;
create policy "staff can view the staff list"
  on staff for select
  using (auth.jwt() ->> 'app_role' in ('staff', 'admin'));

-- feed_posts (0016_feed_notification_board.sql)
drop policy if exists "feed posts are staff-written only" on feed_posts;
create policy "feed posts are staff-written only"
  on feed_posts for insert
  with check (coalesce(auth.jwt() ->> 'app_role', '') in ('staff', 'admin'));


-- ----------------------------------------------------------------------------
-- 3. Functions -- create or replace, same bodies, app_role instead of role.
-- ----------------------------------------------------------------------------

-- create_student (live signature per 0008: 3-arg, p_id optional)
create or replace function public.create_student(p_full_name text, p_class_id text, p_id text default null)
returns students
language plpgsql
security definer
set search_path = public
as $$
declare
  last_id text;
  next_n int;
  new_id text;
  new_row students;
  current_year_prefix text;
  academic_year_label int;
begin
  if coalesce(auth.jwt() ->> 'app_role', '') not in ('staff', 'admin') then
    raise exception 'only staff may create students';
  end if;

  if p_id is not null then
    if not exists (select 1 from alumni_archive where original_id = p_id and reissued_to is null) then
      raise exception 'id % is not an available recycled alumni id', p_id;
    end if;
    new_id := p_id;
    update alumni_archive set reissued_to = p_full_name, reissued_at = now() where original_id = p_id;
  else
    perform pg_advisory_xact_lock(hashtext('next_student_id'));

    academic_year_label := case
      when extract(month from now()) >= 9 then extract(year from now())::int
      else extract(year from now())::int - 1
    end;
    current_year_prefix := 'TCH-' || academic_year_label || '-';

    select id into last_id from students
    where id like current_year_prefix || '%'
    order by id desc limit 1;

    if last_id is null then
      next_n := 1;
    else
      next_n := (split_part(last_id, '-', 3))::int + 1;
    end if;

    new_id := current_year_prefix || lpad(next_n::text, 3, '0');
  end if;

  insert into students (id, full_name, class_id, created_by)
  values (new_id, p_full_name, p_class_id, auth.uid())
  returning * into new_row;

  return new_row;
end;
$$;

-- mark_student_graduated (0008)
create or replace function public.mark_student_graduated(p_student_id text)
returns students
language plpgsql
security definer
set search_path = public
as $$
declare
  row_out students;
begin
  if coalesce(auth.jwt() ->> 'app_role', '') not in ('staff', 'admin') then
    raise exception 'only staff/admin may mark a student graduated';
  end if;

  update students
  set active = false, graduated_at = coalesce(graduated_at, now())
  where id = p_student_id
  returning * into row_out;

  if row_out.id is null then
    raise exception 'student % not found', p_student_id;
  end if;

  return row_out;
end;
$$;

-- recycle_alumni_id (0008)
create or replace function public.recycle_alumni_id(p_student_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  grad_at timestamptz;
  s_name text;
  scores_json jsonb;
  remarks_json jsonb;
  feed_json jsonb;
begin
  if coalesce(auth.jwt() ->> 'app_role', '') <> 'admin' then
    raise exception 'only admin may recycle an alumni id';
  end if;

  select graduated_at, full_name into grad_at, s_name
  from students where id = p_student_id;

  if grad_at is null then
    raise exception 'student % is not marked graduated (or does not exist)', p_student_id;
  end if;

  if grad_at > now() - interval '1 year' then
    raise exception 'student % graduated % -- not eligible for recycling until %',
      p_student_id, grad_at, grad_at + interval '1 year';
  end if;

  select coalesce(jsonb_agg(to_jsonb(s.*)), '[]'::jsonb) into scores_json
    from scores s where s.student_id = p_student_id;
  select coalesce(jsonb_agg(to_jsonb(r.*)), '[]'::jsonb) into remarks_json
    from remarks r where r.student_id = p_student_id;
  select coalesce(jsonb_agg(to_jsonb(f.*)), '[]'::jsonb) into feed_json
    from feed_comments f where f.author_student_id = p_student_id;

  insert into alumni_archive (original_id, full_name, graduated_at, scores_snapshot, remarks_snapshot, feed_snapshot)
  values (p_student_id, s_name, grad_at, scores_json, remarks_json, feed_json);

  delete from students where id = p_student_id;

  return p_student_id;
end;
$$;

-- add_class (0011) -- only the guard line changes; rest of body
-- (id/label construction, existence checks) is untouched and omitted
-- here would be wrong for create-or-replace (it replaces the WHOLE
-- body), so the full function is restated.
create or replace function public.add_class(
  p_stage text,
  p_level int,
  p_arm text,
  p_label text default null
)
returns classes
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id text;
  new_label text;
  new_row classes;
  max_sort int;
begin
  if coalesce(auth.jwt() ->> 'app_role', '') not in ('staff', 'admin') then
    raise exception 'only staff may add a class';
  end if;

  if p_stage not in ('JSS', 'SS') then
    raise exception 'stage must be JSS or SS';
  end if;
  if p_level not in (1, 2, 3) then
    raise exception 'level must be 1, 2, or 3';
  end if;
  if p_arm is null or length(trim(p_arm)) = 0 then
    raise exception 'arm/department name is required';
  end if;

  if p_stage = 'JSS' then
    new_id := 'JSS' || p_level || p_arm;
    new_label := coalesce(p_label, new_id);
  else
    new_id := 'SS' || p_level || ' ' || p_arm;
    new_label := coalesce(p_label, 'SS' || p_level || ' ' || left(p_arm, 3));
  end if;

  if exists (select 1 from classes where id = new_id) then
    raise exception 'class % already exists', new_id;
  end if;

  select coalesce(max(sort_order), 0) into max_sort from classes;

  insert into classes (id, label, arm, sort_order)
  values (new_id, new_label, p_arm, max_sort + 1)
  returning * into new_row;

  return new_row;
end;
$$;

-- run_promotion (live version per 0016 -- unchanged body except the
-- guard line; the feed-wipe addition from 0016 is preserved as-is)
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
  if coalesce(auth.jwt() ->> 'app_role', '') not in ('staff', 'admin') then
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

    delete from feed_reactions;
    delete from feed_posts;
  end if;

  return query select promoted, graduated, pending;
end;
$$;

-- delete_old_feed_activity (0016)
create or replace function public.delete_old_feed_activity(older_than_days int default 7)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count int;
begin
  if coalesce(auth.jwt() ->> 'app_role', '') not in ('staff', 'admin') then
    raise exception 'only staff may delete feed activity';
  end if;

  delete from feed_posts
  where created_at < now() - (older_than_days || ' days')::interval;
  get diagnostics deleted_count = row_count;

  return deleted_count;
end;
$$;

comment on function run_promotion is
  'Staff-triggered promotion + term rollover. Guard fixed in 0020 to '
  'check app_role (not role -- see that migration''s header for why '
  '"role" as a JWT claim name is unsafe with PostgREST).';
