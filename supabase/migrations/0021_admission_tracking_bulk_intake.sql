-- ============================================================================
-- Admission tracking + bulk JSS1 intake.
--
-- Context (direct, from the school): admitting students is fundamental to
-- the business model. Every year there is a new JSS1 intake (2-3 arms, 60+
-- students), plus a trickle of new students into every other class, plus
-- students who leave.
--
-- Student ID convention is UNCHANGED: TCH-<academic-year>-<NNN>, sequence
-- resets per academic year (Sept 1 rollover), id permanent through
-- promotion, graduate ids recyclable after 1 year (0007/0008). This
-- migration only adds what that convention cannot express by itself:
--
--  1. The year inside an id is NOT a reliable cohort marker. All seeded
--     legacy students carry TCH-2025 whatever year they really joined, and
--     recycled ids (e.g. TCH-2025-014) will be handed to later intakes.
--     So admission facts get their own columns; ids stay opaque labels.
--     Legacy rows are left NULL on purpose -- guessing would be worse.
--  2. deleted_at already records WHEN a student left (0001); what was
--     missing is WHY, so a withdrawal is distinguishable from an entry
--     made in error.
--  3. create_student() adds one student per call -- fine for the trickle,
--     clumsy for a 60+ intake. create_students_bulk() admits a whole batch
--     atomically with gap-free ids.
--
-- NOT applied automatically. Review, then run in the Supabase SQL editor.
-- ============================================================================

alter table students add column admitted_academic_year text;   -- '2026/2027', same format as terms.academic_year
alter table students add column admission_type text
  check (admission_type in ('intake', 'transfer_in'));
alter table students add column exit_reason text
  check (exit_reason in ('withdrawn', 'transferred_out', 'entered_in_error', 'other'));

comment on column students.admitted_academic_year is
  'Academic session the student joined the school. NULL for legacy rows seeded before this column existed -- do not infer from the id prefix.';
comment on column students.admission_type is
  'intake = part of the yearly JSS1 intake; transfer_in = joined mid-stream into any class. NULL for legacy rows.';
comment on column students.exit_reason is
  'Why a student was removed (set alongside deleted_at). Graduates are tracked by graduated_at, not here.';

-- Start year of the current academic session (Sept 1 rollover, same
-- boundary as run_promotion and create_student).
create or replace function public.current_academic_year_start()
returns int
language sql
stable
as $$
  select case
    when extract(month from now()) >= 9 then extract(year from now())::int
    else extract(year from now())::int - 1
  end;
$$;

-- Next free sequence number for an id prefix. Looks at live students AND
-- archived alumni so a freed id with the same prefix is never skipped over
-- or collided with. Caller must already hold the advisory lock.
create or replace function public.next_student_seq(p_prefix text)
returns int
language sql
stable
as $$
  select coalesce(max(n), 0) + 1 from (
    select split_part(id, '-', 3)::int as n from students
      where id like p_prefix || '%'
    union all
    select split_part(original_id, '-', 3)::int from alumni_archive
      where original_id like p_prefix || '%'
  ) t;
$$;

-- ---------------------------------------------------------------------------
-- create_student: same behaviour as 0020, plus admission tracking.
-- Old 3-arg signature is dropped first -- keeping both overloads would make
-- every 2- or 3-arg rpc call ambiguous.
-- ---------------------------------------------------------------------------
drop function if exists public.create_student(text, text, text);

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
  if coalesce(auth.jwt() ->> 'app_role', '') not in ('staff', 'admin') then
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

revoke all on function public.create_student(text, text, text, text) from public;
grant execute on function public.create_student(text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- create_students_bulk: admit a whole batch in ONE transaction.
--   p_rows: [{"full_name": "...", "class_id": "JSS1A"}, ...]
-- Ids are allocated gap-free, in array order, under the same advisory lock
-- as create_student. All-or-nothing: any bad row rolls back the batch.
-- For admission type 'intake', every row must target a JSS1 class.
-- ---------------------------------------------------------------------------
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
  if coalesce(auth.jwt() ->> 'app_role', '') not in ('staff', 'admin') then
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

revoke all on function public.create_students_bulk(jsonb, text) from public;
grant execute on function public.create_students_bulk(jsonb, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Leavers: when a student is soft-removed without graduating and no reason
-- was given, default exit_reason to 'other' so the field is never silently
-- blank on a removed student. Restoring a student clears it.
-- ---------------------------------------------------------------------------
create or replace function public.students_exit_reason_default()
returns trigger
language plpgsql
as $$
begin
  if old.active = true and new.active = false and new.graduated_at is null then
    new.exit_reason := coalesce(new.exit_reason, 'other');
  elsif old.active = false and new.active = true then
    new.exit_reason := null;
  end if;
  return new;
end;
$$;

create trigger trg_students_exit_reason
  before update on students
  for each row execute function public.students_exit_reason_default();
