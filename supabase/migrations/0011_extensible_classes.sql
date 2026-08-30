-- ============================================================================
-- Classes become genuinely extensible: any junior level might need more
-- than 2 arms, any senior level might need more than 2 departments,
-- eventually. Direct instruction. Two arms/departments per level was seed
-- data, never meant to be a hard limit -- this migration makes that
-- explicit in the schema instead of leaving it implicit in what happened
-- to get seeded.
--
-- `arm` already existed (0001) holding the SS department name
-- ('Science'/'Actuarial'/null for JSS) -- reused here to also hold the
-- JSS arm letter ('A'/'B'/...), so one column consistently means "which
-- branch at this level" for both stages, rather than adding a second
-- column that means almost the same thing.
-- ============================================================================

alter table classes add column stage text check (stage in ('JSS', 'SS'));
alter table classes add column level int check (level in (1, 2, 3));

update classes set stage = 'JSS', level = substring(id from 4 for 1)::int, arm = substring(id from 5)
  where id like 'JSS%';
update classes set stage = 'SS', level = substring(id from 3 for 1)::int
  where id like 'SS%';

alter table classes alter column stage set not null;
alter table classes alter column level set not null;
alter table classes alter column arm set not null;

create unique index idx_classes_stage_level_arm on classes(stage, level, arm);

-- Adds one new arm (JSS) or department (SS) at a given level. Atomic --
-- computes id/label/sort_order and shifts every later row's sort_order in
-- the same transaction, so the new class lands grouped next to its
-- siblings in class-tab order instead of always at the very end.
--
-- p_arm: for JSS, a short arm code appended straight to the id, e.g. 'C'
-- -> 'JSS1C'. For SS, the department name, e.g. 'Commercial' ->
-- 'SS2 Commercial'. p_label lets the caller override the short tab label
-- (defaults to the id for JSS, or "SS<level> <first 3 letters>" for SS,
-- matching the existing Sci/Act convention).
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
  insert_after_sort int;
  new_row classes;
begin
  if coalesce(auth.jwt() ->> 'role', '') not in ('staff', 'admin') then
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

  select max(sort_order) into insert_after_sort
  from classes where stage = p_stage and level = p_level;

  if insert_after_sort is null then
    select coalesce(max(sort_order), 0) into insert_after_sort from classes;
  end if;

  update classes set sort_order = sort_order + 1 where sort_order > insert_after_sort;

  insert into classes (id, label, arm, stage, level, sort_order)
  values (new_id, new_label, p_arm, p_stage, p_level, insert_after_sort + 1)
  returning * into new_row;

  return new_row;
end;
$$;

revoke all on function public.add_class(text, int, text, text) from public;
grant execute on function public.add_class(text, int, text, text) to authenticated;
