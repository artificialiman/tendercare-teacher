-- ============================================================================
-- Root cause of "only staff may run promotion" (and, on investigation,
-- every other staff/admin-gated action failing identically -- not a
-- run_promotion()-specific bug): this project has zero Auth Hooks
-- configured (confirmed directly in the dashboard, Authentication ->
-- Hooks). Without a Custom Access Token Hook, app_metadata is NOT
-- automatically flattened onto the JWT as top-level claims -- it stays
-- nested at auth.jwt()->'app_metadata'->>'role', not auth.jwt()->>'role'.
--
-- 0003_staff_auth_roles.sql's comment claimed "Supabase's default JWT
-- claim mapping *does* expose [app_metadata] as auth.jwt() ->> 'role'"
-- -- that assumption was simply wrong for this project's configuration
-- (whether it was ever true for any Supabase project, or the person who
-- wrote that comment was thinking of a different default, doesn't
-- matter now -- what matters is every single one of this codebase's
-- ~20 auth.jwt() ->> 'role' checks, across 0002, 0004, 0007, 0008,
-- 0009, 0010, 0011, 0012/0014/0015, 0016, has been reading a claim that
-- was never actually being set at the top level).
--
-- Confirmed directly against the live database before writing this fix
-- (not guessed): raw_app_meta_data for both staff@tendercare.local and
-- admin@tendercare.local already contains {"role": "staff"} /
-- {"role": "admin"} correctly -- re-running 0003's backfill query
-- changed nothing because the data was never the problem. The problem
-- is that nothing was ever configured to copy it onto the token.
--
-- Fix: a Custom Access Token Hook that reads the already-correct
-- app_metadata.role (no new table, no schema change -- the data
-- this needs has been sitting there correctly the whole time) and
-- promotes it onto the JWT at the top level, exactly where every
-- existing check in this codebase already expects to find it. Nothing
-- downstream changes -- every existing auth.jwt() ->> 'role' check
-- across every migration starts working as originally intended, with
-- zero further code changes.
-- ============================================================================

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
as $$
declare
  claims jsonb;
  user_role text;
begin
  claims := event -> 'claims';

  select raw_app_meta_data ->> 'role' into user_role
  from auth.users
  where id = (event ->> 'user_id')::uuid;

  if user_role is not null then
    claims := jsonb_set(claims, '{role}', to_jsonb(user_role));
  end if;

  event := jsonb_set(event, '{claims}', claims);
  return event;
end;
$$;

-- Required grants for the hook to run at all -- Supabase Auth calls this
-- function as the supabase_auth_admin role, which by default has no
-- access to either this function or auth.users. Both grants are
-- mandatory; the hook silently fails token issuance without them.
grant usage on schema public to supabase_auth_admin;
grant execute on function public.custom_access_token_hook to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook from authenticated, anon, public;

-- ============================================================================
-- This migration only creates the function. It does NOT enable it --
-- that's a dashboard-only step (Authentication -> Hooks -> Custom
-- Access Token -> select public.custom_access_token_hook from the
-- dropdown), not something any migration file can do. After enabling
-- it there, every currently-logged-in staff/admin session still needs
-- one fresh login (existing JWTs were minted before the hook existed
-- and won't retroactively gain the claim) -- same requirement as the
-- 0003 backfill, for the same reason: a hook only ever runs at the
-- moment a token is issued, never against a token that already exists.
-- ============================================================================

comment on function custom_access_token_hook is
  'Custom Access Token Hook -- promotes auth.users.raw_app_meta_data.role '
  'onto the JWT as a top-level "role" claim. MUST be enabled manually in '
  'Authentication > Hooks (Custom Access Token) for this function to '
  'actually run; creating it here does not enable it. Every staff/admin '
  'RLS check and function guard in this codebase has assumed this claim '
  'exists since 0003 -- it never did until this hook is both created '
  'AND enabled.';
