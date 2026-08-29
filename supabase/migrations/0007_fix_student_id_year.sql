-- ============================================================================
-- create_student() had 'TCH-2025-' as a literal string constant, not
-- derived from anything -- confirmed by pulling the live function body
-- (see handoff/ADD-STUDENT-AND-BRAND-SPEC.md in Teacher-care for the
-- verification). Every student created through this function, in any
-- year, would have gotten a 2025 ID forever.
--
-- CORRECTION to that spec doc's suggested fix: it recommended deriving
-- the prefix from to_char(now(), 'YYYY') directly (raw calendar year).
-- That's wrong for this school specifically -- the academic year rolls
-- over on September 1st (see the promotion invariant), not January 1st,
-- and terms.academic_year already models sessions as 'YYYY/YYYY' spans
-- for exactly this reason. Verified against the live clock: today is
-- 2026-08-29 -- three days before the Sept 1 rollover -- so a raw
-- to_char(now(),'YYYY') would assign new students 'TCH-2026-...' RIGHT
-- NOW, even though the school is still inside the 2025/2026 session and
-- the existing 376 students are correctly labeled 'TCH-2025-...'. The
-- fix below derives the *academic* year instead: before September 1st,
-- the label is (calendar year - 1); on or after, it's the calendar year
-- itself -- same boundary the promotion job uses.
--
-- DEFAULT CHOSEN (was left open in the spec, deciding here rather than
-- leaving it unresolved): the sequence RESETS per academic year -- the
-- first student added in the 2026/2027 session becomes TCH-2026-001,
-- not TCH-2026-377. Reasoning: a human-readable ID tied to an
-- enrollment session should read as "the Nth student in that session's
-- cohort," not carry forward a running total that no longer means
-- anything once the year prefix changes. Reversible: if global-
-- continuous numbering is wanted instead, drop the `where id like ...`
-- filter below and this is a one-line revert.
-- ============================================================================

create or replace function public.create_student(p_full_name text, p_class_id text)
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
  if coalesce(auth.jwt() ->> 'role', '') <> 'staff' then
    raise exception 'only staff may create students';
  end if;

  perform pg_advisory_xact_lock(hashtext('next_student_id'));

  -- Academic year, not calendar year: rolls over Sept 1, same boundary
  -- as the promotion job, not Jan 1.
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

  insert into students (id, full_name, class_id, created_by)
  values (new_id, p_full_name, p_class_id, auth.uid())
  returning * into new_row;

  return new_row;
end;
$$;

comment on function public.create_student is
  'Allocates the next TCH-<academic-year>-<seq> ID for a new student. '
  'Academic year rolls over Sept 1 (matches the promotion job''s '
  'boundary), not Jan 1 -- see this migration''s header for why a raw '
  'calendar-year derivation would have been wrong. Sequence resets per '
  'academic year; see header for how to revert to global-continuous '
  'numbering if that turns out to be the wrong call. Advisory-locked '
  'so concurrent calls genuinely serialize rather than racing on the '
  'same "next" number.';
