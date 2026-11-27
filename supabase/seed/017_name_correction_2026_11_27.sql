-- Seed data: 1 name correction, 27 November 2026 (SS2 Science).
--
-- Mirrors scripts/roster/applied/2026-11-27_014.json. Source: Mr Iman. Id unchanged.
--
-- Run ONCE, after 016, in a transaction.

begin;

update students set full_name = 'Akinyugha Taiwo' where id = 'TCH-2025-192'; -- was Akinyogha Taiwo

commit;
