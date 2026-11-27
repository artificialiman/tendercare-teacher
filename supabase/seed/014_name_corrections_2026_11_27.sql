-- Seed data: 2 name corrections, 27 November 2026 (SS2 Science).
--
-- Mirrors scripts/roster/applied/2026-11-27_011.json, applied to the canonical roster
-- (scripts/roster/students.json) and published to every app. Source: Mr Iman.
-- Ids unchanged, so transcripts and passwords still match.
--
-- Run ONCE, after 013, in a transaction.

begin;

update students set full_name = 'Ayangbola Damola' where id = 'TCH-2025-198'; -- was Ayangbola Dammilola
update students set full_name = 'Ashaye Damilola'  where id = 'TCH-2025-197'; -- was Ashaye Damola

commit;
