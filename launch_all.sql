-- =============================================================================
-- LAUNCHER : installation complete + jeu de test + tests de perf
-- =============================================================================
-- Tout en un. A lancer comme SYS sur un PDB FRAIS (XE_CERGY ou XE_PAU).
--
-- USAGE :
--   cd c:\Users\VM-Analysis\Desktop\tad\Cy-infrastructure
--   sqlplus sys/<mdp>@//localhost:1521/XE_CERGY as sysdba @launch_all.sql
--
-- Le script bdd_Cy_infrastructure.sql bascule mid-execution en ADMIN_CYTECH
-- via CONNECT. Tout ce qui suit s'execute donc en ADMIN_CYTECH/cytech2026.
--
-- Prerequis : le PDB existe deja et est OPEN (voir README.md etape 2).
-- Si tu veux repartir d'un PDB tout neuf, drop+recreate avant de lancer ce
-- script :
--   ALTER PLUGGABLE DATABASE <pdb> CLOSE IMMEDIATE;
--   DROP PLUGGABLE DATABASE <pdb> INCLUDING DATAFILES;
--   CREATE PLUGGABLE DATABASE <pdb> ADMIN USER pdbadmin IDENTIFIED BY pdbpass
--     FILE_NAME_CONVERT = ('<seedpath>', '<pdbpath>');
--   ALTER PLUGGABLE DATABASE <pdb> OPEN;
-- =============================================================================

SET ECHO OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR CONTINUE

PROMPT
PROMPT *****************************************************************
PROMPT *  1. SCHEMA + USERS + TABLESPACES + INDEX + VUES + CLUSTER     *
PROMPT *****************************************************************
@bdd_Cy_infrastructure.sql

PROMPT
PROMPT *****************************************************************
PROMPT *  2. TRIGGERS                                                  *
PROMPT *****************************************************************
@pl_sql_triggers.sql

PROMPT
PROMPT *****************************************************************
PROMPT *  3. FUNCTIONS                                                 *
PROMPT *****************************************************************
@pl_sql_functions.sql

PROMPT
PROMPT *****************************************************************
PROMPT *  4. PROCEDURES                                                *
PROMPT *****************************************************************
@pl_sql_procedures.sql

PROMPT
PROMPT *****************************************************************
PROMPT *  5. PACKAGES                                                  *
PROMPT *****************************************************************
@pl_sql_packages.sql

PROMPT
PROMPT *****************************************************************
PROMPT *  6. JEU DE TEST                                               *
PROMPT *****************************************************************
@jeu_de_test.sql

PROMPT
PROMPT *****************************************************************
PROMPT *  7. TESTS DE PERFORMANCE                                      *
PROMPT *****************************************************************
SET DEFINE OFF
@tests_perf.sql

PROMPT
PROMPT *****************************************************************
PROMPT *  TERMINE                                                      *
PROMPT *****************************************************************
EXIT
