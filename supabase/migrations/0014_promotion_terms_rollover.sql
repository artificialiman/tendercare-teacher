-- ============================================================================
-- run_promotion() previously handled student promotion/graduation only --
-- it never touched the terms table, so "current term" silently went stale
-- the moment promotion ran each year (the September 1 rollover). This
-- migration folds the term rollover into the same function: whichever
-- term is currently marked is_current becomes last year's, and a fresh
-- Term 1 opens for the new academic year, derived from the current one
-- (e.g. 2025/2026 -> 2026/2027) rather than hardcoded, so this keeps
-- working correctly every year without further changes.
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
begin
  if coalesce(auth.jwt() ->> 'role', '') not in ('staff', 'admin') then
    raise exception 'only staff may run promotion';
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

  -- Roll the academic term forward too: whichever row is currently
  -- marked is_current becomes last year's, and a fresh Term 1 opens for
  -- the new academic year (e.g. 2025/2026 -> 2026/2027). Without this,
  -- "current term" silently goes stale the moment promotion runs, since
  -- nothing else in this function ever touched the terms table before.
  select * into cur_term from terms where is_current = true order by id desc limit 1;
  if found then
    cur_year_start := split_part(cur_term.academic_year, '/', 1)::int;
    new_academic_year := (cur_year_start + 1) || '/' || (cur_year_start + 2);
    new_term_id := replace(new_academic_year, '/', '-') || '-T1';

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
