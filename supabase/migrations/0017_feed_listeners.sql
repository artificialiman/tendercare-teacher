-- ============================================================================
-- Feed-posting listeners (Lane 2, continued). Same pattern as
-- 0006_auto_remarks.sql's on_score_change trigger: react to a write via a
-- DB trigger, not scattered calls in client code, so a post fires no
-- matter which code path made the underlying write (score entry UI,
-- offline sync queue, admin panel, a future script) rather than only the
-- one call site someone remembered to instrument. See 0016 for
-- feed_posts/feed_reactions themselves and why they're new tables, not
-- a repurpose of feed_comments/feed_likes.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Result uploads + class averages, both from the same scores-write event.
-- "Result upload" and "class average" are listed as two separate content
-- types in the spec, but they're not two separate triggers here -- a
-- class average can only meaningfully change when a score in that class
-- changes, so computing both off one trigger avoids two triggers racing
-- to read a consistent view of the same table. Posted once per
-- student+term completion (mirrors 0006's own "complete" definition
-- exactly, reusing it rather than inventing a second notion of
-- "complete"), not once per individual CA/Exam cell edit -- a teacher
-- entering 30 students' CA scores one field at a time should not flood
-- the feed with 30 near-duplicate posts before any of those students'
-- terms are actually complete.
-- ----------------------------------------------------------------------------

create or replace function public.post_feed_for_score_change(p_student_id text, p_term_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_class_id text;
  v_required_subjects int;
  v_complete_subjects int;
  v_class_average numeric;
begin
  select class_id into v_class_id from students where id = p_student_id;
  if v_class_id is null then
    return;
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

  -- Same completeness gate as recompute_remark() in 0006 -- only post
  -- once this student's term is genuinely done, not on every keystroke.
  if v_required_subjects = 0 or v_complete_subjects < v_required_subjects then
    return;
  end if;

  insert into feed_posts (kind, payload)
  values (
    'result_upload',
    jsonb_build_object(
      'student_id', p_student_id,
      'class_id', v_class_id,
      'term_id', p_term_id
    )
  );

  -- Class average: only meaningful once at least one student in the
  -- class has a complete term, and recomputed off the same trigger --
  -- avoids a second listener re-deriving "is this class's data ready"
  -- independently and possibly disagreeing with the result-upload check
  -- above about what "ready" means.
  select avg(ca + exam) into v_class_average
  from scores sc
  join students st on st.id = sc.student_id
  where st.class_id = v_class_id
    and sc.term_id = p_term_id
    and sc.ca is not null
    and sc.exam is not null;

  if v_class_average is not null then
    insert into feed_posts (kind, payload)
    values (
      'class_average',
      jsonb_build_object(
        'class_id', v_class_id,
        'term_id', p_term_id,
        'average', round(v_class_average, 1)
      )
    );
  end if;
end;
$$;

create or replace function public.on_score_change_post_feed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'DELETE' then
    perform public.post_feed_for_score_change(old.student_id, old.term_id);
    return old;
  else
    perform public.post_feed_for_score_change(new.student_id, new.term_id);
    return new;
  end if;
end;
$$;

-- Second trigger on the same table/event as 0006's on_score_change --
-- Postgres runs both triggers for the same AFTER INSERT/UPDATE/DELETE
-- event in name order (on_score_change_post_feed sorts after
-- on_score_change alphabetically, so the remark is recomputed first,
-- feed posted second -- order doesn't actually matter here since they
-- read independent state, but noting it since silent trigger-ordering
-- assumptions are exactly the kind of thing that bites later).
drop trigger if exists on_score_change_feed on scores;
create trigger on_score_change_feed
  after insert or update or delete on scores
  for each row
  execute function public.on_score_change_post_feed();

-- ----------------------------------------------------------------------------
-- Media changes: portrait_url on students. Posted on any change
-- (set, cleared, or replaced) -- the spec says "media changes" without
-- narrowing to only-additions, and a cleared portrait is as much a
-- media change as a new one.
-- ----------------------------------------------------------------------------

create or replace function public.on_portrait_change_post_feed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.portrait_url is distinct from old.portrait_url then
    insert into feed_posts (kind, payload)
    values (
      'media_change',
      jsonb_build_object('student_id', new.id, 'class_id', new.class_id)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists on_portrait_change_feed on students;
create trigger on_portrait_change_feed
  after update of portrait_url on students
  for each row
  execute function public.on_portrait_change_post_feed();

-- ----------------------------------------------------------------------------
-- Staff changes: new teacher roles (is_class_teacher/subject changing on
-- an existing row) and part-time/corps-member arrivals (a new staff row
-- with that staff_type). Split into insert vs. update explicitly rather
-- than one trigger trying to infer "arrival vs. role change" from a
-- single row of NEW/OLD, since an INSERT has no OLD row to compare
-- against at all.
-- ----------------------------------------------------------------------------

create or replace function public.on_staff_insert_post_feed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.staff_type in ('part_time', 'corps_member') then
    insert into feed_posts (kind, payload)
    values (
      'staff_arrival',
      jsonb_build_object('staff_id', new.id, 'full_name', new.full_name, 'staff_type', new.staff_type)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists on_staff_insert_feed on staff;
create trigger on_staff_insert_feed
  after insert on staff
  for each row
  execute function public.on_staff_insert_post_feed();

create or replace function public.on_staff_update_post_feed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_class_teacher is distinct from old.is_class_teacher
     or new.subject is distinct from old.subject then
    insert into feed_posts (kind, payload)
    values (
      'staff_role_change',
      jsonb_build_object(
        'staff_id', new.id,
        'full_name', new.full_name,
        'is_class_teacher', new.is_class_teacher,
        'subject', new.subject
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists on_staff_update_feed on staff;
create trigger on_staff_update_feed
  after update of is_class_teacher, subject on staff
  for each row
  execute function public.on_staff_update_post_feed();

comment on function post_feed_for_score_change is
  'Fires result_upload + (if applicable) class_average feed_posts once a '
  'student''s term is complete -- same completeness gate as '
  '0006''s recompute_remark(), reused rather than redefined so the two '
  'notions of "complete" never drift apart.';
