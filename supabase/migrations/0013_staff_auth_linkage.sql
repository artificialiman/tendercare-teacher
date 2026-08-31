-- ============================================================================
-- Per-teacher accounts: linking `staff` (the directory, 0010) to real
-- Supabase Auth identities, so `entered_by` on scores/remarks eventually
-- means "this specific person," not "the shared staff login."
--
-- Staged rollout, deliberately -- this migration is additive only. It does
-- NOT flip any existing RLS policy away from the current shared-role check
-- (auth.jwt() ->> 'role' = 'staff'/'admin'). Doing that in the same step
-- as introducing the link would lock every current user out immediately,
-- since nobody has an auth_user_id set yet. The cutover to per-person RLS
-- is a deliberate follow-up migration, made once accounts are actually
-- provisioned -- not bundled here.
-- ============================================================================

alter table staff
  add column auth_user_id uuid unique references auth.users(id);

comment on column staff.auth_user_id is
  'The real Supabase Auth identity for this person, once provisioned. '
  'Null means: this staff row exists (they''re recorded/hired) but they '
  'don''t have login access yet -- a normal, expected state, not an error. '
  'Provenance (scores.entered_by, etc.) points at auth.users(id) directly '
  '(see 0001), so once this link exists, every write that person makes '
  'automatically carries their real identity with zero further schema '
  'change -- this column is the only missing piece.';

-- ----------------------------------------------------------------------------
-- Departure handling: staff.active already exists (0010) and is the
-- correct soft-delete flag per the antifail doctrine (§2.6) -- a departed
-- teacher's row is deactivated, never deleted, so every score/remark they
-- ever entered keeps a valid, readable author forever. auth_user_id is
-- deliberately left untouched on deactivation (not nulled): the link
-- itself is historical fact ("this was Mrs. Adeyemi's account") and stays
-- true even after she leaves. What actually revokes her ability to act is
-- disabling the underlying Supabase Auth user (via the Auth admin API/
-- dashboard, a separate, deliberate action, never automatic from a schema
-- change) plus the is_active_staff() check below, which any future RLS
-- policy should gate writes on.
-- ----------------------------------------------------------------------------

create or replace function is_active_staff(check_auth_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from staff
    where auth_user_id = check_auth_id
      and active = true
  );
$$;

comment on function is_active_staff is
  'True if the given auth.uid() belongs to a currently-active staff row. '
  'Not yet wired into any RLS policy -- exists now so the eventual '
  'per-person cutover (replacing the blanket staff/admin role check) is '
  'a policy change, not a fresh schema build, when that day comes.';

-- ============================================================================
-- What this migration deliberately does NOT do, and why:
--
-- 1. Does not create any Supabase Auth users. That requires the Auth admin
--    API, which needs the service-role key -- a secret that must never
--    reach a public Svelte client. The only safe places for that call are
--    the Supabase dashboard (manual, by an admin) or a Supabase Edge
--    Function invoked by an already-authenticated admin. Building that
--    provisioning flow is the next real gate, not this migration.
--
-- 2. Does not touch the login page. It still authenticates against the two
--    shared staff/admin accounts (0003) until real accounts exist to
--    replace them -- ripping that out before replacements exist would
--    lock the whole school out.
--
-- 3. Does not change any existing RLS policy. Every current policy keeps
--    working exactly as it does today. is_active_staff() is available for
--    the day those policies get tightened to per-person checks -- that's
--    a deliberate, separate migration once staff.auth_user_id is actually
--    populated for real people, not an automatic consequence of this one.
-- ============================================================================
