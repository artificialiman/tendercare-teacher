-- ============================================================================
-- 0023 -- TEMPORARY OPEN ACCESS (midterm exams week)
--
-- Decision (from the school's tech lead): sign-in is removed from the teacher
-- and admin apps for now so the tech team and staff can work freely during
-- midterm exams; the app URLs are shared only with staff and agents. Real
-- auth is implemented AFTER the exams, at which point this migration is
-- switched off.
--
-- WHAT THIS DOES
--   Lets the public (anon) key read/write the tables the two apps use, and
--   run the staff/admin-only functions, WHILE open_access = true.
--
-- WHAT THIS DOES NOT OPEN
--   portal_credentials (password hashes), alumni_archive and the feed tables
--   keep their existing locked policies. Apply after 0021 and 0022.
--
-- KNOW THE TRADE-OFF
--   The anon key ships inside the apps' JavaScript. Anyone who has the key
--   -- not just anyone with the URL -- can read and change student records
--   directly while this is on. Keep the key out of public repos/pages and
--   switch this off as soon as exams end.
--
-- SWITCH OFF (one statement, instant, no code change):
--     update public.app_settings set value = 'false'::jsonb where key = 'open_access';
-- SWITCH ON AGAIN:
--     update public.app_settings set value = 'true'::jsonb where key = 'open_access';
-- REMOVE COMPLETELY: run supabase/rollback/0023_rollback_open_access.sql
-- ============================================================================

create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.app_settings enable row level security;  -- no policies: anon/authenticated cannot read or change it

insert into public.app_settings (key, value) values ('open_access', 'true'::jsonb)
  on conflict (key) do nothing;

create or replace function public.open_access_enabled()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select (value)::text = 'true' from public.app_settings where key = 'open_access'), false);
$$;

-- True if open access is on, OR the signed-in user's app_role is allowed.
-- Auth keeps working exactly as before once open access is switched off.
create or replace function public.caller_may(p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.open_access_enabled()
      or coalesce(auth.jwt() ->> 'app_role', '') = any (p_roles);
$$;

-- ---------------------------------------------------------------------------
-- Table access for the anon key, gated by the switch.
-- ---------------------------------------------------------------------------
create policy "TEMP open access (anon)" on public.students
  for all to anon
  using (public.open_access_enabled())
  with check (public.open_access_enabled());

create policy "TEMP open access (anon)" on public.classes
  for all to anon
  using (public.open_access_enabled())
  with check (public.open_access_enabled());

create policy "TEMP open access (anon)" on public.subjects
  for all to anon
  using (public.open_access_enabled())
  with check (public.open_access_enabled());

create policy "TEMP open access (anon)" on public.class_subjects
  for all to anon
  using (public.open_access_enabled())
  with check (public.open_access_enabled());

create policy "TEMP open access (anon)" on public.terms
  for all to anon
  using (public.open_access_enabled())
  with check (public.open_access_enabled());

create policy "TEMP open access (anon)" on public.scores
  for all to anon
  using (public.open_access_enabled())
  with check (public.open_access_enabled());

create policy "TEMP open access (anon)" on public.remarks
  for all to anon
  using (public.open_access_enabled())
  with check (public.open_access_enabled());

create policy "TEMP open access (anon)" on public.staff
  for all to anon
  using (public.open_access_enabled())
  with check (public.open_access_enabled());

create policy "TEMP open access (anon)" on public.staff_subjects
  for all to anon
  using (public.open_access_enabled())
  with check (public.open_access_enabled());

create policy "TEMP open access (anon)" on public.staff_classes
  for all to anon
  using (public.open_access_enabled())
  with check (public.open_access_enabled());

-- ---------------------------------------------------------------------------
-- Functions: same bodies as 0020/0021, but the role check goes through
-- caller_may(), so it passes while open access is on and still honours
-- app_role afterwards.
-- ---------------------------------------------------------------------------

create or replace function public.mark_student_graduated(p_student_id text)
returns students
language plpgsql
security definer
set search_path = public
as $$
declare
  row_out students;
begin
  if not public.caller_may(array['staff', 'admin']) then
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
  if not public.caller_may(array['admin']) then
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
  if not public.caller_may(array['staff', 'admin']) then
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
  if not public.caller_may(array['staff', 'admin']) then
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

create or replace function public.delete_old_feed_activity(older_than_days int default 7)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count int;
begin
  if not public.caller_may(array['staff', 'admin']) then
    raise exception 'only staff may delete feed activity';
  end if;

  delete from feed_posts
  where created_at < now() - (older_than_days || ' days')::interval;
  get diagnostics deleted_count = row_count;

  return deleted_count;
end;
$$;

create or replace function public.create_student(
  p_full_name text,
  p_class_id text,
  p_id text default null,
  p_admission_type text default 'transfer_in'
)
returns students
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id text;
  new_row students;
  year_start int;
  current_year_prefix text;
begin
  if not public.caller_may(array['staff', 'admin']) then
    raise exception 'only staff may create students';
  end if;

  if p_admission_type not in ('intake', 'transfer_in') then
    raise exception 'admission type must be intake or transfer_in';
  end if;

  year_start := current_academic_year_start();

  if p_id is not null then
    if not exists (select 1 from alumni_archive where original_id = p_id and reissued_to is null) then
      raise exception 'id % is not an available recycled alumni id', p_id;
    end if;
    new_id := p_id;
    update alumni_archive set reissued_to = p_full_name, reissued_at = now() where original_id = p_id;
  else
    perform pg_advisory_xact_lock(hashtext('next_student_id'));
    current_year_prefix := 'TCH-' || year_start || '-';
    new_id := current_year_prefix || lpad(next_student_seq(current_year_prefix)::text, 3, '0');
  end if;

  insert into students (id, full_name, class_id, created_by, admitted_academic_year, admission_type)
  values (new_id, p_full_name, p_class_id, auth.uid(),
          year_start || '/' || (year_start + 1), p_admission_type)
  returning * into new_row;

  return new_row;
end;
$$;

create or replace function public.create_students_bulk(
  p_rows jsonb,
  p_admission_type text default 'intake'
)
returns setof students
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  year_start int;
  current_year_prefix text;
  next_n int;
  new_row students;
begin
  if not public.caller_may(array['staff', 'admin']) then
    raise exception 'only staff may create students';
  end if;

  if p_admission_type not in ('intake', 'transfer_in') then
    raise exception 'admission type must be intake or transfer_in';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'p_rows must be a non-empty JSON array';
  end if;

  perform pg_advisory_xact_lock(hashtext('next_student_id'));

  year_start := current_academic_year_start();
  current_year_prefix := 'TCH-' || year_start || '-';
  next_n := next_student_seq(current_year_prefix);

  for r in
    select ord, btrim(elem ->> 'full_name') as full_name, elem ->> 'class_id' as class_id
    from jsonb_array_elements(p_rows) with ordinality as t(elem, ord)
    order by ord
  loop
    if r.full_name is null or r.full_name = '' then
      raise exception 'row %: full_name is required', r.ord;
    end if;

    if not exists (select 1 from classes where id = r.class_id) then
      raise exception 'row % (%): class % does not exist', r.ord, r.full_name, r.class_id;
    end if;

    if p_admission_type = 'intake'
       and not exists (select 1 from classes where id = r.class_id and stage = 'JSS' and level = 1) then
      raise exception 'row % (%): intake students must go into a JSS1 class, not %', r.ord, r.full_name, r.class_id;
    end if;

    insert into students (id, full_name, class_id, created_by, admitted_academic_year, admission_type)
    values (current_year_prefix || lpad(next_n::text, 3, '0'), r.full_name, r.class_id, auth.uid(),
            year_start || '/' || (year_start + 1), p_admission_type)
    returning * into new_row;

    next_n := next_n + 1;
    return next new_row;
  end loop;

  return;
end;
$$;

-- anon may call these (they were authenticated-only). Each one still checks
-- caller_may() inside, so switching open access off closes them again.
grant execute on function public.create_student(text, text, text, text) to anon;
grant execute on function public.create_students_bulk(jsonb, text) to anon;
grant execute on function public.mark_student_graduated(text) to anon;
grant execute on function public.recycle_alumni_id(text) to anon;
grant execute on function public.add_class(text, int, text, text) to anon;
grant execute on function public.run_promotion() to anon;
grant execute on function public.delete_old_feed_activity(int) to anon;
