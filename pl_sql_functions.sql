SET SERVEROUTPUT ON SIZE UNLIMITED;
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS';




-- =============================================================================
-- SECTION 1 : FONCTIONS UTILITAIRES (standalone)
-- =============================================================================
-- Pourquoi standalone : ces fonctions sont utilisees dans plusieurs packages, les declarer en dehors evite la dependance entre packages.

/* Compte le nbre d'ordinateurs d'un site
  param : id du site
*/
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

/* Compte le nbre de mat??riels d'un site (ordinateurs + peripheriques + telephones)
  param : id du site
*/
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



/* R??cup??re le nom d'un site.
  param : id du site
*/
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



/* Taux d'utilisation des ordinateurs d'un site
  On retourne un pourcentage du nbre d'ordinateurs assign??s.
*/
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


/*
  Retourne l'age moyen des ordinateurs d'un site.
  param : id du site
*/
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



/* Verifier qu'un utilisateur est actif.
  param : id utilisateur
  retourne un booleen.
*/
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



/* Compte le nbre de logiciels install??s sur un ordinateur
  param : id ordinateur
  retourne un entier.
*/
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



/* Donne l'??ge d'un materiel (en jours) depuis l'achat.
  param : id ordinateur
  retourne un entier.
*/
CREATE OR REPLACE FUNCTION f_age_materiel_jours(
  p_ordi_id IN NUMBER
) RETURN NUMBER
IS
  v_date_achat DATE;
BEGIN
  SELECT date_achat INTO v_date_achat
  FROM ordinateurs WHERE id = p_ordi_id;
  IF v_date_achat IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN TRUNC(SYSDATE - v_date_achat);
EXCEPTION
  WHEN NO_DATA_FOUND THEN RETURN NULL;
END;
/


/* Compte le nbre de ports actifs d'un equipement r??seau.
  param : id equipement
  retourne un entier.
*/
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



/*Recherche un utilisateur par son email.
  param : email
  retourne l'id de l'utilisateur (-1 si introuvable).
*/
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



-- ----- Nom complet hierarchique d'un hierarchy_level (CONNECT BY + LISTAGG) ---
-- Reconstruit "Racine > Niveau1 > Niveau2 > ..." en remontant les parents.
CREATE OR REPLACE FUNCTION f_nom_complet_hierarchy_level(
  p_hierarchy_level_id IN NUMBER
) RETURN VARCHAR2
IS
  v_chemin VARCHAR2(500);
BEGIN
  -- CONNECT BY parcourt l'arbre vers la racine.
  -- LISTAGG concatene les noms separes par " > " dans l'ordre racine -> feuille
  -- (donc ORDER BY LEVEL DESC, car LEVEL=1 est le noeud cible, LEVEL=max=racine).
  SELECT LISTAGG(nom, ' > ') WITHIN GROUP (ORDER BY niveau DESC)
    INTO v_chemin
    FROM (
      SELECT nom, LEVEL AS niveau
      FROM hierarchy_level
      START WITH id = p_hierarchy_level_id
      CONNECT BY PRIOR hierarchy_level_parent_id = id
    );
  RETURN v_chemin;
EXCEPTION
  WHEN NO_DATA_FOUND THEN RETURN NULL;
END;
/