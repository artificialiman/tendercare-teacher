-- ============================================================================
-- Repeat/pardon state, and a portrait link -- both plain columns on the
-- existing students table, no new table needed. Covered by the same RLS
-- policy that already governs students (staff can update, students can
-- only read their own row) -- Postgres RLS is row-level, not column-level,
-- so nothing new needs granting here.
-- ============================================================================

alter table students
  add column repeating boolean not null default false,
  add column repeat_assigned_at timestamptz,
  add column repeat_pardoned_at timestamptz,
  add column portrait_url text;

comment on column students.repeating is
  'When true, the September 1st promotion job (see the promotion function/'
  'migration) skips this student -- they stay in class_id rather than '
  'advancing. Set by staff via the roster UI. A student can be repeat-'
  'assigned and later pardoned (repeat_pardoned_at set, repeating flipped '
  'back to false) without deleting the history of the assignment -- '
  'repeat_assigned_at is never cleared, so "was this student ever held '
  'back" stays answerable even after a pardon.';

comment on column students.portrait_url is
  'A link, not an uploaded file -- per invariant #11, provision for '
  'portraits is "even as embedded links", not a full upload/storage '
  'pipeline. Deliberately scoped display surfaces only (invariant #13): '
  'the yearbook, the roster, and the result/auth gate -- not a general '
  'profile-photo feature. NULL is the common case; nothing should assume '
  'every student has one.';
