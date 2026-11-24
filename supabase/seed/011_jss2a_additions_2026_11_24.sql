-- Seed data: 3 JSS2A additions, 24 November 2026.
--
-- Mirrors scripts/roster/applied/2026-11-24_008.json, applied to the canonical roster
-- (scripts/roster/students.json) and published to every app. Source: names given
-- directly by Mr Iman.
--
-- Run ONCE, after 010, in a transaction. Requires 0021.

begin;

insert into students (id, full_name, class_id, admitted_academic_year, admission_type) values
  ('TCH-2026-105', 'Olayinka Caleb',       'JSS2A', '2026/2027', 'transfer_in'),
  ('TCH-2026-106', 'Oloyede Oluwatomisin', 'JSS2A', '2026/2027', 'transfer_in'),
  ('TCH-2026-107', 'Monday Victory',       'JSS2A', '2026/2027', 'transfer_in');

commit;
