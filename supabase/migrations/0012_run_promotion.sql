-- ============================================================================
-- The actual September 1st promotion job. Direct instruction on the shape:
--   everybody's promoted
--   SS3 moves to archive (graduated)
--   new JSS1 opens for filling and splitting
--   JSS3 -> SS1 goes through a department-assignment flow, not automatic
--   repeat/reassign are staff-role actions
--
-- JSS3 does NOT get auto-assigned a department here -- there's no correct
-- automatic guess for Science vs Actuarial. Instead every promoted JSS3
-- student lands in a real holding class, 'SS1 Unassigned' (created on
-- first use, same mechanism as any other add_class() arm), and staff work
-- through that list afterward via the Science/Actuarial/Repeat/Remove
-- assignment flow in the roster UI. Students already sitting in an
-- Unassigned holding class are excluded from this run entirely (arm <>
-- 'Unassigned' below) -- if last year's batch never finished being
-- assigned before this year's promotion runs, they stay exactly where
-- they are rather than getting swept into SS2 Unassigned.
--
-- Same-arm/department targets are created automatically if they don't
-- exist yet (e.g. JSS1C promoting into a JSS2C that's never existed
-- before) -- an arm, once opened, should never hit a dead end on its way
-- up through the levels.
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

  return query select promoted, graduated, pending;
end;
$$;

revoke all on function public.run_promotion() from public;
grant execute on function public.run_promotion() to authenticated;
