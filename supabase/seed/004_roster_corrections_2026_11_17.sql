-- Seed data: roster corrections of 17 November 2026 -- 10 name corrections,
-- 10 SS1 department assignments, 3 transfer-ins.
--
-- Mirrors scripts/roster/applied/2026-11-17_001.json, which was applied to the
-- canonical roster (scripts/roster/students.json) and published to every app.
-- Source: Mr Iman's scores file, kept verbatim in
-- scripts/roster/sources/tendercare-scores-mr-iman-20261117-0633.json.
-- Its CA column was a code, not a score: 0 = old spelling, 1 = correct
-- spelling, 2 = carried along, no change.
--
-- A correction keeps the student's id. Transcripts, portal passwords and
-- last session's scores are all keyed to the id, so the id never moves.
--
-- Run ONCE, after 001-003, in a transaction (all-or-nothing). Requires 0021.

begin;

-- Name corrections (old spelling -> correct spelling)
update students set full_name = 'Adeyemo Olamide'          where id = 'TCH-2025-007'; -- was Adeyemi Olamide
update students set full_name = 'Folorunsho Boluwatife'    where id = 'TCH-2026-008'; -- was Folorunsho Boluwatif
update students set full_name = 'Olatunji Al-ameen'        where id = 'TCH-2025-141'; -- was Olatunji Al-meen
update students set full_name = 'Olowu Faosiyat'           where id = 'TCH-2025-142'; -- was Olowu Fausiyat
update students set full_name = 'Toheeb Waheeb Aduragbemi' where id = 'TCH-2025-149'; -- was Waheed Aduragbemi
update students set full_name = 'Abdul-Rasaq Somod'        where id = 'TCH-2025-153'; -- was Abdul Razak Somod
update students set full_name = 'Ramos Hassanat'           where id = 'TCH-2025-208'; -- was Hassanat
update students set full_name = 'Edwin Divine'             where id = 'TCH-2025-213'; -- was Momoh Divine
update students set full_name = 'Abdulmojeed Saheed'       where id = 'TCH-2025-234'; -- was Abdulmateen saheed
update students set full_name = 'Ibhadore Miracle'         where id = 'TCH-2025-316'; -- was Ibadore Miracle

-- SS1 department assignments (out of the SS1 New holding class)
update students set class_id = 'SS1 Actuarial'
 where id in ('TCH-2025-117', 'TCH-2025-118', 'TCH-2025-149', 'TCH-2025-164');
update students set class_id = 'SS1 Science'
 where id in ('TCH-2025-119', 'TCH-2025-129', 'TCH-2025-141', 'TCH-2025-142', 'TCH-2025-153', 'TCH-2025-181');

-- Transfer-ins, 2026/2027 session (ids continue the TCH-2026 sequence after the JSS1 intake)
insert into students (id, full_name, class_id, admitted_academic_year, admission_type) values
  ('TCH-2026-059', 'Noragbon Beauty',         'JSS3B',         '2026/2027', 'transfer_in'),
  ('TCH-2026-060', 'Fakunmoju Enoch',         'JSS2A',         '2026/2027', 'transfer_in'),
  ('TCH-2026-061', 'Osideko Oyinkosola Mary', 'SS1 Actuarial', '2026/2027', 'transfer_in');

commit;
