-- ============================================================================
-- Real staff-to-subject and staff-to-class assignment tables. These did not
-- exist anywhere in the schema before this migration -- `staff` (0010) only
-- carries a single plain-text `subject` column and an `is_class_teacher`
-- flag, and `class_subjects` (0001) maps which classes study a subject in
-- general, not which staff member teaches which class. Every teacher-side
-- picker (score entry, attendance) has therefore had to show every subject
-- and every class in the school to every signed-in staff account, since
-- there was no real data to scope by -- not a UI oversight, a genuine
-- missing-table gap.
--
-- Mirrors the shape of the no-gate.html / tendercare-teacher.html reference
-- shells' TEACHERS.subjects object (subject -> classes[]), but as real,
-- admin-editable rows instead of hardcoded demo data.
-- ============================================================================

create table staff_subjects (
  staff_id uuid not null references staff(id) on delete cascade,
  subject_id uuid not null references subjects(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (staff_id, subject_id)
);

create table staff_classes (
  staff_id uuid not null references staff(id) on delete cascade,
  class_id text not null references classes(id) on delete cascade,
  is_class_teacher boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (staff_id, class_id)
);

create index idx_staff_subjects_staff on staff_subjects(staff_id);
create index idx_staff_classes_staff on staff_classes(staff_id);

alter table staff_subjects enable row level security;
alter table staff_classes enable row level security;

-- Same two-tier pattern as every other table in this schema (0010, etc.):
-- admin assigns, any signed-in staff account can read (needed for the
-- picker itself -- a teacher has to be able to see their own assignments
-- to use the app at all).
create policy "admin manages staff_subjects"
  on staff_subjects for all
  using (auth.jwt() ->> 'role' = 'admin')
  with check (auth.jwt() ->> 'role' = 'admin');

create policy "staff can view staff_subjects"
  on staff_subjects for select
  using (auth.jwt() ->> 'role' in ('staff', 'admin'));

create policy "admin manages staff_classes"
  on staff_classes for all
  using (auth.jwt() ->> 'role' = 'admin')
  with check (auth.jwt() ->> 'role' = 'admin');

create policy "staff can view staff_classes"
  on staff_classes for select
  using (auth.jwt() ->> 'role' in ('staff', 'admin'));

comment on table staff_subjects is
  'Which subjects a staff member teaches, school-wide (not per-class -- '
  'staff_classes below is what narrows a subject down to specific classes '
  'via class_subjects). Admin-assigned only.';

comment on table staff_classes is
  'Which classes a staff member is attached to, for attendance/bio-edit '
  'scope and for is_class_teacher status. A row here does not by itself '
  'imply a subject -- cross-reference staff_subjects + class_subjects to '
  'get the real (subject, class) pairs a teacher can open a score sheet '
  'for, same join shape as the reference shell''s hardcoded TEACHERS data.';

-- ============================================================================
-- What this migration deliberately does NOT do, and why:
--
-- 1. Does not backfill any rows. No agent should guess which real teacher
--    teaches which real subject/class -- that's the one piece of data only
--    admin actually knows. Assignment happens through the admin staff page
--    (0010's staff CRUD), which should grow pickers for these two tables as
--    its own follow-up, not fabricated here.
-- 2. Does not touch the single `staff.subject` text column from 0010, or
--    remove it -- leaving that in place rather than making an unannounced
--    breaking schema change to a column other code may still read.
-- 3. Not yet applied to the live project from this session -- this
--    session's Supabase MCP connector is scoped to a different
--    organization than the one tendercare-teacher's project lives in, so
--    this file is the source of truth to apply by hand (or from a session
--    with the right connector) before any code that reads these tables
--    will return real data instead of an empty/missing-table state.
-- ============================================================================
