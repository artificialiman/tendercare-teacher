-- Seed data: 5 students added on Mr Iman's phone but never handed in, 20 November 2026.
--
-- Mirrors scripts/roster/applied/2026-11-20_004.json, applied to the canonical roster
-- (scripts/roster/students.json) and published to every app. Source: names given
-- directly by Mr Iman on 20 Nov. They had been added on his phone before the
-- 17 Nov roster update, had no score typed (so were absent from every scores
-- file), and that phone copy was overwritten by the later additions.
-- Odunsi Oluwadarasimi, also re-sent, is already TCH-2026-074 (seed 005).
--
-- Run ONCE, after 006, in a transaction. Requires 0021.

begin;

insert into students (id, full_name, class_id, admitted_academic_year, admission_type) values
  ('TCH-2026-082', 'Falola Omotayo',     'SS2 Actuarial', '2026/2027', 'transfer_in'),
  ('TCH-2026-083', 'Aduloju Fortune',    'SS2 Actuarial', '2026/2027', 'transfer_in'),
  ('TCH-2026-084', 'Olayinka Keziah',    'SS2 Actuarial', '2026/2027', 'transfer_in'),
  ('TCH-2026-085', 'Adamolekun Delight', 'SS1 Science',   '2026/2027', 'transfer_in'),
  ('TCH-2026-086', 'Ochube David',       'SS1 Science',   '2026/2027', 'transfer_in');

commit;
