-- ============================================================================
-- Tendercare core schema — single source of truth for the student roster.
--
-- The whole point of this migration: `students` is the ONE place a student
-- exists. Every other table (scores, remarks, comments, likes, directory
-- entries, portal credentials) references students.id with
-- ON DELETE CASCADE. That means a teacher adding or deleting a student in
-- one place — the dashboard's roster screen — is reflected everywhere else
-- in the suite automatically, because there's nowhere else for a "second
-- copy" of a student to live.
--
-- This replaces the previous approach: student rosters were hardcoded/
-- copy-pasted across at least 7 different HTML files in the old Teacher-care
-- and UTMEDaily repos (tcc_broadsheet.html, sheet.html, admin-broadsheet.html,
-- admin_broadsheet.html, TEACHER-CARE Admin.html, index.html,
-- student-directory.html), which is how they drifted out of sync in the
-- first place. tcc_broadsheet.html and admin_broadsheet.html both turned out
-- to share the same column-shift bug from TCH-2025-234 onward (143 students,
-- the whole SS1 Actuarial–SS3 Actuarial range) — agreeing with each other
-- wasn't actually independent verification, since they're corrupted the same
-- way. student-directory.html (UTMEDaily/Tendercare/Directory) is the
-- confirmed-authoritative source and was used as the seed data — see
-- supabase/seed/001_roster_2024_2025.sql for the full story.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Reference tables
-- ---------------------------------------------------------------------------

create table classes (
  id text primary key,              -- e.g. 'JSS1A', 'SS1 Actuarial'
  label text not null,              -- short tab label, e.g. 'SS1 Act'
  arm text,                         -- 'Science' | 'Actuarial' | null for JSS
  sort_order int not null
);

create table subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null unique
);

-- which subjects each class studies (many-to-many)
create table class_subjects (
  class_id text not null references classes(id) on delete cascade,
  subject_id uuid not null references subjects(id) on delete cascade,
  primary key (class_id, subject_id)
);

create table terms (
  id text primary key,              -- e.g. '2024-2025-T1'
  academic_year text not null,      -- '2024/2025'
  term_number smallint not null check (term_number between 1 and 3),
  is_current boolean not null default false
);

-- ---------------------------------------------------------------------------
-- Students — THE single source of truth for the roster
-- ---------------------------------------------------------------------------

create table students (
  id text primary key,              -- 'TCH-2025-001' — kept as the existing
                                     -- human-readable ID scheme rather than
                                     -- switching to a surrogate uuid, since
                                     -- it's already printed on physical
                                     -- report cards and referenced by
                                     -- students/parents.
  full_name text not null,
  class_id text not null references classes(id),
  active boolean not null default true,  -- soft-delete flag; see note below
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  deleted_at timestamptz,
  deleted_by uuid references auth.users(id)
);

-- NOTE ON DELETE SEMANTICS:
-- Removing a student is a *soft* delete (active=false, deleted_at set) by
-- default, not a hard DELETE FROM students. Reasoning: a student's historical
-- scores and comments are academic records — deleting the row would cascade
-- and destroy last term's grades along with the roster entry, which is a
-- bigger, less reversible action than "remove this student from the current
-- roster." The teacher-facing "delete student" action sets active=false;
-- everywhere else in the suite (portal, directory, yearbook) filters on
-- active=true, so the student disappears from all of them immediately.
-- A separate, explicitly-labeled "permanently erase" action (hard delete)
-- is available for actual mistakes (duplicate entry, wrong school) — that one
-- does cascade for real, via the FKs below.

create index idx_students_class on students(class_id) where active;
create index idx_students_active on students(active);

-- ---------------------------------------------------------------------------
-- Everything below references students(id) with real ON DELETE CASCADE —
-- this only fires on a hard delete (the soft-delete path above is the normal
-- one), but it's what makes "permanently erase" actually clean up everywhere
-- rather than leaving orphaned rows.
-- ---------------------------------------------------------------------------

create table scores (
  id uuid primary key default gen_random_uuid(),
  student_id text not null references students(id) on delete cascade,
  subject_id uuid not null references subjects(id) on delete cascade,
  term_id text not null references terms(id) on delete cascade,
  ca numeric(5,2),                  -- continuous assessment
  exam numeric(5,2),
  entered_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  unique (student_id, subject_id, term_id)
);

create table remarks (
  student_id text not null references students(id) on delete cascade,
  term_id text not null references terms(id) on delete cascade,
  teacher_remark text,
  principal_remark text,
  updated_at timestamptz not null default now(),
  primary key (student_id, term_id)
);

-- portal/directory-facing credential — separate from students so a hard
-- delete of a student cleanly removes portal access too
create table portal_credentials (
  student_id text primary key references students(id) on delete cascade,
  password_hash text not null,
  last_login_at timestamptz
);

-- feed page's comments/likes (tendercare-web), once migrated off
-- localStorage — kept here since it's still "about a student"
create table feed_comments (
  id uuid primary key default gen_random_uuid(),
  post_id text not null,
  author_student_id text references students(id) on delete cascade,
  author_name text not null,        -- kept even if author_student_id is null
                                     -- (anonymous/visitor comments)
  body text not null,
  created_at timestamptz not null default now()
);

create table feed_likes (
  post_id text not null,
  student_id text not null references students(id) on delete cascade,
  primary key (post_id, student_id)
);

create index idx_scores_student on scores(student_id);
create index idx_remarks_student on remarks(student_id);
create index idx_feed_comments_post on feed_comments(post_id);
