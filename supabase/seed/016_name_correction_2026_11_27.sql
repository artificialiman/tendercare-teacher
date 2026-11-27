-- Seed data: 1 name correction, 27 November 2026 (SS3 Science).
--
-- Mirrors scripts/roster/applied/2026-11-27_013.json. Source: Mr Iman. Id unchanged.
--
-- Run ONCE, after 015, in a transaction.

begin;

update students set full_name = 'Sunny Mary' where id = 'TCH-2025-302'; -- was Sunday Mary

commit;
