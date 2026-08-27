-- ============================================================================
-- Staff/admin login — interim mechanism, not the final auth strategy.
--
-- RLS (0002_rls_policies.sql) already checks auth.jwt() ->> 'role' = 'staff'.
-- That claim has to come from *somewhere* real — Supabase mints JWTs itself,
-- so the only way to get a 'role' claim into one is via Supabase Auth users,
-- not an app-level password check. This migration wires that up:
--
--   1. Create exactly two Supabase Auth users (staff@tendercare.local,
--      admin@tendercare.local) via the dashboard or `supabase auth admin
--      create-user`, each with `user_metadata: { "role": "staff" }` or
--      `{ "role": "admin" }` and whatever password you're using right now.
--   2. This trigger copies that metadata's `role` into `app_metadata` on
--      creation, which Supabase's default JWT claim mapping *does* expose
--      as auth.jwt() ->> 'role' — user_metadata alone is NOT exposed to
--      RLS by default, which is why this step exists.
--
-- Deliberately not doing per-user accounts, real password hashing policy,
-- or lockout/rate-limiting here — this is the two-shared-password interim
-- setup, kept to a single trigger so it's easy to rip out wholesale once a
-- real auth strategy is chosen. Nothing downstream (RLS, roster.ts) needs
-- to change when that happens — only how a session gets its 'role' claim.
-- ============================================================================

create or replace function public.sync_role_to_app_metadata()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update auth.users
  set raw_app_meta_data =
    coalesce(raw_app_meta_data, '{}'::jsonb) ||
    jsonb_build_object('role', new.raw_user_meta_data ->> 'role')
  where id = new.id
    and new.raw_user_meta_data ? 'role';
  return new;
end;
$$;

drop trigger if exists on_auth_user_role_sync on auth.users;
create trigger on_auth_user_role_sync
  after insert or update of raw_user_meta_data on auth.users
  for each row
  execute function public.sync_role_to_app_metadata();

-- Existing users created before this trigger existed won't be backfilled
-- automatically — if staff@tendercare.local / admin@tendercare.local were
-- created earlier, re-save their user_metadata (even to the same value)
-- once this migration is applied to fire the trigger, or run:
--
--   update auth.users set raw_user_meta_data = raw_user_meta_data
--   where email in ('staff@tendercare.local', 'admin@tendercare.local');
