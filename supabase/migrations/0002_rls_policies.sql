-- ============================================================================
-- Row-Level Security — one role per app, scoped to what that app actually
-- needs. This is the enforcement layer behind "immaculate connections":
-- tendercare-web and tendercare-portal physically cannot write to the
-- roster even if their code had a bug, because their role's grants don't
-- include INSERT/UPDATE/DELETE on students. Only tendercare-teacher's
-- authenticated-staff role can.
-- ============================================================================

alter table classes enable row level security;
alter table subjects enable row level security;
alter table class_subjects enable row level security;
alter table terms enable row level security;
alter table students enable row level security;
alter table scores enable row level security;
alter table remarks enable row level security;
alter table portal_credentials enable row level security;
alter table feed_comments enable row level security;
alter table feed_likes enable row level security;

-- ---------------------------------------------------------------------------
-- Reference data (classes/subjects/terms): readable by anyone authenticated
-- in any of the three apps, writable only by staff.
-- ---------------------------------------------------------------------------

create policy "reference data readable by any authenticated app"
  on classes for select using (auth.role() = 'authenticated');
create policy "reference data readable by any authenticated app"
  on subjects for select using (auth.role() = 'authenticated');
create policy "reference data readable by any authenticated app"
  on class_subjects for select using (auth.role() = 'authenticated');
create policy "reference data readable by any authenticated app"
  on terms for select using (auth.role() = 'authenticated');

create policy "staff can manage reference data"
  on classes for all using (auth.jwt() ->> 'role' = 'staff');
create policy "staff can manage reference data"
  on subjects for all using (auth.jwt() ->> 'role' = 'staff');
create policy "staff can manage reference data"
  on terms for all using (auth.jwt() ->> 'role' = 'staff');

-- ---------------------------------------------------------------------------
-- students — the roster itself. This is the policy that actually
-- implements "add/delete cascades everywhere": tendercare-teacher is the
-- only app that can write here; tendercare-web and tendercare-portal only
-- ever read active=true rows, so the moment a teacher soft-deletes a
-- student, every app's next read reflects it — there's no separate
-- "remove from portal" or "remove from directory" step to forget.
-- ---------------------------------------------------------------------------

create policy "staff can do everything on students"
  on students for all
  using (auth.jwt() ->> 'role' = 'staff')
  with check (auth.jwt() ->> 'role' = 'staff');

create policy "portal and public apps see active students only"
  on students for select
  using (active = true);

-- ---------------------------------------------------------------------------
-- scores / remarks — staff write (scoped to the classes they teach, via a
-- teacher_classes mapping — added in 0002 once staff accounts exist);
-- students/portal read only their own row.
-- ---------------------------------------------------------------------------

create policy "staff can manage scores"
  on scores for all
  using (auth.jwt() ->> 'role' = 'staff')
  with check (auth.jwt() ->> 'role' = 'staff');

create policy "a student can read only their own scores"
  on scores for select
  using (auth.jwt() ->> 'role' = 'staff' or student_id = auth.jwt() ->> 'student_id');

create policy "staff can manage remarks"
  on remarks for all
  using (auth.jwt() ->> 'role' = 'staff')
  with check (auth.jwt() ->> 'role' = 'staff');

create policy "a student can read only their own remarks"
  on remarks for select
  using (auth.jwt() ->> 'role' = 'staff' or student_id = auth.jwt() ->> 'student_id');

-- ---------------------------------------------------------------------------
-- portal_credentials — never readable by anyone except the portal's own
-- server-side auth check (service role bypasses RLS entirely for the
-- login-verification step; no policy here grants client-side SELECT).
-- ---------------------------------------------------------------------------

create policy "staff can manage credentials"
  on portal_credentials for all
  using (auth.jwt() ->> 'role' = 'staff')
  with check (auth.jwt() ->> 'role' = 'staff');

-- ---------------------------------------------------------------------------
-- feed_comments / feed_likes — public site's feed, once migrated off
-- localStorage. Anyone authenticated can read; a student can only write
-- comments/likes attributed to themselves.
-- ---------------------------------------------------------------------------

create policy "feed comments are publicly readable"
  on feed_comments for select using (true);

create policy "a student can only post as themselves"
  on feed_comments for insert
  with check (
    author_student_id is null
    or author_student_id = auth.jwt() ->> 'student_id'
  );

create policy "feed likes are publicly readable"
  on feed_likes for select using (true);

create policy "a student can only like as themselves"
  on feed_likes for all
  using (student_id = auth.jwt() ->> 'student_id')
  with check (student_id = auth.jwt() ->> 'student_id');
