
-- TABLESPACES

CREATE TABLESPACE TS_MATERIEL_CERGY
  DATAFILE 'ts_materiel_cergy.dbf' SIZE 100M
  AUTOEXTEND ON NEXT 50M MAXSIZE 500M;

CREATE TABLESPACE TS_MATERIEL_PAU
  DATAFILE 'ts_materiel_pau.dbf' SIZE 100M
  AUTOEXTEND ON NEXT 50M MAXSIZE 500M;

CREATE TABLESPACE TS_USERS
  DATAFILE 'ts_users.dbf' SIZE 50M
  AUTOEXTEND ON NEXT 25M MAXSIZE 200M;

CREATE TABLESPACE TS_NETWORK_CERGY
  DATAFILE 'ts_network_cergy.dbf' SIZE 50M
  AUTOEXTEND ON NEXT 25M MAXSIZE 200M;

CREATE TABLESPACE TS_NETWORK_PAU
  DATAFILE 'ts_network_pau.dbf' SIZE 50M
  AUTOEXTEND ON NEXT 25M MAXSIZE 200M;

CREATE TABLESPACE TS_INDEX
  DATAFILE 'ts_index.dbf' SIZE 50M
  AUTOEXTEND ON NEXT 25M MAXSIZE 200M;

CREATE TEMPORARY TABLESPACE TS_TEMP
  TEMPFILE 'ts_temp.dbf' SIZE 50M
  AUTOEXTEND ON NEXT 25M MAXSIZE 200M;

-- UTILISATEURS ET RÔLES ORACLE

-- Rôles
-- R_ADMIN : admin général sur les deux sites
CREATE ROLE R_ADMIN;
-- R_TECH_CERGY : technicien sur le site de Cergy
CREATE ROLE R_TECH_CERGY;
-- R_TECH_PAU : technicien sur le site de Pau
CREATE ROLE R_TECH_PAU;
-- R_CONSULTATION : READONLY sur les deux sites
CREATE ROLE R_CONSULTATION;

-- Privilèges de R_ADMIN
GRANT CONNECT, RESOURCE TO R_ADMIN;
GRANT CREATE TABLE, CREATE VIEW, CREATE PROCEDURE, CREATE TRIGGER TO R_ADMIN;
GRANT CREATE SEQUENCE, CREATE SYNONYM, CREATE DATABASE LINK TO R_ADMIN;
GRANT CREATE CLUSTER, CREATE MATERIALIZED VIEW TO R_ADMIN;
-- UNLIMITED TABLESPACE ne peut pas etre accorde a un role, on le donne
-- directement a l'utilisateur ADMIN_CYTECH plus bas.

-- Privilèges de R_TECH_CERGY
GRANT CONNECT, RESOURCE TO R_TECH_CERGY;
GRANT CREATE SESSION TO R_TECH_CERGY;

-- Privilèges de R_TECH_PAU
GRANT CONNECT, RESOURCE TO R_TECH_PAU;
GRANT CREATE SESSION TO R_TECH_PAU;

-- Privilèges de R_CONSULTATION
GRANT CONNECT TO R_CONSULTATION;
GRANT CREATE SESSION TO R_CONSULTATION;

-- Utilisateurs 
CREATE USER ADMIN_CYTECH IDENTIFIED BY cytech2026
  DEFAULT TABLESPACE TS_USERS
  TEMPORARY TABLESPACE TS_TEMP;

CREATE USER TECH_CERGY IDENTIFIED BY cergy2026
  DEFAULT TABLESPACE TS_MATERIEL_CERGY
  TEMPORARY TABLESPACE TS_TEMP;

CREATE USER TECH_PAU IDENTIFIED BY cergy2026
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


-- SÉQUENCES

CREATE SEQUENCE seq_sites START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_entites START WITH 1 INCREMENT BY 1;
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
CREATE SEQUENCE seq_profils_utilisateurs START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_groupes START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_equip_reseau START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_types_equip_reseau START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_ports_reseau START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_historique START WITH 1 INCREMENT BY 1;



-- Tables partagées entre Cergy et Pau

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

-- Entités (structure hiérarchique : CY Tech > Cergy / Pau > Eleve...)
CREATE TABLE entites (
  id               NUMBER PRIMARY KEY,
  nom              VARCHAR2(255) NOT NULL,
  entite_parent_id NUMBER REFERENCES entites(id),
  site_id          NUMBER NOT NULL REFERENCES sites(id),
  niveau           NUMBER DEFAULT 0,
  nom_complet      VARCHAR2(500),
  est_recursif     NUMBER(1) DEFAULT 0 CHECK (est_recursif IN (0,1)),
  date_creation     DATE DEFAULT SYSDATE,
  date_modification DATE DEFAULT SYSDATE
) TABLESPACE TS_USERS;

-- Localisations physiques (Salle 201, Personelle)
CREATE TABLE localisations (
  id                     NUMBER PRIMARY KEY,
  nom                    VARCHAR2(255) NOT NULL,
  nom_complet            VARCHAR2(500),
  entite_id              NUMBER NOT NULL REFERENCES entites(id),
  localisation_parent_id NUMBER REFERENCES localisations(id),
  batiment               VARCHAR2(50),
  salle                  VARCHAR2(20),
  etage                  VARCHAR2(20),
  date_creation     DATE DEFAULT SYSDATE,
  date_modification DATE DEFAULT SYSDATE
) TABLESPACE TS_USERS;

-- Fabricants
CREATE TABLE fabricants (
  id          NUMBER PRIMARY KEY,
  nom         VARCHAR2(255) NOT NULL UNIQUE
) TABLESPACE TS_USERS;

-- États du matériel
CREATE TABLE etats (
  id          NUMBER PRIMARY KEY,
  nom         VARCHAR2(255) NOT NULL UNIQUE,
  etat VARCHAR2(50) 
) TABLESPACE TS_USERS;

-- Types d'ordinateurs (Desktop, Laptop, Serveur...)
CREATE TABLE types_ordinateur (
  id  NUMBER PRIMARY KEY,
  machine_type VARCHAR2(255) NOT NULL 
) TABLESPACE TS_USERS;

-- Modèles d'ordinateurs
CREATE TABLE modeles_ordinateur (
  id           NUMBER PRIMARY KEY,
  nom          VARCHAR2(255) NOT NULL,
  ref_produit  VARCHAR2(255),
  fabricant_id NUMBER REFERENCES fabricants(id) -- clé etrangère
) TABLESPACE TS_USERS;


-- TABLES UTILISATEURS (TS_USERS)

-- Profils de droits
CREATE TABLE profils (
  id        NUMBER PRIMARY KEY,
  nom       VARCHAR2(255) NOT NULL UNIQUE,
  interface VARCHAR2(50) DEFAULT 'central' CHECK (interface IN ('central','helpdesk')),
  date_creation     DATE DEFAULT SYSDATE,
  date_modification DATE DEFAULT SYSDATE
) TABLESPACE TS_USERS;

-- Utilisateurs
CREATE TABLE utilisateurs (
  id              NUMBER PRIMARY KEY,
  login           VARCHAR2(255) NOT NULL UNIQUE,
  mot_de_passe    VARCHAR2(255) NOT NULL,
  nom             VARCHAR2(255),
  prenom          VARCHAR2(255),
  email           VARCHAR2(255),
  telephone       VARCHAR2(50),
  mobile          VARCHAR2(50),
  entite_id       NUMBER REFERENCES entites(id),
  localisation_id NUMBER REFERENCES localisations(id),
  profil_id       NUMBER REFERENCES profils(id),
  site_id         NUMBER REFERENCES sites(id),
  langue          VARCHAR2(10) DEFAULT 'fr_FR',
  est_actif       NUMBER(1) DEFAULT 1 CHECK (est_actif IN (0,1)),
  est_supprime    NUMBER(1) DEFAULT 0 CHECK (est_supprime IN (0,1)),
  type_auth       NUMBER DEFAULT 1,
  date_debut      DATE,
  date_fin        DATE,
  date_creation     DATE DEFAULT SYSDATE,
  date_modification DATE DEFAULT SYSDATE
) TABLESPACE TS_USERS;

-- Association profils <-> utilisateurs <-> entités
CREATE TABLE profils_utilisateurs (
  id             NUMBER PRIMARY KEY,
  utilisateur_id NUMBER NOT NULL REFERENCES utilisateurs(id),
  profil_id      NUMBER NOT NULL REFERENCES profils(id),
  entite_id      NUMBER NOT NULL REFERENCES entites(id),
  est_recursif   NUMBER(1) DEFAULT 0 CHECK (est_recursif IN (0,1)),
  est_dynamique  NUMBER(1) DEFAULT 0 CHECK (est_dynamique IN (0,1)),
  CONSTRAINT uk_profil_user_entite UNIQUE (utilisateur_id, profil_id, entite_id)
) TABLESPACE TS_USERS;

-- Groupes
CREATE TABLE groupes (
  id               NUMBER PRIMARY KEY,
  nom              VARCHAR2(255) NOT NULL,
  entite_id        NUMBER NOT NULL REFERENCES entites(id),
  groupe_parent_id NUMBER REFERENCES groupes(id),
  est_recursif     NUMBER(1) DEFAULT 0 CHECK (est_recursif IN (0,1)),
  commentaire      VARCHAR2(255),
  date_creation     DATE DEFAULT SYSDATE,
  date_modification DATE DEFAULT SYSDATE
) TABLESPACE TS_USERS;



-- TABLES MATÉRIEL (TS_MATERIEL_CERGY)

-- Ordinateurs
CREATE TABLE ordinateurs (
  id                  NUMBER PRIMARY KEY,
  nom                 VARCHAR2(255) NOT NULL,
  numero_serie        VARCHAR2(255),
  numero_inventaire   VARCHAR2(255),
  entite_id           NUMBER NOT NULL REFERENCES entites(id),
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

-- Périphériques (imprimantes, souris, claviers, vidéoprojecteurs, webcams...)
CREATE TABLE peripheriques (
  id                NUMBER PRIMARY KEY,
  nom               VARCHAR2(255) NOT NULL,
  numero_serie      VARCHAR2(255),
  type_peripherique VARCHAR2(100) NOT NULL
    CHECK (type_peripherique IN ('imprimante','souris','clavier','videoprojecteur','ecran','autre')),
  entite_id         NUMBER NOT NULL REFERENCES entites(id),
  localisation_id   NUMBER REFERENCES localisations(id),
  fabricant_id      NUMBER REFERENCES fabricants(id),
  etat_id           NUMBER REFERENCES etats(id),
  utilisateur_id    NUMBER REFERENCES utilisateurs(id),
  site_id           NUMBER NOT NULL REFERENCES sites(id),
  commentaire       VARCHAR2(255),
  est_supprime      NUMBER(1) DEFAULT 0 CHECK (est_supprime IN (0,1)),
  date_creation     DATE DEFAULT SYSDATE,
  date_modification DATE DEFAULT SYSDATE
) TABLESPACE TS_MATERIEL_CERGY;

-- Téléphones (secrétariat, accueil)
CREATE TABLE telephones (
  id              NUMBER PRIMARY KEY,
  nom             VARCHAR2(255) NOT NULL,
  numero_serie    VARCHAR2(255),
  numero_tel      VARCHAR2(50),
  type_telephone  VARCHAR2(50) DEFAULT 'fixe'
    CHECK (type_telephone IN ('fixe','mobile','ip')),
  entite_id       NUMBER NOT NULL REFERENCES entites(id),
  localisation_id NUMBER REFERENCES localisations(id),
  fabricant_id    NUMBER REFERENCES fabricants(id),
  etat_id         NUMBER REFERENCES etats(id),
  utilisateur_id  NUMBER REFERENCES utilisateurs(id),
  site_id         NUMBER NOT NULL REFERENCES sites(id),
  service         VARCHAR2(100), -- secrétariat, accueil, direction...
  commentaire     VARCHAR2(255),
  est_supprime    NUMBER(1) DEFAULT 0 CHECK (est_supprime IN (0,1)),
  date_creation     DATE DEFAULT SYSDATE,
  date_modification DATE DEFAULT SYSDATE
) TABLESPACE TS_MATERIEL_CERGY;

-- Logiciels
CREATE TABLE logiciels (
  id            NUMBER PRIMARY KEY,
  nom           VARCHAR2(255) NOT NULL,
  editeur       VARCHAR2(255),
  fabricant_id  NUMBER REFERENCES fabricants(id),
  entite_id     NUMBER REFERENCES entites(id),
  est_supprime  NUMBER(1) DEFAULT 0,
  date_creation     DATE DEFAULT SYSDATE,
  date_modification DATE DEFAULT SYSDATE
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



-- TABLES RÉSEAU (TS_NETWORK_CERGY)


-- Types d'équipements réseau
CREATE TABLE types_equip_reseau (
  id  NUMBER PRIMARY KEY,
  nom VARCHAR2(255) NOT NULL UNIQUE  -- switch, routeur, AP WiFi, firewall
) TABLESPACE TS_NETWORK_CERGY;

-- Équipements réseau
CREATE TABLE equipements_reseau (
  id              NUMBER PRIMARY KEY,
  nom             VARCHAR2(255) NOT NULL,
  numero_serie    VARCHAR2(255),
  entite_id       NUMBER NOT NULL REFERENCES entites(id),
  localisation_id NUMBER REFERENCES localisations(id),
  type_equip_id   NUMBER REFERENCES types_equip_reseau(id),
  fabricant_id    NUMBER REFERENCES fabricants(id),
  etat_id         NUMBER REFERENCES etats(id),
  site_id         NUMBER NOT NULL REFERENCES sites(id),
  nb_ports        NUMBER,
  commentaire     VARCHAR2(255),
  est_supprime    NUMBER(1) DEFAULT 0,
  date_creation     DATE DEFAULT SYSDATE,
  date_modification DATE DEFAULT SYSDATE
) TABLESPACE TS_NETWORK_CERGY;

-- Ports réseau (ethernet ou wifi sur un équipement)
CREATE TABLE ports_reseau (
  id            NUMBER PRIMARY KEY,
  nom           VARCHAR2(255),
  equipement_id NUMBER NOT NULL REFERENCES equipements_reseau(id),
  adresse_mac   VARCHAR2(50),
  type_port     VARCHAR2(20) DEFAULT 'ethernet'
    CHECK (type_port IN ('ethernet','wifi')),
  vitesse       NUMBER,  -- en Mbps
  est_actif     NUMBER(1) DEFAULT 1 CHECK (est_actif IN (0,1)),
  date_creation     DATE DEFAULT SYSDATE,
  date_modification DATE DEFAULT SYSDATE
) TABLESPACE TS_NETWORK_CERGY;


-- TABLE HISTORIQUE (AUDIT)

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



-- PARTIE 9 : CLUSTER

CREATE CLUSTER cl_materiel_localisation (localisation_id NUMBER)
  SIZE 512 TABLESPACE TS_MATERIEL_CERGY;

CREATE INDEX idx_cluster_materiel_loc ON CLUSTER cl_materiel_localisation;

-- Pour utiliser le cluster, recréer les tables avec la clause CLUSTER :
-- CREATE TABLE ordinateurs_cl (...) CLUSTER cl_materiel_localisation(localisation_id);
-- CREATE TABLE peripheriques_cl (...) CLUSTER cl_materiel_localisation(localisation_id);
-- Puis : INSERT INTO ordinateurs_cl SELECT * FROM ordinateurs;
-- DROP TABLE ordinateurs; ALTER TABLE ordinateurs_cl RENAME TO ordinateurs;


-- INDEX


-- ── Index B-TREE sur les FK et champs de recherche ──

-- Ordinateurs
CREATE INDEX idx_ordi_entite ON ordinateurs(entite_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_localisation ON ordinateurs(localisation_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_utilisateur ON ordinateurs(utilisateur_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_fabricant ON ordinateurs(fabricant_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_etat ON ordinateurs(etat_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_site ON ordinateurs(site_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_nom ON ordinateurs(nom) TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_serie ON ordinateurs(numero_serie) TABLESPACE TS_INDEX;

-- Périphériques
CREATE INDEX idx_periph_entite ON peripheriques(entite_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_periph_site ON peripheriques(site_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_periph_type ON peripheriques(type_peripherique) TABLESPACE TS_INDEX;
CREATE INDEX idx_periph_utilisateur ON peripheriques(utilisateur_id) TABLESPACE TS_INDEX;

-- Téléphones
CREATE INDEX idx_tel_entite ON telephones(entite_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_tel_site ON telephones(site_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_tel_service ON telephones(service) TABLESPACE TS_INDEX;

-- Utilisateurs
CREATE INDEX idx_user_entite ON utilisateurs(entite_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_user_site ON utilisateurs(site_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_user_nom ON utilisateurs(nom) TABLESPACE TS_INDEX;

-- Équipements réseau
CREATE INDEX idx_equip_entite ON equipements_reseau(entite_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_equip_site ON equipements_reseau(site_id) TABLESPACE TS_INDEX;

-- Ports réseau
CREATE INDEX idx_port_equip ON ports_reseau(equipement_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_port_mac ON ports_reseau(adresse_mac) TABLESPACE TS_INDEX;

-- Historique
CREATE INDEX idx_hist_objet ON historique(type_objet, objet_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_hist_date ON historique(date_action) TABLESPACE TS_INDEX;

-- ── Index Bitmap (colonnes à faible cardinalité) ──
CREATE BITMAP INDEX idx_bmp_ordi_supprime ON ordinateurs(est_supprime) TABLESPACE TS_INDEX;
CREATE BITMAP INDEX idx_bmp_ordi_template ON ordinateurs(est_template) TABLESPACE TS_INDEX;
CREATE BITMAP INDEX idx_bmp_user_actif ON utilisateurs(est_actif) TABLESPACE TS_INDEX;
CREATE BITMAP INDEX idx_bmp_user_supprime ON utilisateurs(est_supprime) TABLESPACE TS_INDEX;
CREATE BITMAP INDEX idx_bmp_port_type ON ports_reseau(type_port) TABLESPACE TS_INDEX;

-- ── Index par fonction ──
CREATE INDEX idx_ordi_nom_upper ON ordinateurs(UPPER(nom)) TABLESPACE TS_INDEX;
CREATE INDEX idx_user_login_upper ON utilisateurs(UPPER(login)) TABLESPACE TS_INDEX;



--  VUES

-- Vue : Parc informatique Cergy
CREATE OR REPLACE VIEW vue_parc_cergy AS
SELECT o.id, o.nom, o.numero_serie, o.numero_inventaire,
       f.nom AS fabricant, e.nom AS etat,
       l.nom AS localisation, l.batiment, l.salle,
       u.nom AS utilisateur_nom, u.prenom AS utilisateur_prenom,
       o.date_creation, o.date_modification
FROM ordinateurs o
  LEFT JOIN fabricants f ON o.fabricant_id = f.id
  LEFT JOIN etats e ON o.etat_id = e.id
  LEFT JOIN localisations l ON o.localisation_id = l.id
  LEFT JOIN utilisateurs u ON o.utilisateur_id = u.id
WHERE o.site_id = 1 AND o.est_supprime = 0;

-- Vue : Parc informatique Pau
CREATE OR REPLACE VIEW vue_parc_pau AS
SELECT o.id, o.nom, o.numero_serie, o.numero_inventaire,
       f.nom AS fabricant, e.nom AS etat,
       l.nom AS localisation, l.batiment, l.salle,
       u.nom AS utilisateur_nom, u.prenom AS utilisateur_prenom,
       o.date_creation, o.date_modification
FROM ordinateurs o
  LEFT JOIN fabricants f ON o.fabricant_id = f.id
  LEFT JOIN etats e ON o.etat_id = e.id
  LEFT JOIN localisations l ON o.localisation_id = l.id
  LEFT JOIN utilisateurs u ON o.utilisateur_id = u.id
WHERE o.site_id = 2 AND o.est_supprime = 0;

-- Vue : Tous les périphériques par site avec type
CREATE OR REPLACE VIEW vue_peripheriques_site AS
SELECT p.id, p.nom, p.type_peripherique, p.numero_serie,
       s.nom AS site, l.nom AS localisation,
       f.nom AS fabricant, e.nom AS etat,
       u.nom AS utilisateur_nom, u.prenom AS utilisateur_prenom
FROM peripheriques p
  LEFT JOIN sites s ON p.site_id = s.id
  LEFT JOIN localisations l ON p.localisation_id = l.id
  LEFT JOIN fabricants f ON p.fabricant_id = f.id
  LEFT JOIN etats e ON p.etat_id = e.id
  LEFT JOIN utilisateurs u ON p.utilisateur_id = u.id
WHERE p.est_supprime = 0;

-- Vue : Réseau par site (équipements + ports)
CREATE OR REPLACE VIEW vue_reseau_site AS
SELECT er.id, er.nom AS equipement, ter.nom AS type_equipement,
       s.nom AS site, l.nom AS localisation,
       pr.nom AS port, pr.adresse_mac, pr.type_port, pr.vitesse, pr.est_actif
FROM equipements_reseau er
  LEFT JOIN types_equip_reseau ter ON er.type_equip_id = ter.id
  LEFT JOIN sites s ON er.site_id = s.id
  LEFT JOIN localisations l ON er.localisation_id = l.id
  LEFT JOIN ports_reseau pr ON pr.equipement_id = er.id
WHERE er.est_supprime = 0;

-- Vue : Utilisateurs avec profils et droits
CREATE OR REPLACE VIEW vue_utilisateurs_droits AS
SELECT u.id, u.login, u.nom, u.prenom, u.email,
       s.nom AS site, ent.nom AS entite,
       p.nom AS profil, p.interface,
       u.est_actif, u.date_creation
FROM utilisateurs u
  LEFT JOIN sites s ON u.site_id = s.id
  LEFT JOIN entites ent ON u.entite_id = ent.id
  LEFT JOIN profils_utilisateurs pu ON pu.utilisateur_id = u.id
  LEFT JOIN profils p ON pu.profil_id = p.id
WHERE u.est_supprime = 0;

-- Vue matérialisée : Stats du parc par site
CREATE MATERIALIZED VIEW mv_stats_parc
  REFRESH ON DEMAND
AS
SELECT s.nom AS site, e.nom AS etat, COUNT(*) AS nb_ordinateurs
FROM ordinateurs o
  JOIN sites s ON o.site_id = s.id
  LEFT JOIN etats e ON o.etat_id = e.id
WHERE o.est_supprime = 0
GROUP BY s.nom, e.nom;


--  BDDR (Base de Données Répartie)

-- Database Link : Cergy vers Pau
CREATE DATABASE LINK db_pau
  CONNECT TO TECH_PAU IDENTIFIED BY cergy2026
  USING 'XE_PAU';

-- Database Link : Pau vers Cergy (à exécuter depuis Pau)
-- CREATE DATABASE LINK db_cergy
--   CONNECT TO TECH_CERGY IDENTIFIED BY techcergy2026
--   USING 'XE_CERGY';

-- Synonymes pour transparence d'accès
CREATE PUBLIC SYNONYM ordinateurs_pau FOR ordinateurs@db_pau;
CREATE PUBLIC SYNONYM peripheriques_pau FOR peripheriques@db_pau;
CREATE PUBLIC SYNONYM telephones_pau FOR telephones@db_pau;
CREATE PUBLIC SYNONYM equipements_reseau_pau FOR equipements_reseau@db_pau;

-- Vue de défragmentation : parc global (Cergy + Pau)
CREATE OR REPLACE VIEW vue_parc_global AS
SELECT id, nom, numero_serie, site_id, entite_id, date_creation FROM ordinateurs
UNION ALL
SELECT id, nom, numero_serie, site_id, entite_id, date_creation FROM ordinateurs@db_pau;

-- Vues matérialisées côté Pau (réplication des référentiels depuis Cergy)
-- À exécuter depuis le serveur de Pau :
-- CREATE MATERIALIZED VIEW mv_fabricants REFRESH ON DEMAND
--   AS SELECT * FROM fabricants@db_cergy;
-- CREATE MATERIALIZED VIEW mv_etats REFRESH ON DEMAND
--   AS SELECT * FROM etats@db_cergy;
-- CREATE MATERIALIZED VIEW mv_utilisateurs REFRESH ON DEMAND
--   AS SELECT * FROM utilisateurs@db_cergy;



-- PRIVILÈGES OBJETS

-- Technicien Cergy : droits complets sur matériel et réseau Cergy
GRANT SELECT, INSERT, UPDATE, DELETE ON ordinateurs TO TECH_CERGY;
GRANT SELECT, INSERT, UPDATE, DELETE ON peripheriques TO TECH_CERGY;
GRANT SELECT, INSERT, UPDATE, DELETE ON telephones TO TECH_CERGY;
GRANT SELECT, INSERT, UPDATE, DELETE ON logiciels TO TECH_CERGY;
GRANT SELECT, INSERT, UPDATE, DELETE ON versions_logiciel TO TECH_CERGY;
GRANT SELECT, INSERT, UPDATE, DELETE ON installations_logiciels TO TECH_CERGY;
GRANT SELECT, INSERT, UPDATE, DELETE ON equipements_reseau TO TECH_CERGY;
GRANT SELECT, INSERT, UPDATE, DELETE ON ports_reseau TO TECH_CERGY;
GRANT SELECT ON utilisateurs TO TECH_CERGY;
GRANT SELECT ON profils TO TECH_CERGY;

-- Technicien Pau : lecture sur Cergy
GRANT SELECT ON ordinateurs TO TECH_PAU;
GRANT SELECT ON utilisateurs TO TECH_PAU;
GRANT SELECT ON fabricants TO TECH_PAU;
GRANT SELECT ON etats TO TECH_PAU;

-- Lecture seule : accès aux vues uniquement
GRANT SELECT ON vue_parc_cergy TO USER_RO;
GRANT SELECT ON vue_parc_pau TO USER_RO;
GRANT SELECT ON vue_peripheriques_site TO USER_RO;
GRANT SELECT ON vue_reseau_site TO USER_RO;
GRANT SELECT ON vue_utilisateurs_droits TO USER_RO;
GRANT SELECT ON mv_stats_parc TO USER_RO;

-- Séquences pour les techniciens
GRANT ALTER ON seq_ordinateurs TO TECH_CERGY;
GRANT ALTER ON seq_peripheriques TO TECH_CERGY;
GRANT ALTER ON seq_telephones TO TECH_CERGY;

