-- Seed data: 4 JSS3 students missing from the original directory, 23 November 2026.
--
-- Mirrors scripts/roster/applied/2026-11-23_006.json, applied to the canonical roster
-- (scripts/roster/students.json) and published to every app. Source: names given
-- directly by Mr Iman on 23 Nov. Adio Daniel Oluwadami is the "Adio Daniel" of last
-- session's JSS2A score sheet (Teacher-care j2a.csv), skipped by seed 002 because
-- the directory never listed him.
--
-- Run ONCE, after 008, in a transaction. Requires 0021.

begin;

insert into students (id, full_name, class_id, admitted_academic_year, admission_type) values
  ('TCH-2026-090', 'Adedokun Oluwadarasimi', 'JSS3B', '2026/2027', 'transfer_in'),
  ('TCH-2026-091', 'Adio Daniel Oluwadami',  'JSS3A', '2026/2027', 'transfer_in'),
  ('TCH-2026-092', 'Adio Daniel Araoluwa',   'JSS3B', '2026/2027', 'transfer_in'),
  ('TCH-2026-093', 'Adewale Shedrack',       'JSS3B', '2026/2027', 'transfer_in');

commit;
