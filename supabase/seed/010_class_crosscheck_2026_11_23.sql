-- Seed data: class cross-check of 23 November 2026 (01:17) -- 1 class move, 11 additions.
--
-- Mirrors scripts/roster/applied/2026-11-23_007.json, applied to the canonical roster
-- (scripts/roster/students.json) and published to every app. Source: names given
-- directly by Mr Iman. Fagbola Oladerin Emmanualla, Oyeniran Rokibat and Olushola
-- Esther are in last session's score sheets (j2b.csv, j1b.csv) and were set aside by
-- seed 002 as unmatched.
-- Already present, unchanged: Adedokun Oluwadarasimi (TCH-2026-090), Adewale Shedrack
-- (TCH-2026-093), Toki Abigail (TCH-2026-058), Ajibola Aishat (TCH-2026-046).
--
-- Run ONCE, after 009, in a transaction. Requires 0021.

begin;

update students set class_id = 'JSS3A' where id = 'TCH-2025-099'; -- Fagbola Oladerin Emmanualla, was JSS3B

insert into students (id, full_name, class_id, admitted_academic_year, admission_type) values
  ('TCH-2026-094', 'Babayemi David',      'JSS3A', '2026/2027', 'transfer_in'),
  ('TCH-2026-095', 'Aniebo Munachi',      'JSS3A', '2026/2027', 'transfer_in'),
  ('TCH-2026-096', 'Adebayo Abdulrahmon', 'JSS3A', '2026/2027', 'transfer_in'),
  ('TCH-2026-097', 'Oyelakin Lateefat',   'JSS3A', '2026/2027', 'transfer_in'),
  ('TCH-2026-098', 'Muhammed Okiki',      'JSS3A', '2026/2027', 'transfer_in'),
  ('TCH-2026-099', 'Oluwatoyin Pemisire', 'JSS3A', '2026/2027', 'transfer_in'),
  ('TCH-2026-100', 'Adedeji Christianah', 'JSS3B', '2026/2027', 'transfer_in'),
  ('TCH-2026-101', 'Odekoya Subomi',      'JSS1A', '2026/2027', 'intake'),
  ('TCH-2026-102', 'Oyeniran Rokibat',    'JSS2B', '2026/2027', 'transfer_in'),
  ('TCH-2026-103', 'Olushola Esther',     'JSS2B', '2026/2027', 'transfer_in'),
  ('TCH-2026-104', 'Busari Yusuf',        'JSS2B', '2026/2027', 'transfer_in');

commit;
