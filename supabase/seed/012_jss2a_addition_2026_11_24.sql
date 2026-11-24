-- Seed data: 1 JSS2A addition, 24 November 2026.
--
-- Mirrors scripts/roster/applied/2026-11-24_009.json, applied to the canonical roster
-- (scripts/roster/students.json) and published to every app. Source: Mr Iman.
--
-- Run ONCE, after 011, in a transaction. Requires 0021.

begin;

insert into students (id, full_name, class_id, admitted_academic_year, admission_type) values
  ('TCH-2026-108', 'Ndubuisi Favour', 'JSS2A', '2026/2027', 'transfer_in');

commit;
