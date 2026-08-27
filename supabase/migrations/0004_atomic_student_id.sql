-- ============================================================================
-- Atomic student creation — fixes a real race condition in the previous
-- approach.
--
-- src/lib/roster.ts's old addStudent()/nextStudentId() did this from the
-- browser, as two separate round trips:
--   1. SELECT the current max id
--   2. parse out the number, add 1
--   3. INSERT the new student with that id
--
-- Two staff members adding a student at close to the same moment can both
-- finish step 1 before either finishes step 3, so both compute the same
-- next ID — one INSERT then fails on the primary key (best case) or, if
-- retried naively, could reuse an ID a moment later (worse case). This
-- isn't hypothetical: two teachers using the roster screen during the
-- same registration rush is exactly the scenario the app exists for.
--
-- Fix: do the allocate-and-insert as ONE Postgres function call — one
-- transaction, one round trip — using a transaction-scoped advisory lock
-- so concurrent calls genuinely serialize instead of racing. The second
-- caller blocks on the lock until the first's transaction (SELECT max +
-- INSERT + lock release) fully commits, so it always sees the
-- just-inserted row. This also correctly handles the empty-roster case,
-- which locking an existing row (`select ... for update`) would not:
-- with no row yet to lock, two concurrent *first* inserts could still
-- both compute 'TCH-2025-001' under that approach.
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
begin
  -- SECURITY DEFINER bypasses RLS for this function's own queries, so the
  -- 'staff' check has to happen explicitly here — granting EXECUTE to
  -- 'authenticated' alone (Supabase's generic logged-in role) would let
  -- ANY authenticated caller create students, not just staff, since it
  -- doesn't distinguish the 'staff' JWT claim RLS checks everywhere else.
  if coalesce(auth.jwt() ->> 'role', '') <> 'staff' then
    raise exception 'only staff may create students';
  end if;

  -- Arbitrary constant key, scoped to this function's concern only.
  -- Released automatically when this transaction ends (commit or
  -- rollback), so it never needs manual unlocking.
  perform pg_advisory_xact_lock(hashtext('next_student_id'));

  select id into last_id from students order by id desc limit 1;

  if last_id is null then
    next_n := 1;
  else
    next_n := (split_part(last_id, '-', 3))::int + 1;
  end if;

  new_id := 'TCH-2025-' || lpad(next_n::text, 3, '0');

  insert into students (id, full_name, class_id, created_by)
  values (new_id, p_full_name, p_class_id, auth.uid())
  returning * into new_row;

  return new_row;
end;
$$;

-- EXECUTE is still granted broadly to 'authenticated' (Supabase has no
-- finer-grained function-level grant tied to a JWT claim) — the actual
-- gate is the explicit role check inside the function body above, not
-- this grant. Non-staff authenticated callers reach the exception, not
-- the insert.
revoke all on function public.create_student(text, text) from public;
grant execute on function public.create_student(text, text) to authenticated;
