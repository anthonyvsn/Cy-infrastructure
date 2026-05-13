-- =============================================================================
-- PL/SQL METIER -- Projet GLPI CY Tech multi-sites
-- =============================================================================
-- A executer en tant que ADMIN_CYTECH, APRES bdd_Cy_infrastructure.sql et
-- jeu_de_test.sql (sinon les triggers d'audit polluent l'historique pendant
-- le peuplement).
--
-- Contenu :
--   1) Triggers d'auto-incrementation des PK (depuis les seq_*)
--   2) Triggers de mise a jour automatique de date_modification
--   3) Triggers d'audit -> table historique
--   4) Triggers de validation metier (coherence site_id, format MAC, dates)
--   5) Package pkg_metier : fonctions de statistiques + procedures de
--      maintenance + curseurs explicites pour traitements batch
--
-- Concepts du cours couverts :
--   - Triggers BEFORE/AFTER, ROW-LEVEL, multi-evenement
--   - PRAGMA AUTONOMOUS_TRANSACTION (audit independant)
--   - Curseurs explicites (parametre, OPEN/FETCH/CLOSE) et boucles FOR
--   - Procedures stockees, fonctions PL/SQL, packages
--   - Gestion d'erreurs (RAISE_APPLICATION_ERROR, codes < -20000)
--   - %ROWTYPE, %TYPE, exceptions nominees (NO_DATA_FOUND, DUP_VAL_ON_INDEX)
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS';





-- =============================================================================
-- SECTION 1 : TRIGGERS D'AUTO-INCREMENTATION DES PK
-- =============================================================================
-- Pourquoi : meme si le jeu de test passe explicitement seq.NEXTVAL,
-- une application cliente peut ne pas le faire. Le trigger garantit que
-- toute INSERT sans id recoit automatiquement une cle unique.
-- Test IS NULL : on n'ecrase pas une valeur explicitement fournie.

CREATE OR REPLACE TRIGGER trg_pk_sites
BEFORE INSERT ON sites
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN :NEW.id := seq_sites.NEXTVAL; END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_pk_entites
BEFORE INSERT ON entites
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN :NEW.id := seq_entites.NEXTVAL; END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_pk_localisations
BEFORE INSERT ON localisations
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN :NEW.id := seq_localisations.NEXTVAL; END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_pk_utilisateurs
BEFORE INSERT ON utilisateurs
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN :NEW.id := seq_utilisateurs.NEXTVAL; END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_pk_ordinateurs
BEFORE INSERT ON ordinateurs
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN :NEW.id := seq_ordinateurs.NEXTVAL; END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_pk_peripheriques
BEFORE INSERT ON peripheriques
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN :NEW.id := seq_peripheriques.NEXTVAL; END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_pk_telephones
BEFORE INSERT ON telephones
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN :NEW.id := seq_telephones.NEXTVAL; END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_pk_equip_reseau
BEFORE INSERT ON equipements_reseau
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN :NEW.id := seq_equip_reseau.NEXTVAL; END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_pk_ports_reseau
BEFORE INSERT ON ports_reseau
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN :NEW.id := seq_ports_reseau.NEXTVAL; END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_pk_historique
BEFORE INSERT ON historique
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN :NEW.id := seq_historique.NEXTVAL; END IF;
END;
/





-- =============================================================================
-- SECTION 2 : TRIGGERS DE MAJ AUTOMATIQUE DE date_modification
-- =============================================================================
-- Pourquoi : on veut tracer la derniere modification de chaque ligne sans
-- depender du code client (qui peut oublier de mettre a jour ce champ).
-- BEFORE UPDATE FOR EACH ROW : on modifie :NEW avant que la ligne ne soit
-- ecrite, sans declencher un second UPDATE recursif.

CREATE OR REPLACE TRIGGER trg_majdate_ordinateurs
BEFORE UPDATE ON ordinateurs
FOR EACH ROW
BEGIN
  :NEW.date_modification := SYSDATE;
END;
/

CREATE OR REPLACE TRIGGER trg_majdate_peripheriques
BEFORE UPDATE ON peripheriques
FOR EACH ROW
BEGIN
  :NEW.date_modification := SYSDATE;
END;
/

CREATE OR REPLACE TRIGGER trg_majdate_telephones
BEFORE UPDATE ON telephones
FOR EACH ROW
BEGIN
  :NEW.date_modification := SYSDATE;
END;
/

CREATE OR REPLACE TRIGGER trg_majdate_utilisateurs
BEFORE UPDATE ON utilisateurs
FOR EACH ROW
BEGIN
  :NEW.date_modification := SYSDATE;
END;
/

CREATE OR REPLACE TRIGGER trg_majdate_equip_reseau
BEFORE UPDATE ON equipements_reseau
FOR EACH ROW
BEGIN
  :NEW.date_modification := SYSDATE;
END;
/





-- =============================================================================
-- SECTION 3 : TRIGGERS D'AUDIT VERS LA TABLE historique
-- =============================================================================
-- Stratégie :
--   - 1 trigger AFTER INSERT/UPDATE/DELETE par table sensible
--   - On enregistre :
--       * type_objet  = nom logique de la table
--       * objet_id    = PK de la ligne touchee
--       * champ_modifie, ancienne_valeur, nouvelle_valeur (pour UPDATE)
--       * type_action = INSERT / UPDATE / DELETE
--       * utilisateur_id (NULL ici : pas d'utilisateur applicatif courant)
--   - L'audit s'execute en transaction normale : si la transaction metier
--     echoue, l'audit est ROLLBACK aussi (coherence). Pour un audit qui
--     survit a un rollback, on utilise pkg_metier.audit_erreur ci-dessous
--     (avec PRAGMA AUTONOMOUS_TRANSACTION).

-- Procedure utilitaire reutilisable (factorisation des INSERT historique).
CREATE OR REPLACE PROCEDURE log_change(
  p_type_objet   VARCHAR2,
  p_objet_id     NUMBER,
  p_champ        VARCHAR2,
  p_ancienne     VARCHAR2,
  p_nouvelle     VARCHAR2,
  p_action       VARCHAR2
) IS
BEGIN
  INSERT INTO historique(
    id, type_objet, objet_id, utilisateur_id,
    champ_modifie, ancienne_valeur, nouvelle_valeur,
    type_action, date_action
  ) VALUES (
    seq_historique.NEXTVAL, p_type_objet, p_objet_id, NULL,
    p_champ, p_ancienne, p_nouvelle,
    p_action, SYSDATE
  );
END;
/


-- ----- Audit ORDINATEURS ----------------------------------------------------
-- Compound trigger : un seul objet pour les 3 evenements (INSERT/UPDATE/DELETE).
-- Pourquoi : evite de declarer 3 triggers separes et la fonction utilitaire est
-- partagee. On utilise CASE WHEN INSERTING / UPDATING / DELETING.
CREATE OR REPLACE TRIGGER trg_audit_ordinateurs
AFTER INSERT OR UPDATE OR DELETE ON ordinateurs
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    log_change('ordinateurs', :NEW.id, NULL, NULL, :NEW.nom, 'INSERT');
  ELSIF DELETING THEN
    log_change('ordinateurs', :OLD.id, NULL, :OLD.nom, NULL, 'DELETE');
  ELSIF UPDATING THEN
    -- Une entree par champ modifie : facilite la recherche d'historique fine.
    IF NVL(:OLD.nom,'#') <> NVL(:NEW.nom,'#') THEN
      log_change('ordinateurs', :NEW.id, 'nom', :OLD.nom, :NEW.nom, 'UPDATE');
    END IF;
    IF NVL(:OLD.localisation_id,-1) <> NVL(:NEW.localisation_id,-1) THEN
      log_change('ordinateurs', :NEW.id, 'localisation_id',
                 TO_CHAR(:OLD.localisation_id), TO_CHAR(:NEW.localisation_id), 'UPDATE');
    END IF;
    IF NVL(:OLD.utilisateur_id,-1) <> NVL(:NEW.utilisateur_id,-1) THEN
      log_change('ordinateurs', :NEW.id, 'utilisateur_id',
                 TO_CHAR(:OLD.utilisateur_id), TO_CHAR(:NEW.utilisateur_id), 'UPDATE');
    END IF;
    IF NVL(:OLD.etat_id,-1) <> NVL(:NEW.etat_id,-1) THEN
      log_change('ordinateurs', :NEW.id, 'etat_id',
                 TO_CHAR(:OLD.etat_id), TO_CHAR(:NEW.etat_id), 'UPDATE');
    END IF;
    IF NVL(:OLD.site_id,-1) <> NVL(:NEW.site_id,-1) THEN
      log_change('ordinateurs', :NEW.id, 'site_id',
                 TO_CHAR(:OLD.site_id), TO_CHAR(:NEW.site_id), 'UPDATE');
    END IF;
    IF NVL(:OLD.est_supprime,-1) <> NVL(:NEW.est_supprime,-1) THEN
      log_change('ordinateurs', :NEW.id, 'est_supprime',
                 TO_CHAR(:OLD.est_supprime), TO_CHAR(:NEW.est_supprime), 'UPDATE');
    END IF;
  END IF;
END;
/


-- ----- Audit UTILISATEURS ---------------------------------------------------
CREATE OR REPLACE TRIGGER trg_audit_utilisateurs
AFTER INSERT OR UPDATE OR DELETE ON utilisateurs
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    log_change('utilisateurs', :NEW.id, NULL, NULL, :NEW.login, 'INSERT');
  ELSIF DELETING THEN
    log_change('utilisateurs', :OLD.id, NULL, :OLD.login, NULL, 'DELETE');
  ELSIF UPDATING THEN
    IF NVL(:OLD.login,'#') <> NVL(:NEW.login,'#') THEN
      log_change('utilisateurs', :NEW.id, 'login', :OLD.login, :NEW.login, 'UPDATE');
    END IF;
    IF NVL(:OLD.email,'#') <> NVL(:NEW.email,'#') THEN
      log_change('utilisateurs', :NEW.id, 'email', :OLD.email, :NEW.email, 'UPDATE');
    END IF;
    IF NVL(:OLD.est_actif,-1) <> NVL(:NEW.est_actif,-1) THEN
      log_change('utilisateurs', :NEW.id, 'est_actif',
                 TO_CHAR(:OLD.est_actif), TO_CHAR(:NEW.est_actif), 'UPDATE');
    END IF;
    IF NVL(:OLD.profil_id,-1) <> NVL(:NEW.profil_id,-1) THEN
      log_change('utilisateurs', :NEW.id, 'profil_id',
                 TO_CHAR(:OLD.profil_id), TO_CHAR(:NEW.profil_id), 'UPDATE');
    END IF;
    IF NVL(:OLD.entite_id,-1) <> NVL(:NEW.entite_id,-1) THEN
      log_change('utilisateurs', :NEW.id, 'entite_id',
                 TO_CHAR(:OLD.entite_id), TO_CHAR(:NEW.entite_id), 'UPDATE');
    END IF;
  END IF;
END;
/


-- ----- Audit EQUIPEMENTS RESEAU ---------------------------------------------
CREATE OR REPLACE TRIGGER trg_audit_equip_reseau
AFTER INSERT OR UPDATE OR DELETE ON equipements_reseau
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    log_change('equipements_reseau', :NEW.id, NULL, NULL, :NEW.nom, 'INSERT');
  ELSIF DELETING THEN
    log_change('equipements_reseau', :OLD.id, NULL, :OLD.nom, NULL, 'DELETE');
  ELSIF UPDATING THEN
    IF NVL(:OLD.nom,'#') <> NVL(:NEW.nom,'#') THEN
      log_change('equipements_reseau', :NEW.id, 'nom', :OLD.nom, :NEW.nom, 'UPDATE');
    END IF;
    IF NVL(:OLD.etat_id,-1) <> NVL(:NEW.etat_id,-1) THEN
      log_change('equipements_reseau', :NEW.id, 'etat_id',
                 TO_CHAR(:OLD.etat_id), TO_CHAR(:NEW.etat_id), 'UPDATE');
    END IF;
    IF NVL(:OLD.localisation_id,-1) <> NVL(:NEW.localisation_id,-1) THEN
      log_change('equipements_reseau', :NEW.id, 'localisation_id',
                 TO_CHAR(:OLD.localisation_id), TO_CHAR(:NEW.localisation_id), 'UPDATE');
    END IF;
  END IF;
END;
/


-- ----- Audit PERIPHERIQUES (compact, juste les changements d'etat et de loc)
CREATE OR REPLACE TRIGGER trg_audit_peripheriques
AFTER INSERT OR UPDATE OR DELETE ON peripheriques
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    log_change('peripheriques', :NEW.id, NULL, NULL, :NEW.nom, 'INSERT');
  ELSIF DELETING THEN
    log_change('peripheriques', :OLD.id, NULL, :OLD.nom, NULL, 'DELETE');
  ELSIF UPDATING THEN
    IF NVL(:OLD.etat_id,-1) <> NVL(:NEW.etat_id,-1) THEN
      log_change('peripheriques', :NEW.id, 'etat_id',
                 TO_CHAR(:OLD.etat_id), TO_CHAR(:NEW.etat_id), 'UPDATE');
    END IF;
    IF NVL(:OLD.localisation_id,-1) <> NVL(:NEW.localisation_id,-1) THEN
      log_change('peripheriques', :NEW.id, 'localisation_id',
                 TO_CHAR(:OLD.localisation_id), TO_CHAR(:NEW.localisation_id), 'UPDATE');
    END IF;
  END IF;
END;
/





-- =============================================================================
-- SECTION 4 : TRIGGERS DE VALIDATION METIER
-- =============================================================================
-- Pourquoi en BEFORE : on doit pouvoir refuser l'insertion / mise a jour
-- avant qu'elle n'atteigne la table. RAISE_APPLICATION_ERROR (-20xxx)
-- propage une exception qui ROLLBACK la ligne en cours.

-- ----- Coherence site_id : un ordinateur dans une entite doit etre du meme
-- site que cette entite. Garde-fou contre les saisies incoherentes.
CREATE OR REPLACE TRIGGER trg_coherence_site_ordi
BEFORE INSERT OR UPDATE ON ordinateurs
FOR EACH ROW
DECLARE
  v_site_entite NUMBER;
BEGIN
  SELECT site_id INTO v_site_entite
    FROM entites WHERE id = :NEW.entite_id;
  IF v_site_entite <> :NEW.site_id THEN
    RAISE_APPLICATION_ERROR(-20101,
      'Incoherence site : ordinateur(site_id=' || :NEW.site_id
      || ') vs entite(site_id=' || v_site_entite || ').');
  END IF;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20102,
      'Entite ' || :NEW.entite_id || ' introuvable.');
END;
/


-- ----- Validation du format MAC sur ports_reseau ----------------------------
-- Une adresse MAC doit etre au format XX:XX:XX:XX:XX:XX (hex).
CREATE OR REPLACE TRIGGER trg_valid_mac
BEFORE INSERT OR UPDATE ON ports_reseau
FOR EACH ROW
BEGIN
  IF :NEW.adresse_mac IS NOT NULL
     AND NOT REGEXP_LIKE(:NEW.adresse_mac,
                         '^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$')
  THEN
    RAISE_APPLICATION_ERROR(-20110,
      'Adresse MAC invalide : "' || :NEW.adresse_mac
      || '" (attendu XX:XX:XX:XX:XX:XX).');
  END IF;
END;
/


-- ----- Coherence des dates utilisateurs : date_fin >= date_debut -----------
CREATE OR REPLACE TRIGGER trg_valid_dates_user
BEFORE INSERT OR UPDATE ON utilisateurs
FOR EACH ROW
BEGIN
  IF :NEW.date_debut IS NOT NULL
     AND :NEW.date_fin  IS NOT NULL
     AND :NEW.date_fin  < :NEW.date_debut
  THEN
    RAISE_APPLICATION_ERROR(-20120,
      'date_fin (' || TO_CHAR(:NEW.date_fin,'YYYY-MM-DD')
      || ') anterieure a date_debut ('
      || TO_CHAR(:NEW.date_debut,'YYYY-MM-DD') || ').');
  END IF;
END;
/


-- ----- Verrou contre l'auto-reference d'entite ------------------------------
-- Une entite ne peut pas etre son propre parent (boucle infinie de hierarchie).
CREATE OR REPLACE TRIGGER trg_valid_entite_parent
BEFORE INSERT OR UPDATE ON entites
FOR EACH ROW
BEGIN
  IF :NEW.entite_parent_id = :NEW.id THEN
    RAISE_APPLICATION_ERROR(-20130,
      'Une entite ne peut pas etre son propre parent.');
  END IF;
END;
/





-- =============================================================================
-- SECTION 5 : PACKAGE pkg_metier
-- =============================================================================
-- Regroupe : fonctions de statistiques, procedures de maintenance, traitements
-- batch via curseurs explicites. Tout le metier "non-trigger" tient dans ce
-- package pour faciliter le grant et l'evolution.

-- ---- Specification --------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_metier AS

  -- ===== FONCTIONS DE STATISTIQUES =====

  -- Nombre de materiels (ordi + periph + tel) par site (non supprimes).
  FUNCTION f_nb_materiel_site(p_site_id NUMBER) RETURN NUMBER;

  -- Age moyen du parc d'ordinateurs en annees pour un site.
  FUNCTION f_age_moyen_parc(p_site_id NUMBER) RETURN NUMBER;

  -- Taux d'occupation d'une localisation = nb ordis affectes / capacite estimee
  -- (capacite = nb ordis distincts historiquement vus, ou min 1 pour eviter /0).
  FUNCTION f_taux_occupation_localisation(p_loc_id NUMBER) RETURN NUMBER;

  -- Nombre d'ordinateurs dans un etat donne (par nom d'etat).
  FUNCTION f_count_ordi_etat(p_etat_nom VARCHAR2) RETURN NUMBER;

  -- Recherche d'un utilisateur par email -> id (-1 si introuvable).
  FUNCTION f_user_id_par_email(p_email VARCHAR2) RETURN NUMBER;

  -- Reconstruit le nom_complet d'une entite par remontee recursive (parents).
  FUNCTION f_nom_complet_entite(p_entite_id NUMBER) RETURN VARCHAR2;


  -- ===== PROCEDURES METIER =====

  -- Transfert d'un ordinateur entre sites : modifie site_id, localisation,
  -- desaffecte l'utilisateur si different de site, et trace dans historique.
  PROCEDURE transferer_materiel(
    p_ordi_id           NUMBER,
    p_nouveau_site_id   NUMBER,
    p_nouvelle_loc_id   NUMBER,
    p_motif             VARCHAR2 DEFAULT NULL
  );

  -- Archivage logique d'un utilisateur : est_supprime=1 + desaffectation
  -- de tout son materiel (utilisateur_id -> NULL).
  PROCEDURE archiver_utilisateur(p_user_id NUMBER);

  -- Purge physique de la corbeille : delete des lignes est_supprime=1
  -- vieilles de plus de p_jours_retention jours.
  PROCEDURE purger_corbeille(p_jours_retention NUMBER DEFAULT 90);

  -- Refresh de la vue materialisee mv_stats_parc.
  PROCEDURE refresh_mv_stats;

  -- Audit independant : log d'une erreur metier meme si la transaction
  -- principale fait ROLLBACK. Utilise PRAGMA AUTONOMOUS_TRANSACTION.
  PROCEDURE audit_erreur(p_type_objet VARCHAR2, p_objet_id NUMBER, p_message VARCHAR2);


  -- ===== TRAITEMENTS BATCH (CURSEURS EXPLICITES) =====

  -- Recalcul de nom_complet pour toutes les entites (utile apres reorganisation).
  PROCEDURE recalculer_nom_complet_entites;

  -- Marque comme "Reforme" tous les ordinateurs de plus de p_annees ans.
  PROCEDURE marquer_obsoletes(p_annees NUMBER DEFAULT 7);

  -- Rapport formate du parc d'un site (utilise un curseur joignant
  -- 4 tables et affichant un tableau aligne via DBMS_OUTPUT).
  PROCEDURE rapport_parc_site(p_site_id NUMBER);

END pkg_metier;
/


-- ---- Body -----------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY pkg_metier AS

  -- ===================== AUDIT INDEPENDANT =====================
  PROCEDURE audit_erreur(p_type_objet VARCHAR2, p_objet_id NUMBER, p_message VARCHAR2) IS
    -- PRAGMA : cette procedure roule dans sa propre transaction. Son COMMIT
    -- est isole, donc la trace survit meme si l'appelant fait ROLLBACK.
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO historique(id, type_objet, objet_id, utilisateur_id,
                           champ_modifie, ancienne_valeur, nouvelle_valeur,
                           type_action, date_action)
    VALUES (seq_historique.NEXTVAL, p_type_objet, p_objet_id, NULL,
            'ERREUR', NULL, SUBSTR(p_message, 1, 4000),
            'UPDATE', SYSDATE);
    COMMIT;  -- obligatoire avant la fin d'une autonomous transaction
  END audit_erreur;


  -- ===================== FONCTIONS STATS =====================

  FUNCTION f_nb_materiel_site(p_site_id NUMBER) RETURN NUMBER IS
    v_total NUMBER;
  BEGIN
    -- Somme des 3 tables materiel pour le site donne (non supprimes).
    SELECT (SELECT COUNT(*) FROM ordinateurs   WHERE site_id = p_site_id AND est_supprime = 0)
         + (SELECT COUNT(*) FROM peripheriques WHERE site_id = p_site_id AND est_supprime = 0)
         + (SELECT COUNT(*) FROM telephones    WHERE site_id = p_site_id AND est_supprime = 0)
      INTO v_total FROM dual;
    RETURN v_total;
  END;


  FUNCTION f_age_moyen_parc(p_site_id NUMBER) RETURN NUMBER IS
    v_age NUMBER;
  BEGIN
    -- AVG sur (SYSDATE - date_achat) en annees. NULL si pas de ligne.
    SELECT NVL(ROUND(AVG((SYSDATE - date_achat) / 365.25), 2), 0)
      INTO v_age
      FROM ordinateurs
     WHERE site_id = p_site_id
       AND est_supprime = 0
       AND date_achat IS NOT NULL;
    RETURN v_age;
  END;


  FUNCTION f_taux_occupation_localisation(p_loc_id NUMBER) RETURN NUMBER IS
    v_actifs NUMBER;
    v_total  NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_total   FROM ordinateurs WHERE localisation_id = p_loc_id;
    SELECT COUNT(*) INTO v_actifs  FROM ordinateurs
       WHERE localisation_id = p_loc_id
         AND est_supprime = 0
         AND utilisateur_id IS NOT NULL;
    IF v_total = 0 THEN RETURN 0; END IF;
    RETURN ROUND(v_actifs / v_total * 100, 2);
  END;


  FUNCTION f_count_ordi_etat(p_etat_nom VARCHAR2) RETURN NUMBER IS
    v_count NUMBER;
  BEGIN
    -- Jointure pour traduire le nom en id, puis count.
    SELECT COUNT(*) INTO v_count
      FROM ordinateurs o
      JOIN etats e ON e.id = o.etat_id
     WHERE UPPER(e.nom) = UPPER(p_etat_nom)
       AND o.est_supprime = 0;
    RETURN v_count;
  END;


  FUNCTION f_user_id_par_email(p_email VARCHAR2) RETURN NUMBER IS
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


  FUNCTION f_nom_complet_entite(p_entite_id NUMBER) RETURN VARCHAR2 IS
    -- Reconstruit le nom complet en remontant les parents via CONNECT BY.
    -- LISTAGG : concatene les noms separes par " > " dans l'ordre racine -> feuille.
    v_chemin VARCHAR2(500);
  BEGIN
    SELECT LISTAGG(nom, ' > ') WITHIN GROUP (ORDER BY niveau ASC)
      INTO v_chemin
      FROM (
        SELECT nom, LEVEL AS niveau
          FROM entites
         WHERE LEVEL > 0
         START WITH id = p_entite_id
         CONNECT BY PRIOR entite_parent_id = id
      );
    -- LISTAGG renvoie dans l'ordre des LEVEL = du noeud cible vers la racine.
    -- On inverse en triant DESC pour avoir racine -> feuille.
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


  -- ===================== PROCEDURES METIER =====================

  PROCEDURE transferer_materiel(
    p_ordi_id           NUMBER,
    p_nouveau_site_id   NUMBER,
    p_nouvelle_loc_id   NUMBER,
    p_motif             VARCHAR2 DEFAULT NULL
  ) IS
    -- %ROWTYPE : on charge toute la ligne pour avoir l'ancien etat.
    v_ordi      ordinateurs%ROWTYPE;
    v_site_loc  NUMBER;
  BEGIN
    -- 1) Verifie que l'ordinateur existe.
    SELECT * INTO v_ordi FROM ordinateurs WHERE id = p_ordi_id;

    -- 2) Verifie que la nouvelle localisation est bien dans le nouveau site.
    SELECT e.site_id INTO v_site_loc
      FROM localisations l
      JOIN entites e ON e.id = l.entite_id
     WHERE l.id = p_nouvelle_loc_id;

    IF v_site_loc <> p_nouveau_site_id THEN
      RAISE_APPLICATION_ERROR(-20200,
        'La localisation ' || p_nouvelle_loc_id
        || ' n appartient pas au site ' || p_nouveau_site_id || '.');
    END IF;

    -- 3) Si on change de site, on doit aussi changer entite_id pour rester
    --    coherent avec le trigger trg_coherence_site_ordi.
    --    On affecte l'entite racine du nouveau site (niveau = 1).
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
             utilisateur_id  = NULL  -- desaffecte (a reaffecter manuellement)
       WHERE id = p_ordi_id;
    END;

    DBMS_OUTPUT.PUT_LINE('Ordinateur ' || p_ordi_id
      || ' transfere : site ' || v_ordi.site_id || ' -> ' || p_nouveau_site_id
      || ' (motif: ' || NVL(p_motif, 'non precise') || ').');

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      -- audit independant : meme si l'appelant rollback, on garde la trace.
      audit_erreur('ordinateurs', p_ordi_id,
                   'Transfert echoue : ordinateur ou localisation introuvable.');
      RAISE_APPLICATION_ERROR(-20201,
        'Ordinateur ' || p_ordi_id || ' ou localisation '
        || p_nouvelle_loc_id || ' introuvable.');
  END transferer_materiel;


  PROCEDURE archiver_utilisateur(p_user_id NUMBER) IS
    v_count_ordi   NUMBER;
    v_count_periph NUMBER;
    v_count_tel    NUMBER;
  BEGIN
    -- Desaffecte le materiel
    UPDATE ordinateurs   SET utilisateur_id = NULL WHERE utilisateur_id = p_user_id;
    v_count_ordi := SQL%ROWCOUNT;
    UPDATE peripheriques SET utilisateur_id = NULL WHERE utilisateur_id = p_user_id;
    v_count_periph := SQL%ROWCOUNT;
    UPDATE telephones    SET utilisateur_id = NULL WHERE utilisateur_id = p_user_id;
    v_count_tel := SQL%ROWCOUNT;

    -- Marque l'utilisateur comme supprime (suppression logique).
    UPDATE utilisateurs
       SET est_supprime = 1,
           est_actif    = 0,
           date_fin     = NVL(date_fin, SYSDATE)
     WHERE id = p_user_id;

    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20210,
        'Utilisateur ' || p_user_id || ' introuvable.');
    END IF;

    DBMS_OUTPUT.PUT_LINE('Utilisateur ' || p_user_id || ' archive. Materiel desaffecte : '
      || v_count_ordi || ' ordi, ' || v_count_periph || ' periph, '
      || v_count_tel || ' tel.');
  END archiver_utilisateur;


  PROCEDURE purger_corbeille(p_jours_retention NUMBER DEFAULT 90) IS
    v_nb_ordi   NUMBER;
    v_nb_periph NUMBER;
    v_nb_tel    NUMBER;
    v_nb_user   NUMBER;
    v_seuil     DATE := SYSDATE - p_jours_retention;
  BEGIN
    -- DELETE physique des lignes logiquement supprimees depuis p_jours_retention.
    -- L'audit DELETE se declenchera automatiquement via les triggers.
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

    DBMS_OUTPUT.PUT_LINE('Purge corbeille (' || p_jours_retention || ' jours) : '
      || v_nb_ordi || ' ordis, ' || v_nb_periph || ' periph, '
      || v_nb_tel || ' tel, ' || v_nb_user || ' users.');
  END purger_corbeille;


  PROCEDURE refresh_mv_stats IS
  BEGIN
    -- Refresh complet de la MV (COMPLETE = recalcul total, FAST = incremental).
    DBMS_MVIEW.REFRESH('mv_stats_parc', 'C');
    DBMS_OUTPUT.PUT_LINE('mv_stats_parc rafraichie.');
  END refresh_mv_stats;


  -- ===================== TRAITEMENTS BATCH =====================

  PROCEDURE recalculer_nom_complet_entites IS
    -- Curseur explicite : on traite les entites par niveau croissant
    -- pour que le parent ait toujours son nom_complet a jour quand on
    -- traite le fils.
    CURSOR c_entites IS
      SELECT id, nom, entite_parent_id, niveau
        FROM entites
       ORDER BY niveau ASC, id ASC;
    v_nb       NUMBER := 0;
    v_chemin   VARCHAR2(500);
  BEGIN
    FOR e IN c_entites LOOP
      IF e.entite_parent_id IS NULL THEN
        v_chemin := e.nom;
      ELSE
        SELECT nom_complet INTO v_chemin FROM entites WHERE id = e.entite_parent_id;
        v_chemin := v_chemin || ' > ' || e.nom;
      END IF;
      UPDATE entites SET nom_complet = v_chemin WHERE id = e.id;
      v_nb := v_nb + 1;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('nom_complet recalcule pour ' || v_nb || ' entites.');
  END recalculer_nom_complet_entites;


  PROCEDURE marquer_obsoletes(p_annees NUMBER DEFAULT 7) IS
    -- Curseur explicite parametre. On affecte l'etat "Reforme".
    CURSOR c_vieux(cp_seuil DATE) IS
      SELECT id FROM ordinateurs
       WHERE date_achat < cp_seuil
         AND est_supprime = 0
       FOR UPDATE OF etat_id;  -- verrouillage des lignes pendant le traitement

    v_etat_reforme NUMBER;
    v_nb           NUMBER := 0;
    v_seuil        DATE := ADD_MONTHS(SYSDATE, -12 * p_annees);
  BEGIN
    -- Recupere l'id de l'etat "Reforme" (cree par le jeu de test).
    SELECT id INTO v_etat_reforme FROM etats WHERE UPPER(nom) = 'REFORME' AND ROWNUM = 1;

    FOR ordi IN c_vieux(v_seuil) LOOP
      UPDATE ordinateurs SET etat_id = v_etat_reforme
       WHERE CURRENT OF c_vieux;  -- maj de la ligne courante du curseur
      v_nb := v_nb + 1;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE(v_nb || ' ordinateurs marques Reforme (seuil > '
      || p_annees || ' ans).');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('Etat "Reforme" inexistant dans la table etats.');
  END marquer_obsoletes;


  PROCEDURE rapport_parc_site(p_site_id NUMBER) IS
    v_nom_site VARCHAR2(100);
    -- Curseur explicite parametre joignant 4 tables.
    CURSOR c_parc(cp_site NUMBER) IS
      SELECT o.id, o.nom, o.numero_serie,
             f.nom AS fabricant, e.nom AS etat,
             l.nom AS salle,
             u.login AS utilisateur,
             o.date_achat
        FROM ordinateurs o
        LEFT JOIN fabricants    f ON f.id = o.fabricant_id
        LEFT JOIN etats         e ON e.id = o.etat_id
        LEFT JOIN localisations l ON l.id = o.localisation_id
        LEFT JOIN utilisateurs  u ON u.id = o.utilisateur_id
       WHERE o.site_id = cp_site
         AND o.est_supprime = 0
       ORDER BY e.nom, o.nom;
    v_nb NUMBER := 0;
  BEGIN
    SELECT nom INTO v_nom_site FROM sites WHERE id = p_site_id;

    DBMS_OUTPUT.PUT_LINE('================ RAPPORT PARC : ' || v_nom_site
      || ' ================');
    DBMS_OUTPUT.PUT_LINE('Nb materiels (ordi+periph+tel) : '
      || f_nb_materiel_site(p_site_id));
    DBMS_OUTPUT.PUT_LINE('Age moyen du parc ordi : '
      || f_age_moyen_parc(p_site_id) || ' ans');
    DBMS_OUTPUT.PUT_LINE('-----------------------------------------');
    DBMS_OUTPUT.PUT_LINE(RPAD('Nom',20) || RPAD('Fabricant',12)
      || RPAD('Etat',16) || RPAD('Salle',12) || 'Utilisateur');
    DBMS_OUTPUT.PUT_LINE('-----------------------------------------');

    FOR rec IN c_parc(p_site_id) LOOP
      DBMS_OUTPUT.PUT_LINE(
        RPAD(NVL(rec.nom,'?'), 20)
       || RPAD(NVL(rec.fabricant,'-'), 12)
       || RPAD(NVL(rec.etat,'-'), 16)
       || RPAD(NVL(rec.salle,'-'), 12)
       || NVL(rec.utilisateur, '-'));
      v_nb := v_nb + 1;
      EXIT WHEN v_nb >= 30;   -- limite l'affichage console (jeu de test = 1500)
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('-----------------------------------------');
    DBMS_OUTPUT.PUT_LINE('(' || v_nb || ' lignes affichees, max 30)');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('Site ' || p_site_id || ' introuvable.');
  END rapport_parc_site;

END pkg_metier;
/





-- =============================================================================
-- SECTION 6 : TESTS RAPIDES
-- =============================================================================
-- A executer apres avoir charge le jeu de test. Decommente selon ton besoin.

-- -- Stats globales
-- SELECT pkg_metier.f_nb_materiel_site(1) AS nb_cergy FROM dual;
-- SELECT pkg_metier.f_age_moyen_parc(1)  AS age_cergy FROM dual;
-- SELECT pkg_metier.f_count_ordi_etat('En service') AS en_service FROM dual;
--
-- -- Rapport formate
-- EXEC pkg_metier.rapport_parc_site(1);
--
-- -- Batch
-- EXEC pkg_metier.recalculer_nom_complet_entites;
-- EXEC pkg_metier.marquer_obsoletes(5);
--
-- -- Maintenance
-- EXEC pkg_metier.refresh_mv_stats;
-- EXEC pkg_metier.purger_corbeille(180);
--
-- -- Transfert + audit
-- EXEC pkg_metier.transferer_materiel(p_ordi_id => 1, p_nouveau_site_id => 2,
--                                     p_nouvelle_loc_id => 35, p_motif => 'Demenagement');
--
-- -- Verifier la trace dans historique
-- SELECT type_objet, objet_id, champ_modifie, ancienne_valeur, nouvelle_valeur,
--        type_action, date_action
--   FROM historique
--  WHERE type_objet = 'ordinateurs' AND objet_id = 1
--  ORDER BY date_action DESC;





-- =============================================================================
-- DROITS D'EXECUTION SUR LE PACKAGE
-- =============================================================================
-- TECH_CERGY peut tout faire sauf purger
GRANT EXECUTE ON pkg_metier TO TECH_CERGY;
GRANT EXECUTE ON pkg_metier TO TECH_PAU;
-- USER_RO : lecture seule sur les fonctions (pas via package directement).