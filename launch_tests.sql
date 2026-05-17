-- =============================================================================
-- LAUNCHER : jeu de test + tests de performance
-- =============================================================================
-- Suppose que le schema (bdd_Cy_infrastructure.sql + tous les pl_sql_*.sql)
-- est deja deploye SUR UN PDB FRAIS (sans donnees ni sequences avancees).
--
-- USAGE :
--   cd c:\Users\VM-Analysis\Desktop\tad\Cy-infrastructure
--   sqlplus ADMIN_CYTECH/cytech2026@//localhost:1521/XE_CERGY @launch_tests.sql
--
-- Pour relancer apres un premier passage :
--   1) En SYS dans le CDB : drop+recreate le PDB (plus simple et propre)
--      ALTER PLUGGABLE DATABASE XE_CERGY CLOSE IMMEDIATE;
--      DROP PLUGGABLE DATABASE XE_CERGY INCLUDING DATAFILES;
--      -- puis CREATE PLUGGABLE DATABASE comme dans README
--   2) Redeployer le schema et les PL/SQL (cf. launch_all.sql)
--   3) Relancer ce script
-- =============================================================================

SET ECHO OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR CONTINUE

PROMPT
PROMPT *****************************************************************
PROMPT *  1. JEU DE TEST (genere ~13 000 lignes en 3-4 s)              *
PROMPT *****************************************************************
@jeu_de_test.sql

PROMPT
PROMPT *****************************************************************
PROMPT *  2. TESTS DE PERFORMANCE (EXPLAIN PLAN + benchmarks)          *
PROMPT *****************************************************************
SET DEFINE OFF
@tests_perf.sql

PROMPT
PROMPT *****************************************************************
PROMPT *  TERMINE -- recuperer les temps dans DBMS_OUTPUT ci-dessus    *
PROMPT *****************************************************************
EXIT
