-- ============================================================================
-- Remarks are auto-assigned from a student's average once their term is
-- complete -- not manually typed by staff. "Complete" means every subject
-- their class takes (class_subjects) has both a CA and an Exam score
-- recorded in `scores` for that term. The moment the last missing score
-- for a student+term is filled in, this fires and writes the remark --
-- staff never has to remember to go type one.
--
-- Band boundaries mirror remark_for() in tendercare-teacher/scripts/
-- report-pipeline/generate.py exactly (75/70/65/60/55/50/45/40) -- keep
-- these two in sync if either changes; this is the DB-side twin of that
-- function, not an independent judgment call.
-- ============================================================================

create or replace function public.remark_text_for_average(p_average numeric)
returns text
language sql
immutable
as $$
  select case
    when p_average >= 75 then 'Distinction'
    when p_average >= 70 then 'Excellent'
    when p_average >= 65 then 'Very Good'
    when p_average >= 60 then 'Good'
    when p_average >= 55 then 'Credible'
    when p_average >= 50 then 'Fair'
    when p_average >= 45 then 'Pass'
    when p_average >= 40 then 'Weak'
    else 'Needs Improvement'
  end;
$$;

create or replace function public.recompute_remark(p_student_id text, p_term_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_class_id text;
  v_required_subjects int;
  v_complete_subjects int;
  v_average numeric;
  v_remark text;
begin
  select class_id into v_class_id from students where id = p_student_id;
  if v_class_id is null then
    return; -- student doesn't exist (shouldn't happen via FK, belt-and-suspenders)
  end if;

  select count(*) into v_required_subjects
  from class_subjects
  where class_id = v_class_id;

  select count(*) into v_complete_subjects
  from scores
  where student_id = p_student_id
    and term_id = p_term_id
    and ca is not null
    and exam is not null;

  -- Not complete yet (or the class has zero subjects assigned, which
  -- means "complete" is meaningless -- don't auto-remark against
  -- nothing) -- clear any stale remark rather than leave an old one
  -- sitting there from before a score got edited back out.
  if v_required_subjects = 0 or v_complete_subjects < v_required_subjects then
    delete from remarks where student_id = p_student_id and term_id = p_term_id;
    return;
  end if;

  select avg(ca + exam) into v_average
  from scores
  where student_id = p_student_id
    and term_id = p_term_id;

  v_remark := remark_text_for_average(v_average);

  insert into remarks (student_id, term_id, teacher_remark, principal_remark, updated_at)
  values (p_student_id, p_term_id, v_remark, v_remark, now())
  on conflict (student_id, term_id)
  do update set
    teacher_remark = excluded.teacher_remark,
    principal_remark = excluded.principal_remark,
    updated_at = now();
end;
$$;

-- Fires after any score write for a student+term -- covers a CA entered
-- today and an Exam entered next week equally well, since either one
-- can be the write that completes the term.
create or replace function public.on_score_change_recompute_remark()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'DELETE' then
    perform public.recompute_remark(old.student_id, old.term_id);
    return old;
  else
    perform public.recompute_remark(new.student_id, new.term_id);
    return new;
  end if;
end;
$$;

drop trigger if exists on_score_change on scores;
create trigger on_score_change
  after insert or update or delete on scores
  for each row
  execute function public.on_score_change_recompute_remark();

-- remarks.teacher_remark/principal_remark are now written exclusively by
-- the trigger above -- direct client writes should stop. Not revoking
-- staff's existing UPDATE grant outright (RLS in 0002 already scopes it
-- to staff only, and an app-level removal of the write path is the real
-- fix -- see roster.ts), but this comment marks the intent for whoever
-- next reads this migration.
comment on table remarks is
  'Auto-populated by on_score_change_recompute_remark() -- see this '
  'migration. Not a manual-entry table anymore; do not add a UI that '
  'writes to it directly.';
