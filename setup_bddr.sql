/*
	Setup de la BDDR avec un lien symetrqie entre Pau et Cergy.
	Commandes :
		sqlplus ADMIN_CYTECH/cytech2026@//localhost:1521/XE_PAU @setup_bddr.sql
	
	Prérequis :
		- XE_CERGY deploye et accessible (launch_all.sql execute)
		- XE_PAU deploye (launch_all.sql execute sur XE_PAU)
*/

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK ON
WHENEVER SQLERROR CONTINUE

PROMPT
PROMPT === Creation du lien symetrique db_cergy (PAU -> CERGY) ===
PROMPT

-- Supprime l'eventuel lien existant
DROP DATABASE LINK db_cergy;

CREATE DATABASE LINK db_cergy
  CONNECT TO TECH_CERGY IDENTIFIED BY cergy2026
  USING '//localhost:1521/XE_CERGY';

PROMPT
PROMPT === Verification de la connectivite ===
PROMPT

-- Test local (PAU)
SELECT 'PAU local' AS source, COUNT(*) AS nb_ordis FROM ordinateurs;

-- Test distant vers CERGY
SELECT 'CERGY distant' AS source, COUNT(*) AS nb_ordis FROM ordinateurs@db_cergy;

PROMPT
PROMPT === Synonymes publics PAU -> CERGY (optionnel) ===
PROMPT

CREATE OR REPLACE PUBLIC SYNONYM ordinateurs_cergy     FOR ordinateurs@db_cergy;
CREATE OR REPLACE PUBLIC SYNONYM peripheriques_cergy   FOR peripheriques@db_cergy;
CREATE OR REPLACE PUBLIC SYNONYM telephones_cergy      FOR telephones@db_cergy;
CREATE OR REPLACE PUBLIC SYNONYM equipements_reseau_cergy FOR equipements_reseau@db_cergy;

PROMPT
PROMPT === Vue globale PAU (parc Pau + parc Cergy distant) ===
PROMPT

CREATE OR REPLACE FORCE VIEW vue_parc_global_pau AS
SELECT 'PAU'   AS source, id, nom, numero_serie, site_id, hierarchy_level_id, date_creation
  FROM ordinateurs
UNION ALL
SELECT 'CERGY' AS source, id, nom, numero_serie, site_id, hierarchy_level_id, date_creation
  FROM ordinateurs@db_cergy;

PROMPT
PROMPT === BDDR operationnelle ===
PROMPT   - CERGY peut lire PAU via :  SELECT * FROM ordinateurs@db_pau
PROMPT   - PAU peut lire CERGY via :  SELECT * FROM ordinateurs@db_cergy
PROMPT
