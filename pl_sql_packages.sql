-- =============================================================================
-- PL/SQL PACKAGES, FONCTIONS, PROCEDURES, CURSEURS -- Projet GLPI CY Tech
-- =============================================================================
-- Fichier consolide regroupant toute la logique metier (hors triggers).
--
-- ORDRE D'EXECUTION : a executer APRES pl_sql_triggers.sql et le jeu de test.
--
-- Contenu :
--   Section 1 : Fonctions utilitaires standalone (8 fonctions)
--   Section 2 : Procedures de gestion standalone (5 procedures)
--   Section 3 : Package PKG_PARC_INFO  -- gestion du parc informatique
--   Section 4 : Package PKG_STATS      -- statistiques et rapports
--   Section 5 : Package PKG_RESEAU     -- gestion reseau
--   Section 6 : Package PKG_MAINTENANCE-- audit autonome, maintenance, batch
--   Section 7 : Droits d'execution
--   Section 8 : Exemples d'utilisation (commentes)
--
-- Concepts du cours couverts :
--   - Fonctions et procedures standalone vs en package
--   - Packages avec spec + body
--   - Constantes et exceptions custom dans les packages
--   - PRAGMA EXCEPTION_INIT (exceptions nommees lies a un code -20xxx)
--   - PRAGMA AUTONOMOUS_TRANSACTION (audit independant du rollback)
--   - Curseurs explicites parametres (OPEN/FETCH/CLOSE, FOR..IN)
--   - SYS_REFCURSOR (curseurs retournes par fonctions)
--   - FOR UPDATE OF + WHERE CURRENT OF (verrouillage + maj curseur)
--   - CONNECT BY + LISTAGG (parcours hierarchique)
--   - %ROWTYPE, %TYPE
--   - Exceptions nominees : NO_DATA_FOUND, DUP_VAL_ON_INDEX
--   - RAISE_APPLICATION_ERROR (codes < -20000)
--   - SQL%ROWCOUNT, SQLCODE, SQLERRM
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS';




-- =============================================================================
-- SECTION 1 : FONCTIONS UTILITAIRES (standalone)
-- =============================================================================
-- Pourquoi standalone : ces fonctions sont utilisees dans plusieurs packages,
-- les declarer en dehors evite la dependance entre packages.

-- ----- Compter le nombre d'ordinateurs d'un site ----------------------------
CREATE OR REPLACE FUNCTION f_nb_ordinateurs_site(
  p_site_id IN NUMBER
) RETURN NUMBER
IS
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count
    FROM ordinateurs
   WHERE site_id = p_site_id AND est_supprime = 0;
  RETURN v_count;
END;
/


-- ----- Compter le nombre total de materiels d'un site -----------------------
-- (ordinateurs + peripheriques + telephones)
CREATE OR REPLACE FUNCTION f_nb_materiel_site(
  p_site_id IN NUMBER
) RETURN NUMBER
IS
  v_nb_ordi   NUMBER;
  v_nb_periph NUMBER;
  v_nb_tel    NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_nb_ordi
    FROM ordinateurs WHERE site_id = p_site_id AND est_supprime = 0;
  SELECT COUNT(*) INTO v_nb_periph
    FROM peripheriques WHERE site_id = p_site_id AND est_supprime = 0;
  SELECT COUNT(*) INTO v_nb_tel
    FROM telephones WHERE site_id = p_site_id AND est_supprime = 0;
  RETURN v_nb_ordi + v_nb_periph + v_nb_tel;
END;
/


-- ----- Nom d'un site a partir de son id -------------------------------------
CREATE OR REPLACE FUNCTION f_nom_site(
  p_site_id IN NUMBER
) RETURN VARCHAR2
IS
  v_nom VARCHAR2(100);
BEGIN
  SELECT nom INTO v_nom FROM sites WHERE id = p_site_id;
  RETURN v_nom;
EXCEPTION
  WHEN NO_DATA_FOUND THEN RETURN NULL;
END;
/


-- ----- Taux d'utilisation d'un site -----------------------------------------
-- (nb ordis assignes a un utilisateur / nb ordis total)
CREATE OR REPLACE FUNCTION f_taux_utilisation_site(
  p_site_id IN NUMBER
) RETURN NUMBER
IS
  v_total   NUMBER;
  v_assigne NUMBER;
BEGIN
  SELECT COUNT(*), COUNT(utilisateur_id)
    INTO v_total, v_assigne
    FROM ordinateurs
   WHERE site_id = p_site_id AND est_supprime = 0;
  IF v_total = 0 THEN RETURN 0; END IF;
  RETURN ROUND((v_assigne / v_total) * 100, 2);
END;
/


-- ----- Age moyen du parc d'un site (en annees) ------------------------------
CREATE OR REPLACE FUNCTION f_age_moyen_parc(
  p_site_id IN NUMBER
) RETURN NUMBER
IS
  v_age NUMBER;
BEGIN
  SELECT NVL(ROUND(AVG((SYSDATE - date_achat) / 365.25), 2), 0)
    INTO v_age
    FROM ordinateurs
   WHERE site_id = p_site_id
     AND est_supprime = 0
     AND date_achat IS NOT NULL;
  RETURN v_age;
END;
/


-- ----- Verifier qu'un utilisateur est actif ---------------------------------
CREATE OR REPLACE FUNCTION f_utilisateur_actif(
  p_user_id IN NUMBER
) RETURN BOOLEAN
IS
  v_actif NUMBER;
BEGIN
  SELECT est_actif INTO v_actif
    FROM utilisateurs
   WHERE id = p_user_id AND est_supprime = 0;
  RETURN (v_actif = 1);
EXCEPTION
  WHEN NO_DATA_FOUND THEN RETURN FALSE;
END;
/


-- ----- Nombre de logiciels installes sur un ordinateur ----------------------
CREATE OR REPLACE FUNCTION f_nb_logiciels_ordinateur(
  p_ordi_id IN NUMBER
) RETURN NUMBER
IS
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count
    FROM installations_logiciels
   WHERE ordinateur_id = p_ordi_id;
  RETURN v_count;
END;
/


-- ----- Age d'un materiel en jours depuis l'achat ----------------------------
CREATE OR REPLACE FUNCTION f_age_materiel_jours(
  p_ordi_id IN NUMBER
) RETURN NUMBER
IS
  v_date_achat DATE;
BEGIN
  SELECT date_achat INTO v_date_achat
    FROM ordinateurs WHERE id = p_ordi_id;
  IF v_date_achat IS NULL THEN RETURN NULL; END IF;
  RETURN TRUNC(SYSDATE - v_date_achat);
EXCEPTION
  WHEN NO_DATA_FOUND THEN RETURN NULL;
END;
/


-- ----- Nombre de ports actifs d'un equipement reseau ------------------------
CREATE OR REPLACE FUNCTION f_nb_ports_actifs(
  p_equip_id IN NUMBER
) RETURN NUMBER
IS
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count
    FROM ports_reseau
   WHERE equipement_id = p_equip_id AND est_actif = 1;
  RETURN v_count;
END;
/


-- ----- Recherche d'un utilisateur par email -> id ---------------------------
-- Retourne -1 si introuvable (pas d'exception levee).
CREATE OR REPLACE FUNCTION f_user_id_par_email(
  p_email IN VARCHAR2
) RETURN NUMBER
IS
  v_id NUMBER;
BEGIN
  SELECT id INTO v_id FROM utilisateurs
   WHERE UPPER(email) = UPPER(p_email)
     AND est_supprime = 0
     AND ROWNUM = 1;
  RETURN v_id;
EXCEPTION
  WHEN NO_DATA_FOUND THEN RETURN -1;
END;
/


-- ----- Nom complet hierarchique d'une entite (CONNECT BY + LISTAGG) ---------
-- Reconstruit "Racine > Niveau1 > Niveau2 > ..." en remontant les parents.
CREATE OR REPLACE FUNCTION f_nom_complet_entite(
  p_entite_id IN NUMBER
) RETURN VARCHAR2
IS
  v_chemin VARCHAR2(500);
BEGIN
  -- CONNECT BY parcourt l'arbre de l'entite vers la racine.
  -- LISTAGG concatene les noms separes par " > " dans l'ordre racine -> feuille
  -- (donc ORDER BY LEVEL DESC, car LEVEL=1 est le noeud cible, LEVEL=max=racine).
  SELECT LISTAGG(nom, ' > ') WITHIN GROUP (ORDER BY niveau DESC)
    INTO v_chemin
    FROM (
      SELECT nom, LEVEL AS niveau
        FROM entites
       START WITH id = p_entite_id
       CONNECT BY PRIOR entite_parent_id = id
    );
  RETURN v_chemin;
EXCEPTION
  WHEN NO_DATA_FOUND THEN RETURN NULL;
END;
/




-- =============================================================================
-- SECTION 2 : PROCEDURES DE GESTION (standalone)
-- =============================================================================
-- Pourquoi standalone : operations "tactiques" appelees ponctuellement, pas
-- assez liees a un domaine pour justifier un package dedie.

-- ----- Ajouter un ordinateur avec verifications complete --------------------
CREATE OR REPLACE PROCEDURE p_ajouter_ordinateur(
  p_nom              IN VARCHAR2,
  p_numero_serie     IN VARCHAR2 DEFAULT NULL,
  p_numero_inventaire IN VARCHAR2 DEFAULT NULL,
  p_entite_id        IN NUMBER,
  p_localisation_id  IN NUMBER DEFAULT NULL,
  p_type_ordi_id     IN NUMBER DEFAULT NULL,
  p_modele_id        IN NUMBER DEFAULT NULL,
  p_fabricant_id     IN NUMBER DEFAULT NULL,
  p_etat_id          IN NUMBER DEFAULT NULL,
  p_utilisateur_id   IN NUMBER DEFAULT NULL,
  p_site_id          IN NUMBER,
  p_date_achat       IN DATE DEFAULT NULL,
  p_id_out           OUT NUMBER
) IS
  v_site_entite NUMBER;
  v_count_serie NUMBER;

  -- Exceptions nommees liees aux codes -20xxx
  e_site_invalide    EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_site_invalide, -20101);
  e_serie_doublon    EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_serie_doublon, -20150);
BEGIN
  -- 1) Verifier que l'entite existe et recuperer son site
  BEGIN
    SELECT site_id INTO v_site_entite
      FROM entites WHERE id = p_entite_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20102,
        'L entite ' || p_entite_id || ' n existe pas.');
  END;

  -- 2) Verifier la coherence site/entite
  IF v_site_entite != p_site_id THEN
    RAISE_APPLICATION_ERROR(-20101,
      'Site incoherent : entite sur site ' || v_site_entite
      || ', ordinateur sur site ' || p_site_id);
  END IF;

  -- 3) Verifier l'unicite du numero de serie sur le site
  IF p_numero_serie IS NOT NULL THEN
    SELECT COUNT(*) INTO v_count_serie
      FROM ordinateurs
     WHERE numero_serie = p_numero_serie AND site_id = p_site_id;
    IF v_count_serie > 0 THEN
      RAISE_APPLICATION_ERROR(-20150,
        'Le numero de serie "' || p_numero_serie
        || '" existe deja sur ce site.');
    END IF;
  END IF;

  -- 4) Insertion
  p_id_out := seq_ordinateurs.NEXTVAL;
  INSERT INTO ordinateurs (
    id, nom, numero_serie, numero_inventaire,
    entite_id, localisation_id, type_ordinateur_id,
    modele_id, fabricant_id, etat_id, utilisateur_id,
    site_id, date_achat, date_creation, date_modification
  ) VALUES (
    p_id_out, p_nom, p_numero_serie, p_numero_inventaire,
    p_entite_id, p_localisation_id, p_type_ordi_id,
    p_modele_id, p_fabricant_id, p_etat_id, p_utilisateur_id,
    p_site_id, p_date_achat, SYSDATE, SYSDATE
  );

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Ordinateur "' || p_nom || '" ajoute (id=' || p_id_out || ').');
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Erreur : ' || SQLCODE || ' - ' || SQLERRM);
    RAISE;
END;
/


-- ----- Transferer un ordinateur d'un site a un autre ------------------------
CREATE OR REPLACE PROCEDURE p_transferer_ordinateur(
  p_ordi_id         IN NUMBER,
  p_nouveau_site_id IN NUMBER,
  p_nouvelle_entite IN NUMBER,
  p_nouvelle_loc    IN NUMBER DEFAULT NULL
) IS
  v_ancien_site NUMBER;
  v_nom_ordi    VARCHAR2(255);
  v_site_entite NUMBER;
BEGIN
  -- Verifier l'ordinateur
  BEGIN
    SELECT site_id, nom INTO v_ancien_site, v_nom_ordi
      FROM ordinateurs
     WHERE id = p_ordi_id AND est_supprime = 0;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20201,
        'Ordinateur id=' || p_ordi_id || ' introuvable ou supprime.');
  END;

  -- Verifier coherence nouvelle entite / nouveau site
  SELECT site_id INTO v_site_entite
    FROM entites WHERE id = p_nouvelle_entite;
  IF v_site_entite != p_nouveau_site_id THEN
    RAISE_APPLICATION_ERROR(-20202,
      'L entite ' || p_nouvelle_entite || ' n appartient pas au site '
      || p_nouveau_site_id);
  END IF;

  -- Effectuer le transfert (desaffectation utilisateur)
  UPDATE ordinateurs
     SET site_id         = p_nouveau_site_id,
         entite_id       = p_nouvelle_entite,
         localisation_id = p_nouvelle_loc,
         utilisateur_id  = NULL
   WHERE id = p_ordi_id;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Ordinateur "' || v_nom_ordi || '" transfere du site '
    || v_ancien_site || ' vers le site ' || p_nouveau_site_id || '.');
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Erreur transfert : ' || SQLCODE || ' - ' || SQLERRM);
    RAISE;
END;
/


-- ----- Desactiver un utilisateur et liberer son materiel --------------------
-- Utilise un curseur explicite pour parcourir les ordis affectes.
CREATE OR REPLACE PROCEDURE p_desactiver_utilisateur(
  p_user_id IN NUMBER
) IS
  v_login     VARCHAR2(255);
  v_nb_ordi   NUMBER := 0;
  v_nb_periph NUMBER;
  v_nb_tel    NUMBER;

  -- Curseur explicite pour parcourir tous les ordinateurs de l'utilisateur
  CURSOR cur_ordis IS
    SELECT id, nom FROM ordinateurs
     WHERE utilisateur_id = p_user_id AND est_supprime = 0;
BEGIN
  -- Verifier que l'utilisateur existe
  BEGIN
    SELECT login INTO v_login
      FROM utilisateurs WHERE id = p_user_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20301,
        'Utilisateur id=' || p_user_id || ' introuvable.');
  END;

  -- Liberer les ordinateurs (parcours avec curseur explicite)
  FOR rec IN cur_ordis LOOP
    UPDATE ordinateurs SET utilisateur_id = NULL WHERE id = rec.id;
    v_nb_ordi := v_nb_ordi + 1;
    DBMS_OUTPUT.PUT_LINE('  - Ordinateur libere : ' || rec.nom);
  END LOOP;

  -- Liberer les peripheriques (utilise SQL%ROWCOUNT pour compter)
  UPDATE peripheriques SET utilisateur_id = NULL
   WHERE utilisateur_id = p_user_id AND est_supprime = 0;
  v_nb_periph := SQL%ROWCOUNT;

  -- Liberer les telephones
  UPDATE telephones SET utilisateur_id = NULL
   WHERE utilisateur_id = p_user_id AND est_supprime = 0;
  v_nb_tel := SQL%ROWCOUNT;

  -- Desactiver l'utilisateur
  UPDATE utilisateurs
     SET est_actif = 0, date_fin = SYSDATE
   WHERE id = p_user_id;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Utilisateur "' || v_login || '" desactive. '
    || 'Materiel libere : ' || v_nb_ordi || ' ordis, '
    || v_nb_periph || ' periph, ' || v_nb_tel || ' tel.');
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Erreur desactivation : ' || SQLCODE || ' - ' || SQLERRM);
    RAISE;
END;
/


-- ----- Installer un logiciel sur un ordinateur ------------------------------
-- Demontre la gestion de DUP_VAL_ON_INDEX (exception nommee Oracle).
CREATE OR REPLACE PROCEDURE p_installer_logiciel(
  p_ordi_id    IN NUMBER,
  p_version_id IN NUMBER
) IS
  v_nom_ordi     VARCHAR2(255);
  v_nom_logiciel VARCHAR2(255);
  v_nom_version  VARCHAR2(255);
  v_count        NUMBER;
BEGIN
  -- Verifier l'ordinateur
  BEGIN
    SELECT nom INTO v_nom_ordi
      FROM ordinateurs WHERE id = p_ordi_id AND est_supprime = 0;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20401,
        'Ordinateur id=' || p_ordi_id || ' introuvable ou supprime.');
  END;

  -- Verifier la version
  BEGIN
    SELECT l.nom, vl.nom INTO v_nom_logiciel, v_nom_version
      FROM versions_logiciel vl
      JOIN logiciels l ON vl.logiciel_id = l.id
     WHERE vl.id = p_version_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20402,
        'Version de logiciel id=' || p_version_id || ' introuvable.');
  END;

  -- Verifier si pas deja installe
  SELECT COUNT(*) INTO v_count
    FROM installations_logiciels
   WHERE ordinateur_id = p_ordi_id AND version_logiciel_id = p_version_id;
  IF v_count > 0 THEN
    RAISE_APPLICATION_ERROR(-20403,
      v_nom_logiciel || ' v' || v_nom_version
      || ' est deja installe sur "' || v_nom_ordi || '".');
  END IF;

  -- Installer
  INSERT INTO installations_logiciels (id, ordinateur_id, version_logiciel_id, date_installation)
  VALUES (seq_install_logiciels.NEXTVAL, p_ordi_id, p_version_id, SYSDATE);

  COMMIT;
  DBMS_OUTPUT.PUT_LINE(v_nom_logiciel || ' v' || v_nom_version
    || ' installe sur "' || v_nom_ordi || '".');
EXCEPTION
  WHEN DUP_VAL_ON_INDEX THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Installation deja existante (contrainte unique).');
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Erreur installation : ' || SQLCODE || ' - ' || SQLERRM);
    RAISE;
END;
/


-- ----- Suppression logique d'un materiel (soft delete) ----------------------
-- Demontre l'utilisation de CASE WHEN sur un parametre VARCHAR2.
CREATE OR REPLACE PROCEDURE p_supprimer_materiel(
  p_type_materiel IN VARCHAR2,
  p_materiel_id   IN NUMBER
) IS
  v_nom VARCHAR2(255);
BEGIN
  CASE UPPER(p_type_materiel)
    WHEN 'ORDINATEUR' THEN
      SELECT nom INTO v_nom FROM ordinateurs WHERE id = p_materiel_id;
      UPDATE ordinateurs
         SET est_supprime = 1, utilisateur_id = NULL
       WHERE id = p_materiel_id;
    WHEN 'PERIPHERIQUE' THEN
      SELECT nom INTO v_nom FROM peripheriques WHERE id = p_materiel_id;
      UPDATE peripheriques
         SET est_supprime = 1, utilisateur_id = NULL
       WHERE id = p_materiel_id;
    WHEN 'TELEPHONE' THEN
      SELECT nom INTO v_nom FROM telephones WHERE id = p_materiel_id;
      UPDATE telephones
         SET est_supprime = 1, utilisateur_id = NULL
       WHERE id = p_materiel_id;
    ELSE
      RAISE_APPLICATION_ERROR(-20501,
        'Type de materiel inconnu : "' || p_type_materiel
        || '". Valeurs : ORDINATEUR, PERIPHERIQUE, TELEPHONE.');
  END CASE;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE(p_type_materiel || ' "' || v_nom || '" (id='
    || p_materiel_id || ') supprime logiquement.');
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE(p_type_materiel || ' id=' || p_materiel_id || ' introuvable.');
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Erreur suppression : ' || SQLCODE || ' - ' || SQLERRM);
    RAISE;
END;
/




-- =============================================================================
-- SECTION 3 : PACKAGE PKG_PARC_INFO -- Gestion du parc informatique
-- =============================================================================
-- Regroupe les operations sur les ordinateurs, peripheriques, telephones.
-- Demontre : constantes, exceptions custom, curseurs parametres, SYS_REFCURSOR.

-- ----- Specification (interface publique) ----------------------------------
CREATE OR REPLACE PACKAGE pkg_parc_info AS

  -- Constantes
  c_site_cergy CONSTANT NUMBER := 1;
  c_site_pau   CONSTANT NUMBER := 2;

  -- Exceptions personnalisees
  e_materiel_not_found EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_materiel_not_found, -20600);
  e_site_incoherent    EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_site_incoherent, -20601);

  -- Fonctions
  FUNCTION nb_materiel_par_etat(p_site_id IN NUMBER, p_etat_id IN NUMBER) RETURN NUMBER;
  FUNCTION rechercher_ordinateur(p_terme IN VARCHAR2) RETURN SYS_REFCURSOR;
  FUNCTION materiel_obsolete(p_seuil_jours IN NUMBER DEFAULT 1825) RETURN SYS_REFCURSOR;

  -- Procedures
  PROCEDURE affecter_ordinateur(p_ordi_id IN NUMBER, p_user_id IN NUMBER);
  PROCEDURE liberer_ordinateur(p_ordi_id IN NUMBER);
  PROCEDURE changer_etat_ordinateur(p_ordi_id IN NUMBER, p_etat_id IN NUMBER);
  PROCEDURE rapport_parc_site(p_site_id IN NUMBER);
  PROCEDURE inventaire_complet;

  -- Batch : utilise FOR UPDATE OF + WHERE CURRENT OF
  PROCEDURE marquer_obsoletes(p_annees IN NUMBER DEFAULT 7);

END pkg_parc_info;
/


-- ----- Body (implementation) ------------------------------------------------
CREATE OR REPLACE PACKAGE BODY pkg_parc_info AS

  -- Compter le materiel par etat et par site
  FUNCTION nb_materiel_par_etat(
    p_site_id IN NUMBER,
    p_etat_id IN NUMBER
  ) RETURN NUMBER
  IS
    v_count NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_count
      FROM ordinateurs
     WHERE site_id = p_site_id
       AND etat_id = p_etat_id
       AND est_supprime = 0;
    RETURN v_count;
  END nb_materiel_par_etat;


  -- Rechercher un ordinateur par nom (retourne un curseur ouvert)
  -- Usage : v_cur := pkg_parc_info.rechercher_ordinateur('PC-CERGY%');
  FUNCTION rechercher_ordinateur(
    p_terme IN VARCHAR2
  ) RETURN SYS_REFCURSOR
  IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT o.id, o.nom, o.numero_serie,
             s.nom AS site, l.nom AS localisation,
             e.nom AS etat,
             u.nom || ' ' || u.prenom AS utilisateur
        FROM ordinateurs o
        LEFT JOIN sites s ON o.site_id = s.id
        LEFT JOIN localisations l ON o.localisation_id = l.id
        LEFT JOIN etats e ON o.etat_id = e.id
        LEFT JOIN utilisateurs u ON o.utilisateur_id = u.id
       WHERE UPPER(o.nom) LIKE UPPER(p_terme)
         AND o.est_supprime = 0
       ORDER BY o.nom;
    RETURN v_cur;
  END rechercher_ordinateur;


  -- Lister le materiel obsolete (> N jours depuis l'achat)
  FUNCTION materiel_obsolete(
    p_seuil_jours IN NUMBER DEFAULT 1825  -- 5 ans par defaut
  ) RETURN SYS_REFCURSOR
  IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT o.id, o.nom, o.numero_serie,
             s.nom AS site,
             o.date_achat,
             TRUNC(SYSDATE - o.date_achat) AS age_jours
        FROM ordinateurs o
        JOIN sites s ON o.site_id = s.id
       WHERE o.date_achat IS NOT NULL
         AND TRUNC(SYSDATE - o.date_achat) > p_seuil_jours
         AND o.est_supprime = 0
       ORDER BY o.date_achat ASC;
    RETURN v_cur;
  END materiel_obsolete;


  -- Affecter un ordinateur a un utilisateur
  PROCEDURE affecter_ordinateur(
    p_ordi_id IN NUMBER,
    p_user_id IN NUMBER
  ) IS
    v_site_ordi  NUMBER;
    v_site_user  NUMBER;
    v_nom_ordi   VARCHAR2(255);
    v_login_user VARCHAR2(255);
    v_actif      NUMBER;
  BEGIN
    -- Verifier l'ordinateur
    BEGIN
      SELECT site_id, nom INTO v_site_ordi, v_nom_ordi
        FROM ordinateurs
       WHERE id = p_ordi_id AND est_supprime = 0;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20600,
          'Ordinateur id=' || p_ordi_id || ' introuvable.');
    END;

    -- Verifier l'utilisateur
    BEGIN
      SELECT site_id, login, est_actif
        INTO v_site_user, v_login_user, v_actif
        FROM utilisateurs
       WHERE id = p_user_id AND est_supprime = 0;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20600,
          'Utilisateur id=' || p_user_id || ' introuvable.');
    END;

    IF v_actif = 0 THEN
      RAISE_APPLICATION_ERROR(-20602,
        'L utilisateur "' || v_login_user || '" est inactif.');
    END IF;

    IF v_site_ordi != v_site_user THEN
      RAISE_APPLICATION_ERROR(-20601,
        'Sites incoherents : ordi sur site ' || v_site_ordi
        || ', utilisateur sur site ' || v_site_user);
    END IF;

    UPDATE ordinateurs
       SET utilisateur_id = p_user_id
     WHERE id = p_ordi_id;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Ordinateur "' || v_nom_ordi
      || '" affecte a "' || v_login_user || '".');
  END affecter_ordinateur;


  -- Liberer un ordinateur
  PROCEDURE liberer_ordinateur(
    p_ordi_id IN NUMBER
  ) IS
    v_nom VARCHAR2(255);
  BEGIN
    SELECT nom INTO v_nom
      FROM ordinateurs WHERE id = p_ordi_id AND est_supprime = 0;
    UPDATE ordinateurs SET utilisateur_id = NULL WHERE id = p_ordi_id;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Ordinateur "' || v_nom || '" libere.');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20600,
        'Ordinateur id=' || p_ordi_id || ' introuvable.');
  END liberer_ordinateur;


  -- Changer l'etat d'un ordinateur
  PROCEDURE changer_etat_ordinateur(
    p_ordi_id IN NUMBER,
    p_etat_id IN NUMBER
  ) IS
    v_nom_ordi VARCHAR2(255);
    v_nom_etat VARCHAR2(255);
    v_count    NUMBER;
  BEGIN
    SELECT nom INTO v_nom_ordi
      FROM ordinateurs WHERE id = p_ordi_id AND est_supprime = 0;

    SELECT COUNT(*) INTO v_count FROM etats WHERE id = p_etat_id;
    IF v_count = 0 THEN
      RAISE_APPLICATION_ERROR(-20603, 'Etat id=' || p_etat_id || ' inexistant.');
    END IF;

    SELECT nom INTO v_nom_etat FROM etats WHERE id = p_etat_id;

    UPDATE ordinateurs SET etat_id = p_etat_id WHERE id = p_ordi_id;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Ordinateur "' || v_nom_ordi
      || '" -> etat "' || v_nom_etat || '".');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20600,
        'Ordinateur id=' || p_ordi_id || ' introuvable.');
  END changer_etat_ordinateur;


  -- Rapport detaille du parc d'un site (3 curseurs parametres)
  PROCEDURE rapport_parc_site(
    p_site_id IN NUMBER
  ) IS
    v_nom_site   VARCHAR2(100);
    v_nb_ordi    NUMBER;
    v_nb_periph  NUMBER;
    v_nb_tel     NUMBER;
    v_nb_users   NUMBER;
    v_nb_equip_r NUMBER;
    v_taux_util  NUMBER;

    -- Curseur parametre : repartition par etat
    CURSOR cur_etats(pc_site NUMBER) IS
      SELECT NVL(e.nom, 'Non defini') AS etat, COUNT(*) AS nb
        FROM ordinateurs o
        LEFT JOIN etats e ON o.etat_id = e.id
       WHERE o.site_id = pc_site AND o.est_supprime = 0
       GROUP BY e.nom
       ORDER BY nb DESC;

    -- Curseur parametre : top 5 fabricants
    CURSOR cur_fabricants(pc_site NUMBER) IS
      SELECT f.nom AS fabricant, COUNT(*) AS nb
        FROM ordinateurs o
        JOIN fabricants f ON o.fabricant_id = f.id
       WHERE o.site_id = pc_site AND o.est_supprime = 0
       GROUP BY f.nom
       ORDER BY nb DESC
       FETCH FIRST 5 ROWS ONLY;

    -- Curseur parametre : peripheriques par type
    CURSOR cur_periph_types(pc_site NUMBER) IS
      SELECT type_peripherique, COUNT(*) AS nb
        FROM peripheriques
       WHERE site_id = pc_site AND est_supprime = 0
       GROUP BY type_peripherique
       ORDER BY nb DESC;
  BEGIN
    v_nom_site := f_nom_site(p_site_id);
    IF v_nom_site IS NULL THEN
      RAISE_APPLICATION_ERROR(-20604, 'Site id=' || p_site_id || ' inexistant.');
    END IF;

    -- Compteurs globaux
    SELECT COUNT(*) INTO v_nb_ordi
      FROM ordinateurs WHERE site_id = p_site_id AND est_supprime = 0;
    SELECT COUNT(*) INTO v_nb_periph
      FROM peripheriques WHERE site_id = p_site_id AND est_supprime = 0;
    SELECT COUNT(*) INTO v_nb_tel
      FROM telephones WHERE site_id = p_site_id AND est_supprime = 0;
    SELECT COUNT(*) INTO v_nb_users
      FROM utilisateurs WHERE site_id = p_site_id
       AND est_supprime = 0 AND est_actif = 1;
    SELECT COUNT(*) INTO v_nb_equip_r
      FROM equipements_reseau WHERE site_id = p_site_id AND est_supprime = 0;
    v_taux_util := f_taux_utilisation_site(p_site_id);

    -- Affichage
    DBMS_OUTPUT.PUT_LINE('===========================================');
    DBMS_OUTPUT.PUT_LINE('   RAPPORT DU PARC -- ' || UPPER(v_nom_site));
    DBMS_OUTPUT.PUT_LINE('   Date : ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI'));
    DBMS_OUTPUT.PUT_LINE('===========================================');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('-- Synthese --');
    DBMS_OUTPUT.PUT_LINE('  Ordinateurs      : ' || v_nb_ordi);
    DBMS_OUTPUT.PUT_LINE('  Peripheriques    : ' || v_nb_periph);
    DBMS_OUTPUT.PUT_LINE('  Telephones       : ' || v_nb_tel);
    DBMS_OUTPUT.PUT_LINE('  Equipements res. : ' || v_nb_equip_r);
    DBMS_OUTPUT.PUT_LINE('  Utilisateurs     : ' || v_nb_users);
    DBMS_OUTPUT.PUT_LINE('  Taux utilisation : ' || v_taux_util || ' %');
    DBMS_OUTPUT.PUT_LINE('');

    DBMS_OUTPUT.PUT_LINE('-- Ordinateurs par etat --');
    FOR rec IN cur_etats(p_site_id) LOOP
      DBMS_OUTPUT.PUT_LINE('  ' || RPAD(rec.etat, 20) || ' : ' || rec.nb);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');

    DBMS_OUTPUT.PUT_LINE('-- Top 5 fabricants --');
    FOR rec IN cur_fabricants(p_site_id) LOOP
      DBMS_OUTPUT.PUT_LINE('  ' || RPAD(rec.fabricant, 20) || ' : ' || rec.nb);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');

    DBMS_OUTPUT.PUT_LINE('-- Peripheriques par type --');
    FOR rec IN cur_periph_types(p_site_id) LOOP
      DBMS_OUTPUT.PUT_LINE('  ' || RPAD(rec.type_peripherique, 20) || ' : ' || rec.nb);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('===========================================');
  END rapport_parc_site;


  -- Inventaire complet : appelle rapport_parc_site pour chaque site
  PROCEDURE inventaire_complet IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('+-----------------------------------------+');
    DBMS_OUTPUT.PUT_LINE('|     INVENTAIRE GLOBAL CY TECH            |');
    DBMS_OUTPUT.PUT_LINE('+-----------------------------------------+');
    DBMS_OUTPUT.PUT_LINE('');

    -- Curseur implicite sur les sites
    FOR rec_site IN (SELECT id, nom FROM sites ORDER BY id) LOOP
      rapport_parc_site(rec_site.id);
      DBMS_OUTPUT.PUT_LINE('');
    END LOOP;
  END inventaire_complet;


  -- Marquer comme "Reforme" les ordis > N annees
  -- Demonstration FOR UPDATE OF + WHERE CURRENT OF.
  PROCEDURE marquer_obsoletes(
    p_annees IN NUMBER DEFAULT 7
  ) IS
    -- Curseur explicite parametre avec verrouillage des lignes pendant le traitement
    CURSOR c_vieux(cp_seuil DATE) IS
      SELECT id FROM ordinateurs
       WHERE date_achat < cp_seuil
         AND est_supprime = 0
       FOR UPDATE OF etat_id;  -- verrou pose

    v_etat_reforme NUMBER;
    v_nb           NUMBER := 0;
    v_seuil        DATE := ADD_MONTHS(SYSDATE, -12 * p_annees);
  BEGIN
    -- Recupere l'id de l'etat "Reforme" (cree par le jeu de test)
    SELECT id INTO v_etat_reforme
      FROM etats
     WHERE UPPER(nom) = 'REFORME'
       AND ROWNUM = 1;

    FOR ordi IN c_vieux(v_seuil) LOOP
      UPDATE ordinateurs SET etat_id = v_etat_reforme
       WHERE CURRENT OF c_vieux;  -- maj de la ligne courante du curseur
      v_nb := v_nb + 1;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE(v_nb || ' ordinateurs marques Reforme (seuil > '
      || p_annees || ' ans).');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('Etat "Reforme" inexistant dans la table etats.');
  END marquer_obsoletes;

END pkg_parc_info;
/




-- =============================================================================
-- SECTION 4 : PACKAGE PKG_STATS -- Statistiques et rapports
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_stats AS
  FUNCTION nb_utilisateurs_actifs(p_site_id IN NUMBER DEFAULT NULL) RETURN NUMBER;
  FUNCTION nb_logiciels_installes_site(p_site_id IN NUMBER) RETURN NUMBER;
  FUNCTION logiciel_plus_installe RETURN VARCHAR2;

  PROCEDURE rapport_logiciels_site(p_site_id IN NUMBER);
  PROCEDURE rapport_activite_recente(p_nb_jours IN NUMBER DEFAULT 30);
  PROCEDURE rapport_utilisateurs_sans_materiel(p_site_id IN NUMBER);
END pkg_stats;
/


CREATE OR REPLACE PACKAGE BODY pkg_stats AS

  -- Nb utilisateurs actifs (global ou par site)
  FUNCTION nb_utilisateurs_actifs(
    p_site_id IN NUMBER DEFAULT NULL
  ) RETURN NUMBER
  IS
    v_count NUMBER;
  BEGIN
    IF p_site_id IS NULL THEN
      SELECT COUNT(*) INTO v_count
        FROM utilisateurs WHERE est_actif = 1 AND est_supprime = 0;
    ELSE
      SELECT COUNT(*) INTO v_count
        FROM utilisateurs
       WHERE est_actif = 1 AND est_supprime = 0 AND site_id = p_site_id;
    END IF;
    RETURN v_count;
  END nb_utilisateurs_actifs;


  -- Nb total de logiciels installes sur un site
  FUNCTION nb_logiciels_installes_site(
    p_site_id IN NUMBER
  ) RETURN NUMBER
  IS
    v_count NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_count
      FROM installations_logiciels il
      JOIN ordinateurs o ON il.ordinateur_id = o.id
     WHERE o.site_id = p_site_id AND o.est_supprime = 0;
    RETURN v_count;
  END nb_logiciels_installes_site;


  -- Nom du logiciel le plus installe
  FUNCTION logiciel_plus_installe RETURN VARCHAR2
  IS
    v_nom VARCHAR2(255);
  BEGIN
    SELECT l.nom INTO v_nom
      FROM installations_logiciels il
      JOIN versions_logiciel vl ON il.version_logiciel_id = vl.id
      JOIN logiciels l ON vl.logiciel_id = l.id
     GROUP BY l.nom
     ORDER BY COUNT(*) DESC
     FETCH FIRST 1 ROWS ONLY;
    RETURN v_nom;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN 'Aucune installation';
  END logiciel_plus_installe;


  -- Rapport des logiciels installes par site
  PROCEDURE rapport_logiciels_site(
    p_site_id IN NUMBER
  ) IS
    v_nom_site VARCHAR2(100);

    -- Curseur : logiciels les plus installes
    CURSOR cur_logiciels IS
      SELECT l.nom AS logiciel, COUNT(*) AS nb_installations
        FROM installations_logiciels il
        JOIN versions_logiciel vl ON il.version_logiciel_id = vl.id
        JOIN logiciels l ON vl.logiciel_id = l.id
        JOIN ordinateurs o ON il.ordinateur_id = o.id
       WHERE o.site_id = p_site_id AND o.est_supprime = 0
       GROUP BY l.nom
       ORDER BY nb_installations DESC;
  BEGIN
    v_nom_site := f_nom_site(p_site_id);

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('-- Logiciels installes -- ' || v_nom_site || ' --');
    DBMS_OUTPUT.PUT_LINE('');

    FOR rec IN cur_logiciels LOOP
      DBMS_OUTPUT.PUT_LINE('  ' || RPAD(rec.logiciel, 30) || ' : '
        || rec.nb_installations || ' installation(s)');
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  Total : '
      || nb_logiciels_installes_site(p_site_id) || ' installations');
  END rapport_logiciels_site;


  -- Rapport d'activite recente (historique des N derniers jours)
  PROCEDURE rapport_activite_recente(
    p_nb_jours IN NUMBER DEFAULT 30
  ) IS
    v_nb_insert NUMBER;
    v_nb_update NUMBER;
    v_nb_delete NUMBER;

    -- Curseur : activite par type d'objet
    CURSOR cur_activite IS
      SELECT type_objet,
             SUM(CASE WHEN type_action = 'INSERT' THEN 1 ELSE 0 END) AS inserts,
             SUM(CASE WHEN type_action = 'UPDATE' THEN 1 ELSE 0 END) AS updates,
             SUM(CASE WHEN type_action = 'DELETE' THEN 1 ELSE 0 END) AS deletes,
             COUNT(*) AS total
        FROM historique
       WHERE date_action >= SYSDATE - p_nb_jours
       GROUP BY type_objet
       ORDER BY total DESC;
  BEGIN
    -- Totaux globaux
    SELECT
      SUM(CASE WHEN type_action = 'INSERT' THEN 1 ELSE 0 END),
      SUM(CASE WHEN type_action = 'UPDATE' THEN 1 ELSE 0 END),
      SUM(CASE WHEN type_action = 'DELETE' THEN 1 ELSE 0 END)
    INTO v_nb_insert, v_nb_update, v_nb_delete
    FROM historique
    WHERE date_action >= SYSDATE - p_nb_jours;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('-- Activite des ' || p_nb_jours || ' derniers jours --');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  Insertions : ' || NVL(v_nb_insert, 0));
    DBMS_OUTPUT.PUT_LINE('  Modifications : ' || NVL(v_nb_update, 0));
    DBMS_OUTPUT.PUT_LINE('  Suppressions : ' || NVL(v_nb_delete, 0));
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  Detail par type d objet :');

    FOR rec IN cur_activite LOOP
      DBMS_OUTPUT.PUT_LINE('    ' || RPAD(rec.type_objet, 18)
        || '  I:' || LPAD(rec.inserts, 4)
        || '  U:' || LPAD(rec.updates, 4)
        || '  D:' || LPAD(rec.deletes, 4)
        || '  Total:' || LPAD(rec.total, 5));
    END LOOP;
  END rapport_activite_recente;


  -- Utilisateurs actifs sans aucun materiel affecte (utilise NOT EXISTS)
  PROCEDURE rapport_utilisateurs_sans_materiel(
    p_site_id IN NUMBER
  ) IS
    v_nom_site VARCHAR2(100);
    v_count    NUMBER := 0;

    CURSOR cur_sans_materiel IS
      SELECT u.id, u.login, u.nom, u.prenom, u.email
        FROM utilisateurs u
       WHERE u.site_id = p_site_id
         AND u.est_actif = 1
         AND u.est_supprime = 0
         AND NOT EXISTS (
           SELECT 1 FROM ordinateurs
            WHERE utilisateur_id = u.id AND est_supprime = 0)
         AND NOT EXISTS (
           SELECT 1 FROM peripheriques
            WHERE utilisateur_id = u.id AND est_supprime = 0)
         AND NOT EXISTS (
           SELECT 1 FROM telephones
            WHERE utilisateur_id = u.id AND est_supprime = 0)
       ORDER BY u.nom, u.prenom;
  BEGIN
    v_nom_site := f_nom_site(p_site_id);

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('-- Utilisateurs sans materiel -- ' || v_nom_site || ' --');
    DBMS_OUTPUT.PUT_LINE('');

    FOR rec IN cur_sans_materiel LOOP
      v_count := v_count + 1;
      DBMS_OUTPUT.PUT_LINE('  ' || LPAD(v_count, 3) || '. '
        || rec.nom || ' ' || rec.prenom
        || ' (' || rec.login || ')'
        || CASE WHEN rec.email IS NOT NULL THEN ' -- ' || rec.email ELSE '' END);
    END LOOP;

    IF v_count = 0 THEN
      DBMS_OUTPUT.PUT_LINE('  Tous les utilisateurs ont du materiel.');
    ELSE
      DBMS_OUTPUT.PUT_LINE('');
      DBMS_OUTPUT.PUT_LINE('  Total : ' || v_count || ' utilisateur(s)');
    END IF;
  END rapport_utilisateurs_sans_materiel;

END pkg_stats;
/




-- =============================================================================
-- SECTION 5 : PACKAGE PKG_RESEAU -- Gestion reseau
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_reseau AS
  FUNCTION taux_occupation_ports(p_equip_id IN NUMBER) RETURN NUMBER;

  PROCEDURE ajouter_equipement_reseau(
    p_nom             IN VARCHAR2,
    p_numero_serie    IN VARCHAR2 DEFAULT NULL,
    p_entite_id       IN NUMBER,
    p_localisation_id IN NUMBER DEFAULT NULL,
    p_type_equip_id   IN NUMBER DEFAULT NULL,
    p_fabricant_id    IN NUMBER DEFAULT NULL,
    p_etat_id         IN NUMBER DEFAULT NULL,
    p_site_id         IN NUMBER,
    p_nb_ports        IN NUMBER DEFAULT 0,
    p_id_out          OUT NUMBER
  );
  PROCEDURE creer_ports_equipement(p_equip_id IN NUMBER, p_nb_ports IN NUMBER);
  PROCEDURE activer_port(p_port_id IN NUMBER);
  PROCEDURE desactiver_port(p_port_id IN NUMBER);
  PROCEDURE rapport_reseau_site(p_site_id IN NUMBER);
END pkg_reseau;
/


CREATE OR REPLACE PACKAGE BODY pkg_reseau AS

  FUNCTION taux_occupation_ports(
    p_equip_id IN NUMBER
  ) RETURN NUMBER
  IS
    v_total  NUMBER;
    v_actifs NUMBER;
  BEGIN
    SELECT COUNT(*), SUM(CASE WHEN est_actif = 1 THEN 1 ELSE 0 END)
      INTO v_total, v_actifs
      FROM ports_reseau
     WHERE equipement_id = p_equip_id;
    IF v_total = 0 THEN RETURN 0; END IF;
    RETURN ROUND((v_actifs / v_total) * 100, 2);
  END taux_occupation_ports;


  PROCEDURE ajouter_equipement_reseau(
    p_nom             IN VARCHAR2,
    p_numero_serie    IN VARCHAR2 DEFAULT NULL,
    p_entite_id       IN NUMBER,
    p_localisation_id IN NUMBER DEFAULT NULL,
    p_type_equip_id   IN NUMBER DEFAULT NULL,
    p_fabricant_id    IN NUMBER DEFAULT NULL,
    p_etat_id         IN NUMBER DEFAULT NULL,
    p_site_id         IN NUMBER,
    p_nb_ports        IN NUMBER DEFAULT 0,
    p_id_out          OUT NUMBER
  ) IS
    v_site_entite NUMBER;
  BEGIN
    SELECT site_id INTO v_site_entite FROM entites WHERE id = p_entite_id;
    IF v_site_entite != p_site_id THEN
      RAISE_APPLICATION_ERROR(-20701,
        'Site incoherent pour l equipement reseau.');
    END IF;

    p_id_out := seq_equip_reseau.NEXTVAL;
    INSERT INTO equipements_reseau (
      id, nom, numero_serie, entite_id, localisation_id,
      type_equip_id, fabricant_id, etat_id, site_id, nb_ports,
      date_creation, date_modification
    ) VALUES (
      p_id_out, p_nom, p_numero_serie, p_entite_id, p_localisation_id,
      p_type_equip_id, p_fabricant_id, p_etat_id, p_site_id, p_nb_ports,
      SYSDATE, SYSDATE
    );

    IF p_nb_ports > 0 THEN
      creer_ports_equipement(p_id_out, p_nb_ports);
    END IF;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Equipement reseau "' || p_nom || '" ajoute (id='
      || p_id_out || ') avec ' || p_nb_ports || ' port(s).');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('Erreur ajout equipement : ' || SQLCODE || ' - ' || SQLERRM);
      RAISE;
  END ajouter_equipement_reseau;


  PROCEDURE creer_ports_equipement(
    p_equip_id IN NUMBER,
    p_nb_ports IN NUMBER
  ) IS
  BEGIN
    FOR i IN 1..p_nb_ports LOOP
      INSERT INTO ports_reseau (
        id, nom, equipement_id, type_port, est_actif,
        date_creation, date_modification
      ) VALUES (
        seq_ports_reseau.NEXTVAL,
        'Port-' || LPAD(i, 3, '0'),
        p_equip_id, 'ethernet', 0,
        SYSDATE, SYSDATE
      );
    END LOOP;
  END creer_ports_equipement;


  PROCEDURE activer_port(p_port_id IN NUMBER) IS
  BEGIN
    UPDATE ports_reseau SET est_actif = 1 WHERE id = p_port_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20702, 'Port id=' || p_port_id || ' introuvable.');
    END IF;
    COMMIT;
  END activer_port;


  PROCEDURE desactiver_port(p_port_id IN NUMBER) IS
  BEGIN
    UPDATE ports_reseau SET est_actif = 0 WHERE id = p_port_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20703, 'Port id=' || p_port_id || ' introuvable.');
    END IF;
    COMMIT;
  END desactiver_port;


  PROCEDURE rapport_reseau_site(
    p_site_id IN NUMBER
  ) IS
    v_nom_site VARCHAR2(100);

    -- Curseur : equipements reseau avec occupation des ports (sous-requetes)
    CURSOR cur_equip IS
      SELECT er.id, er.nom, NVL(ter.nom, 'N/A') AS type_equip,
             er.nb_ports,
             NVL(l.nom, 'N/A') AS localisation,
             (SELECT COUNT(*) FROM ports_reseau
               WHERE equipement_id = er.id) AS ports_total,
             (SELECT COUNT(*) FROM ports_reseau
               WHERE equipement_id = er.id AND est_actif = 1) AS ports_actifs
        FROM equipements_reseau er
        LEFT JOIN types_equip_reseau ter ON er.type_equip_id = ter.id
        LEFT JOIN localisations l ON er.localisation_id = l.id
       WHERE er.site_id = p_site_id AND er.est_supprime = 0
       ORDER BY ter.nom, er.nom;

    v_total_equip  NUMBER := 0;
    v_total_ports  NUMBER := 0;
    v_total_actifs NUMBER := 0;
  BEGIN
    v_nom_site := f_nom_site(p_site_id);

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('-- Reseau -- ' || v_nom_site || ' --');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  ' || RPAD('Equipement', 25) || RPAD('Type', 15)
      || RPAD('Localisation', 20) || RPAD('Ports', 12) || 'Occup.');
    DBMS_OUTPUT.PUT_LINE('  ' || RPAD('-', 25, '-') || RPAD('-', 15, '-')
      || RPAD('-', 20, '-') || RPAD('-', 12, '-') || '------');

    FOR rec IN cur_equip LOOP
      v_total_equip  := v_total_equip + 1;
      v_total_ports  := v_total_ports + rec.ports_total;
      v_total_actifs := v_total_actifs + rec.ports_actifs;
      DBMS_OUTPUT.PUT_LINE('  '
        || RPAD(rec.nom, 25)
        || RPAD(rec.type_equip, 15)
        || RPAD(rec.localisation, 20)
        || RPAD(rec.ports_actifs || '/' || rec.ports_total, 12)
        || CASE WHEN rec.ports_total > 0
             THEN TO_CHAR(ROUND(rec.ports_actifs/rec.ports_total*100)) || '%'
             ELSE 'N/A'
           END);
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  Total : ' || v_total_equip || ' equipement(s), '
      || v_total_ports || ' port(s) dont ' || v_total_actifs || ' actif(s)');
    IF v_total_ports > 0 THEN
      DBMS_OUTPUT.PUT_LINE('  Taux d occupation global : '
        || ROUND(v_total_actifs / v_total_ports * 100, 1) || '%');
    END IF;
  END rapport_reseau_site;

END pkg_reseau;
/




-- =============================================================================
-- SECTION 6 : PACKAGE PKG_MAINTENANCE -- Audit autonome, maintenance, batch
-- =============================================================================
-- Demonstration des concepts avances :
--   - PRAGMA AUTONOMOUS_TRANSACTION pour un audit qui survit aux ROLLBACK
--   - Refresh des vues materialisees
--   - Traitements batch sur les hierarchies (CONNECT BY indirect via curseur)

CREATE OR REPLACE PACKAGE pkg_maintenance AS

  -- Audit independant : log une erreur metier meme si la transaction
  -- principale fait ROLLBACK (transaction autonome).
  PROCEDURE audit_erreur(
    p_type_objet IN VARCHAR2,
    p_objet_id   IN NUMBER,
    p_message    IN VARCHAR2
  );

  -- Purge physique de la corbeille : delete des lignes est_supprime=1
  -- vieilles de plus de p_jours_retention jours.
  PROCEDURE purger_corbeille(p_jours_retention IN NUMBER DEFAULT 90);

  -- Refresh de la vue materialisee mv_stats_parc.
  PROCEDURE refresh_mv_stats;

  -- Recalcule nom_complet pour toutes les entites (apres reorganisation).
  -- Curseur explicite trie par niveau croissant pour que le parent soit
  -- toujours traite avant le fils.
  PROCEDURE recalculer_nom_complet_entites;

  -- Transfert d'un ordinateur entre sites (site_id, entite_id, localisation).
  -- Demonstration du %ROWTYPE.
  PROCEDURE transferer_materiel(
    p_ordi_id           IN NUMBER,
    p_nouveau_site_id   IN NUMBER,
    p_nouvelle_loc_id   IN NUMBER,
    p_motif             IN VARCHAR2 DEFAULT NULL
  );

  -- Archivage logique d'un utilisateur : est_supprime=1 + desaffectation.
  PROCEDURE archiver_utilisateur(p_user_id IN NUMBER);

END pkg_maintenance;
/


CREATE OR REPLACE PACKAGE BODY pkg_maintenance AS

  -- ===================== AUDIT INDEPENDANT =====================
  PROCEDURE audit_erreur(
    p_type_objet IN VARCHAR2,
    p_objet_id   IN NUMBER,
    p_message    IN VARCHAR2
  ) IS
    -- PRAGMA : cette procedure roule dans sa propre transaction. Son COMMIT
    -- est isole, donc la trace survit meme si l'appelant fait ROLLBACK.
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO historique(
      id, type_objet, objet_id, utilisateur_id,
      champ_modifie, ancienne_valeur, nouvelle_valeur,
      type_action, date_action
    ) VALUES (
      seq_historique.NEXTVAL, p_type_objet, p_objet_id, NULL,
      'ERREUR', NULL, SUBSTR(p_message, 1, 4000),
      'UPDATE', SYSDATE
    );
    COMMIT;  -- obligatoire avant la fin d'une autonomous transaction
  END audit_erreur;


  -- ===================== PURGE CORBEILLE =====================
  PROCEDURE purger_corbeille(
    p_jours_retention IN NUMBER DEFAULT 90
  ) IS
    v_nb_ordi   NUMBER;
    v_nb_periph NUMBER;
    v_nb_tel    NUMBER;
    v_nb_user   NUMBER;
    v_seuil     DATE := SYSDATE - p_jours_retention;
  BEGIN
    DELETE FROM ordinateurs
     WHERE est_supprime = 1 AND date_modification < v_seuil;
    v_nb_ordi := SQL%ROWCOUNT;

    DELETE FROM peripheriques
     WHERE est_supprime = 1 AND date_modification < v_seuil;
    v_nb_periph := SQL%ROWCOUNT;

    DELETE FROM telephones
     WHERE est_supprime = 1 AND date_modification < v_seuil;
    v_nb_tel := SQL%ROWCOUNT;

    DELETE FROM utilisateurs
     WHERE est_supprime = 1 AND date_modification < v_seuil;
    v_nb_user := SQL%ROWCOUNT;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Purge corbeille (' || p_jours_retention || ' jours) : '
      || v_nb_ordi || ' ordis, ' || v_nb_periph || ' periph, '
      || v_nb_tel || ' tel, ' || v_nb_user || ' users.');
  END purger_corbeille;


  -- ===================== REFRESH VUE MATERIALISEE =====================
  PROCEDURE refresh_mv_stats IS
  BEGIN
    -- C = COMPLETE (recalcul total). F serait FAST (incremental).
    DBMS_MVIEW.REFRESH('mv_stats_parc', 'C');
    DBMS_OUTPUT.PUT_LINE('mv_stats_parc rafraichie.');
  END refresh_mv_stats;


  -- ===================== RECALCUL NOMS COMPLETS =====================
  PROCEDURE recalculer_nom_complet_entites IS
    -- Curseur trie par niveau croissant : on traite parents AVANT enfants.
    CURSOR c_entites IS
      SELECT id, nom, entite_parent_id, niveau
        FROM entites
       ORDER BY niveau ASC, id ASC;
    v_nb     NUMBER := 0;
    v_chemin VARCHAR2(500);
  BEGIN
    FOR e IN c_entites LOOP
      IF e.entite_parent_id IS NULL THEN
        v_chemin := e.nom;
      ELSE
        SELECT nom_complet INTO v_chemin
          FROM entites WHERE id = e.entite_parent_id;
        v_chemin := v_chemin || ' > ' || e.nom;
      END IF;
      UPDATE entites SET nom_complet = v_chemin WHERE id = e.id;
      v_nb := v_nb + 1;
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('nom_complet recalcule pour ' || v_nb || ' entites.');
  END recalculer_nom_complet_entites;


  -- ===================== TRANSFERT MATERIEL =====================
  PROCEDURE transferer_materiel(
    p_ordi_id         IN NUMBER,
    p_nouveau_site_id IN NUMBER,
    p_nouvelle_loc_id IN NUMBER,
    p_motif           IN VARCHAR2 DEFAULT NULL
  ) IS
    -- %ROWTYPE : on charge toute la ligne pour avoir l'ancien etat
    v_ordi     ordinateurs%ROWTYPE;
    v_site_loc NUMBER;
  BEGIN
    -- 1) Verifie que l'ordinateur existe
    SELECT * INTO v_ordi FROM ordinateurs WHERE id = p_ordi_id;

    -- 2) Verifie que la nouvelle localisation est dans le nouveau site
    SELECT e.site_id INTO v_site_loc
      FROM localisations l
      JOIN entites e ON e.id = l.entite_id
     WHERE l.id = p_nouvelle_loc_id;

    IF v_site_loc <> p_nouveau_site_id THEN
      RAISE_APPLICATION_ERROR(-20200,
        'La localisation ' || p_nouvelle_loc_id
        || ' n appartient pas au site ' || p_nouveau_site_id || '.');
    END IF;

    -- 3) Affecte a l'entite racine du nouveau site (coherence avec le trigger)
    DECLARE
      v_entite_racine NUMBER;
    BEGIN
      SELECT id INTO v_entite_racine
        FROM entites
       WHERE site_id = p_nouveau_site_id
         AND niveau = 1
         AND ROWNUM = 1;

      UPDATE ordinateurs
         SET site_id         = p_nouveau_site_id,
             localisation_id = p_nouvelle_loc_id,
             entite_id       = v_entite_racine,
             utilisateur_id  = NULL  -- desaffecte (a reaffecter)
       WHERE id = p_ordi_id;
    END;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Ordinateur ' || p_ordi_id
      || ' transfere : site ' || v_ordi.site_id || ' -> ' || p_nouveau_site_id
      || ' (motif: ' || NVL(p_motif, 'non precise') || ').');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      -- Audit independant : meme si l'appelant rollback, on garde la trace.
      audit_erreur('ordinateurs', p_ordi_id,
                   'Transfert echoue : ordinateur ou localisation introuvable.');
      RAISE_APPLICATION_ERROR(-20201,
        'Ordinateur ' || p_ordi_id || ' ou localisation '
        || p_nouvelle_loc_id || ' introuvable.');
  END transferer_materiel;


  -- ===================== ARCHIVAGE UTILISATEUR =====================
  PROCEDURE archiver_utilisateur(
    p_user_id IN NUMBER
  ) IS
    v_count_ordi   NUMBER;
    v_count_periph NUMBER;
    v_count_tel    NUMBER;
  BEGIN
    -- Desaffecte le materiel (SQL%ROWCOUNT pour compter)
    UPDATE ordinateurs   SET utilisateur_id = NULL WHERE utilisateur_id = p_user_id;
    v_count_ordi   := SQL%ROWCOUNT;
    UPDATE peripheriques SET utilisateur_id = NULL WHERE utilisateur_id = p_user_id;
    v_count_periph := SQL%ROWCOUNT;
    UPDATE telephones    SET utilisateur_id = NULL WHERE utilisateur_id = p_user_id;
    v_count_tel    := SQL%ROWCOUNT;

    -- Suppression logique
    UPDATE utilisateurs
       SET est_supprime = 1,
           est_actif    = 0,
           date_fin     = NVL(date_fin, SYSDATE)
     WHERE id = p_user_id;

    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20210,
        'Utilisateur ' || p_user_id || ' introuvable.');
    END IF;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Utilisateur ' || p_user_id || ' archive. Materiel desaffecte : '
      || v_count_ordi || ' ordi, ' || v_count_periph || ' periph, '
      || v_count_tel || ' tel.');
  END archiver_utilisateur;

END pkg_maintenance;
/




-- =============================================================================
-- SECTION 7 : DROITS D'EXECUTION SUR LES PACKAGES
-- =============================================================================

GRANT EXECUTE ON pkg_parc_info   TO TECH_CERGY;
GRANT EXECUTE ON pkg_parc_info   TO TECH_PAU;
GRANT EXECUTE ON pkg_stats       TO TECH_CERGY;
GRANT EXECUTE ON pkg_stats       TO TECH_PAU;
-- USER_RO en lecture seule : peut consulter les stats
GRANT EXECUTE ON pkg_stats       TO USER_RO;
GRANT EXECUTE ON pkg_reseau      TO TECH_CERGY;
GRANT EXECUTE ON pkg_reseau      TO TECH_PAU;
GRANT EXECUTE ON pkg_maintenance TO TECH_CERGY;
GRANT EXECUTE ON pkg_maintenance TO TECH_PAU;
-- USER_RO n'a PAS execute sur pkg_maintenance (qui contient les purges)




-- =============================================================================
-- SECTION 8 : EXEMPLES D'UTILISATION (commentes)
-- =============================================================================
/*
-- ----- Fonctions standalone -----
SELECT f_nb_ordinateurs_site(1) FROM dual;           -- nb ordis Cergy
SELECT f_nb_materiel_site(2) FROM dual;              -- nb materiel total Pau
SELECT f_taux_utilisation_site(1) FROM dual;         -- % utilisation Cergy
SELECT f_age_moyen_parc(1) FROM dual;                -- age moyen parc Cergy
SELECT f_nb_logiciels_ordinateur(42) FROM dual;      -- logiciels sur ordi 42
SELECT f_age_materiel_jours(10) FROM dual;           -- age en jours
SELECT f_nom_complet_entite(4) FROM dual;            -- "Cergy > IT > Reseau"

-- ----- Procedures standalone -----
DECLARE v_id NUMBER;
BEGIN p_ajouter_ordinateur('PC-CERGY-201', 'SN123', 'INV001',
                            3, 5, 1, 1, 1, 1, NULL, 1, SYSDATE, v_id);
END;
/
EXEC p_transferer_ordinateur(42, 2, 8, 15);          -- transferer ordi vers Pau
EXEC p_desactiver_utilisateur(10);                   -- desactiver + liberer
EXEC p_installer_logiciel(42, 3);                    -- installer version 3
EXEC p_supprimer_materiel('ORDINATEUR', 42);         -- soft delete

-- ----- Package PKG_PARC_INFO -----
SELECT pkg_parc_info.nb_materiel_par_etat(1, 2) FROM dual;
EXEC pkg_parc_info.affecter_ordinateur(42, 10);
EXEC pkg_parc_info.liberer_ordinateur(42);
EXEC pkg_parc_info.changer_etat_ordinateur(42, 3);
EXEC pkg_parc_info.rapport_parc_site(1);             -- rapport Cergy
EXEC pkg_parc_info.inventaire_complet;               -- rapport global
EXEC pkg_parc_info.marquer_obsoletes(5);             -- > 5 ans = Reforme

-- ----- Package PKG_STATS -----
SELECT pkg_stats.nb_utilisateurs_actifs FROM dual;
SELECT pkg_stats.nb_utilisateurs_actifs(1) FROM dual;
SELECT pkg_stats.logiciel_plus_installe FROM dual;
EXEC pkg_stats.rapport_logiciels_site(1);
EXEC pkg_stats.rapport_activite_recente(7);          -- 7 derniers jours
EXEC pkg_stats.rapport_utilisateurs_sans_materiel(1);

-- ----- Package PKG_RESEAU -----
DECLARE v_id NUMBER;
BEGIN pkg_reseau.ajouter_equipement_reseau('SW-CERGY-01', 'SN-SW-01',
                                            3, 5, 1, 1, 1, 1, 24, v_id);
END;
/
SELECT pkg_reseau.taux_occupation_ports(1) FROM dual;
EXEC pkg_reseau.activer_port(5);
EXEC pkg_reseau.desactiver_port(5);
EXEC pkg_reseau.rapport_reseau_site(1);

-- ----- Package PKG_MAINTENANCE -----
EXEC pkg_maintenance.audit_erreur('ordinateurs', 42, 'Test audit autonome');
EXEC pkg_maintenance.purger_corbeille(180);          -- purge > 180 jours
EXEC pkg_maintenance.refresh_mv_stats;
EXEC pkg_maintenance.recalculer_nom_complet_entites;
EXEC pkg_maintenance.transferer_materiel(1, 2, 35, 'Demenagement');
EXEC pkg_maintenance.archiver_utilisateur(10);

-- ----- Verifier la trace dans historique -----
SELECT type_objet, objet_id, champ_modifie, ancienne_valeur, nouvelle_valeur,
       type_action, date_action
  FROM historique
 WHERE type_objet = 'ordinateurs' AND objet_id = 1
 ORDER BY date_action DESC;
*/




-- =============================================================================
-- FIN DU FICHIER PACKAGES
-- Recapitulatif :
--   11 fonctions standalone
--    5 procedures standalone (curseurs, exceptions, CASE)
--    4 packages :
--      PKG_PARC_INFO   : 3 fcts + 6 procs (SYS_REFCURSOR, FOR UPDATE OF)
--      PKG_STATS       : 3 fcts + 3 procs (NOT EXISTS, CASE)
--      PKG_RESEAU      : 1 fct  + 5 procs (sous-requetes, boucle FOR)
--      PKG_MAINTENANCE : 0 fct  + 6 procs (PRAGMA AUTONOMOUS_TRANSACTION,
--                        CONNECT BY via curseur, %ROWTYPE)
--   Total : 18 fonctions, 25 procedures, 15+ curseurs
-- =============================================================================
