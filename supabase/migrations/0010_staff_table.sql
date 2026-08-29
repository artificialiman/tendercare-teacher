-- ============================================================================
-- Staff roster — separate from the two shared staff/admin *login* accounts
-- (0003_staff_auth_roles.sql). Those two accounts are how the app currently
-- authenticates; this table is who those accounts represent day to day --
-- the actual list of people, so admin has something to add/remove/assign
-- roles to, per direct instruction. Permission tiers between the three
-- staff types are still explicitly undecided (per INVARIANTS.md) -- this
-- table only tracks who they are, not what they're allowed to do; every
-- write here already funnels through the shared 'staff'/'admin' JWT roles
-- either way, so tiering later doesn't require a schema change, only new
-- RLS policies.
-- ============================================================================

create table staff (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  staff_type text not null check (staff_type in ('part_time', 'full_time', 'corps_member')),
  is_class_teacher boolean not null default false,
  subject text,                     -- one of `subjects`.name; kept as plain text since a
                                     -- teacher can be assigned before that subject row exists
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

create index idx_staff_active on staff(active);

create policy "admin manages staff"
  on staff for all
  using (auth.jwt() ->> 'role' = 'admin')
  with check (auth.jwt() ->> 'role' = 'admin');

create policy "staff can view the staff list"
  on staff for select
  using (auth.jwt() ->> 'role' in ('staff', 'admin'));
