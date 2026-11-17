-- Seed data: SS1 department assignments and SS1 transfer-ins of 17 November 2026.
--
-- Mirrors scripts/roster/applied/2026-11-17_002.json, applied to the canonical roster
-- (scripts/roster/students.json) and published to every app. Source: Mr Iman's second
-- scores file, kept verbatim in scripts/roster/sources/tendercare-scores-mr-iman-20261117-0704.json
-- (every SS1 student coded 2: the class on the line is the department; the code is not a score).
--
-- Not applied, on purpose: phone id TCH-2025-422 'Rotimi Eniola' (SS1 Science) repeats the existing
-- TCH-2025-179 Rotimi Eniola. Phone id TCH-2025-416 is TCH-2026-061, added by seed 004.
--
-- Run ONCE, after 004, in a transaction. Requires 0021.

begin;

update students set class_id = 'SS1 Science' where id in (
  'TCH-2025-125',
  'TCH-2025-127',
  'TCH-2025-128',
  'TCH-2025-130',
  'TCH-2025-134',
  'TCH-2025-136',
  'TCH-2025-137',
  'TCH-2025-139',
  'TCH-2025-144',
  'TCH-2025-145',
  'TCH-2025-146',
  'TCH-2025-150',
  'TCH-2025-152',
  'TCH-2025-154',
  'TCH-2025-156',
  'TCH-2025-157',
  'TCH-2025-158',
  'TCH-2025-159',
  'TCH-2025-160',
  'TCH-2025-167',
  'TCH-2025-168',
  'TCH-2025-169',
  'TCH-2025-172',
  'TCH-2025-173',
  'TCH-2025-174',
  'TCH-2025-177',
  'TCH-2025-178',
  'TCH-2025-179',
  'TCH-2025-180',
  'TCH-2025-182',
  'TCH-2025-183'
);

update students set class_id = 'SS1 Actuarial' where id in (
  'TCH-2025-120',
  'TCH-2025-121',
  'TCH-2025-122',
  'TCH-2025-131',
  'TCH-2025-132',
  'TCH-2025-133',
  'TCH-2025-135',
  'TCH-2025-138',
  'TCH-2025-140',
  'TCH-2025-143',
  'TCH-2025-148',
  'TCH-2025-151',
  'TCH-2025-155',
  'TCH-2025-165',
  'TCH-2025-166',
  'TCH-2025-170',
  'TCH-2025-171',
  'TCH-2025-175',
  'TCH-2025-176'
);

insert into students (id, full_name, class_id, admitted_academic_year, admission_type) values
  ('TCH-2026-062', 'Akeredolu Damilare', 'SS1 Actuarial', '2026/2027', 'transfer_in'),
  ('TCH-2026-063', 'Akintoye Ibrahim', 'SS1 Actuarial', '2026/2027', 'transfer_in'),
  ('TCH-2026-064', 'Murphy Ubongabasi', 'SS1 Actuarial', '2026/2027', 'transfer_in'),
  ('TCH-2026-065', 'Obiora Kenneth', 'SS1 Actuarial', '2026/2027', 'transfer_in'),
  ('TCH-2026-066', 'Monday Hope', 'SS1 Actuarial', '2026/2027', 'transfer_in'),
  ('TCH-2026-067', 'Bello Ibrahim', 'SS1 Actuarial', '2026/2027', 'transfer_in'),
  ('TCH-2026-068', 'Omotosho Elisha', 'SS1 Science', '2026/2027', 'transfer_in'),
  ('TCH-2026-069', 'Hassan Haniff', 'SS1 Science', '2026/2027', 'transfer_in'),
  ('TCH-2026-070', 'Salimonu Maimuna', 'SS1 Science', '2026/2027', 'transfer_in'),
  ('TCH-2026-071', 'Oladeji Abdul-Ganiyu', 'SS1 Science', '2026/2027', 'transfer_in'),
  ('TCH-2026-072', 'Dominion Nekabari', 'SS1 Science', '2026/2027', 'transfer_in'),
  ('TCH-2026-073', 'Ajayi Toluwase', 'SS1 Science', '2026/2027', 'transfer_in'),
  ('TCH-2026-074', 'Odunsi Oluwadarasimi', 'SS1 Science', '2026/2027', 'transfer_in'),
  ('TCH-2026-075', 'Obaoye Daniel', 'SS1 Science', '2026/2027', 'transfer_in');

commit;
