-- Seed data: 6 SS2 Science students missing from the original directory, 17 November 2026.
--
-- Mirrors scripts/roster/applied/2026-11-17_003.json, applied to the canonical roster
-- (scripts/roster/students.json) and published to every app. Source: Mr Iman's third
-- scores file, kept verbatim in scripts/roster/sources/tendercare-scores-mr-iman-20261117-0829.json
-- (each coded 2; the code is not a score). The phone had given them provisional ids
-- TCH-2026-077..082; the canonical sequence continues gap-free from TCH-2026-075.
--
-- Run ONCE, after 005, in a transaction. Requires 0021.

begin;

insert into students (id, full_name, class_id, admitted_academic_year, admission_type) values
  ('TCH-2026-076', 'Yusuf Farida Iye',   'SS2 Science', '2026/2027', 'transfer_in'),
  ('TCH-2026-077', 'Kingsley Wisdom',    'SS2 Science', '2026/2027', 'transfer_in'),
  ('TCH-2026-078', 'Akeredolu Abigail',  'SS2 Science', '2026/2027', 'transfer_in'),
  ('TCH-2026-079', 'Inaku Elizabeth',    'SS2 Science', '2026/2027', 'transfer_in'),
  ('TCH-2026-080', 'Babayemi Favour',    'SS2 Science', '2026/2027', 'transfer_in'),
  ('TCH-2026-081', 'Olugbodee Tajudeen', 'SS2 Science', '2026/2027', 'transfer_in');

commit;
