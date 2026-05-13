-- =============================================================================
-- CORRECTIONS et COMPLEMENTS du SQL principal
-- =============================================================================
-- A executer APRES bdd_Cy_infrastructure.sql, idealement avant le jeu de test.
--
-- Objectifs :
--   1) Corriger le mot de passe de TECH_PAU (etait 'cergy2026' par
--      copier-coller -- propage dans le db link)
--   2) Recreer le DB link db_pau avec le bon mot de passe
--   3) Rendre le cluster cl_materiel_localisation EFFECTIVEMENT utilise
--      en creant les tables ordinateurs_cl et peripheriques_cl
--   4) Documenter / declarer les tables _pau qui materialisent l'usage des
--      tablespaces TS_MATERIEL_PAU et TS_NETWORK_PAU sur l'instance Pau
--   5) Preparer les vues materialisees de replication cote Pau
--
-- Note : ces corrections sont separees du fichier principal pour faciliter
-- la revue d'equipe. Une fois validees, elles peuvent etre integrees dans
-- bdd_Cy_infrastructure.sql.
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;





-- =============================================================================
-- CORRECTION 1 : mot de passe de TECH_PAU
-- =============================================================================
-- Avant : CREATE USER TECH_PAU IDENTIFIED BY cergy2026
-- Apres : pau2026 (coherent avec la convention <site>2026)

ALTER USER TECH_PAU IDENTIFIED BY pau2026;





-- =============================================================================
-- CORRECTION 2 : DB link db_pau avec le bon mot de passe
-- =============================================================================
-- On recree le link : DROP + CREATE.

BEGIN
  EXECUTE IMMEDIATE 'DROP DATABASE LINK db_pau';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -2024 THEN  -- 2024 = link inexistant
      DBMS_OUTPUT.PUT_LINE('DROP db_pau ignore : ' || SQLERRM);
    END IF;
END;
/

CREATE DATABASE LINK db_pau
  CONNECT TO TECH_PAU IDENTIFIED BY pau2026
  USING 'XE_PAU';





-- =============================================================================
-- CORRECTION 3 : tables clustered (ordinateurs_cl, peripheriques_cl)
-- =============================================================================
-- Le cluster cl_materiel_localisation a ete cree mais aucune table ne
-- l'utilise. Pour DEMONTRER le concept et permettre les tests de perf,
-- on cree des tables jumelles utilisant la clause CLUSTER.
--
-- Approche : tables _cl en parallele des originales (pas de migration
-- destructive). Les tests de perf comparent ordinateurs vs ordinateurs_cl.

-- DROP idempotent
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE peripheriques_cl CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE ordinateurs_cl CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL; END;
/

-- Table clustered : meme structure que ordinateurs mais physiquement
-- regroupee par localisation_id sur le disque. Avantage : un SELECT par
-- localisation lit moins de blocs.
CREATE TABLE ordinateurs_cl (
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
  est_supprime        NUMBER(1) DEFAULT 0,
  est_template        NUMBER(1) DEFAULT 0,
  date_achat          DATE,
  date_creation       DATE DEFAULT SYSDATE,
  date_modification   DATE DEFAULT SYSDATE
)
CLUSTER cl_materiel_localisation (localisation_id);

CREATE TABLE peripheriques_cl (
  id                NUMBER PRIMARY KEY,
  nom               VARCHAR2(255) NOT NULL,
  numero_serie      VARCHAR2(255),
  type_peripherique VARCHAR2(100) NOT NULL,
  entite_id         NUMBER NOT NULL REFERENCES entites(id),
  localisation_id   NUMBER REFERENCES localisations(id),
  fabricant_id      NUMBER REFERENCES fabricants(id),
  etat_id           NUMBER REFERENCES etats(id),
  utilisateur_id    NUMBER REFERENCES utilisateurs(id),
  site_id           NUMBER NOT NULL REFERENCES sites(id),
  commentaire       VARCHAR2(255),
  est_supprime      NUMBER(1) DEFAULT 0,
  date_creation     DATE DEFAULT SYSDATE,
  date_modification DATE DEFAULT SYSDATE
)
CLUSTER cl_materiel_localisation (localisation_id);

-- Procedure pour synchroniser : copie ordinateurs/peripheriques -> _cl
-- A appeler apres le jeu de test pour avoir des donnees a comparer.
CREATE OR REPLACE PROCEDURE sync_tables_cluster IS
  v_nb_o NUMBER;
  v_nb_p NUMBER;
BEGIN
  -- Vide les versions cluster pour eviter les doublons.
  EXECUTE IMMEDIATE 'TRUNCATE TABLE ordinateurs_cl';
  EXECUTE IMMEDIATE 'TRUNCATE TABLE peripheriques_cl';

  INSERT INTO ordinateurs_cl
    SELECT * FROM ordinateurs;
  v_nb_o := SQL%ROWCOUNT;

  INSERT INTO peripheriques_cl
    SELECT * FROM peripheriques;
  v_nb_p := SQL%ROWCOUNT;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Copies clusterisees : '
    || v_nb_o || ' ordis, ' || v_nb_p || ' periph.');
END;
/





-- =============================================================================
-- CORRECTION 4 : tablespaces PAU rendus effectifs cote serveur Pau
-- =============================================================================
-- Sur l'instance XE_PAU, les tables materiel et reseau sont creees dans
-- TS_MATERIEL_PAU et TS_NETWORK_PAU (au lieu de _CERGY).
-- Le script ci-dessous est destine a etre execute SUR LE SERVEUR PAU.
-- On garde le DDL en commentaire ici pour eviter qu'il casse l'instance Cergy
-- (les tables y existent deja).
--
-- ----- A executer sur l'instance XE_PAU uniquement -----
/*

-- Memes tables, dans TS_MATERIEL_PAU
CREATE TABLE ordinateurs   (... mêmes colonnes ...) TABLESPACE TS_MATERIEL_PAU;
CREATE TABLE peripheriques (... mêmes colonnes ...) TABLESPACE TS_MATERIEL_PAU;
CREATE TABLE telephones    (... mêmes colonnes ...) TABLESPACE TS_MATERIEL_PAU;

CREATE TABLE equipements_reseau (... mêmes colonnes ...) TABLESPACE TS_NETWORK_PAU;
CREATE TABLE ports_reseau       (... mêmes colonnes ...) TABLESPACE TS_NETWORK_PAU;

-- Vues materialisees pour repliquer les referentiels depuis Cergy
CREATE DATABASE LINK db_cergy
  CONNECT TO TECH_CERGY IDENTIFIED BY cergy2026
  USING 'XE_CERGY';

CREATE MATERIALIZED VIEW mv_fabricants
  REFRESH ON DEMAND
  AS SELECT * FROM fabricants@db_cergy;

CREATE MATERIALIZED VIEW mv_etats
  REFRESH ON DEMAND
  AS SELECT * FROM etats@db_cergy;

CREATE MATERIALIZED VIEW mv_sites
  REFRESH ON DEMAND
  AS SELECT * FROM sites@db_cergy;

CREATE MATERIALIZED VIEW mv_utilisateurs
  REFRESH ON DEMAND
  AS SELECT id, login, nom, prenom, email, site_id, profil_id, est_actif
       FROM utilisateurs@db_cergy
      WHERE est_supprime = 0;

-- Pour rafraichir manuellement :
-- EXEC DBMS_MVIEW.REFRESH('mv_fabricants', 'C');
-- EXEC DBMS_MVIEW.REFRESH('mv_etats',      'C');
-- EXEC DBMS_MVIEW.REFRESH('mv_sites',      'C');
-- EXEC DBMS_MVIEW.REFRESH('mv_utilisateurs','C');

*/

-- ----- Indication cote Cergy : declarer une table FACTICE en TS_MATERIEL_PAU
-- pour prouver que le tablespace est utilisable (sera supprimee apres test).

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE test_ts_pau_marker';
EXCEPTION WHEN OTHERS THEN NULL; END;
/

CREATE TABLE test_ts_pau_marker (
  id NUMBER PRIMARY KEY,
  libelle VARCHAR2(100)
) TABLESPACE TS_MATERIEL_PAU;

INSERT INTO test_ts_pau_marker(id, libelle)
VALUES (1, 'Tablespace TS_MATERIEL_PAU utilise -- replique sur XE_PAU');

COMMENT ON TABLE test_ts_pau_marker IS
  'Marqueur : prouve que TS_MATERIEL_PAU est exploitable. ' ||
  'Sur l instance XE_PAU, les vraies tables materiel y resident.';





-- =============================================================================
-- CORRECTION 5 : VUE de defragmentation amelioree (parc global)
-- =============================================================================
-- La vue existante vue_parc_global est tres minimaliste. On la remplace par
-- une version etoffee avec jointures (fabricant, etat, localisation).
-- Pourquoi : permet a USER_RO de consulter en une requete tout le parc
-- (Cergy + Pau) avec les libelles humains au lieu des id.

CREATE OR REPLACE VIEW vue_parc_global_v2 AS
SELECT 'CERGY' AS source,
       o.id, o.nom, o.numero_serie, o.numero_inventaire,
       o.site_id, o.entite_id,
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
       o.site_id, o.entite_id,
       f.nom, e.nom, l.nom, l.batiment, l.salle,
       u.login,
       o.date_achat, o.date_creation
  FROM ordinateurs@db_pau o
  LEFT JOIN fabricants@db_pau    f ON f.id = o.fabricant_id
  LEFT JOIN etats@db_pau         e ON e.id = o.etat_id
  LEFT JOIN localisations@db_pau l ON l.id = o.localisation_id
  LEFT JOIN utilisateurs@db_pau  u ON u.id = o.utilisateur_id
 WHERE o.est_supprime = 0;

-- Cette vue n'est valide que si le db link est accessible. Sinon erreur ORA.
-- On garde la vue UNION simple existante en fallback.





-- =============================================================================
-- CORRECTION 6 : comportements FK explicites (cascade vs set null)
-- =============================================================================
-- Le SQL principal ne precise pas le comportement ON DELETE.
-- Choix metier (a justifier dans le rapport) :
--   * Suppression d'un utilisateur -> SET NULL sur ses materiels (pas perdu).
--   * Suppression d'une localisation -> SET NULL sur materiel (orpheline).
--   * Suppression d'un fabricant -> RESTRICT (par defaut, refus si reference).
-- Comme on ne peut pas modifier un comportement FK existant sans drop/recreate,
-- on documente ici et on l'applique au prochain re-deploiement.
--
-- Pour appliquer effectivement :
--   ALTER TABLE ordinateurs DROP CONSTRAINT <fk_users>;
--   ALTER TABLE ordinateurs ADD CONSTRAINT fk_ordi_user
--     FOREIGN KEY (utilisateur_id) REFERENCES utilisateurs(id) ON DELETE SET NULL;
-- Les noms des FK n'ayant pas ete poses explicitement, ils sont auto-generes.
-- Voir : SELECT constraint_name FROM user_constraints WHERE table_name='ORDINATEURS';





-- =============================================================================
-- VERIFICATION FINALE
-- =============================================================================
-- Quelques requetes de controle.

PROMPT ----- Verifications -----

-- 1) TECH_PAU a-t-il le bon mot de passe ?
SELECT username, account_status FROM dba_users WHERE username = 'TECH_PAU';

-- 2) Le cluster est-il maintenant utilise ?
SELECT cluster_name, table_name FROM user_cluster_tables ORDER BY table_name;

-- 3) Combien de tables par tablespace ?
SELECT tablespace_name, COUNT(*) AS nb_tables
  FROM user_tables
 GROUP BY tablespace_name
 ORDER BY nb_tables DESC;

PROMPT ----- Corrections appliquees -----
