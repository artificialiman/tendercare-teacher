-- ============================================================================
-- Fixes a real bug in 0018's custom_access_token_hook(), found from the
-- symptom it caused: after enabling the hook, login itself still
-- succeeded, but every subsequent PostgREST request (classes, students,
-- promotion_already_run RPC, everything) started returning 401 --
-- worse than the P0001 application error from before the hook existed,
-- not better.
--
-- The cause: 0018's function ended with `return event;` -- returning
-- the entire, unmodified event object (which still has the top-level
-- shape {user_id, claims, authentication_method, ...}) as if it were
-- itself the hook's output. Per Supabase's own documented example
-- (supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook),
-- a Custom Access Token Hook must return specifically
-- `jsonb_build_object('claims', <the modified claims object>)` -- NOT
-- the event, and not the claims object bare either. Returning the raw
-- event back produced a malformed hook response; Supabase Auth still
-- issued *a* token (hence login appearing to succeed), but apparently
-- not one PostgREST's JWT verification accepted for actual API calls,
-- hence the 401s on every REST/RPC call once a session existed.
--
-- Fix is a corrected function body only -- the grants from 0018 (which
-- were correct and are not the bug) are left untouched; only the
-- function itself is replaced.
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

  -- The fix: return ONLY {"claims": claims}, matching Supabase's
  -- required hook response shape exactly -- not the full event object
  -- 0018 returned, and not a bare claims object either.
  return jsonb_build_object('claims', claims);
end;
$$;

comment on function custom_access_token_hook is
  'Custom Access Token Hook -- promotes auth.users.raw_app_meta_data.role '
  'onto the JWT as a top-level "role" claim. Fixed in 0019 after 0018''s '
  'version returned the wrong response shape (the raw event instead of '
  '{"claims": ...}), which caused every REST/RPC call to 401 even though '
  'login itself appeared to succeed. MUST be enabled in Authentication > '
  'Hooks (Custom Access Token) for this to run at all -- if it was '
  'already enabled against 0018''s broken version, no further dashboard '
  'action is needed here, this migration replaces the function in place. '
  'Still requires one fresh login after this migration is applied, since '
  'the currently-active session''s token was minted by the broken '
  'version and stays broken until a new one is issued.';
