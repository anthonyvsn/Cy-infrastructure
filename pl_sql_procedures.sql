/*
    Ce fichier contient des procédures de gestion (standalone)
    Ce sont des opérations appelees ponctuellement, pas assez liees a un domaine pour justifier un package dedie.
*/

/*
    Ajoute un ordinateur (avec vérifications préalables).
*/
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
      FROM hierarchy_level WHERE id = p_entite_id;
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
        'Le numero de serie "' || p_numero_serie || '" existe deja sur ce site.');
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
    FROM hierarchy_level WHERE id = p_nouvelle_entite;
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



/*
    Desactive un utilisateur et libere son materiel.
    A noter : On utilise un CURSOR explicite pour parcourir les ordis affectes.
*/
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
      RAISE_APPLICATION_ERROR(-20301, 'Utilisateur id=' || p_user_id || ' introuvable.');
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



/*
    Installe un logiciel sur un ordinateur
*/
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
      RAISE_APPLICATION_ERROR(-20401, 'Ordinateur id=' || p_ordi_id || ' introuvable ou supprime.');
  END;

  -- Verifier la version
  BEGIN
    SELECT l.nom, vl.nom INTO v_nom_logiciel, v_nom_version
      FROM versions_logiciel vl
      JOIN logiciels l ON vl.logiciel_id = l.id
     WHERE vl.id = p_version_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20402, 'Version de logiciel id=' || p_version_id || ' introuvable.');
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



/*
    Assure la suppression du matériel
*/
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
  DBMS_OUTPUT.PUT_LINE(p_type_materiel || ' "' || v_nom || '" (id=' || p_materiel_id || ') supprime logiquement.');
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE(p_type_materiel || ' id=' || p_materiel_id || ' introuvable.');
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Erreur suppression : ' || SQLCODE || ' - ' || SQLERRM);
    RAISE;
END;
