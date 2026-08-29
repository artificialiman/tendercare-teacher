-- Companion to 0008_alumni_id_recycling.sql -- alumni_archive gets RLS
-- enabled automatically (this project's rls_auto_enable trigger fires on
-- table creation), but that leaves it with zero policies until one exists,
-- which means nobody -- not even admin -- can read or write it. Only admin
-- should ever touch this table, matching recycle_alumni_id()'s own
-- admin-only check.
create policy "admin can manage alumni archive"
  on alumni_archive for all
  using (auth.jwt() ->> 'role' = 'admin')
  with check (auth.jwt() ->> 'role' = 'admin');
