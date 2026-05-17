/*
  Schema principal -- Projet GLPI CY Tech multi-sites (Cergy + Pau).

  Decisions de modelisation :
    - Table `hierarchy_level` (anciennement `entites` / `hierarchy_levels`) :
      structure hierarchique organisationnelle (CY Tech > Cergy/Pau > departements).
    - Table `profils` CONSERVEE comme simple lookup (Admin, Technicien, Enseignant,
      Etudiant, Administration). Permet de classer les utilisateurs par role
      applicatif sans dupliquer les libelles. Reference via utilisateurs.profil_id.
    - Table `profils_utilisateurs` (M:N profils <-> utilisateurs <-> hierarchy_level)
      SUPPRIMEE : dans le contexte CY Tech un utilisateur n'a qu'un profil, la
      relation 1:1 deguisee en M:N n'apportait rien.
    - Table `groupes` conservee : referencee par ordinateurs.groupe_id pour
      regrouper du materiel (ex : "PCs salle TP Cauchy").

  Note Oracle : `CREATE OR REPLACE` n'est valide QUE pour
  VIEW / PROCEDURE / FUNCTION / TRIGGER / PACKAGE / SYNONYM / TYPE.
  Pour TABLE / TABLESPACE / ROLE / USER / CLUSTER / SEQUENCE : DROP puis CREATE.
  Le bloc "DROP idempotent" en tete du fichier permet de relancer le script
  proprement.

  Cluster `cl_materiel_localisation` : abandonne (bonus pedagogique non concluant).

  Ordre d'execution : voir README.md
*/

ALTER SESSION SET "_ORACLE_SCRIPT"=true;
SET SERVEROUTPUT ON SIZE UNLIMITED;

-- =============================================================================
-- 0. RESOLUTION DU PDB COURANT + REPERTOIRE DES DATAFILES
-- =============================================================================
-- On lit le PDB courant pour :
--   1) Faire pointer db_create_file_dest sur le dossier du PDB (OMF active)
--      => evite la collision de noms .dbf entre XE_CERGY et XE_PAU.
--   2) Reconstruire la connexion ADMIN_CYTECH plus bas via &current_pdb.
-- Hypothese : les PDBs sont a C:\app\<user>\product\21c\oradata\XE\<pdb_name>\
-- (chemin par defaut Oracle XE 21c). Ajuste si ton install differe.

SET HEADING OFF
SET FEEDBACK OFF
COLUMN pdb_name NEW_VALUE current_pdb NOPRINT
SELECT sys_context('USERENV','CON_NAME') AS pdb_name FROM dual;
COLUMN datafile_dir NEW_VALUE datafile_dir NOPRINT
SELECT REGEXP_REPLACE(name, '[^\\]+$', '') AS datafile_dir
  FROM v$datafile
 WHERE con_id = sys_context('USERENV','CON_ID')
   AND ROWNUM = 1;
SET HEADING ON
SET FEEDBACK ON

ALTER SESSION SET db_create_file_dest = '&datafile_dir';

-- =============================================================================
-- 0b. NETTOYAGE IDEMPOTENT (DROP silencieux avant re-creation)
--     Permet de relancer le script sans dropper le PDB.
--     _ORACLE_SCRIPT=true est deja actif (ligne precedente du fichier).
-- =============================================================================
BEGIN
  -- Sessions actives
  FOR s IN (SELECT sid, serial# FROM v$session
             WHERE username IN ('ADMIN_CYTECH','TECH_CERGY','TECH_PAU','USER_RO')) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.serial# || ''' IMMEDIATE';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
  -- Utilisateurs (CASCADE supprime toutes leurs sequences/tables/vues/etc.)
  FOR u IN (SELECT username FROM dba_users
             WHERE username IN ('ADMIN_CYTECH','TECH_CERGY','TECH_PAU','USER_RO')) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
  -- Roles
  FOR r IN (SELECT role FROM dba_roles
             WHERE role IN ('R_ADMIN','R_TECH_CERGY','R_TECH_PAU','R_CONSULTATION')) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP ROLE ' || r.role;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
  -- Tablespaces
  FOR ts IN (SELECT tablespace_name FROM dba_tablespaces
              WHERE tablespace_name IN
                ('TS_MATERIEL_CERGY','TS_MATERIEL_PAU','TS_USERS',
                 'TS_NETWORK_CERGY','TS_NETWORK_PAU','TS_INDEX')) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP TABLESPACE ' || ts.tablespace_name ||
                        ' INCLUDING CONTENTS AND DATAFILES';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
  FOR ts IN (SELECT tablespace_name FROM dba_temp_files
              WHERE tablespace_name = 'TS_TEMP') LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP TABLESPACE TS_TEMP INCLUDING CONTENTS AND TEMPFILES';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('Nettoyage idempotent termine.');
END;
/

-- =============================================================================
-- 1. TABLESPACES (auto-place dans &datafile_dir grace a OMF)
-- =============================================================================

CREATE TABLESPACE TS_MATERIEL_CERGY
  DATAFILE SIZE 100M AUTOEXTEND ON NEXT 50M MAXSIZE 500M;

CREATE TABLESPACE TS_MATERIEL_PAU
  DATAFILE SIZE 100M AUTOEXTEND ON NEXT 50M MAXSIZE 500M;

CREATE TABLESPACE TS_USERS
  DATAFILE SIZE 50M AUTOEXTEND ON NEXT 25M MAXSIZE 200M;

CREATE TABLESPACE TS_NETWORK_CERGY
  DATAFILE SIZE 50M AUTOEXTEND ON NEXT 25M MAXSIZE 200M;

CREATE TABLESPACE TS_NETWORK_PAU
  DATAFILE SIZE 50M AUTOEXTEND ON NEXT 25M MAXSIZE 200M;

CREATE TABLESPACE TS_INDEX
  DATAFILE SIZE 50M AUTOEXTEND ON NEXT 25M MAXSIZE 200M;

CREATE TEMPORARY TABLESPACE TS_TEMP
  TEMPFILE SIZE 50M AUTOEXTEND ON NEXT 25M MAXSIZE 200M;


-- =============================================================================
-- 2. UTILISATEURS ET ROLES ORACLE
-- =============================================================================

-- Roles
-- R_ADMIN        : admin general (Cergy + Pau)
-- R_TECH_CERGY   : technicien Cergy
-- R_TECH_PAU     : technicien Pau
-- R_CONSULTATION : lecture seule
CREATE ROLE R_ADMIN;
CREATE ROLE R_TECH_CERGY;
CREATE ROLE R_TECH_PAU;
CREATE ROLE R_CONSULTATION;

-- Privileges R_ADMIN
GRANT CONNECT, RESOURCE TO R_ADMIN;
GRANT CREATE TABLE, CREATE VIEW, CREATE PROCEDURE, CREATE TRIGGER TO R_ADMIN;
GRANT CREATE SEQUENCE, CREATE SYNONYM, CREATE DATABASE LINK TO R_ADMIN;
GRANT CREATE CLUSTER, CREATE MATERIALIZED VIEW TO R_ADMIN;
-- UNLIMITED TABLESPACE est un privilege qui ne peut etre accorde qu'a un user,
-- pas a un role. On le grant directement a ADMIN_CYTECH plus bas.

-- Privileges R_TECH_CERGY
GRANT CONNECT, RESOURCE TO R_TECH_CERGY;
GRANT CREATE SESSION TO R_TECH_CERGY;

-- Privileges R_TECH_PAU
GRANT CONNECT, RESOURCE TO R_TECH_PAU;
GRANT CREATE SESSION TO R_TECH_PAU;

-- Privileges R_CONSULTATION
GRANT CONNECT TO R_CONSULTATION;
GRANT CREATE SESSION TO R_CONSULTATION;

-- Utilisateurs
CREATE USER ADMIN_CYTECH IDENTIFIED BY cytech2026
  DEFAULT TABLESPACE TS_USERS
  TEMPORARY TABLESPACE TS_TEMP;

CREATE USER TECH_CERGY IDENTIFIED BY cergy2026
  DEFAULT TABLESPACE TS_MATERIEL_CERGY
  TEMPORARY TABLESPACE TS_TEMP;

CREATE USER TECH_PAU IDENTIFIED BY pau2026
  DEFAULT TABLESPACE TS_MATERIEL_PAU
  TEMPORARY TABLESPACE TS_TEMP;

CREATE USER USER_RO IDENTIFIED BY RO2026
  DEFAULT TABLESPACE TS_USERS
  TEMPORARY TABLESPACE TS_TEMP;

-- Attribution des roles
GRANT R_ADMIN TO ADMIN_CYTECH;
GRANT R_TECH_CERGY TO TECH_CERGY;
GRANT R_TECH_PAU TO TECH_PAU;

-- UNLIMITED TABLESPACE doit etre accorde directement aux utilisateurs (pas aux roles)
GRANT UNLIMITED TABLESPACE TO ADMIN_CYTECH;
GRANT UNLIMITED TABLESPACE TO TECH_CERGY;
GRANT UNLIMITED TABLESPACE TO TECH_PAU;
GRANT R_CONSULTATION TO USER_RO;

-- UNLIMITED TABLESPACE : privilege direct sur l'utilisateur (pas via role)
GRANT UNLIMITED TABLESPACE TO ADMIN_CYTECH;
ALTER USER TECH_CERGY QUOTA UNLIMITED ON TS_MATERIEL_CERGY;
ALTER USER TECH_CERGY QUOTA UNLIMITED ON TS_NETWORK_CERGY;
ALTER USER TECH_PAU    QUOTA UNLIMITED ON TS_MATERIEL_PAU;
ALTER USER TECH_PAU    QUOTA UNLIMITED ON TS_NETWORK_PAU;

-- Pour creer des synonymes publics et des MV depuis le schema admin
GRANT CREATE PUBLIC SYNONYM TO ADMIN_CYTECH;
GRANT DROP PUBLIC SYNONYM   TO ADMIN_CYTECH;

-- ============================================================================
-- BASCULE DE SESSION : on quitte SYSDBA et on devient ADMIN_CYTECH.
-- Raison : on ne peut pas creer de TRIGGER sur des tables possedees par SYS
-- (ORA-04089). Tout le schema applicatif (tables, vues, sequences, etc.)
-- doit etre cree dans le schema ADMIN_CYTECH.
-- &current_pdb a deja ete resolu en haut du script.
-- ============================================================================

-- Droit d'ecriture sur PLAN_TABLE (necessaire pour EXPLAIN PLAN dans tests_perf)
GRANT SELECT, INSERT, UPDATE, DELETE ON SYS.PLAN_TABLE$ TO ADMIN_CYTECH;

CONNECT ADMIN_CYTECH/cytech2026@//localhost:1521/&current_pdb


-- =============================================================================
-- 3. SEQUENCES
-- =============================================================================

CREATE SEQUENCE seq_sites START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_hierarchy_level START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_localisations START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_fabricants START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_etats START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_types_ordinateur START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_modeles_ordinateur START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_ordinateurs START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_peripheriques START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_telephones START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_logiciels START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_versions_logiciel START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_install_logiciels START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_utilisateurs START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_profils START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_groupes START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_equip_reseau START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_types_equip_reseau START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_ports_reseau START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_historique START WITH 1 INCREMENT BY 1;


-- =============================================================================
-- 4. TABLES REFERENTIELLES (partagees entre Cergy et Pau)
-- =============================================================================

-- Sites CY Tech
CREATE TABLE sites (
  id          NUMBER PRIMARY KEY,
  nom         VARCHAR2(100) NOT NULL,
  adresse     VARCHAR2(255),
  ville       VARCHAR2(100) NOT NULL,
  code_postal VARCHAR2(10),
  telephone   VARCHAR2(20),
  date_creation     DATE DEFAULT SYSDATE,
  date_modification DATE DEFAULT SYSDATE
) TABLESPACE TS_USERS;

-- Hierarchy_level : structure organisationnelle
-- (CY Tech > Cergy / Pau > Departement Info / Maths / ...)
CREATE TABLE hierarchy_level (
  id                        NUMBER PRIMARY KEY,
  nom                       VARCHAR2(255) NOT NULL,
  hierarchy_level_parent_id NUMBER REFERENCES hierarchy_level(id),
  site_id                   NUMBER NOT NULL REFERENCES sites(id),
  niveau                    NUMBER DEFAULT 0,
  nom_complet               VARCHAR2(500),
  est_recursif              NUMBER(1) DEFAULT 0 CHECK (est_recursif IN (0,1)),
  date_creation             DATE DEFAULT SYSDATE,
  date_modification         DATE DEFAULT SYSDATE
) TABLESPACE TS_USERS;

-- Localisations physiques (Salle 201, Bureau...)
CREATE TABLE localisations (
  id                     NUMBER PRIMARY KEY,
  nom                    VARCHAR2(255) NOT NULL,
  nom_complet            VARCHAR2(500),
  hierarchy_level_id     NUMBER NOT NULL REFERENCES hierarchy_level(id),
  localisation_parent_id NUMBER REFERENCES localisations(id),
  batiment               VARCHAR2(50),
  salle                  VARCHAR2(20),
  etage                  VARCHAR2(20),
  date_creation          DATE DEFAULT SYSDATE,
  date_modification      DATE DEFAULT SYSDATE
) TABLESPACE TS_USERS;

-- Fabricants
CREATE TABLE fabricants (
  id  NUMBER PRIMARY KEY,
  nom VARCHAR2(255) NOT NULL UNIQUE
) TABLESPACE TS_USERS;

-- Etats du materiel
CREATE TABLE etats (
  id   NUMBER PRIMARY KEY,
  nom  VARCHAR2(255) NOT NULL UNIQUE,
  etat VARCHAR2(50)
) TABLESPACE TS_USERS;

-- Types d'ordinateurs (Desktop, Laptop, Serveur...)
CREATE TABLE types_ordinateur (
  id           NUMBER PRIMARY KEY,
  machine_type VARCHAR2(255) NOT NULL
) TABLESPACE TS_USERS;

-- Modeles d'ordinateurs
CREATE TABLE modeles_ordinateur (
  id           NUMBER PRIMARY KEY,
  nom          VARCHAR2(255) NOT NULL,
  ref_produit  VARCHAR2(255),
  fabricant_id NUMBER REFERENCES fabricants(id)
) TABLESPACE TS_USERS;

-- Profils applicatifs (lookup)
-- Admin / Technicien / Enseignant / Etudiant / Administration
CREATE TABLE profils (
  id        NUMBER PRIMARY KEY,
  nom       VARCHAR2(100) NOT NULL UNIQUE,
  interface VARCHAR2(50)   -- 'central' (admin) ou 'helpdesk' (utilisateur)
) TABLESPACE TS_USERS;


-- =============================================================================
-- 5. TABLES UTILISATEURS (TS_USERS)
-- =============================================================================

-- Utilisateurs
CREATE TABLE utilisateurs (
  id                 NUMBER PRIMARY KEY,
  login              VARCHAR2(255) NOT NULL UNIQUE,
  mot_de_passe       VARCHAR2(255) NOT NULL,
  nom                VARCHAR2(255),
  prenom             VARCHAR2(255),
  email              VARCHAR2(255),
  telephone          VARCHAR2(50),
  mobile             VARCHAR2(50),
  hierarchy_level_id NUMBER REFERENCES hierarchy_level(id),
  localisation_id    NUMBER REFERENCES localisations(id),
  profil_id          NUMBER REFERENCES profils(id),
  site_id            NUMBER REFERENCES sites(id),
  langue             VARCHAR2(10) DEFAULT 'fr_FR',
  est_actif          NUMBER(1) DEFAULT 1 CHECK (est_actif IN (0,1)),
  est_supprime       NUMBER(1) DEFAULT 0 CHECK (est_supprime IN (0,1)),
  type_auth          NUMBER DEFAULT 1,
  date_debut         DATE,
  date_fin           DATE,
  date_creation      DATE DEFAULT SYSDATE,
  date_modification  DATE DEFAULT SYSDATE
) TABLESPACE TS_USERS;

-- Groupes (regroupement logique de materiel ; ex : "PCs salle TP Cauchy")
CREATE TABLE groupes (
  id                 NUMBER PRIMARY KEY,
  nom                VARCHAR2(255) NOT NULL,
  hierarchy_level_id NUMBER NOT NULL REFERENCES hierarchy_level(id),
  groupe_parent_id   NUMBER REFERENCES groupes(id),
  est_recursif       NUMBER(1) DEFAULT 0 CHECK (est_recursif IN (0,1)),
  commentaire        VARCHAR2(255),
  date_creation      DATE DEFAULT SYSDATE,
  date_modification  DATE DEFAULT SYSDATE
) TABLESPACE TS_USERS;


-- =============================================================================
-- 6. TABLES MATERIEL (TS_MATERIEL_CERGY pour l'instance Cergy)
-- =============================================================================
-- Cote XE_PAU, les memes tables sont creees dans TS_MATERIEL_PAU.
-- Voir le bloc "DEPLOIEMENT COTE PAU" en fin de fichier.

-- Ordinateurs
CREATE TABLE ordinateurs (
  id                  NUMBER PRIMARY KEY,
  nom                 VARCHAR2(255) NOT NULL,
  numero_serie        VARCHAR2(255),
  numero_inventaire   VARCHAR2(255),
  hierarchy_level_id  NUMBER NOT NULL REFERENCES hierarchy_level(id),
  localisation_id     NUMBER REFERENCES localisations(id),
  type_ordinateur_id  NUMBER REFERENCES types_ordinateur(id),
  modele_id           NUMBER REFERENCES modeles_ordinateur(id),
  fabricant_id        NUMBER REFERENCES fabricants(id),
  etat_id             NUMBER REFERENCES etats(id),
  utilisateur_id      NUMBER REFERENCES utilisateurs(id),
  groupe_id           NUMBER REFERENCES groupes(id),
  technicien_id       NUMBER REFERENCES utilisateurs(id),
  site_id             NUMBER NOT NULL REFERENCES sites(id),
  commentaire         VARCHAR2(255),
  est_supprime        NUMBER(1) DEFAULT 0 CHECK (est_supprime IN (0,1)),
  est_template        NUMBER(1) DEFAULT 0 CHECK (est_template IN (0,1)),
  date_achat          DATE,
  date_creation       DATE DEFAULT SYSDATE,
  date_modification   DATE DEFAULT SYSDATE
) TABLESPACE TS_MATERIEL_CERGY;

-- Peripheriques (imprimantes, souris, claviers, videoprojecteurs...)
CREATE TABLE peripheriques (
  id                 NUMBER PRIMARY KEY,
  nom                VARCHAR2(255) NOT NULL,
  numero_serie       VARCHAR2(255),
  type_peripherique  VARCHAR2(100) NOT NULL
    CHECK (type_peripherique IN ('imprimante','souris','clavier','videoprojecteur','ecran','autre')),
  hierarchy_level_id NUMBER NOT NULL REFERENCES hierarchy_level(id),
  localisation_id    NUMBER REFERENCES localisations(id),
  fabricant_id       NUMBER REFERENCES fabricants(id),
  etat_id            NUMBER REFERENCES etats(id),
  utilisateur_id     NUMBER REFERENCES utilisateurs(id),
  site_id            NUMBER NOT NULL REFERENCES sites(id),
  commentaire        VARCHAR2(255),
  est_supprime       NUMBER(1) DEFAULT 0 CHECK (est_supprime IN (0,1)),
  date_creation      DATE DEFAULT SYSDATE,
  date_modification  DATE DEFAULT SYSDATE
) TABLESPACE TS_MATERIEL_CERGY;

-- Telephones (secretariat, accueil...)
CREATE TABLE telephones (
  id                 NUMBER PRIMARY KEY,
  nom                VARCHAR2(255) NOT NULL,
  numero_serie       VARCHAR2(255),
  numero_tel         VARCHAR2(50),
  type_telephone     VARCHAR2(50) DEFAULT 'fixe'
    CHECK (type_telephone IN ('fixe','mobile','ip')),
  hierarchy_level_id NUMBER NOT NULL REFERENCES hierarchy_level(id),
  localisation_id    NUMBER REFERENCES localisations(id),
  fabricant_id       NUMBER REFERENCES fabricants(id),
  etat_id            NUMBER REFERENCES etats(id),
  utilisateur_id     NUMBER REFERENCES utilisateurs(id),
  site_id            NUMBER NOT NULL REFERENCES sites(id),
  service            VARCHAR2(100),
  commentaire        VARCHAR2(255),
  est_supprime       NUMBER(1) DEFAULT 0 CHECK (est_supprime IN (0,1)),
  date_creation      DATE DEFAULT SYSDATE,
  date_modification  DATE DEFAULT SYSDATE
) TABLESPACE TS_MATERIEL_CERGY;

-- Logiciels
CREATE TABLE logiciels (
  id                 NUMBER PRIMARY KEY,
  nom                VARCHAR2(255) NOT NULL,
  editeur            VARCHAR2(255),
  fabricant_id       NUMBER REFERENCES fabricants(id),
  hierarchy_level_id NUMBER REFERENCES hierarchy_level(id),
  est_supprime       NUMBER(1) DEFAULT 0,
  date_creation      DATE DEFAULT SYSDATE,
  date_modification  DATE DEFAULT SYSDATE
) TABLESPACE TS_MATERIEL_CERGY;

-- Versions de logiciels
CREATE TABLE versions_logiciel (
  id            NUMBER PRIMARY KEY,
  nom           VARCHAR2(255) NOT NULL,
  logiciel_id   NUMBER NOT NULL REFERENCES logiciels(id),
  etat_id       NUMBER REFERENCES etats(id),
  date_creation DATE DEFAULT SYSDATE
) TABLESPACE TS_MATERIEL_CERGY;

-- Installations de logiciels (quel ordi a quel logiciel)
CREATE TABLE installations_logiciels (
  id                  NUMBER PRIMARY KEY,
  ordinateur_id       NUMBER NOT NULL REFERENCES ordinateurs(id),
  version_logiciel_id NUMBER NOT NULL REFERENCES versions_logiciel(id),
  date_installation   DATE DEFAULT SYSDATE,
  CONSTRAINT uk_install_log UNIQUE (ordinateur_id, version_logiciel_id)
) TABLESPACE TS_MATERIEL_CERGY;


-- =============================================================================
-- 7. TABLES RESEAU (TS_NETWORK_CERGY)
-- =============================================================================

-- Types d'equipement reseau (switch, routeur, AP WiFi...)
CREATE TABLE types_equip_reseau (
  id  NUMBER PRIMARY KEY,
  nom VARCHAR2(255) NOT NULL UNIQUE
) TABLESPACE TS_NETWORK_CERGY;

-- Equipements reseau
CREATE TABLE equipements_reseau (
  id                 NUMBER PRIMARY KEY,
  nom                VARCHAR2(255) NOT NULL,
  numero_serie       VARCHAR2(255),
  hierarchy_level_id NUMBER NOT NULL REFERENCES hierarchy_level(id),
  localisation_id    NUMBER REFERENCES localisations(id),
  type_equip_id      NUMBER REFERENCES types_equip_reseau(id),
  fabricant_id       NUMBER REFERENCES fabricants(id),
  etat_id            NUMBER REFERENCES etats(id),
  site_id            NUMBER NOT NULL REFERENCES sites(id),
  nb_ports           NUMBER,
  commentaire        VARCHAR2(255),
  est_supprime       NUMBER(1) DEFAULT 0,
  date_creation      DATE DEFAULT SYSDATE,
  date_modification  DATE DEFAULT SYSDATE
) TABLESPACE TS_NETWORK_CERGY;

-- Ports reseau (ethernet ou wifi)
CREATE TABLE ports_reseau (
  id                NUMBER PRIMARY KEY,
  nom               VARCHAR2(255),
  equipement_id     NUMBER NOT NULL REFERENCES equipements_reseau(id),
  adresse_mac       VARCHAR2(50),
  type_port         VARCHAR2(20) DEFAULT 'ethernet'
    CHECK (type_port IN ('ethernet','wifi')),
  vitesse           NUMBER,
  est_actif         NUMBER(1) DEFAULT 1 CHECK (est_actif IN (0,1)),
  date_creation     DATE DEFAULT SYSDATE,
  date_modification DATE DEFAULT SYSDATE
) TABLESPACE TS_NETWORK_CERGY;


-- =============================================================================
-- 7 bis. CLUSTER (co-localisation par localisation_id)
-- =============================================================================
-- Un cluster regroupe physiquement sur disque les lignes de plusieurs tables
-- qui partagent une cle. Ici, ordinateurs et peripheriques partageant la meme
-- localisation_id sont stockes ensemble dans les memes blocs.
--   Avantage : un SELECT "tous les ordis + periph d'une salle" lit moins
--              de blocs (regroupement physique).
--   Inconvenient : INSERT/UPDATE plus couteux, table cluster monolithique
--              (pas de TRUNCATE individuel).
--
-- Approche pedagogique : on cree des tables jumelles _cl en parallele des
-- originales (pas de migration destructive). tests_perf.sql synchronise les
-- _cl apres le jeu de test puis compare les performances cluster vs heap.

CREATE CLUSTER cl_materiel_localisation (localisation_id NUMBER)
  SIZE 512 TABLESPACE TS_MATERIEL_CERGY;

CREATE INDEX idx_cluster_materiel_loc ON CLUSTER cl_materiel_localisation
  TABLESPACE TS_INDEX;

CREATE TABLE ordinateurs_cl (
  id                  NUMBER PRIMARY KEY,
  nom                 VARCHAR2(255) NOT NULL,
  numero_serie        VARCHAR2(255),
  numero_inventaire   VARCHAR2(255),
  hierarchy_level_id  NUMBER NOT NULL REFERENCES hierarchy_level(id),
  localisation_id     NUMBER REFERENCES localisations(id),
  type_ordinateur_id  NUMBER REFERENCES types_ordinateur(id),
  modele_id           NUMBER REFERENCES modeles_ordinateur(id),
  fabricant_id        NUMBER REFERENCES fabricants(id),
  etat_id             NUMBER REFERENCES etats(id),
  utilisateur_id      NUMBER REFERENCES utilisateurs(id),
  groupe_id           NUMBER REFERENCES groupes(id),
  technicien_id       NUMBER REFERENCES utilisateurs(id),
  site_id             NUMBER NOT NULL REFERENCES sites(id),
  commentaire         VARCHAR2(255),
  est_supprime        NUMBER(1) DEFAULT 0,
  est_template        NUMBER(1) DEFAULT 0,
  date_achat          DATE,
  date_creation       DATE DEFAULT SYSDATE,
  date_modification   DATE DEFAULT SYSDATE
) CLUSTER cl_materiel_localisation (localisation_id);

CREATE TABLE peripheriques_cl (
  id                 NUMBER PRIMARY KEY,
  nom                VARCHAR2(255) NOT NULL,
  numero_serie       VARCHAR2(255),
  type_peripherique  VARCHAR2(100) NOT NULL,
  hierarchy_level_id NUMBER NOT NULL REFERENCES hierarchy_level(id),
  localisation_id    NUMBER REFERENCES localisations(id),
  fabricant_id       NUMBER REFERENCES fabricants(id),
  etat_id            NUMBER REFERENCES etats(id),
  utilisateur_id     NUMBER REFERENCES utilisateurs(id),
  site_id            NUMBER NOT NULL REFERENCES sites(id),
  commentaire        VARCHAR2(255),
  est_supprime       NUMBER(1) DEFAULT 0,
  date_creation      DATE DEFAULT SYSDATE,
  date_modification  DATE DEFAULT SYSDATE
) CLUSTER cl_materiel_localisation (localisation_id);


-- =============================================================================
-- 8. TABLE HISTORIQUE (audit)
-- =============================================================================

CREATE TABLE historique (
  id              NUMBER PRIMARY KEY,
  type_objet      VARCHAR2(100) NOT NULL,
  objet_id        NUMBER NOT NULL,
  utilisateur_id  NUMBER REFERENCES utilisateurs(id),
  champ_modifie   VARCHAR2(255),
  ancienne_valeur VARCHAR2(4000),
  nouvelle_valeur VARCHAR2(4000),
  type_action     VARCHAR2(20) CHECK (type_action IN ('INSERT','UPDATE','DELETE')),
  date_action     DATE DEFAULT SYSDATE
) TABLESPACE TS_USERS;


-- =============================================================================
-- 9. INDEX
-- =============================================================================

-- ── Index B-TREE sur FK et champs de recherche ──

-- Ordinateurs
CREATE INDEX idx_ordi_hierarchy_level ON ordinateurs(hierarchy_level_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_localisation    ON ordinateurs(localisation_id)    TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_utilisateur     ON ordinateurs(utilisateur_id)     TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_fabricant       ON ordinateurs(fabricant_id)       TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_etat            ON ordinateurs(etat_id)            TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_site            ON ordinateurs(site_id)            TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_nom             ON ordinateurs(nom)                TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_serie           ON ordinateurs(numero_serie)       TABLESPACE TS_INDEX;

-- Peripheriques
CREATE INDEX idx_periph_hierarchy_level ON peripheriques(hierarchy_level_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_periph_site            ON peripheriques(site_id)            TABLESPACE TS_INDEX;
CREATE INDEX idx_periph_type            ON peripheriques(type_peripherique)  TABLESPACE TS_INDEX;
CREATE INDEX idx_periph_utilisateur     ON peripheriques(utilisateur_id)     TABLESPACE TS_INDEX;

-- Telephones
CREATE INDEX idx_tel_hierarchy_level ON telephones(hierarchy_level_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_tel_site            ON telephones(site_id)            TABLESPACE TS_INDEX;
CREATE INDEX idx_tel_service         ON telephones(service)            TABLESPACE TS_INDEX;

-- Utilisateurs
CREATE INDEX idx_user_hierarchy_level ON utilisateurs(hierarchy_level_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_user_site            ON utilisateurs(site_id)            TABLESPACE TS_INDEX;
CREATE INDEX idx_user_nom             ON utilisateurs(nom)                TABLESPACE TS_INDEX;
CREATE INDEX idx_user_profil          ON utilisateurs(profil_id)          TABLESPACE TS_INDEX;

-- Equipements reseau
CREATE INDEX idx_equip_hierarchy_level ON equipements_reseau(hierarchy_level_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_equip_site            ON equipements_reseau(site_id)            TABLESPACE TS_INDEX;

-- Ports reseau
CREATE INDEX idx_port_equip ON ports_reseau(equipement_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_port_mac   ON ports_reseau(adresse_mac)   TABLESPACE TS_INDEX;

-- Historique
CREATE INDEX idx_hist_objet ON historique(type_objet, objet_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_hist_date  ON historique(date_action)          TABLESPACE TS_INDEX;

-- ── Index Bitmap (faible cardinalite) ──
CREATE BITMAP INDEX idx_bmp_ordi_supprime  ON ordinateurs(est_supprime) TABLESPACE TS_INDEX;
CREATE BITMAP INDEX idx_bmp_ordi_template  ON ordinateurs(est_template) TABLESPACE TS_INDEX;
CREATE BITMAP INDEX idx_bmp_user_actif     ON utilisateurs(est_actif)   TABLESPACE TS_INDEX;
CREATE BITMAP INDEX idx_bmp_user_supprime  ON utilisateurs(est_supprime) TABLESPACE TS_INDEX;
CREATE BITMAP INDEX idx_bmp_port_type      ON ports_reseau(type_port)   TABLESPACE TS_INDEX;

-- ── Index par fonction ──
CREATE INDEX idx_ordi_nom_upper   ON ordinateurs(UPPER(nom))    TABLESPACE TS_INDEX;
CREATE INDEX idx_user_login_upper ON utilisateurs(UPPER(login)) TABLESPACE TS_INDEX;


-- =============================================================================
-- 10. VUES
-- =============================================================================

-- Parc Cergy
CREATE OR REPLACE VIEW vue_parc_cergy AS
SELECT o.id, o.nom, o.numero_serie, o.numero_inventaire,
       f.nom AS fabricant, e.nom AS etat,
       l.nom AS localisation, l.batiment, l.salle,
       u.nom AS utilisateur_nom, u.prenom AS utilisateur_prenom,
       o.date_creation, o.date_modification
FROM ordinateurs o
  LEFT JOIN fabricants    f ON o.fabricant_id    = f.id
  LEFT JOIN etats         e ON o.etat_id         = e.id
  LEFT JOIN localisations l ON o.localisation_id = l.id
  LEFT JOIN utilisateurs  u ON o.utilisateur_id  = u.id
WHERE o.site_id = 1 AND o.est_supprime = 0;

-- Parc Pau
CREATE OR REPLACE VIEW vue_parc_pau AS
SELECT o.id, o.nom, o.numero_serie, o.numero_inventaire,
       f.nom AS fabricant, e.nom AS etat,
       l.nom AS localisation, l.batiment, l.salle,
       u.nom AS utilisateur_nom, u.prenom AS utilisateur_prenom,
       o.date_creation, o.date_modification
FROM ordinateurs o
  LEFT JOIN fabricants    f ON o.fabricant_id    = f.id
  LEFT JOIN etats         e ON o.etat_id         = e.id
  LEFT JOIN localisations l ON o.localisation_id = l.id
  LEFT JOIN utilisateurs  u ON o.utilisateur_id  = u.id
WHERE o.site_id = 2 AND o.est_supprime = 0;

-- Peripheriques par site
CREATE OR REPLACE VIEW vue_peripheriques_site AS
SELECT p.id, p.nom, p.type_peripherique, p.numero_serie,
       s.nom AS site, l.nom AS localisation,
       f.nom AS fabricant, e.nom AS etat,
       u.nom AS utilisateur_nom, u.prenom AS utilisateur_prenom
FROM peripheriques p
  LEFT JOIN sites         s ON p.site_id         = s.id
  LEFT JOIN localisations l ON p.localisation_id = l.id
  LEFT JOIN fabricants    f ON p.fabricant_id    = f.id
  LEFT JOIN etats         e ON p.etat_id         = e.id
  LEFT JOIN utilisateurs  u ON p.utilisateur_id  = u.id
WHERE p.est_supprime = 0;

-- Reseau par site
CREATE OR REPLACE VIEW vue_reseau_site AS
SELECT er.id, er.nom AS equipement, ter.nom AS type_equipement,
       s.nom AS site, l.nom AS localisation,
       pr.nom AS port, pr.adresse_mac, pr.type_port, pr.vitesse, pr.est_actif
FROM equipements_reseau er
  LEFT JOIN types_equip_reseau ter ON er.type_equip_id   = ter.id
  LEFT JOIN sites              s   ON er.site_id         = s.id
  LEFT JOIN localisations      l   ON er.localisation_id = l.id
  LEFT JOIN ports_reseau       pr  ON pr.equipement_id   = er.id
WHERE er.est_supprime = 0;

-- Utilisateurs avec profil et hierarchy_level (jointure simple, plus de M:N)
CREATE OR REPLACE VIEW vue_utilisateurs_droits AS
SELECT u.id, u.login, u.nom, u.prenom, u.email,
       s.nom   AS site,
       h.nom   AS hierarchy_level,
       p.nom   AS profil,
       p.interface,
       u.est_actif, u.date_creation
FROM utilisateurs u
  LEFT JOIN sites           s ON u.site_id            = s.id
  LEFT JOIN hierarchy_level h ON u.hierarchy_level_id = h.id
  LEFT JOIN profils         p ON u.profil_id          = p.id
WHERE u.est_supprime = 0;

-- Vue materialisee : stats du parc par site (ON DEMAND => REFRESH manuel)
CREATE MATERIALIZED VIEW mv_stats_parc
  REFRESH ON DEMAND
AS
SELECT s.nom AS site, e.nom AS etat, COUNT(*) AS nb_ordinateurs
FROM ordinateurs o
  JOIN sites s ON o.site_id = s.id
  LEFT JOIN etats e ON o.etat_id = e.id
WHERE o.est_supprime = 0
GROUP BY s.nom, e.nom;


-- =============================================================================
-- 11. BDDR (Base de donnees repartie)
-- =============================================================================

-- Database Link Cergy -> Pau
CREATE DATABASE LINK db_pau
  CONNECT TO TECH_PAU IDENTIFIED BY pau2026
  USING '//localhost:1521/XE_PAU';

-- Side note : sur l'instance XE_PAU, creer un lien symetrique vers Cergy :
--   CREATE DATABASE LINK db_cergy
--     CONNECT TO TECH_CERGY IDENTIFIED BY cergy2026
--     USING '//localhost:1521/XE_CERGY';

-- Synonymes publics pour transparence d'acces
CREATE OR REPLACE PUBLIC SYNONYM ordinateurs_pau        FOR ordinateurs@db_pau;
CREATE OR REPLACE PUBLIC SYNONYM peripheriques_pau      FOR peripheriques@db_pau;
CREATE OR REPLACE PUBLIC SYNONYM telephones_pau         FOR telephones@db_pau;
CREATE OR REPLACE PUBLIC SYNONYM equipements_reseau_pau FOR equipements_reseau@db_pau;

-- Vue de defragmentation simple : parc global (Cergy + Pau)
-- FORCE : la vue est creee meme si db_pau est pas encore joignable
-- (sera INVALID jusqu'a ALTER VIEW ... COMPILE apres deploiement de Pau).
CREATE OR REPLACE FORCE VIEW vue_parc_global AS
SELECT id, nom, numero_serie, site_id, hierarchy_level_id, date_creation
  FROM ordinateurs
UNION ALL
SELECT id, nom, numero_serie, site_id, hierarchy_level_id, date_creation
  FROM ordinateurs@db_pau;

-- Vue de defragmentation enrichie : parc global avec libelles humains
CREATE OR REPLACE FORCE VIEW vue_parc_global_v2 AS
SELECT 'CERGY' AS source,
       o.id, o.nom, o.numero_serie, o.numero_inventaire,
       o.site_id, o.hierarchy_level_id,
       f.nom AS fabricant, e.nom AS etat,
       l.nom AS localisation, l.batiment, l.salle,
       u.login AS utilisateur,
       o.date_achat, o.date_creation
  FROM ordinateurs o
  LEFT JOIN fabricants    f ON f.id = o.fabricant_id
  LEFT JOIN etats         e ON e.id = o.etat_id
  LEFT JOIN localisations l ON l.id = o.localisation_id
  LEFT JOIN utilisateurs  u ON u.id = o.utilisateur_id
 WHERE o.est_supprime = 0
UNION ALL
SELECT 'PAU' AS source,
       o.id, o.nom, o.numero_serie, o.numero_inventaire,
       o.site_id, o.hierarchy_level_id,
       f.nom, e.nom, l.nom, l.batiment, l.salle,
       u.login,
       o.date_achat, o.date_creation
  FROM ordinateurs@db_pau o
  LEFT JOIN fabricants@db_pau    f ON f.id = o.fabricant_id
  LEFT JOIN etats@db_pau         e ON e.id = o.etat_id
  LEFT JOIN localisations@db_pau l ON l.id = o.localisation_id
  LEFT JOIN utilisateurs@db_pau  u ON u.id = o.utilisateur_id
 WHERE o.est_supprime = 0;


-- =============================================================================
-- 12. PRIVILEGES OBJETS
-- =============================================================================

-- Technicien Cergy : droits complets sur le materiel et le reseau Cergy
GRANT SELECT, INSERT, UPDATE, DELETE ON ordinateurs              TO TECH_CERGY;
GRANT SELECT, INSERT, UPDATE, DELETE ON peripheriques            TO TECH_CERGY;
GRANT SELECT, INSERT, UPDATE, DELETE ON telephones               TO TECH_CERGY;
GRANT SELECT, INSERT, UPDATE, DELETE ON logiciels                TO TECH_CERGY;
GRANT SELECT, INSERT, UPDATE, DELETE ON versions_logiciel        TO TECH_CERGY;
GRANT SELECT, INSERT, UPDATE, DELETE ON installations_logiciels  TO TECH_CERGY;
GRANT SELECT, INSERT, UPDATE, DELETE ON equipements_reseau       TO TECH_CERGY;
GRANT SELECT, INSERT, UPDATE, DELETE ON ports_reseau             TO TECH_CERGY;
-- Tables clusterisees (bonus pedagogique : co-localisation par salle)
GRANT SELECT, INSERT, UPDATE, DELETE ON ordinateurs_cl           TO TECH_CERGY;
GRANT SELECT, INSERT, UPDATE, DELETE ON peripheriques_cl         TO TECH_CERGY;
GRANT SELECT ON utilisateurs TO TECH_CERGY;
GRANT SELECT ON profils      TO TECH_CERGY;

-- Technicien Pau : lecture sur toutes les tables consommees via le db_link
-- (les vues vue_parc_global* font jointures sur ces tables).
GRANT SELECT ON sites            TO TECH_PAU;
GRANT SELECT ON hierarchy_level  TO TECH_PAU;
GRANT SELECT ON localisations    TO TECH_PAU;
GRANT SELECT ON ordinateurs      TO TECH_PAU;
GRANT SELECT ON peripheriques    TO TECH_PAU;
GRANT SELECT ON telephones       TO TECH_PAU;
GRANT SELECT ON equipements_reseau TO TECH_PAU;
GRANT SELECT ON ports_reseau     TO TECH_PAU;
GRANT SELECT ON utilisateurs     TO TECH_PAU;
GRANT SELECT ON fabricants       TO TECH_PAU;
GRANT SELECT ON etats            TO TECH_PAU;
GRANT SELECT ON profils          TO TECH_PAU;

-- Synonymes publics pour permettre l'acces sans qualifier admin_cytech.
-- Necessaire car le db_link s'authentifie comme TECH_PAU qui n'a pas
-- admin_cytech dans son search path par defaut.
CREATE OR REPLACE PUBLIC SYNONYM sites              FOR admin_cytech.sites;
CREATE OR REPLACE PUBLIC SYNONYM hierarchy_level    FOR admin_cytech.hierarchy_level;
CREATE OR REPLACE PUBLIC SYNONYM localisations      FOR admin_cytech.localisations;
CREATE OR REPLACE PUBLIC SYNONYM ordinateurs        FOR admin_cytech.ordinateurs;
CREATE OR REPLACE PUBLIC SYNONYM peripheriques      FOR admin_cytech.peripheriques;
CREATE OR REPLACE PUBLIC SYNONYM telephones         FOR admin_cytech.telephones;
CREATE OR REPLACE PUBLIC SYNONYM equipements_reseau FOR admin_cytech.equipements_reseau;
CREATE OR REPLACE PUBLIC SYNONYM ports_reseau       FOR admin_cytech.ports_reseau;
CREATE OR REPLACE PUBLIC SYNONYM utilisateurs       FOR admin_cytech.utilisateurs;
CREATE OR REPLACE PUBLIC SYNONYM fabricants         FOR admin_cytech.fabricants;
CREATE OR REPLACE PUBLIC SYNONYM etats              FOR admin_cytech.etats;
CREATE OR REPLACE PUBLIC SYNONYM profils            FOR admin_cytech.profils;

-- USER_RO : acces uniquement aux vues + MV
GRANT SELECT ON vue_parc_cergy           TO USER_RO;
GRANT SELECT ON vue_parc_pau             TO USER_RO;
GRANT SELECT ON vue_peripheriques_site   TO USER_RO;
GRANT SELECT ON vue_reseau_site          TO USER_RO;
GRANT SELECT ON vue_utilisateurs_droits  TO USER_RO;
GRANT SELECT ON vue_parc_global          TO USER_RO;
GRANT SELECT ON vue_parc_global_v2       TO USER_RO;
GRANT SELECT ON mv_stats_parc            TO USER_RO;

-- Sequences (les techniciens doivent pouvoir consommer NEXTVAL)
GRANT SELECT ON seq_ordinateurs   TO TECH_CERGY;
GRANT SELECT ON seq_peripheriques TO TECH_CERGY;
GRANT SELECT ON seq_telephones    TO TECH_CERGY;


-- =============================================================================
-- 13. DEPLOIEMENT COTE PAU (documentation)
-- =============================================================================
-- Sur l'instance XE_PAU, executer un script analogue qui :
--   1) Cree les memes tablespaces locaux (TS_MATERIEL_PAU et TS_NETWORK_PAU
--      sont les seuls qui hebergent du data ; les autres servent juste aux
--      referentiels et a l'index).
--   2) Cree les tables ordinateurs / peripheriques / telephones dans
--      TS_MATERIEL_PAU et equipements_reseau / ports_reseau dans
--      TS_NETWORK_PAU. La definition (colonnes, FK, CHECK) est identique
--      a celle de Cergy.
--   3) Cree le DB link symetrique db_cergy.
--   4) Repplique les referentiels via des vues materialisees ON DEMAND :
--        CREATE MATERIALIZED VIEW mv_fabricants  REFRESH ON DEMAND
--          AS SELECT * FROM fabricants@db_cergy;
--        CREATE MATERIALIZED VIEW mv_etats       REFRESH ON DEMAND
--          AS SELECT * FROM etats@db_cergy;
--        CREATE MATERIALIZED VIEW mv_sites       REFRESH ON DEMAND
--          AS SELECT * FROM sites@db_cergy;
--        CREATE MATERIALIZED VIEW mv_profils     REFRESH ON DEMAND
--          AS SELECT * FROM profils@db_cergy;
--        CREATE MATERIALIZED VIEW mv_utilisateurs REFRESH ON DEMAND
--          AS SELECT id, login, nom, prenom, email, site_id, profil_id, est_actif
--               FROM utilisateurs@db_cergy
--              WHERE est_supprime = 0;
--   5) Pour rafraichir : EXEC DBMS_MVIEW.REFRESH('mv_<name>', 'C');


-- =============================================================================
-- 14. NOTES FK ON DELETE (a documenter dans le rapport)
-- =============================================================================
-- Les FK ci-dessus n'imposent pas de comportement ON DELETE explicite
-- (par defaut Oracle : NO ACTION = refus si la cle est referencee).
-- Choix metier recommandes pour la prochaine migration :
--   * Suppression d'un utilisateur  -> SET NULL sur ses materiels
--                                       (on ne perd pas le materiel).
--   * Suppression d'une localisation -> SET NULL sur le materiel
--                                       (orphelin reaffectable).
--   * Suppression d'un fabricant     -> RESTRICT (defaut, refus).
-- Pour appliquer effectivement (apres avoir release les anciennes FK) :
--   ALTER TABLE ordinateurs DROP CONSTRAINT <fk_name>;
--   ALTER TABLE ordinateurs ADD CONSTRAINT fk_ordi_user
--     FOREIGN KEY (utilisateur_id) REFERENCES utilisateurs(id) ON DELETE SET NULL;
-- Les noms de FK n'ont pas ete poses explicitement, ils sont auto-generes :
--   SELECT constraint_name FROM user_constraints WHERE table_name = 'ORDINATEURS';
