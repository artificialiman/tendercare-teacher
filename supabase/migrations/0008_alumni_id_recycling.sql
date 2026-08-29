-- ============================================================================
-- Alumni ID recycling — corrected model, direct instruction:
-- "id should never reset ... reset in that context means promotion. The
-- students with their id automatically promote to the next class, but
-- alumni/transfer genuinely reset to new class/transfers-in."
--
-- So: a student's id is permanent through every promotion (JSS1->JSS2->...
-- ->SS3) -- promotion only ever changes class_id, never touches id, and
-- nothing in this migration changes that. The ONLY place an id's ownership
-- legitimately changes is when a student becomes alumni (graduates) and,
-- exactly one year later, that specific id is deliberately handed to a new
-- admission -- either a fresh JSS1 intake or a transfer-in joining any
-- class, admin's choice, not automatic.
--
-- Literal string reuse is the real thing being asked for, not just freeing
-- a slot -- see handoff/ALUMNI-ID-RECYCLING-AND-ADMIN-PLAN.md in
-- Teacher-care for the fuller writeup. That means a graduate's full
-- history (scores, remarks, feed activity) has to be archived off the live
-- tables before their id can become someone else's primary key -- reusing
-- the id without archiving first would silently merge a new student's
-- future records with a stranger's five-year academic history under one
-- primary key, which is exactly what students.id-as-PK was chosen to
-- prevent (see 0001's header). This migration makes that archive step
-- mandatory and atomic with the id being freed.
-- ============================================================================

-- Distinguishes "this student graduated" from a generic soft-delete
-- (active=false alone already covers mistakes/withdrawals -- graduated_at
-- being set specifically means "alumni, eligible for the recycling clock").
alter table students add column graduated_at timestamptz;

-- Invariant #2 (student bio, teacher-editable) -- scope confirmed directly:
-- name/ID/portrait/average-remark. name/id/portrait already exist as
-- columns or are derived (average-remark comes from the existing remarks
-- trigger, not stored here); bio is the one genuinely missing field.
alter table students add column bio text;

-- ---------------------------------------------------------------------------
-- Archive -- holds a graduate's full record as a snapshot, keyed by the
-- id being freed, so their history survives the primary key being reused.
-- ---------------------------------------------------------------------------
create table alumni_archive (
  original_id text primary key,       -- the freed id, e.g. 'TCH-2025-014'
  full_name text not null,
  graduated_at timestamptz not null,
  recycled_at timestamptz not null default now(),
  scores_snapshot jsonb not null,      -- full scores rows for this student
  remarks_snapshot jsonb not null,     -- full remarks rows for this student
  feed_snapshot jsonb not null,        -- feed_comments/feed_likes authored
  reissued_to text,                    -- new student's full_name once the id is reused; null = still available
  reissued_at timestamptz
);

create index idx_alumni_archive_available on alumni_archive(original_id) where reissued_to is null;

-- Marks a student as alumni without deleting anything yet -- starts the
-- one-year clock. Separate from the eventual automatic promotion job
-- (invariant #9, not built) so this doesn't have to wait on that.
create or replace function public.mark_student_graduated(p_student_id text)
returns students
language plpgsql
security definer
set search_path = public
as $$
declare
  row_out students;
begin
  if coalesce(auth.jwt() ->> 'role', '') not in ('staff', 'admin') then
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

revoke all on function public.mark_student_graduated(text) from public;
grant execute on function public.mark_student_graduated(text) to authenticated;

-- Archives a graduate's history and hard-deletes their row, freeing the id
-- text for reuse. Admin-only (not staff) -- this is a real destructive
-- step, unlike the rest of the suite's soft-delete-by-default posture.
-- Gated to graduated_at <= now() - 1 year, matching the one-year window
-- given directly, and can't run twice on the same id since the row is gone
-- after the first call.
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
  if coalesce(auth.jwt() ->> 'role', '') <> 'admin' then
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

  -- Hard delete -- cascades to scores/remarks/feed_comments/feed_likes/
  -- portal_credentials per the ON DELETE CASCADE FKs in 0001, which is
  -- safe now because the snapshot above already preserved that data.
  delete from students where id = p_student_id;

  return p_student_id;
end;
$$;

revoke all on function public.recycle_alumni_id(text) from public;
grant execute on function public.recycle_alumni_id(text) to authenticated;

-- Extends create_student with an optional explicit id -- admin picks a
-- specific freed id from alumni_archive (via the admin UI) rather than the
-- function guessing when reuse is appropriate. Omitting p_id keeps the
-- existing sequential TCH-<academic-year>-<seq> behaviour unchanged for
-- ordinary new admissions.
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
  if coalesce(auth.jwt() ->> 'role', '') not in ('staff', 'admin') then
    raise exception 'only staff may create students';
  end if;

  if p_id is not null then
    -- Explicit reuse path -- must be a freed, not-yet-reissued alumni id.
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

comment on function public.create_student is
  'Allocates a new student id. With p_id omitted: next TCH-<academic-year>-<seq> '
  'in the normal sequence -- promotion never touches this, only new admissions do. '
  'With p_id set: reuses a specific freed alumni id (must exist in alumni_archive, '
  'unreissued) -- admin''s explicit choice for a JSS1 intake or transfer-in, not automatic.';

revoke all on function public.create_student(text, text, text) from public;
grant execute on function public.create_student(text, text, text) to authenticated;
