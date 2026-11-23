-- Seed data: JSS1 cross-check of 23 November 2026 -- 1 name correction, 3 intake additions.
--
-- Mirrors scripts/roster/applied/2026-11-23_005.json, applied to the canonical roster
-- (scripts/roster/students.json) and published to every app. Source: names given
-- directly by Mr Iman on 23 Nov. Famakinwa Hannah (TCH-2026-048) and Folorunsho
-- Boluwatife (TCH-2026-008) were already present and are unchanged.
--
-- Run ONCE, after 007, in a transaction. Requires 0021.

begin;

update students set full_name = 'Abdulakeem Aishat' where id = 'TCH-2026-045'; -- was Akeem Aishat

insert into students (id, full_name, class_id, admitted_academic_year, admission_type) values
  ('TCH-2026-087', 'Fakunle Eniola',   'JSS1B', '2026/2027', 'intake'),
  ('TCH-2026-088', 'Odekoya Sulaimon', 'JSS1A', '2026/2027', 'intake'),
  ('TCH-2026-089', 'Bello Sulaimon',   'JSS1A', '2026/2027', 'intake');

commit;
