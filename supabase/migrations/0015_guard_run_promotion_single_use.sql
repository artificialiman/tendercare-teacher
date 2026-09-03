-- ============================================================================
-- run_promotion() had no guard against being run twice -- calling it a
-- second time in the same cycle would double-promote every student a
-- level too far, re-graduate SS3 again, and roll the academic term
-- forward twice. This adds a guard directly in the function: before
-- doing anything, it computes what the rollover would produce (the next
-- academic year's Term 1) and refuses outright if that term already
-- exists, meaning this cycle's promotion already ran.
--
-- promotion_already_run() exposes that same check read-only, so the
-- attendance page can retract the button entirely once it's been used,
-- instead of staff finding out by hitting the error.
-- ============================================================================

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

  -- Guard: figure out what the rollover WOULD produce before doing
  -- anything else. If that term already exists, this has already been
  -- run for this cycle -- refuse outright rather than double-promote
  -- every student and roll the term forward twice.
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
  end if;

  return query select promoted, graduated, pending;
end;
$$;

revoke all on function public.run_promotion() from public;
grant execute on function public.run_promotion() to authenticated;

create or replace function public.promotion_already_run()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from terms
    where id = (
      select replace(
        (split_part(t.academic_year, '/', 1)::int + 1) || '/' || (split_part(t.academic_year, '/', 1)::int + 2),
        '/', '-'
      ) || '-T1'
      from terms t where t.is_current = true order by t.id desc limit 1
    )
  );
$$;

grant execute on function public.promotion_already_run() to authenticated;
