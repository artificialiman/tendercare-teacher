-- Seed data: the 2026/2027 JSS1 intake (58 students, JSS1A + JSS1B).
--
-- Source: names supplied directly by the school, transcribed exactly as
-- given (spelling and surname-first order untouched, including two entries
-- worth a second look -- see "CHECK BEFORE RUNNING"). Boys/girls grouping
-- is preserved only as the order below; `students` has no gender column
-- and none is invented here.
--
-- Goes in through create_students_bulk() (0021) as ONE atomic batch with
-- admission_type 'intake', so ids are allocated gap-free by the real id
-- sequence (TCH-<year>-NNN) instead of being hand-typed, and every row is
-- stamped admitted_academic_year / admission_type. Any bad row rolls the
-- whole batch back.
--
-- ORDER OF OPERATIONS -- READ FIRST
--   1. Migrations 0021 (and 0022/0023 if used) must already be applied.
--   2. The September 1st promotion must ALREADY have been run for this
--      academic year. These students land in JSS1A/JSS1B; if last year's
--      JSS1 is still there, run_promotion() would advance this intake to
--      JSS2 along with them. Promotion first, intake second.
--   3. Run this once. Re-running admits everyone a second time.
--
-- CHECK BEFORE RUNNING (transcribed as supplied, not corrected)
--   * JSS1A girls: ADEYEMO WALIAT and ADEBOYE WALIAT -- same first name,
--     different surnames. Two pupils, or one entered twice?
--   * JSS1B girls: SHOBOWALW FAITH -- likely a typo for SHOBOWALE.

select id, full_name, class_id, admitted_academic_year, admission_type
from create_students_bulk(
  jsonb_build_array(
    -- 1A boys (16)
    jsonb_build_object('full_name', 'ABRAHAM BABAYEMI', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'ADULOJU FAVOUR', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'AFUWAPE TOMIWA', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'ANIEBO ONYEKACHI', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'ATUNDE PRAISE', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'AWOTOYE ANTHONY', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'BENSON EZEKIEL', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'FOLORUNSHO BOLUWATIF', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'JOSEPH MATTHEW', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'MUSTAPHA IBRAHIM', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'ODUSANYA SEMILORE', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'OLALERE HABEEB', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'PAULINUS GODWIN', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'SAMUEL DIVINE', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'TIAMYU ELIJAH', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'LATEEF MUBARAQ', 'class_id', 'JSS1A'),
    -- 1A girls (13)
    jsonb_build_object('full_name', 'AMIRAT ABDULRAHMAN', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'ADEBOYE IMISI', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'ADEYEMO WALIAT', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'ADEBOYE WALIAT', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'PRECIOUS NEHMAT', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'JAMES CHERISH', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'MMADUABUCHI CYNTHIA', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'OLOGUNORE FAVOUR', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'OWOLEWA SEUN', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'OYEBANJI OLUWATOBILOBA', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'OYEWOLE TEMILOLUWA', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'SULAIMON AMIRAT', 'class_id', 'JSS1A'),
    jsonb_build_object('full_name', 'SUNNY GRACE', 'class_id', 'JSS1A'),
    -- 1B boys (15)
    jsonb_build_object('full_name', 'ABDULMOJEED ALIAMIN', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'AWODIYA DAVID OLUWADAMILOLA', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'ALEXANDER CHIBUZOR', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'AMOS OWEN', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'ELUMEZIE GOODLUCK', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'IDOWU SAMSON', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'LATEEF MALIK', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'AJAYI INIOLUWA', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'OLUWASEUN SAMUEL', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'OKEZUOEZE KAMSI', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'OLOWU FARUQ', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'YUSUF ABDULWAHAB', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'OLUSOLA JAMES', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'OYESIJI PROSPER', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'BAKARE BAMIDELE', 'class_id', 'JSS1B'),
    -- 1B girls (14)
    jsonb_build_object('full_name', 'AKEEM AISHAT', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'AJIBOLA AISHAT', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'ABDULGANIU MISTURAH', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'FAMAKINWA HANNAH', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'HASSAN JAZEELAT', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'JIMOH ABIDAT', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'LAW EGBUEJE KENDRA', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'OLUMIDE SHARON', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'OKEBIYI PHOEBE', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'OBAOYE DASOLA', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'OYEBODE MERCY', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'SHOBOWALW FAITH', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'SANNI ARAFAT', 'class_id', 'JSS1B'),
    jsonb_build_object('full_name', 'TOKI ABIGAIL', 'class_id', 'JSS1B')
  ),
  'intake'
);
