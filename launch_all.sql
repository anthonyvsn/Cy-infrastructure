/*
    Ce fichier fait :
        -> l'installation complète du projet (schema et tous les .sql necessaires)
        -> lancement du jeu de test
        -> lancement des tests de performance

    Commandes :
        cd c:\Users\VM-Analysis\Desktop\tad\Cy-infrastructure
        sqlplus sys/<mdp>@//localhost:1521/XE_CERGY as sysdba @launch_all.sql
*/

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
