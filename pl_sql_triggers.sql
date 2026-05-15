-- =============================================================================
-- TRIGGERS PL/SQL -- Projet GLPI CY Tech multi-sites
-- =============================================================================
-- Fichier consolide regroupant TOUS les triggers du projet.
--
-- ORDRE D'EXECUTION RECOMMANDE :
--   1) bdd_Cy_infrastructure.sql
--   2) corrections_sql.sql
--   3) Section 1 de CE fichier (triggers d'auto-incrementation des PK)
--      => indispensables AVANT le jeu de test pour que les INSERTs sans
--         id soient acceptes
--   4) jeu_de_test.sql (peuplement)
--   5) Sections 2-6 de CE fichier (audit, validation, INSTEAD OF...)
--      => apres le peuplement pour ne pas polluer historique
--   6) pl_sql_packages.sql
--
-- Astuce : pour appliquer tout le fichier d'un coup malgre l'audit qui pollue
--   le peuplement, faire un TRUNCATE TABLE historique apres le jeu de test.
--
-- Contenu :
--   Section 1 : Triggers d'auto-incrementation des PK (10 triggers)
--   Section 2 : Triggers de mise a jour de date_modification (12 triggers)
--   Section 3 : Triggers d'audit (8 triggers) avec procedure factorisee log_change
--   Section 4 : Triggers de validation site/hierarchy_level (5 triggers)
--   Section 5 : Triggers de validation metier (MAC, dates, suppressions, unicite)
--   Section 6 : Trigger INSTEAD OF sur vue (bonus pedagogique)
--
-- Concepts du cours couverts :
--   - Triggers BEFORE/AFTER, ROW-LEVEL, multi-evenement
--   - INSTEAD OF sur vues
--   - Procedure factorisee log_change pour eviter la duplication
--   - Gestion d'erreurs (RAISE_APPLICATION_ERROR, codes < -20000)
--   - %ROWTYPE, %TYPE, REGEXP_LIKE
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
  IF :NEW.id IS NULL THEN
    :NEW.id := seq_sites.NEXTVAL;
  END IF;
END;


CREATE OR REPLACE TRIGGER trg_pk_hierarchy_level
BEFORE INSERT ON hierarchy_level
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN
    :NEW.id := seq_hierarchy_level.NEXTVAL;
  END IF;
END;


CREATE OR REPLACE TRIGGER trg_pk_localisations
BEFORE INSERT ON localisations
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN
    :NEW.id := seq_localisations.NEXTVAL;
  END IF;
END;


CREATE OR REPLACE TRIGGER trg_pk_utilisateurs
BEFORE INSERT ON utilisateurs
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN
    :NEW.id := seq_utilisateurs.NEXTVAL;
  END IF;
END;


CREATE OR REPLACE TRIGGER trg_pk_ordinateurs
BEFORE INSERT ON ordinateurs
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN
    :NEW.id := seq_ordinateurs.NEXTVAL;
  END IF;
END;


CREATE OR REPLACE TRIGGER trg_pk_peripheriques
BEFORE INSERT ON peripheriques
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN
    :NEW.id := seq_peripheriques.NEXTVAL;
  END IF;
END;


CREATE OR REPLACE TRIGGER trg_pk_telephones
BEFORE INSERT ON telephones
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN
    :NEW.id := seq_telephones.NEXTVAL;
  END IF;
END;


CREATE OR REPLACE TRIGGER trg_pk_equip_reseau
BEFORE INSERT ON equipements_reseau
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN
    :NEW.id := seq_equip_reseau.NEXTVAL;
  END IF;
END;


CREATE OR REPLACE TRIGGER trg_pk_ports_reseau
BEFORE INSERT ON ports_reseau
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN
    :NEW.id := seq_ports_reseau.NEXTVAL;
  END IF;
END;


CREATE OR REPLACE TRIGGER trg_pk_historique
BEFORE INSERT ON historique
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN
    :NEW.id := seq_historique.NEXTVAL;
  END IF;
END;





-- =============================================================================
-- SECTION 2 : TRIGGERS DE MAJ AUTOMATIQUE DE date_modification
-- =============================================================================
-- Pourquoi : on veut tracer la derniere modification de chaque ligne sans
-- dependre du code client (qui peut oublier de mettre a jour ce champ).
-- BEFORE UPDATE FOR EACH ROW : on modifie :NEW avant que la ligne ne soit
-- ecrite, sans declencher un second UPDATE recursif.

-- Triggers propres aux dates (update)
CREATE OR REPLACE TRIGGER trg_majdate_sites
BEFORE UPDATE ON sites
FOR EACH ROW
BEGIN
  :NEW.date_modification := SYSDATE;
END;


CREATE OR REPLACE TRIGGER trg_majdate_hierarchy_level
BEFORE UPDATE ON hierarchy_level
FOR EACH ROW
BEGIN
  :NEW.date_modification := SYSDATE;
END;


CREATE OR REPLACE TRIGGER trg_majdate_localisations
BEFORE UPDATE ON localisations
FOR EACH ROW
BEGIN
  :NEW.date_modification := SYSDATE;
END;


/* trg_majdate_profils est supprimé. */

CREATE OR REPLACE TRIGGER trg_majdate_groupes
BEFORE UPDATE ON groupes
FOR EACH ROW
BEGIN
  :NEW.date_modification := SYSDATE;
END;


CREATE OR REPLACE TRIGGER trg_majdate_utilisateurs
BEFORE UPDATE ON utilisateurs
FOR EACH ROW
BEGIN
  :NEW.date_modification := SYSDATE;
END;


CREATE OR REPLACE TRIGGER trg_majdate_ordinateurs
BEFORE UPDATE ON ordinateurs
FOR EACH ROW
BEGIN
  :NEW.date_modification := SYSDATE;
END;


CREATE OR REPLACE TRIGGER trg_majdate_peripheriques
BEFORE UPDATE ON peripheriques
FOR EACH ROW
BEGIN
  :NEW.date_modification := SYSDATE;
END;


CREATE OR REPLACE TRIGGER trg_majdate_telephones
BEFORE UPDATE ON telephones
FOR EACH ROW
BEGIN
  :NEW.date_modification := SYSDATE;
END;


CREATE OR REPLACE TRIGGER trg_majdate_logiciels
BEFORE UPDATE ON logiciels
FOR EACH ROW
BEGIN
  :NEW.date_modification := SYSDATE;
END;


CREATE OR REPLACE TRIGGER trg_majdate_equip_reseau
BEFORE UPDATE ON equipements_reseau
FOR EACH ROW
BEGIN
  :NEW.date_modification := SYSDATE;
END;


CREATE OR REPLACE TRIGGER trg_majdate_ports_reseau
BEFORE UPDATE ON ports_reseau
FOR EACH ROW
BEGIN
  :NEW.date_modification := SYSDATE;
END;





-- =============================================================================
-- SECTION 3 : TRIGGERS D'AUDIT VERS LA TABLE historique
-- =============================================================================
-- Strategie :
--   - 1 trigger AFTER INSERT/UPDATE/DELETE par table sensible
--   - Procedure utilitaire log_change qui factorise les INSERT INTO historique
--     => evite des centaines de lignes dupliquees
--   - Pattern NVL(...) <> NVL(...) pour comparer en gerant les NULL proprement
--   - Audit en transaction normale : si la transaction metier ROLLBACK,
--     l'audit ROLLBACK aussi. Pour un audit qui survit a un rollback,
--     voir pkg_maintenance.audit_erreur dans pl_sql_packages.sql
--     (qui utilise PRAGMA AUTONOMOUS_TRANSACTION).

-- ----- Procedure utilitaire (factorisation des INSERT historique) -----------
/*
 Ensemble des triggers d'ajout d'informations dans la table historique.
 Ces triggers font tous appel à la procedure log_change.
*/
CREATE OR REPLACE PROCEDURE log_change(
  p_type_objet   VARCHAR2,
  p_objet_id     NUMBER,
  p_champ        VARCHAR2,
  p_ancienne     VARCHAR2,
  p_nouvelle     VARCHAR2,
  p_action       VARCHAR2
) IS
BEGIN
  INSERT INTO historique(id, type_objet, objet_id, utilisateur_id, champ_modifie, ancienne_valeur, nouvelle_valeur, type_action, date_action)
  VALUES (
    seq_historique.NEXTVAL, p_type_objet, p_objet_id, NULL,
    p_champ, p_ancienne, p_nouvelle,
    p_action, SYSDATE
  );
END;



-- ----- Audit ORDINATEURS ----------------------------------------------------
CREATE OR REPLACE TRIGGER trg_audit_ordinateurs
AFTER INSERT OR UPDATE OR DELETE ON ordinateurs
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    log_change('ordinateurs', :NEW.id, NULL, NULL, :NEW.nom, 'INSERT');
  ELSIF DELETING THEN
    log_change('ordinateurs', :OLD.id, NULL, :OLD.nom, NULL, 'DELETE');
  ELSIF UPDATING THEN
    IF NVL(:OLD.nom,'#') <> NVL(:NEW.nom,'#') THEN
      log_change('ordinateurs', :NEW.id, 'nom', :OLD.nom, :NEW.nom, 'UPDATE');
    END IF;
    IF NVL(:OLD.etat_id,-1) <> NVL(:NEW.etat_id,-1) THEN
      log_change('ordinateurs', :NEW.id, 'etat_id',
                 TO_CHAR(:OLD.etat_id), TO_CHAR(:NEW.etat_id), 'UPDATE');
    END IF;
    IF NVL(:OLD.localisation_id,-1) <> NVL(:NEW.localisation_id,-1) THEN
      log_change('ordinateurs', :NEW.id, 'localisation_id',
                 TO_CHAR(:OLD.localisation_id), TO_CHAR(:NEW.localisation_id), 'UPDATE');
    END IF;
    IF NVL(:OLD.utilisateur_id,-1) <> NVL(:NEW.utilisateur_id,-1) THEN
      log_change('ordinateurs', :NEW.id, 'utilisateur_id',
                 TO_CHAR(:OLD.utilisateur_id), TO_CHAR(:NEW.utilisateur_id), 'UPDATE');
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



-- ----- Audit PERIPHERIQUES --------------------------------------------------
CREATE OR REPLACE TRIGGER trg_audit_peripheriques
AFTER INSERT OR UPDATE OR DELETE ON peripheriques
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    log_change('peripheriques', :NEW.id, NULL, NULL, :NEW.nom, 'INSERT');
  ELSIF DELETING THEN
    log_change('peripheriques', :OLD.id, NULL, :OLD.nom, NULL, 'DELETE');
  ELSIF UPDATING THEN
    IF NVL(:OLD.nom,'#') <> NVL(:NEW.nom,'#') THEN
      log_change('peripheriques', :NEW.id, 'nom', :OLD.nom, :NEW.nom, 'UPDATE');
    END IF;
    IF NVL(:OLD.etat_id,-1) <> NVL(:NEW.etat_id,-1) THEN
      log_change('peripheriques', :NEW.id, 'etat_id',
                 TO_CHAR(:OLD.etat_id), TO_CHAR(:NEW.etat_id), 'UPDATE');
    END IF;
    IF NVL(:OLD.localisation_id,-1) <> NVL(:NEW.localisation_id,-1) THEN
      log_change('peripheriques', :NEW.id, 'localisation_id',
                 TO_CHAR(:OLD.localisation_id), TO_CHAR(:NEW.localisation_id), 'UPDATE');
    END IF;
    IF NVL(:OLD.est_supprime,-1) <> NVL(:NEW.est_supprime,-1) THEN
      log_change('peripheriques', :NEW.id, 'est_supprime',
                 TO_CHAR(:OLD.est_supprime), TO_CHAR(:NEW.est_supprime), 'UPDATE');
    END IF;
  END IF;
END;



-- ----- Audit TELEPHONES -----------------------------------------------------
CREATE OR REPLACE TRIGGER trg_audit_telephones
AFTER INSERT OR UPDATE OR DELETE ON telephones
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    log_change('telephones', :NEW.id, NULL, NULL, :NEW.nom, 'INSERT');
  ELSIF DELETING THEN
    log_change('telephones', :OLD.id, NULL, :OLD.nom, NULL, 'DELETE');
  ELSIF UPDATING THEN
    IF NVL(:OLD.nom,'#') <> NVL(:NEW.nom,'#') THEN
      log_change('telephones', :NEW.id, 'nom', :OLD.nom, :NEW.nom, 'UPDATE');
    END IF;
    IF NVL(:OLD.etat_id,-1) <> NVL(:NEW.etat_id,-1) THEN
      log_change('telephones', :NEW.id, 'etat_id',
                 TO_CHAR(:OLD.etat_id), TO_CHAR(:NEW.etat_id), 'UPDATE');
    END IF;
    IF NVL(:OLD.est_supprime,-1) <> NVL(:NEW.est_supprime,-1) THEN
      log_change('telephones', :NEW.id, 'est_supprime',
                 TO_CHAR(:OLD.est_supprime), TO_CHAR(:NEW.est_supprime), 'UPDATE');
    END IF;
  END IF;
END;



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
    IF NVL(:OLD.est_supprime,-1) <> NVL(:NEW.est_supprime,-1) THEN
      log_change('utilisateurs', :NEW.id, 'est_supprime',
                 TO_CHAR(:OLD.est_supprime), TO_CHAR(:NEW.est_supprime), 'UPDATE');
    END IF;
    IF NVL(:OLD.profil_id,-1) <> NVL(:NEW.profil_id,-1) THEN
      log_change('utilisateurs', :NEW.id, 'profil_id',
                 TO_CHAR(:OLD.profil_id), TO_CHAR(:NEW.profil_id), 'UPDATE');
    END IF;
    IF NVL(:OLD.hierarchy_level_id,-1) <> NVL(:NEW.hierarchy_level_id,-1) THEN
      log_change('utilisateurs', :NEW.id, 'hierarchy_level_id',
                 TO_CHAR(:OLD.hierarchy_level_id), TO_CHAR(:NEW.hierarchy_level_id), 'UPDATE');
    END IF;
  END IF;
END;



-- ----- Audit EQUIPEMENTS_RESEAU ---------------------------------------------
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
    IF NVL(:OLD.est_supprime,-1) <> NVL(:NEW.est_supprime,-1) THEN
      log_change('equipements_reseau', :NEW.id, 'est_supprime',
                 TO_CHAR(:OLD.est_supprime), TO_CHAR(:NEW.est_supprime), 'UPDATE');
    END IF;
  END IF;
END;



-- ----- Audit LOGICIELS ------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_audit_logiciels
AFTER INSERT OR UPDATE OR DELETE ON logiciels
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    log_change('logiciels', :NEW.id, NULL, NULL, :NEW.nom, 'INSERT');
  ELSIF DELETING THEN
    log_change('logiciels', :OLD.id, NULL, :OLD.nom, NULL, 'DELETE');
  ELSIF UPDATING THEN
    IF NVL(:OLD.nom,'#') <> NVL(:NEW.nom,'#') THEN
      log_change('logiciels', :NEW.id, 'nom', :OLD.nom, :NEW.nom, 'UPDATE');
    END IF;
    IF NVL(:OLD.est_supprime,-1) <> NVL(:NEW.est_supprime,-1) THEN
      log_change('logiciels', :NEW.id, 'est_supprime',
                 TO_CHAR(:OLD.est_supprime), TO_CHAR(:NEW.est_supprime), 'UPDATE');
    END IF;
  END IF;
END;



-- ----- Audit INSTALLATIONS_LOGICIELS ----------------------------------------
CREATE OR REPLACE TRIGGER trg_audit_install_log
AFTER INSERT OR DELETE ON installations_logiciels
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    log_change('installations_logiciels', :NEW.id, 'ordi/version', NULL,
               :NEW.ordinateur_id || '/' || :NEW.version_logiciel_id, 'INSERT');
  ELSIF DELETING THEN
    log_change('installations_logiciels', :OLD.id, 'ordi/version',
               :OLD.ordinateur_id || '/' || :OLD.version_logiciel_id, NULL, 'DELETE');
  END IF;
END;
/


-- ----- Audit PORTS_RESEAU ---------------------------------------------------
CREATE OR REPLACE TRIGGER trg_audit_ports_reseau
AFTER INSERT OR UPDATE OR DELETE ON ports_reseau
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    log_change('ports_reseau', :NEW.id, NULL, NULL, :NEW.nom, 'INSERT');
  ELSIF DELETING THEN
    log_change('ports_reseau', :OLD.id, NULL, :OLD.nom, NULL, 'DELETE');
  ELSIF UPDATING THEN
    IF NVL(:OLD.est_actif,-1) <> NVL(:NEW.est_actif,-1) THEN
      log_change('ports_reseau', :NEW.id, 'est_actif',
                 TO_CHAR(:OLD.est_actif), TO_CHAR(:NEW.est_actif), 'UPDATE');
    END IF;
    IF NVL(:OLD.adresse_mac,'#') <> NVL(:NEW.adresse_mac,'#') THEN
      log_change('ports_reseau', :NEW.id, 'adresse_mac',
                 :OLD.adresse_mac, :NEW.adresse_mac, 'UPDATE');
    END IF;
  END IF;
END;



-- =============================================================================
-- SECTION 4 : TRIGGERS DE VALIDATION SITE / ENTITE
-- =============================================================================
-- Un materiel dans une hierarchy_level doit etre du meme site que cette hierarchy_level.
-- On se prémunit des saisies incoherentes.

CREATE OR REPLACE TRIGGER trg_coherence_site_ordi
BEFORE INSERT OR UPDATE ON ordinateurs
FOR EACH ROW
DECLARE
  v_site_hierarchy_level NUMBER;
BEGIN
  SELECT site_id INTO v_site_hierarchy_level
    FROM hierarchy_level WHERE id = :NEW.hierarchy_level_id;
  IF v_site_hierarchy_level <> :NEW.site_id THEN
    RAISE_APPLICATION_ERROR(-20101,
      'Incoherence site : ordinateur(site_id=' || :NEW.site_id
      || ') vs hierarchy_level(site_id=' || v_site_hierarchy_level || ').');
  END IF;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20102,
      'Entite ' || :NEW.hierarchy_level_id || ' introuvable.');
END;


CREATE OR REPLACE TRIGGER trg_coherence_site_periph
BEFORE INSERT OR UPDATE ON peripheriques
FOR EACH ROW
DECLARE
  v_site_hierarchy_level NUMBER;
BEGIN
  SELECT site_id INTO v_site_hierarchy_level
    FROM hierarchy_level WHERE id = :NEW.hierarchy_level_id;
  IF v_site_hierarchy_level <> :NEW.site_id THEN
    RAISE_APPLICATION_ERROR(-20103,
      'Incoherence site : peripherique(site_id=' || :NEW.site_id
      || ') vs hierarchy_level(site_id=' || v_site_hierarchy_level || ').');
  END IF;
END;


CREATE OR REPLACE TRIGGER trg_coherence_site_tel
BEFORE INSERT OR UPDATE ON telephones
FOR EACH ROW
DECLARE
  v_site_hierarchy_level NUMBER;
BEGIN
  SELECT site_id INTO v_site_hierarchy_level
    FROM hierarchy_level WHERE id = :NEW.hierarchy_level_id;
  IF v_site_hierarchy_level <> :NEW.site_id THEN
    RAISE_APPLICATION_ERROR(-20104,
      'Incoherence site : telephone(site_id=' || :NEW.site_id
      || ') vs hierarchy_level(site_id=' || v_site_hierarchy_level || ').');
  END IF;
END;


CREATE OR REPLACE TRIGGER trg_coherence_site_equip
BEFORE INSERT OR UPDATE ON equipements_reseau
FOR EACH ROW
DECLARE
  v_site_hierarchy_level NUMBER;
BEGIN
  SELECT site_id INTO v_site_hierarchy_level
    FROM hierarchy_level WHERE id = :NEW.hierarchy_level_id;
  IF v_site_hierarchy_level <> :NEW.site_id THEN
    RAISE_APPLICATION_ERROR(-20105,
      'Incoherence site : equipement(site_id=' || :NEW.site_id
      || ') vs hierarchy_level(site_id=' || v_site_hierarchy_level || ').');
  END IF;
END;


CREATE OR REPLACE TRIGGER trg_coherence_site_user
BEFORE INSERT OR UPDATE ON utilisateurs
FOR EACH ROW
DECLARE
  v_site_hierarchy_level NUMBER;
BEGIN
  -- Verification seulement si les deux champs sont renseignes
  IF :NEW.hierarchy_level_id IS NOT NULL AND :NEW.site_id IS NOT NULL THEN
    SELECT site_id INTO v_site_hierarchy_level
      FROM hierarchy_level WHERE id = :NEW.hierarchy_level_id;
    IF v_site_hierarchy_level <> :NEW.site_id THEN
      RAISE_APPLICATION_ERROR(-20106,
        'Incoherence site : utilisateur(site_id=' || :NEW.site_id
        || ') vs hierarchy_level(site_id=' || v_site_hierarchy_level || ').');
    END IF;
  END IF;
END;





-- =============================================================================
-- SECTION 5 : TRIGGERS DE VALIDATION METIER
-- =============================================================================

/* Validation du format MAC sur ports_reseau
  Une adresse MAC doit etre au format XX:XX:XX:XX:XX:XX (hex).
*/
CREATE OR REPLACE TRIGGER trg_valid_mac
BEFORE INSERT OR UPDATE ON ports_reseau
FOR EACH ROW
BEGIN
  IF :NEW.adresse_mac IS NOT NULL
     AND NOT REGEXP_LIKE(:NEW.adresse_mac, '^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$')    /* on utilise des regex.*/
  THEN
    RAISE_APPLICATION_ERROR(-20110, 'Adresse MAC invalide : "' || :NEW.adresse_mac || '" (attendu XX:XX:XX:XX:XX:XX).');
  END IF;
END;



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
      'date_fin (' || TO_CHAR(:NEW.date_fin,'YYYY-MM-DD') || ') anterieure a date_debut (' || TO_CHAR(:NEW.date_debut,'YYYY-MM-DD') || ').');
  END IF;
END;



-- ----- Verrou contre l'auto-reference de hierarchy_level ------------------------------
-- Une hierarchy_level ne peut pas etre son propre parent.
CREATE OR REPLACE TRIGGER trg_valid_hierarchy_level_parent
BEFORE INSERT OR UPDATE ON hierarchy_level
FOR EACH ROW
BEGIN
  IF :NEW.hierarchy_level_parent_id = :NEW.id THEN
    RAISE_APPLICATION_ERROR(-20130,
      'Une hierarchy_level ne peut pas etre son propre parent.');
  END IF;
END;



-- ----- Empecher la suppression d'un ordinateur avec logiciels installes -----
CREATE OR REPLACE TRIGGER trg_valid_delete_ordinateur
BEFORE DELETE ON ordinateurs
FOR EACH ROW
DECLARE
  v_nb_install NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_nb_install
    FROM installations_logiciels
   WHERE ordinateur_id = :OLD.id;
  IF v_nb_install > 0 THEN
    RAISE_APPLICATION_ERROR(-20140,
      'Impossible de supprimer l ordinateur (id=' || :OLD.id || ') : ' || v_nb_install || ' logiciel(s) encore installe(s). '
      || 'Desinstallez-les d abord.');
  END IF;
END;



-- ----- Empecher la suppression d'un equipement reseau avec ports actifs -----
CREATE OR REPLACE TRIGGER trg_valid_delete_equip_reseau
BEFORE DELETE ON equipements_reseau
FOR EACH ROW
DECLARE
  v_nb_ports NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_nb_ports
    FROM ports_reseau
   WHERE equipement_id = :OLD.id AND est_actif = 1;
  IF v_nb_ports > 0 THEN
    RAISE_APPLICATION_ERROR(-20141,
      'Impossible de supprimer l equipement reseau (id=' || :OLD.id || ') : ' || v_nb_ports || ' port(s) encore actif(s). '
      || 'Desactivez-les d abord.');
  END IF;
END;



-- ----- Unicite du numero de serie par site (ordinateurs) --------------------
CREATE OR REPLACE TRIGGER trg_valid_serie_ordinateur
BEFORE INSERT OR UPDATE ON ordinateurs
FOR EACH ROW
DECLARE
  v_count NUMBER;
BEGIN
  IF :NEW.numero_serie IS NOT NULL THEN
    SELECT COUNT(*) INTO v_count
    FROM ordinateurs
    WHERE numero_serie = :NEW.numero_serie AND site_id = :NEW.site_id AND id != NVL(:NEW.id, -1);
    IF v_count > 0 THEN
      RAISE_APPLICATION_ERROR(-20150,
        'Le numero de serie "' || :NEW.numero_serie || '" existe deja sur ce site.');
    END IF;
  END IF;
END;





-- =============================================================================
-- SECTION 6 : TRIGGER INSTEAD OF SUR VUE GLOBALE (bonus)
-- =============================================================================
-- Permet d'inserer dans la vue vue_parc_global qui est un UNION ALL : sans ce
-- trigger, Oracle refuse l'INSERT car ne sait pas quelle table cibler.
-- Le trigger redirige vers la table locale ou distante selon site_id.

CREATE OR REPLACE TRIGGER trg_insert_vue_parc_global
INSTEAD OF INSERT ON vue_parc_global
FOR EACH ROW
BEGIN
  IF :NEW.site_id = 1 THEN
    -- Insertion locale (Cergy)
    INSERT INTO ordinateurs (id, nom, numero_serie, site_id, hierarchy_level_id, date_creation)
    VALUES (seq_ordinateurs.NEXTVAL, :NEW.nom, :NEW.numero_serie,
            :NEW.site_id, :NEW.hierarchy_level_id, SYSDATE);
  ELSIF :NEW.site_id = 2 THEN
    -- Insertion distante (Pau via database link)
    INSERT INTO ordinateurs@db_pau (id, nom, numero_serie, site_id, hierarchy_level_id, date_creation)
    VALUES (seq_ordinateurs.NEXTVAL, :NEW.nom, :NEW.numero_serie,
            :NEW.site_id, :NEW.hierarchy_level_id, SYSDATE);
  ELSE
    RAISE_APPLICATION_ERROR(-20160,
      'Site inconnu (site_id=' || :NEW.site_id || '). Valeurs attendues : 1 (Cergy) ou 2 (Pau).');
  END IF;
END;





-- =============================================================================
-- FIN DU FICHIER TRIGGERS
-- Recapitulatif :
--  10 triggers PK auto-increment
--  12 triggers date_modification
--   8 triggers d'audit (avec procedure factorisee log_change)
--   5 triggers coherence sitehierarchy_level
--   6 triggers validation metier (MAC, dates, suppressions, unicite)
--   1 trigger INSTEAD OF sur vue (bonus)
-- Total : 42 triggers + 1 procedure utilitaire
-- =============================================================================
