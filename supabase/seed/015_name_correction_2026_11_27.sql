-- Seed data: 1 name correction, 27 November 2026 (SS2 Science).
--
-- Mirrors scripts/roster/applied/2026-11-27_012.json. Source: Mr Iman. Id unchanged.
--
-- Run ONCE, after 014, in a transaction.

begin;

update students set full_name = 'Olugbode Tajudeen' where id = 'TCH-2026-081'; -- was Olugbodee Tajudeen

commit;
