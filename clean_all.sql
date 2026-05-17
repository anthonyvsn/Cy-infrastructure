/*
	Ce fichier contient le script de nettoyage complet du projet.
	Il est a executer sous SYSTEM dans SQL*PLUS.
*/

SET SERVEROUTPUT ON SIZE UNLIMITED;
SET FEEDBACK OFF;

-- Destruction des sessions actives
BEGIN
	FOR s IN (SELECT sid, serial#, username
				FROM v$session
				WHERE username IN ('ADMIN_CYTECH','TECH_CERGY','TECH_PAU','USER_RO')) LOOP
		BEGIN
		EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.serial# || ''' IMMEDIATE';
		DBMS_OUTPUT.PUT_LINE('KILL session : ' || s.username || ' (sid=' || s.sid || ')');
		EXCEPTION
		WHEN OTHERS THEN NULL;
		END;
	END LOOP;
END;
/

DECLARE
	PROCEDURE d(stmt VARCHAR2) IS
	BEGIN
		EXECUTE IMMEDIATE stmt;
		DBMS_OUTPUT.PUT_LINE('OK : ' || stmt);
	EXCEPTION
		WHEN OTHERS THEN
		DBMS_OUTPUT.PUT_LINE('SKIP : ' || stmt || ' -- ' || SQLERRM);
	END;
BEGIN

  -- Suppression des PUBLIC SYNONYM
  d('DROP PUBLIC SYNONYM ordinateurs_pau');
  d('DROP PUBLIC SYNONYM peripheriques_pau');
  d('DROP PUBLIC SYNONYM telephones_pau');
  d('DROP PUBLIC SYNONYM equipements_reseau_pau');

  -- Suppression des DATABASE LINK
  d('DROP DATABASE LINK db_pau');

  -- Suppression des MATERIALIZED VIEW
  d('DROP MATERIALIZED VIEW mv_stats_parc');

  -- Suppression des VIEW
  d('DROP VIEW vue_parc_global_v2');
  d('DROP VIEW vue_parc_global');
  d('DROP VIEW vue_utilisateurs_droits');
  d('DROP VIEW vue_reseau_site');
  d('DROP VIEW vue_peripheriques_site');
  d('DROP VIEW vue_parc_pau');
  d('DROP VIEW vue_parc_cergy');

  -- Suppression des TRIGGER
  d('DROP TRIGGER trg_pk_sites');
  d('DROP TRIGGER trg_pk_entites');
  d('DROP TRIGGER trg_pk_localisations');
  d('DROP TRIGGER trg_pk_utilisateurs');
  d('DROP TRIGGER trg_pk_ordinateurs');
  d('DROP TRIGGER trg_pk_peripheriques');
  d('DROP TRIGGER trg_pk_telephones');
  d('DROP TRIGGER trg_pk_equip_reseau');
  d('DROP TRIGGER trg_pk_ports_reseau');
  d('DROP TRIGGER trg_pk_historique');
  d('DROP TRIGGER trg_majdate_sites');
  d('DROP TRIGGER trg_majdate_entites');
  d('DROP TRIGGER trg_majdate_localisations');
  d('DROP TRIGGER trg_majdate_profils');
  d('DROP TRIGGER trg_majdate_groupes');
  d('DROP TRIGGER trg_majdate_utilisateurs');
  d('DROP TRIGGER trg_majdate_ordinateurs');
  d('DROP TRIGGER trg_majdate_peripheriques');
  d('DROP TRIGGER trg_majdate_telephones');
  d('DROP TRIGGER trg_majdate_logiciels');
  d('DROP TRIGGER trg_majdate_equip_reseau');
  d('DROP TRIGGER trg_majdate_ports_reseau');
  d('DROP TRIGGER trg_audit_ordinateurs');
  d('DROP TRIGGER trg_audit_peripheriques');
  d('DROP TRIGGER trg_audit_telephones');
  d('DROP TRIGGER trg_audit_utilisateurs');
  d('DROP TRIGGER trg_audit_equip_reseau');
  d('DROP TRIGGER trg_audit_logiciels');
  d('DROP TRIGGER trg_audit_install_log');
  d('DROP TRIGGER trg_audit_ports_reseau');
  d('DROP TRIGGER trg_coherence_site_ordi');
  d('DROP TRIGGER trg_coherence_site_periph');
  d('DROP TRIGGER trg_coherence_site_tel');
  d('DROP TRIGGER trg_coherence_site_equip');
  d('DROP TRIGGER trg_coherence_site_user');
  d('DROP TRIGGER trg_valid_mac');
  d('DROP TRIGGER trg_valid_dates_user');
  d('DROP TRIGGER trg_valid_entite_parent');
  d('DROP TRIGGER trg_valid_delete_ordinateur');
  d('DROP TRIGGER trg_valid_delete_equip_reseau');
  d('DROP TRIGGER trg_valid_serie_ordinateur');

  -- Suppression des PACKAGE
  d('DROP PACKAGE pkg_maintenance');
  d('DROP PACKAGE pkg_reseau');
  d('DROP PACKAGE pkg_stats');
  d('DROP PACKAGE pkg_parc_info');

  -- Suppression des PROCEDURE et FONCTION
  d('DROP PROCEDURE sync_tables_cluster');
  d('DROP PROCEDURE log_change');
  d('DROP PROCEDURE p_ajouter_ordinateur');
  d('DROP PROCEDURE p_transferer_ordinateur');
  d('DROP PROCEDURE p_desactiver_utilisateur');
  d('DROP PROCEDURE p_installer_logiciel');
  d('DROP PROCEDURE p_supprimer_materiel');
  d('DROP FUNCTION f_nb_ordinateurs_site');
  d('DROP FUNCTION f_nb_materiel_site');
  d('DROP FUNCTION f_nom_site');
  d('DROP FUNCTION f_taux_utilisation_site');
  d('DROP FUNCTION f_age_moyen_parc');
  d('DROP FUNCTION f_utilisateur_actif');
  d('DROP FUNCTION f_nb_logiciels_ordinateur');
  d('DROP FUNCTION f_age_materiel_jours');
  d('DROP FUNCTION f_nb_ports_actifs');
  d('DROP FUNCTION f_user_id_par_email');
  d('DROP FUNCTION f_nom_complet_entite');

  -- Suppression des TABLE (par ordre de dependances d'abord)
  -- On utilise CASCADE CONSTRAINTS pour ignorer les Foreign Key
  d('DROP TABLE installations_logiciels CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE versions_logiciel        CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE logiciels                CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE ports_reseau             CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE equipements_reseau       CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE types_equip_reseau       CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE historique               CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE telephones               CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE peripheriques            CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE ordinateurs              CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE ordinateurs_cl           CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE peripheriques_cl         CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE test_ts_pau_marker       CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE profils_utilisateurs     CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE groupes                  CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE utilisateurs             CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE profils                  CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE localisations            CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE entites                  CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE sites                    CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE modeles_ordinateur       CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE fabricants               CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE etats                    CASCADE CONSTRAINTS PURGE');
  d('DROP TABLE types_ordinateur         CASCADE CONSTRAINTS PURGE');

  -- Suppression des CLUSTER
  d('DROP CLUSTER cl_materiel_localisation INCLUDING TABLES CASCADE CONSTRAINTS');

  -- Suppression des SEQUENCE
  d('DROP SEQUENCE seq_sites');
  d('DROP SEQUENCE seq_entites');
  d('DROP SEQUENCE seq_localisations');
  d('DROP SEQUENCE seq_fabricants');
  d('DROP SEQUENCE seq_etats');
  d('DROP SEQUENCE seq_types_ordinateur');
  d('DROP SEQUENCE seq_modeles_ordinateur');
  d('DROP SEQUENCE seq_ordinateurs');
  d('DROP SEQUENCE seq_peripheriques');
  d('DROP SEQUENCE seq_telephones');
  d('DROP SEQUENCE seq_logiciels');
  d('DROP SEQUENCE seq_versions_logiciel');
  d('DROP SEQUENCE seq_install_logiciels');
  d('DROP SEQUENCE seq_utilisateurs');
  d('DROP SEQUENCE seq_profils');
  d('DROP SEQUENCE seq_profils_utilisateurs');
  d('DROP SEQUENCE seq_groupes');
  d('DROP SEQUENCE seq_equip_reseau');
  d('DROP SEQUENCE seq_types_equip_reseau');
  d('DROP SEQUENCE seq_ports_reseau');
  d('DROP SEQUENCE seq_historique');

  -- Suppression des USER
  d('ALTER SESSION SET "_ORACLE_SCRIPT"=true');
  d('DROP USER ADMIN_CYTECH CASCADE');
  d('DROP USER TECH_CERGY   CASCADE');
  d('DROP USER TECH_PAU     CASCADE');
  d('DROP USER USER_RO      CASCADE');

  -- Suppression des ROLE
  d('DROP ROLE R_ADMIN');
  d('DROP ROLE R_TECH_CERGY');
  d('DROP ROLE R_TECH_PAU');
  d('DROP ROLE R_CONSULTATION');

END;
/


-- Suppression des TABLESPACE (supprime aussi les datafiles .dbf)
BEGIN EXECUTE IMMEDIATE 'DROP TABLESPACE TS_MATERIEL_CERGY INCLUDING CONTENTS AND DATAFILES'; EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('SKIP : DROP TABLESPACE TS_MATERIEL_CERGY'); END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLESPACE TS_MATERIEL_PAU   INCLUDING CONTENTS AND DATAFILES'; EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('SKIP : DROP TABLESPACE TS_MATERIEL_PAU');   END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLESPACE TS_USERS          INCLUDING CONTENTS AND DATAFILES'; EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('SKIP : DROP TABLESPACE TS_USERS');          END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLESPACE TS_NETWORK_CERGY  INCLUDING CONTENTS AND DATAFILES'; EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('SKIP : DROP TABLESPACE TS_NETWORK_CERGY');  END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLESPACE TS_NETWORK_PAU    INCLUDING CONTENTS AND DATAFILES'; EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('SKIP : DROP TABLESPACE TS_NETWORK_PAU');    END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLESPACE TS_INDEX          INCLUDING CONTENTS AND DATAFILES'; EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('SKIP : DROP TABLESPACE TS_INDEX');          END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLESPACE TS_TEMP           INCLUDING CONTENTS AND TEMPFILES'; EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('SKIP : DROP TABLESPACE TS_TEMP');           END;
/

PROMPT
PROMPT ================================================================
PROMPT  Nettoyage termine. Relancez bdd_Cy_infrastructure.sql.
PROMPT ================================================================

SET FEEDBACK ON;
