-- =============================================================================
-- JEU DE TEST PL/SQL -- Projet GLPI CY Tech multi-sites
-- =============================================================================
-- Genere des donnees REALISTES basees sur la structure reelle de CY Tech
-- (campus Cergy et Pau, ecoles d'ingenieurs).
--
-- Volumes par defaut :
--   Sites           : 2 (Cergy, Pau)
--   Hierarchy_level : 15 (CY Tech > Cergy/Pau > services + departements)
--   Localisations   : 95 (5 batiments + 75 salles + 15 bureaux)
--      - Cergy/Parc   : Condorcet, Cauchy, Turing (3 etages x 5 salles + 5 bureaux)
--      - Cergy/Fermat : 1 batiment Fermat (2 etages x 5 salles + 5 bureaux)
--      - Pau          : 1 batiment PAU (2 etages x 5 salles + 5 bureaux)
--      Format salles : <Batiment><etage><n>   ex: Turing201
--
--   Fabricants      : 20    Etats : 8    Types ordi : 5    Modeles : 30
--   Profils         : 5 (Admin, Technicien, Enseignant, Etudiant, Administration)
--   Groupes         : 20
--
--   Utilisateurs    : 2620 (2500 etu + 80 prof + 30 admin + 10 tech)
--                     Ratio Cergy/Pau ~ 80/20
--   Ordinateurs     : 2760
--      - 140 PC fixes (4 salles a Cauchy etage 2 x 35 PC, sans utilisateur)
--      - 2620 portables (1 par utilisateur)
--   Peripheriques   : ~360
--      - 280 souris+clavier (1 jeu par PC fixe)
--      - 65 videoprojecteurs (1 par salle)
--      - 13 imprimantes (1 par etage)
--   Telephones      : 30 fixes (1 par admin)
--
--   Logiciels       : 20      Versions : ~80     Installations : ~5000
--
--   Reseau          : 143 equipements
--      - 65 switchs (1 par salle, 48 ports chacun => 3120 ports)
--      - 65 routeurs WiFi (1 par salle)
--      - 13 bornes WiFi (1 par etage)
--
-- Utilise : procedures, fonctions, curseurs explicites, DBMS_RANDOM, boucles FOR.
-- A executer en tant que ADMIN_CYTECH (apres bdd_Cy_infrastructure.sql).
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;
SET DEFINE OFF
-- DEFINE OFF : evite que SQL*Plus interprete les '&' dans les chaines
-- (ex : 'Dept Biotech & Chimie') comme des variables de substitution.
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD';

-- -----------------------------------------------------------------------------
-- SPECIFICATION DU PACKAGE
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_jeu_test AS

  -- Procedure maitresse. Les volumes par defaut refletent la realite CY Tech
  -- (pour les tests de perf, augmenter p_nb_etudiants pour faire grossir le parc).
  PROCEDURE generer_tout(
    p_nb_etudiants  NUMBER DEFAULT 2500,
    p_nb_profs      NUMBER DEFAULT 80,
    p_nb_admins     NUMBER DEFAULT 30,
    p_nb_techs      NUMBER DEFAULT 10
  );

  -- Vide toutes les tables (ordre inverse des FK)
  PROCEDURE reset_donnees;

  -- Helpers de generation aleatoire
  FUNCTION random_string(p_len NUMBER) RETURN VARCHAR2;
  FUNCTION random_mac    RETURN VARCHAR2;
  FUNCTION random_serial(p_prefix VARCHAR2 DEFAULT 'SN') RETURN VARCHAR2;
  FUNCTION random_date_passee(p_jours_max NUMBER DEFAULT 1825) RETURN DATE;
  FUNCTION random_id(p_seq_name VARCHAR2) RETURN NUMBER;

END pkg_jeu_test;
/

-- -----------------------------------------------------------------------------
-- CORPS DU PACKAGE
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY pkg_jeu_test AS

  -- Tableaux de noms de reference
  TYPE t_str_array IS TABLE OF VARCHAR2(100) INDEX BY PLS_INTEGER;
  TYPE t_num_array IS TABLE OF NUMBER         INDEX BY PLS_INTEGER;

  v_prenoms      t_str_array;
  v_noms         t_str_array;
  v_fabricants   t_str_array;
  v_etats_lib    t_str_array;
  v_types_ordi   t_str_array;
  v_types_periph t_str_array;
  v_types_equip  t_str_array;
  v_logiciels    t_str_array;
  v_os           t_str_array;

  -- Codes des sites (assumes : sites cree dans cet ordre, seq commence a 1)
  c_site_cergy   CONSTANT NUMBER := 1;
  c_site_pau     CONSTANT NUMBER := 2;

  -- Profils (codes a affecter)
  c_prof_admin       CONSTANT NUMBER := 1;
  c_prof_technicien  CONSTANT NUMBER := 2;
  c_prof_enseignant  CONSTANT NUMBER := 3;
  c_prof_etudiant    CONSTANT NUMBER := 4;
  c_prof_administ    CONSTANT NUMBER := 5;

  -- IDs des hierarchy_level stockes a mesure de la creation (cf peupler_hierarchy_level)
  v_ent_cergy_gestion       NUMBER;
  v_ent_cergy_it            NUMBER;
  v_ent_cergy_admin         NUMBER;
  v_ent_cergy_profs         NUMBER;
  v_ent_cergy_info          NUMBER;
  v_ent_cergy_maths         NUMBER;
  v_ent_cergy_biotech       NUMBER;
  v_ent_cergy_gc            NUMBER;
  v_ent_pau_gestion         NUMBER;
  v_ent_pau_it              NUMBER;
  v_ent_pau_admin           NUMBER;
  v_ent_pau_profs           NUMBER;
  v_ent_pau_info            NUMBER;
  v_ent_pau_maths           NUMBER;

  -- Bornes basses/hautes des hierarchy_level par site (pour pick aleatoire d'un dpt)
  v_cergy_dpt_min NUMBER;
  v_cergy_dpt_max NUMBER;
  v_pau_dpt_min   NUMBER;
  v_pau_dpt_max   NUMBER;

  -- ---------------------------------------------------------------------------
  -- HELPERS
  -- ---------------------------------------------------------------------------
  FUNCTION random_string(p_len NUMBER) RETURN VARCHAR2 IS
  BEGIN
    RETURN DBMS_RANDOM.STRING('U', p_len);
  END;

  FUNCTION random_mac RETURN VARCHAR2 IS
    v_mac VARCHAR2(17);
  BEGIN
    v_mac := '';
    FOR i IN 1..6 LOOP
      v_mac := v_mac || LPAD(TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(0, 256)), 'FM0X'), 2, '0');
      IF i < 6 THEN v_mac := v_mac || ':';
      END IF;
    END LOOP;
    RETURN v_mac;
  END;

  FUNCTION random_serial(p_prefix VARCHAR2 DEFAULT 'SN') RETURN VARCHAR2 IS
  BEGIN
    RETURN p_prefix || '-' || TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(100000, 999999))) || '-' || random_string(3);
  END;

  FUNCTION random_date_passee(p_jours_max NUMBER DEFAULT 1825) RETURN DATE IS
  BEGIN
    RETURN SYSDATE - TRUNC(DBMS_RANDOM.VALUE(0, p_jours_max));
  END;

  FUNCTION random_id(p_seq_name VARCHAR2) RETURN NUMBER IS
    v_max NUMBER;
  BEGIN
    EXECUTE IMMEDIATE 'SELECT ' || p_seq_name || '.CURRVAL FROM dual' INTO v_max;
    RETURN TRUNC(DBMS_RANDOM.VALUE(1, v_max + 1));
  END;

  -- Choisit un hierarchy_level aleatoire (departement ou service) selon le site
  FUNCTION random_hl_site(p_site NUMBER) RETURN NUMBER IS
  BEGIN
    IF p_site = 1 THEN
      RETURN TRUNC(DBMS_RANDOM.VALUE(v_cergy_dpt_min, v_cergy_dpt_max + 1));
    ELSE
      RETURN TRUNC(DBMS_RANDOM.VALUE(v_pau_dpt_min, v_pau_dpt_max + 1));
    END IF;
  END;

  -- Choisit une localisation aleatoire (salle ou bureau) d'un site donne
  FUNCTION random_localisation_site(p_site NUMBER) RETURN NUMBER IS
    v_id NUMBER;
  BEGIN
    -- localisations rattachees a un hierarchy_level du site donne
    SELECT id INTO v_id FROM (
      SELECT l.id
        FROM localisations l
        JOIN hierarchy_level e ON e.id = l.hierarchy_level_id
       WHERE e.site_id = p_site
         AND l.salle IS NOT NULL  -- pas les batiments racines
       ORDER BY DBMS_RANDOM.VALUE
    ) WHERE ROWNUM = 1;
    RETURN v_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN NULL;
  END;

  -- ---------------------------------------------------------------------------
  -- INITIALISATION DES TABLEAUX DE REFERENCE
  -- ---------------------------------------------------------------------------
  PROCEDURE init_referentiels IS
  BEGIN
    -- Prenoms (20)
    v_prenoms(1) := 'Alice';     v_prenoms(2) := 'Bob';      v_prenoms(3) := 'Camille';
    v_prenoms(4) := 'David';     v_prenoms(5) := 'Elena';    v_prenoms(6) := 'Florent';
    v_prenoms(7) := 'Gabriel';   v_prenoms(8) := 'Helene';   v_prenoms(9) := 'Ivan';
    v_prenoms(10):= 'Julie';     v_prenoms(11):= 'Karim';    v_prenoms(12):= 'Lucie';
    v_prenoms(13):= 'Mathieu';   v_prenoms(14):= 'Nadia';    v_prenoms(15):= 'Olivier';
    v_prenoms(16):= 'Pauline';   v_prenoms(17):= 'Quentin';  v_prenoms(18):= 'Rachel';
    v_prenoms(19):= 'Samir';     v_prenoms(20):= 'Theo';

    -- Noms (20)
    v_noms(1) := 'Martin';   v_noms(2) := 'Bernard';  v_noms(3) := 'Dubois';
    v_noms(4) := 'Petit';    v_noms(5) := 'Robert';   v_noms(6) := 'Richard';
    v_noms(7) := 'Durand';   v_noms(8) := 'Moreau';   v_noms(9) := 'Laurent';
    v_noms(10):= 'Simon';    v_noms(11):= 'Michel';   v_noms(12):= 'Lefevre';
    v_noms(13):= 'Leroy';    v_noms(14):= 'Roux';     v_noms(15):= 'David';
    v_noms(16):= 'Bertrand'; v_noms(17):= 'Morel';    v_noms(18):= 'Fournier';
    v_noms(19):= 'Girard';   v_noms(20):= 'Bonnet';

    -- Fabricants (20)
    v_fabricants(1) := 'Dell';      v_fabricants(2) := 'HP';        v_fabricants(3) := 'Lenovo';
    v_fabricants(4) := 'Apple';     v_fabricants(5) := 'Asus';      v_fabricants(6) := 'Acer';
    v_fabricants(7) := 'Cisco';     v_fabricants(8) := 'Aruba';     v_fabricants(9) := 'Ubiquiti';
    v_fabricants(10):= 'Netgear';   v_fabricants(11):= 'Logitech';  v_fabricants(12):= 'Microsoft';
    v_fabricants(13):= 'Samsung';   v_fabricants(14):= 'LG';        v_fabricants(15):= 'BenQ';
    v_fabricants(16):= 'Epson';     v_fabricants(17):= 'Brother';   v_fabricants(18):= 'Canon';
    v_fabricants(19):= 'Razer';     v_fabricants(20):= 'MSI';

    v_etats_lib(1) := 'En service';     v_etats_lib(2) := 'En stock';
    v_etats_lib(3) := 'En reparation';  v_etats_lib(4) := 'Reforme';
    v_etats_lib(5) := 'En commande';    v_etats_lib(6) := 'En pret';
    v_etats_lib(7) := 'Hors service';   v_etats_lib(8) := 'En test';

    v_types_ordi(1) := 'Desktop';      v_types_ordi(2) := 'Laptop';
    v_types_ordi(3) := 'Serveur';      v_types_ordi(4) := 'Workstation';
    v_types_ordi(5) := 'Tablette';

    v_types_periph(1) := 'imprimante';     v_types_periph(2) := 'souris';
    v_types_periph(3) := 'clavier';        v_types_periph(4) := 'videoprojecteur';
    v_types_periph(5) := 'ecran';          v_types_periph(6) := 'autre';

    -- 3 types reseau seulement (correspondent a notre structure reelle)
    v_types_equip(1) := 'Switch';
    v_types_equip(2) := 'Routeur WiFi';
    v_types_equip(3) := 'Borne WiFi';

    v_logiciels(1) := 'Microsoft Office';     v_logiciels(2) := 'Adobe Creative Suite';
    v_logiciels(3) := 'Visual Studio Code';   v_logiciels(4) := 'IntelliJ IDEA';
    v_logiciels(5) := 'PyCharm';              v_logiciels(6) := 'Eclipse';
    v_logiciels(7) := 'Docker Desktop';       v_logiciels(8) := 'Slack';
    v_logiciels(9) := 'Zoom';                 v_logiciels(10):= 'Teams';
    v_logiciels(11):= 'Chrome';               v_logiciels(12):= 'Firefox';
    v_logiciels(13):= 'MATLAB';               v_logiciels(14):= 'AutoCAD';
    v_logiciels(15):= 'SolidWorks';           v_logiciels(16):= 'GitHub Desktop';
    v_logiciels(17):= 'Notion';               v_logiciels(18):= 'Postman';
    v_logiciels(19):= 'MySQL Workbench';      v_logiciels(20):= 'Oracle SQL Developer';

    v_os(1) := 'Windows 11';   v_os(2) := 'Windows 10';   v_os(3) := 'Ubuntu 24.04';
    v_os(4) := 'Ubuntu 22.04'; v_os(5) := 'macOS Sonoma'; v_os(6) := 'Debian 12';
    v_os(7) := 'Fedora 40';    v_os(8) := 'Windows Server 2022';
  END init_referentiels;

  -- ---------------------------------------------------------------------------
  -- 1) SITES : 2 sites avec adresses reelles CY Tech
  -- ---------------------------------------------------------------------------
  PROCEDURE peupler_sites IS
  BEGIN
    INSERT INTO sites(id, nom, adresse, ville, code_postal, telephone)
    VALUES (seq_sites.NEXTVAL, 'CY Tech Cergy',
            'Avenue du Parc', 'Cergy', '95000', '0134256900');

    INSERT INTO sites(id, nom, adresse, ville, code_postal, telephone)
    VALUES (seq_sites.NEXTVAL, 'CY Tech Pau',
            '2 boulevard Lucien Favre', 'Pau', '64075', '0559059090');

    DBMS_OUTPUT.PUT_LINE('  Sites : 2 (Cergy, Pau)');
  END peupler_sites;

  -- ---------------------------------------------------------------------------
  -- 2) ENTITES : structure CY Tech ecoles d'ingenieurs
  --    Racine -> Cergy/Pau -> services + departements
  -- ---------------------------------------------------------------------------
  PROCEDURE peupler_hierarchy_level IS
    v_id_racine  NUMBER;
    v_id_cergy   NUMBER;
    v_id_pau     NUMBER;
  BEGIN
    -- Racine
    INSERT INTO hierarchy_level(id, nom, hierarchy_level_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_hierarchy_level.NEXTVAL, 'CY Tech', NULL, c_site_cergy, 0, 'CY Tech')
    RETURNING id INTO v_id_racine;

    -- Niveau 1 : sites (Cergy, Pau) en tant que hierarchy_level organisationnels
    INSERT INTO hierarchy_level(id, nom, hierarchy_level_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_hierarchy_level.NEXTVAL, 'Cergy', v_id_racine, c_site_cergy, 1,
            'CY Tech > Cergy')
    RETURNING id INTO v_id_cergy;

    INSERT INTO hierarchy_level(id, nom, hierarchy_level_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_hierarchy_level.NEXTVAL, 'Pau', v_id_racine, c_site_pau, 1,
            'CY Tech > Pau')
    RETURNING id INTO v_id_pau;

    -- Niveau 2 - Cergy : services + 4 departements pedagogiques
    INSERT INTO hierarchy_level(id, nom, hierarchy_level_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_hierarchy_level.NEXTVAL, 'Gestion', v_id_cergy, c_site_cergy, 2,
            'CY Tech > Cergy > Gestion')
    RETURNING id INTO v_ent_cergy_gestion;

    INSERT INTO hierarchy_level(id, nom, hierarchy_level_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_hierarchy_level.NEXTVAL, 'IT', v_id_cergy, c_site_cergy, 2,
            'CY Tech > Cergy > IT')
    RETURNING id INTO v_ent_cergy_it;

    INSERT INTO hierarchy_level(id, nom, hierarchy_level_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_hierarchy_level.NEXTVAL, 'Administration', v_id_cergy, c_site_cergy, 2,
            'CY Tech > Cergy > Administration')
    RETURNING id INTO v_ent_cergy_admin;

    INSERT INTO hierarchy_level(id, nom, hierarchy_level_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_hierarchy_level.NEXTVAL, 'Bureau des profs', v_id_cergy, c_site_cergy, 2,
            'CY Tech > Cergy > Bureau des profs')
    RETURNING id INTO v_ent_cergy_profs;

    INSERT INTO hierarchy_level(id, nom, hierarchy_level_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_hierarchy_level.NEXTVAL, 'Dept Informatique', v_id_cergy, c_site_cergy, 2,
            'CY Tech > Cergy > Dept Informatique')
    RETURNING id INTO v_ent_cergy_info;

    INSERT INTO hierarchy_level(id, nom, hierarchy_level_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_hierarchy_level.NEXTVAL, 'Dept Maths appliquees', v_id_cergy, c_site_cergy, 2,
            'CY Tech > Cergy > Dept Maths appliquees')
    RETURNING id INTO v_ent_cergy_maths;

    INSERT INTO hierarchy_level(id, nom, hierarchy_level_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_hierarchy_level.NEXTVAL, 'Dept Biotech & Chimie', v_id_cergy, c_site_cergy, 2,
            'CY Tech > Cergy > Dept Biotech & Chimie')
    RETURNING id INTO v_ent_cergy_biotech;

    INSERT INTO hierarchy_level(id, nom, hierarchy_level_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_hierarchy_level.NEXTVAL, 'Dept Genie Civil', v_id_cergy, c_site_cergy, 2,
            'CY Tech > Cergy > Dept Genie Civil')
    RETURNING id INTO v_ent_cergy_gc;

    -- Niveau 2 - Pau : services + 2 departements pedagogiques
    INSERT INTO hierarchy_level(id, nom, hierarchy_level_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_hierarchy_level.NEXTVAL, 'Gestion', v_id_pau, c_site_pau, 2,
            'CY Tech > Pau > Gestion')
    RETURNING id INTO v_ent_pau_gestion;

    INSERT INTO hierarchy_level(id, nom, hierarchy_level_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_hierarchy_level.NEXTVAL, 'IT', v_id_pau, c_site_pau, 2,
            'CY Tech > Pau > IT')
    RETURNING id INTO v_ent_pau_it;

    INSERT INTO hierarchy_level(id, nom, hierarchy_level_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_hierarchy_level.NEXTVAL, 'Administration', v_id_pau, c_site_pau, 2,
            'CY Tech > Pau > Administration')
    RETURNING id INTO v_ent_pau_admin;

    INSERT INTO hierarchy_level(id, nom, hierarchy_level_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_hierarchy_level.NEXTVAL, 'Bureau des profs', v_id_pau, c_site_pau, 2,
            'CY Tech > Pau > Bureau des profs')
    RETURNING id INTO v_ent_pau_profs;

    INSERT INTO hierarchy_level(id, nom, hierarchy_level_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_hierarchy_level.NEXTVAL, 'Dept Informatique', v_id_pau, c_site_pau, 2,
            'CY Tech > Pau > Dept Informatique')
    RETURNING id INTO v_ent_pau_info;

    INSERT INTO hierarchy_level(id, nom, hierarchy_level_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_hierarchy_level.NEXTVAL, 'Dept Maths appliquees', v_id_pau, c_site_pau, 2,
            'CY Tech > Pau > Dept Maths appliquees')
    RETURNING id INTO v_ent_pau_maths;

    -- Pour la selection aleatoire d'un hierarchy_level par site
    v_cergy_dpt_min := v_ent_cergy_gestion;
    v_cergy_dpt_max := v_ent_cergy_gc;
    v_pau_dpt_min   := v_ent_pau_gestion;
    v_pau_dpt_max   := v_ent_pau_maths;

    DBMS_OUTPUT.PUT_LINE('  Entites : 15 (1 racine + 2 sites + 8 Cergy + 6 Pau)');
  END peupler_hierarchy_level;

  -- ---------------------------------------------------------------------------
  -- 3) LOCALISATIONS : batiments + salles + bureaux
  --    Structure : 5 batiments (Condorcet/Cauchy/Turing a Cergy/Parc,
  --    Fermat a Cergy/Fermat, PAU a Pau)
  --    Salles : format <Batiment><etage><n>  ex: Turing201, Cauchy202
  --    Bureaux : Bureau_<Batiment>_01 a Bureau_<Batiment>_05
  -- ---------------------------------------------------------------------------
  PROCEDURE creer_batiment(
    p_nom_bat    VARCHAR2,
    p_site_id    NUMBER,
    p_hierarchy_level_id  NUMBER,
    p_nb_etages  NUMBER,
    p_nb_salles_par_etage NUMBER DEFAULT 5,
    p_nb_bureaux NUMBER DEFAULT 5
  ) IS
    v_id_bat NUMBER;
  BEGIN
    -- Le batiment lui-meme (localisation racine)
    INSERT INTO localisations(id, nom, nom_complet, hierarchy_level_id, localisation_parent_id,
                              batiment, salle, etage)
    VALUES (seq_localisations.NEXTVAL, p_nom_bat,
            'Batiment ' || p_nom_bat, p_hierarchy_level_id, NULL,
            p_nom_bat, NULL, NULL)
    RETURNING id INTO v_id_bat;

    -- Salles : pour chaque etage, p_nb_salles_par_etage salles
    -- nom = <Batiment><etage><n>   ex: Turing201
    FOR et IN 1..p_nb_etages LOOP
      FOR sa IN 1..p_nb_salles_par_etage LOOP
        INSERT INTO localisations(id, nom, nom_complet, hierarchy_level_id, localisation_parent_id,
                                  batiment, salle, etage)
        VALUES (seq_localisations.NEXTVAL,
                p_nom_bat || et || LPAD(sa, 2, '0'),
                'Batiment ' || p_nom_bat || ' > Etage ' || et || ' > Salle ' || LPAD(sa, 2, '0'),
                p_hierarchy_level_id,
                v_id_bat,
                p_nom_bat,
                LPAD(TO_CHAR(sa), 2, '0'),
                TO_CHAR(et));
      END LOOP;
    END LOOP;

    -- Bureaux : Bureau_<Bat>_01 .. _05
    FOR b IN 1..p_nb_bureaux LOOP
      INSERT INTO localisations(id, nom, nom_complet, hierarchy_level_id, localisation_parent_id,
                                batiment, salle, etage)
      VALUES (seq_localisations.NEXTVAL,
              'Bureau_' || p_nom_bat || '_' || LPAD(b, 2, '0'),
              'Batiment ' || p_nom_bat || ' > Bureau ' || LPAD(b, 2, '0'),
              p_hierarchy_level_id,
              v_id_bat,
              p_nom_bat,
              'Bureau' || LPAD(TO_CHAR(b), 2, '0'),
              NULL);
    END LOOP;
  END creer_batiment;

  PROCEDURE peupler_localisations IS
  BEGIN
    -- Cergy - Site du Parc : 3 batiments de 3 etages
    creer_batiment('Condorcet', 1, v_ent_cergy_info,    3);
    creer_batiment('Cauchy',    1, v_ent_cergy_maths,   3);
    creer_batiment('Turing',    1, v_ent_cergy_info,    3);

    -- Cergy - Site Fermat (FT) : 1 batiment de 2 etages
    creer_batiment('Fermat',    1, v_ent_cergy_gc,      2);

    -- Pau : 1 batiment de 2 etages
    creer_batiment('PAU',       2,   v_ent_pau_info,      2);

    DBMS_OUTPUT.PUT_LINE('  Localisations : 5 batiments + 75 salles + 25 bureaux = 105');
  END peupler_localisations;

  -- ---------------------------------------------------------------------------
  -- 4) FABRICANTS / ETATS / TYPES / MODELES / PROFILS / GROUPES
  -- ---------------------------------------------------------------------------
  PROCEDURE peupler_fabricants IS
    v_nom VARCHAR2(100);
  BEGIN
    FOR i IN 1..20 LOOP
      v_nom := v_fabricants(i);
      INSERT INTO fabricants(id, nom) VALUES (seq_fabricants.NEXTVAL, v_nom);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Fabricants : ' || TO_CHAR(20));
  END peupler_fabricants;

  PROCEDURE peupler_etats IS
    v_nom VARCHAR2(100);
  BEGIN
    FOR i IN 1..8 LOOP
      v_nom := v_etats_lib(i);
      INSERT INTO etats(id, nom, etat) VALUES (seq_etats.NEXTVAL, v_nom, v_nom);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Etats : ' || TO_CHAR(8));
  END peupler_etats;

  PROCEDURE peupler_types_ordi IS
    v_nom VARCHAR2(100);
  BEGIN
    FOR i IN 1..5 LOOP
      v_nom := v_types_ordi(i);
      INSERT INTO types_ordinateur(id, machine_type)
      VALUES (seq_types_ordinateur.NEXTVAL, v_nom);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Types ordi : ' || TO_CHAR(5));
  END peupler_types_ordi;

  PROCEDURE peupler_modeles IS
    v_idx      NUMBER;
    v_fab_name VARCHAR2(100);
    v_fab_cnt  NUMBER := v_fabricants.COUNT;
  BEGIN
    FOR i IN 1..30 LOOP
      v_idx := MOD(i, v_fab_cnt) + 1;
      v_fab_name := v_fabricants(v_idx);
      INSERT INTO modeles_ordinateur(id, nom, ref_produit, fabricant_id)
      VALUES (seq_modeles_ordinateur.NEXTVAL,
              v_fab_name || ' Model ' || i,
              'REF-' || LPAD(i, 4, '0'),
              v_idx);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Modeles : 30');
  END peupler_modeles;

  -- 5 profils nommes (conformes a la realite CY Tech)
  PROCEDURE peupler_profils IS
  BEGIN
    INSERT INTO profils(id, nom, interface)
    VALUES (seq_profils.NEXTVAL, 'Admin',          'central');
    INSERT INTO profils(id, nom, interface)
    VALUES (seq_profils.NEXTVAL, 'Technicien',     'central');
    INSERT INTO profils(id, nom, interface)
    VALUES (seq_profils.NEXTVAL, 'Enseignant',     'helpdesk');
    INSERT INTO profils(id, nom, interface)
    VALUES (seq_profils.NEXTVAL, 'Etudiant',       'helpdesk');
    INSERT INTO profils(id, nom, interface)
    VALUES (seq_profils.NEXTVAL, 'Administration', 'central');
    DBMS_OUTPUT.PUT_LINE('  Profils : 5 (Admin/Technicien/Enseignant/Etudiant/Administration)');
  END peupler_profils;

  PROCEDURE peupler_groupes IS
    v_site   NUMBER;
    v_hl     NUMBER;
    v_recur  NUMBER;
  BEGIN
    FOR i IN 1..20 LOOP
      v_site := CASE WHEN MOD(i,2)=0 THEN c_site_cergy ELSE c_site_pau END;
      v_hl := random_hl_site(v_site);
      v_recur := CASE WHEN MOD(i, 3) = 0 THEN 1 ELSE 0 END;
      INSERT INTO groupes(id, nom, hierarchy_level_id, est_recursif, commentaire)
      VALUES (seq_groupes.NEXTVAL, 'Groupe ' || i, v_hl, v_recur,
              'Groupe genere automatiquement');
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Groupes : 20');
  END peupler_groupes;

  -- ---------------------------------------------------------------------------
  -- 5) UTILISATEURS : 2500 etu + 80 prof + 30 admin + 10 tech (par defaut)
  --    Repartition ~ 80% Cergy / 20% Pau
  -- ---------------------------------------------------------------------------
  PROCEDURE inserer_utilisateur(
    p_profil_id IN NUMBER,
    p_site_id   IN NUMBER,
    p_hierarchy_level_id IN NUMBER,
    p_idx       IN NUMBER,
    p_prefix    IN VARCHAR2
  ) IS
    v_prenom    VARCHAR2(100);
    v_nom       VARCHAR2(100);
    v_login     VARCHAR2(255);
    v_pwd       VARCHAR2(255);
    v_email     VARCHAR2(255);
    v_tel       VARCHAR2(50);
    v_loc       NUMBER;
    v_actif     NUMBER;
    v_supprime  NUMBER;
    v_d_debut   DATE;
    v_d_creat   DATE;
  BEGIN
    -- Toutes les valeurs sont calculees en PL/SQL avant l'INSERT
    -- (Oracle interdit collections PL/SQL et fcts a etat dans une INSERT VALUES).
    v_prenom   := v_prenoms(TRUNC(DBMS_RANDOM.VALUE(1, v_prenoms.COUNT + 1)));
    v_nom      := v_noms(TRUNC(DBMS_RANDOM.VALUE(1, v_noms.COUNT + 1)));
    v_login    := LOWER(p_prefix || SUBSTR(v_prenom, 1, 1) || v_nom) || p_idx;
    v_pwd      := 'hash_' || random_string(16);
    v_email    := LOWER(v_prenom) || '.' || LOWER(v_nom) || '@cytech.fr';
    v_tel      := '06' || LPAD(TRUNC(DBMS_RANDOM.VALUE(0, 100000000)), 8, '0');
    v_loc      := random_localisation_site(p_site_id);
    v_actif    := CASE WHEN DBMS_RANDOM.VALUE < 0.95 THEN 1 ELSE 0 END;
    v_supprime := CASE WHEN DBMS_RANDOM.VALUE < 0.02 THEN 1 ELSE 0 END;
    v_d_debut  := random_date_passee(2000);
    v_d_creat  := random_date_passee(2000);

    INSERT INTO utilisateurs(id, login, mot_de_passe, nom, prenom, email, telephone,
                             hierarchy_level_id, localisation_id, profil_id, site_id,
                             langue, est_actif, est_supprime, type_auth,
                             date_debut, date_creation, date_modification)
    VALUES (seq_utilisateurs.NEXTVAL,
            v_login, v_pwd, v_nom, v_prenom, v_email, v_tel,
            p_hierarchy_level_id, v_loc, p_profil_id, p_site_id,
            'fr_FR', v_actif, v_supprime, 1,
            v_d_debut, v_d_creat, SYSDATE);
  END inserer_utilisateur;

  PROCEDURE peupler_utilisateurs(
    p_nb_etudiants NUMBER,
    p_nb_profs     NUMBER,
    p_nb_admins    NUMBER,
    p_nb_techs     NUMBER
  ) IS
    v_site NUMBER;
    v_ent  NUMBER;
  BEGIN
    -- Etudiants : hierarchy_level = departements pedagogiques (info/maths/biotech/gc)
    FOR i IN 1..p_nb_etudiants LOOP
      v_site := CASE WHEN DBMS_RANDOM.VALUE < 0.8 THEN 1 ELSE 2 END;
      IF v_site = 1 THEN
        v_ent := CASE TRUNC(DBMS_RANDOM.VALUE(0, 4))
                   WHEN 0 THEN v_ent_cergy_info
                   WHEN 1 THEN v_ent_cergy_maths
                   WHEN 2 THEN v_ent_cergy_biotech
                   ELSE v_ent_cergy_gc
                 END;
      ELSE
        v_ent := CASE WHEN DBMS_RANDOM.VALUE < 0.5 THEN v_ent_pau_info
                                                  ELSE v_ent_pau_maths END;
      END IF;
      inserer_utilisateur(c_prof_etudiant, v_site, v_ent, i, 'etu_');
    END LOOP;

    -- Enseignants : hierarchy_level Bureau des profs (1 par site)
    FOR i IN 1..p_nb_profs LOOP
      v_site := CASE WHEN DBMS_RANDOM.VALUE < 0.81 THEN 1 ELSE 2 END;
      v_ent  := CASE WHEN v_site = 1 THEN v_ent_cergy_profs ELSE v_ent_pau_profs END;
      inserer_utilisateur(c_prof_enseignant, v_site, v_ent, i, 'prof_');
    END LOOP;

    -- Administration (gestion/scolarite/direction)
    FOR i IN 1..p_nb_admins LOOP
      v_site := CASE WHEN DBMS_RANDOM.VALUE < 0.83 THEN 1 ELSE 2 END;
      v_ent  := CASE WHEN v_site = 1 THEN v_ent_cergy_admin ELSE v_ent_pau_admin END;
      inserer_utilisateur(c_prof_administ, v_site, v_ent, i, 'adm_');
    END LOOP;

    -- Techniciens IT : hierarchy_level IT
    FOR i IN 1..p_nb_techs LOOP
      v_site := CASE WHEN DBMS_RANDOM.VALUE < 0.7 THEN 1 ELSE 2 END;
      v_ent  := CASE WHEN v_site = 1 THEN v_ent_cergy_it ELSE v_ent_pau_it END;
      inserer_utilisateur(c_prof_technicien, v_site, v_ent, i, 'tech_');
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('  Utilisateurs : ' ||
      (p_nb_etudiants + p_nb_profs + p_nb_admins + p_nb_techs)
      || ' (' || p_nb_etudiants || ' etu + ' || p_nb_profs
      || ' prof + ' || p_nb_admins || ' admin + ' || p_nb_techs || ' tech)');
  END peupler_utilisateurs;

  -- ---------------------------------------------------------------------------
  -- 6) ORDINATEURS
  --    a) 140 PC fixes a Cauchy etage 2 (4 salles x ~35 PC), sans utilisateur
  --    b) 1 PC portable par utilisateur, dans sa localisation
  -- ---------------------------------------------------------------------------
  PROCEDURE peupler_pc_fixes_cauchy IS
    v_id_type_desktop NUMBER;
    v_count           NUMBER := 0;
    v_pc_par_salle    NUMBER := 35;
    v_fab_cnt         NUMBER := v_fabricants.COUNT;
    v_serie           VARCHAR2(50);
    v_modele          NUMBER;
    v_fab             NUMBER;
    v_achat           DATE;
    v_creat           DATE;
    CURSOR c_salles_pc IS
      SELECT id, nom, hierarchy_level_id
        FROM localisations
       WHERE batiment = 'Cauchy' AND etage = '2' AND salle IS NOT NULL
       ORDER BY nom
       FETCH FIRST 4 ROWS ONLY;
  BEGIN
    SELECT id INTO v_id_type_desktop
      FROM types_ordinateur WHERE machine_type = 'Desktop' AND ROWNUM = 1;

    FOR sa IN c_salles_pc LOOP
      FOR k IN 1..v_pc_par_salle LOOP
        v_count  := v_count + 1;
        v_serie  := random_serial('SN-FIXE');
        v_modele := TRUNC(DBMS_RANDOM.VALUE(1, 31));
        v_fab    := TRUNC(DBMS_RANDOM.VALUE(1, v_fab_cnt + 1));
        v_achat  := random_date_passee(1825);
        v_creat  := random_date_passee(1825);
        INSERT INTO ordinateurs(id, nom, numero_serie, numero_inventaire,
                                hierarchy_level_id, localisation_id, type_ordinateur_id,
                                modele_id, fabricant_id, etat_id,
                                utilisateur_id, technicien_id, site_id,
                                commentaire, est_supprime, est_template,
                                date_achat, date_creation, date_modification)
        VALUES (seq_ordinateurs.NEXTVAL,
                'FIXE-CGY-' || sa.nom || '-' || LPAD(k, 2, '0'),
                v_serie,
                'INV-FIXE-' || LPAD(v_count, 6, '0'),
                sa.hierarchy_level_id, sa.id, v_id_type_desktop,
                v_modele, v_fab, 1,
                NULL, NULL, c_site_cergy,
                'PC fixe de salle TP',
                0, 0, v_achat, v_creat, SYSDATE);
      END LOOP;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  PC fixes (Cauchy etage 2) : ' || v_count);
  END peupler_pc_fixes_cauchy;

  PROCEDURE peupler_pc_portables IS
    v_id_type_laptop NUMBER;
    v_count          NUMBER := 0;
    v_fab_cnt        NUMBER := v_fabricants.COUNT;
    v_serie          VARCHAR2(50);
    v_modele         NUMBER;
    v_fab            NUMBER;
    v_etat           NUMBER;
    v_supprime       NUMBER;
    v_achat          DATE;
    v_creat          DATE;
    CURSOR c_users IS
      SELECT id, site_id, hierarchy_level_id, localisation_id, nom AS user_nom, prenom
        FROM utilisateurs
       WHERE est_supprime = 0;
  BEGIN
    SELECT id INTO v_id_type_laptop
      FROM types_ordinateur WHERE machine_type = 'Laptop' AND ROWNUM = 1;

    FOR u IN c_users LOOP
      v_count    := v_count + 1;
      v_serie    := random_serial('SN-LT');
      v_modele   := TRUNC(DBMS_RANDOM.VALUE(1, 31));
      v_fab      := TRUNC(DBMS_RANDOM.VALUE(1, v_fab_cnt + 1));
      v_etat     := CASE WHEN DBMS_RANDOM.VALUE < 0.93 THEN 1 ELSE 3 END;
      v_supprime := CASE WHEN DBMS_RANDOM.VALUE < 0.02 THEN 1 ELSE 0 END;
      v_achat    := random_date_passee(1825);
      v_creat    := random_date_passee(1825);
      INSERT INTO ordinateurs(id, nom, numero_serie, numero_inventaire,
                              hierarchy_level_id, localisation_id, type_ordinateur_id,
                              modele_id, fabricant_id, etat_id,
                              utilisateur_id, technicien_id, site_id,
                              commentaire, est_supprime, est_template,
                              date_achat, date_creation, date_modification)
      VALUES (seq_ordinateurs.NEXTVAL,
              'LT-' || CASE u.site_id WHEN 1 THEN 'CGY' ELSE 'PAU' END
                 || '-' || LPAD(v_count, 5, '0'),
              v_serie,
              'INV-LT-' || LPAD(v_count, 6, '0'),
              u.hierarchy_level_id, u.localisation_id, v_id_type_laptop,
              v_modele, v_fab, v_etat,
              u.id, NULL, u.site_id,
              'Portable affecte a ' || u.prenom || ' ' || u.user_nom,
              v_supprime, 0, v_achat, v_creat, SYSDATE);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  PC portables (1 par utilisateur) : ' || v_count);
  END peupler_pc_portables;

  -- ---------------------------------------------------------------------------
  -- 7) PERIPHERIQUES : souris+clavier des PC fixes + videoprojs + imprimantes
  -- ---------------------------------------------------------------------------
  PROCEDURE peupler_peripheriques IS
    v_id_fab_logitech  NUMBER;
    v_id_fab_epson     NUMBER;
    v_id_fab_brother   NUMBER;
    v_count_periph     NUMBER := 0;

    -- Curseurs explicites pour parcourir le materiel a accessoiriser
    CURSOR c_pc_fixes IS
      SELECT id, nom, hierarchy_level_id, localisation_id, site_id
        FROM ordinateurs
       WHERE nom LIKE 'FIXE-%';

    CURSOR c_salles IS
      SELECT id, nom, hierarchy_level_id
        FROM localisations
       WHERE salle IS NOT NULL;  -- salles = lignes avec champ salle non null

    CURSOR c_etages IS  -- une "ligne" par etage par batiment (pour les imprimantes)
      SELECT DISTINCT batiment, etage,
             (SELECT MIN(l2.id) FROM localisations l2
              WHERE l2.batiment = l.batiment AND l2.etage = l.etage
                AND l2.salle IS NOT NULL) AS sample_id
        FROM localisations l
       WHERE etage IS NOT NULL;
  BEGIN
    SELECT id INTO v_id_fab_logitech FROM fabricants WHERE nom = 'Logitech' AND ROWNUM = 1;
    SELECT id INTO v_id_fab_epson    FROM fabricants WHERE nom = 'Epson'    AND ROWNUM = 1;
    SELECT id INTO v_id_fab_brother  FROM fabricants WHERE nom = 'Brother'  AND ROWNUM = 1;

    -- a) Pour chaque PC fixe : 1 souris + 1 clavier
    FOR pc IN c_pc_fixes LOOP
      INSERT INTO peripheriques(id, nom, numero_serie, type_peripherique,
                                hierarchy_level_id, localisation_id, fabricant_id,
                                etat_id, utilisateur_id, site_id,
                                commentaire, est_supprime,
                                date_creation, date_modification)
      VALUES (seq_peripheriques.NEXTVAL,
              'Souris-' || pc.nom, random_serial('SR'), 'souris',
              pc.hierarchy_level_id, pc.localisation_id, v_id_fab_logitech,
              1, NULL, pc.site_id,
              'Souris du PC fixe ' || pc.nom, 0,
              random_date_passee(1825), SYSDATE);
      v_count_periph := v_count_periph + 1;

      INSERT INTO peripheriques(id, nom, numero_serie, type_peripherique,
                                hierarchy_level_id, localisation_id, fabricant_id,
                                etat_id, utilisateur_id, site_id,
                                commentaire, est_supprime,
                                date_creation, date_modification)
      VALUES (seq_peripheriques.NEXTVAL,
              'Clavier-' || pc.nom, random_serial('KB'), 'clavier',
              pc.hierarchy_level_id, pc.localisation_id, v_id_fab_logitech,
              1, NULL, pc.site_id,
              'Clavier du PC fixe ' || pc.nom, 0,
              random_date_passee(1825), SYSDATE);
      v_count_periph := v_count_periph + 1;
    END LOOP;

    -- b) 1 videoprojecteur par salle
    DECLARE
      v_site_id NUMBER;
      v_etat    NUMBER;
      v_serie   VARCHAR2(50);
      v_creat   DATE;
    BEGIN
      FOR sa IN c_salles LOOP
        -- On lit le site via le hierarchy_level pour eviter de se planter sur Bureau_PAU_*
        SELECT site_id INTO v_site_id FROM hierarchy_level WHERE id = sa.hierarchy_level_id;
        v_etat  := CASE WHEN DBMS_RANDOM.VALUE < 0.95 THEN 1 ELSE 3 END;
        v_serie := random_serial('VP');
        v_creat := random_date_passee(1825);
        INSERT INTO peripheriques(id, nom, numero_serie, type_peripherique,
                                  hierarchy_level_id, localisation_id, fabricant_id,
                                  etat_id, utilisateur_id, site_id,
                                  commentaire, est_supprime,
                                  date_creation, date_modification)
        VALUES (seq_peripheriques.NEXTVAL,
                'VP-' || sa.nom, v_serie, 'videoprojecteur',
                sa.hierarchy_level_id, sa.id, v_id_fab_epson,
                v_etat, NULL, v_site_id,
                'Videoprojecteur de salle', 0, v_creat, SYSDATE);
        v_count_periph := v_count_periph + 1;
      END LOOP;
    END;

    -- c) 1 imprimante par etage
    DECLARE
      v_hl_id   NUMBER;
      v_site_id NUMBER;
      v_serie   VARCHAR2(50);
      v_creat   DATE;
    BEGIN
      FOR et IN c_etages LOOP
        SELECT hierarchy_level_id INTO v_hl_id FROM localisations WHERE id = et.sample_id;
        SELECT site_id INTO v_site_id FROM hierarchy_level WHERE id = v_hl_id;
        v_serie := random_serial('PRT');
        v_creat := random_date_passee(1825);
        INSERT INTO peripheriques(id, nom, numero_serie, type_peripherique,
                                  hierarchy_level_id, localisation_id, fabricant_id,
                                  etat_id, utilisateur_id, site_id,
                                  commentaire, est_supprime,
                                  date_creation, date_modification)
        VALUES (seq_peripheriques.NEXTVAL,
                'Imprimante-' || et.batiment || et.etage,
                v_serie, 'imprimante',
                v_hl_id, et.sample_id, v_id_fab_brother,
                1, NULL, v_site_id,
                'Imprimante partagee etage ' || et.etage || ' batiment ' || et.batiment, 0,
                v_creat, SYSDATE);
        v_count_periph := v_count_periph + 1;
      END LOOP;
    END;

    DBMS_OUTPUT.PUT_LINE('  Peripheriques : ' || v_count_periph);
  END peupler_peripheriques;

  -- ---------------------------------------------------------------------------
  -- 8) TELEPHONES FIXES : 1 par utilisateur du service Administration
  -- ---------------------------------------------------------------------------
  PROCEDURE peupler_telephones IS
    v_count   NUMBER := 0;
    v_fab_cnt NUMBER := v_fabricants.COUNT;
    v_serie   VARCHAR2(50);
    v_tel     VARCHAR2(50);
    v_fab     NUMBER;
    v_creat   DATE;
    CURSOR c_admins IS
      SELECT id, nom, prenom, hierarchy_level_id, localisation_id, site_id
        FROM utilisateurs
       WHERE profil_id = c_prof_administ AND est_supprime = 0;
  BEGIN
    FOR u IN c_admins LOOP
      v_count := v_count + 1;
      v_serie := random_serial('TEL');
      v_tel   := CASE WHEN u.site_id = c_site_cergy THEN '0134' ELSE '0559' END
                 || LPAD(TRUNC(DBMS_RANDOM.VALUE(0, 1000000)), 6, '0');
      v_fab   := TRUNC(DBMS_RANDOM.VALUE(1, v_fab_cnt + 1));
      v_creat := random_date_passee(1825);
      INSERT INTO telephones(id, nom, numero_serie, numero_tel, type_telephone,
                             hierarchy_level_id, localisation_id, fabricant_id, etat_id,
                             utilisateur_id, site_id, service, est_supprime,
                             date_creation, date_modification)
      VALUES (seq_telephones.NEXTVAL,
              'Tel-Admin-' || LPAD(v_count, 3, '0'),
              v_serie, v_tel, 'fixe',
              u.hierarchy_level_id, u.localisation_id, v_fab, 1,
              u.id, u.site_id, 'administration', 0,
              v_creat, SYSDATE);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Telephones fixes (admins) : ' || v_count);
  END peupler_telephones;

  -- ---------------------------------------------------------------------------
  -- 9) LOGICIELS + VERSIONS + INSTALLATIONS
  -- ---------------------------------------------------------------------------
  PROCEDURE peupler_logiciels IS
    v_log_cnt  NUMBER := v_logiciels.COUNT;
    v_fab_cnt  NUMBER := v_fabricants.COUNT;
    v_etat_cnt NUMBER := v_etats_lib.COUNT;
    v_log_nom  VARCHAR2(255);
    v_editeur  VARCHAR2(255);
    v_fab      NUMBER;
    v_creat    DATE;
    v_etat     NUMBER;
    v_ver_nom  VARCHAR2(50);
    v_nb_ver   NUMBER;
  BEGIN
    FOR i IN 1..v_log_cnt LOOP
      v_log_nom := v_logiciels(i);
      v_editeur := v_fabricants(TRUNC(DBMS_RANDOM.VALUE(1, v_fab_cnt + 1)));
      v_fab     := TRUNC(DBMS_RANDOM.VALUE(1, v_fab_cnt + 1));
      v_creat   := random_date_passee(1825);
      INSERT INTO logiciels(id, nom, editeur, fabricant_id, hierarchy_level_id, est_supprime,
                            date_creation, date_modification)
      VALUES (seq_logiciels.NEXTVAL, v_log_nom, v_editeur, v_fab,
              1, 0, v_creat, SYSDATE);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Logiciels : ' || v_log_cnt);

    FOR rec IN (SELECT id FROM logiciels) LOOP
      v_nb_ver := TRUNC(DBMS_RANDOM.VALUE(2, 6));
      FOR v IN 1..v_nb_ver LOOP
        v_ver_nom := 'v' || v || '.' || TRUNC(DBMS_RANDOM.VALUE(0, 10));
        v_etat    := TRUNC(DBMS_RANDOM.VALUE(1, v_etat_cnt + 1));
        v_creat   := random_date_passee(1095);
        INSERT INTO versions_logiciel(id, nom, logiciel_id, etat_id, date_creation)
        VALUES (seq_versions_logiciel.NEXTVAL, v_ver_nom, rec.id, v_etat, v_creat);
      END LOOP;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Versions logiciel : creees');
  END peupler_logiciels;

  PROCEDURE peupler_installations IS
    v_count NUMBER := 0;
    CURSOR c_ordi IS SELECT id FROM ordinateurs WHERE est_supprime = 0;
    v_max_version NUMBER;
  BEGIN
    SELECT NVL(MAX(id), 1) INTO v_max_version FROM versions_logiciel;

    FOR rec IN c_ordi LOOP
      FOR k IN 1..TRUNC(DBMS_RANDOM.VALUE(2, 5)) LOOP
        BEGIN
          INSERT INTO installations_logiciels(id, ordinateur_id, version_logiciel_id,
                                              date_installation)
          VALUES (seq_install_logiciels.NEXTVAL, rec.id,
                  TRUNC(DBMS_RANDOM.VALUE(1, v_max_version + 1)),
                  random_date_passee(730));
          v_count := v_count + 1;
        EXCEPTION
          WHEN DUP_VAL_ON_INDEX THEN NULL;
        END;
      END LOOP;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Installations logiciels : ' || v_count);
  END peupler_installations;

  -- ---------------------------------------------------------------------------
  -- 10) RESEAU : 1 switch + 1 routeur WiFi par salle + 1 borne WiFi par etage
  --     Switchs : 48 ports chacun
  -- ---------------------------------------------------------------------------
  PROCEDURE peupler_reseau IS
    v_id_type_switch  NUMBER;
    v_id_type_routeur NUMBER;
    v_id_type_borne   NUMBER;
    v_id_fab_cisco    NUMBER;
    v_id_fab_aruba    NUMBER;
    v_id_fab_ubiquiti NUMBER;
    v_count_equip     NUMBER := 0;
    v_count_ports     NUMBER := 0;
    v_id_equip        NUMBER;

    -- Curseur 1 : toutes les salles (1 switch + 1 routeur WiFi par salle)
    CURSOR c_salles IS
      SELECT id, nom, hierarchy_level_id, batiment, etage,
             (SELECT site_id FROM hierarchy_level WHERE id = l.hierarchy_level_id) AS site_id
        FROM localisations l
       WHERE salle IS NOT NULL
         AND nom NOT LIKE 'Bureau_%';  -- pas les bureaux

    -- Curseur 2 : 1 etage = 1 borne WiFi (on prend une salle sample par etage)
    CURSOR c_etages IS
      SELECT DISTINCT batiment, etage,
             (SELECT MIN(l2.id) FROM localisations l2
              WHERE l2.batiment = l.batiment AND l2.etage = l.etage
                AND l2.salle IS NOT NULL AND l2.nom NOT LIKE 'Bureau_%') AS sample_id,
             (SELECT site_id FROM hierarchy_level e
              JOIN localisations l3 ON l3.hierarchy_level_id = e.id
              WHERE l3.batiment = l.batiment AND ROWNUM = 1) AS site_id
        FROM localisations l
       WHERE etage IS NOT NULL;
  BEGIN
    -- Types d'equipement
    DECLARE v_nom VARCHAR2(100);
    BEGIN
      FOR i IN 1..3 LOOP
        v_nom := v_types_equip(i);
        INSERT INTO types_equip_reseau(id, nom)
        VALUES (seq_types_equip_reseau.NEXTVAL, v_nom);
      END LOOP;
    END;

    SELECT id INTO v_id_type_switch
      FROM types_equip_reseau WHERE nom = 'Switch' AND ROWNUM = 1;
    SELECT id INTO v_id_type_routeur
      FROM types_equip_reseau WHERE nom = 'Routeur WiFi' AND ROWNUM = 1;
    SELECT id INTO v_id_type_borne
      FROM types_equip_reseau WHERE nom = 'Borne WiFi' AND ROWNUM = 1;

    SELECT id INTO v_id_fab_cisco    FROM fabricants WHERE nom = 'Cisco'    AND ROWNUM = 1;
    SELECT id INTO v_id_fab_aruba    FROM fabricants WHERE nom = 'Aruba'    AND ROWNUM = 1;
    SELECT id INTO v_id_fab_ubiquiti FROM fabricants WHERE nom = 'Ubiquiti' AND ROWNUM = 1;

    DBMS_OUTPUT.PUT_LINE('  Types equip reseau : ' || 3);

    -- 1 switch + 1 routeur WiFi par salle
    FOR sa IN c_salles LOOP
      -- Switch
      v_count_equip := v_count_equip + 1;
      INSERT INTO equipements_reseau(id, nom, numero_serie, hierarchy_level_id,
                                     localisation_id, type_equip_id,
                                     fabricant_id, etat_id, site_id,
                                     nb_ports, commentaire, est_supprime,
                                     date_creation, date_modification)
      VALUES (seq_equip_reseau.NEXTVAL,
              'SW-' || CASE sa.site_id WHEN 1 THEN 'CGY' ELSE 'PAU' END
                || '-' || sa.batiment || '-' || sa.nom,
              random_serial('NET-SW'),
              sa.hierarchy_level_id, sa.id,
              v_id_type_switch, v_id_fab_cisco, 1,
              sa.site_id, 48,
              'Switch d acces salle ' || sa.nom, 0,
              random_date_passee(1825), SYSDATE)
      RETURNING id INTO v_id_equip;

      -- Ses 48 ports
      FOR p IN 1..48 LOOP
        INSERT INTO ports_reseau(id, nom, equipement_id, adresse_mac, type_port,
                                 vitesse, est_actif, date_creation, date_modification)
        VALUES (seq_ports_reseau.NEXTVAL,
                'Port-' || LPAD(p, 2, '0'),
                v_id_equip,
                random_mac(),
                'ethernet',
                CASE TRUNC(DBMS_RANDOM.VALUE(0, 3))
                  WHEN 0 THEN 100 WHEN 1 THEN 1000 ELSE 10000 END,
                CASE WHEN DBMS_RANDOM.VALUE < 0.75 THEN 1 ELSE 0 END,
                random_date_passee(1825), SYSDATE);
        v_count_ports := v_count_ports + 1;
      END LOOP;

      -- Routeur WiFi de la salle (pas de "ports" comme un switch, on n'en cree pas)
      v_count_equip := v_count_equip + 1;
      INSERT INTO equipements_reseau(id, nom, numero_serie, hierarchy_level_id,
                                     localisation_id, type_equip_id,
                                     fabricant_id, etat_id, site_id,
                                     nb_ports, commentaire, est_supprime,
                                     date_creation, date_modification)
      VALUES (seq_equip_reseau.NEXTVAL,
              'RTW-' || CASE sa.site_id WHEN 1 THEN 'CGY' ELSE 'PAU' END
                || '-' || sa.batiment || '-' || sa.nom,
              random_serial('NET-RTW'),
              sa.hierarchy_level_id, sa.id,
              v_id_type_routeur, v_id_fab_aruba, 1,
              sa.site_id, 4,
              'Routeur WiFi de la salle ' || sa.nom, 0,
              random_date_passee(1825), SYSDATE);
    END LOOP;

    -- 1 borne WiFi centralisee par etage
    FOR et IN c_etages LOOP
      v_count_equip := v_count_equip + 1;
      INSERT INTO equipements_reseau(id, nom, numero_serie, hierarchy_level_id,
                                     localisation_id, type_equip_id,
                                     fabricant_id, etat_id, site_id,
                                     nb_ports, commentaire, est_supprime,
                                     date_creation, date_modification)
      VALUES (seq_equip_reseau.NEXTVAL,
              'AP-' || CASE et.site_id WHEN 1 THEN 'CGY' ELSE 'PAU' END
                || '-' || et.batiment || '-Et' || et.etage,
              random_serial('NET-AP'),
              (SELECT hierarchy_level_id FROM localisations WHERE id = et.sample_id),
              et.sample_id,
              v_id_type_borne, v_id_fab_ubiquiti, 1,
              et.site_id, 0,
              'Borne WiFi etage ' || et.etage || ' batiment ' || et.batiment, 0,
              random_date_passee(1825), SYSDATE);
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('  Equipements reseau : ' || v_count_equip
      || ' (switchs + routeurs WiFi + bornes)');
    DBMS_OUTPUT.PUT_LINE('  Ports reseau : ' || v_count_ports);
  END peupler_reseau;

  -- ---------------------------------------------------------------------------
  -- ORCHESTRATION
  -- ---------------------------------------------------------------------------
  PROCEDURE generer_tout(
    p_nb_etudiants  NUMBER DEFAULT 2500,
    p_nb_profs      NUMBER DEFAULT 80,
    p_nb_admins     NUMBER DEFAULT 30,
    p_nb_techs      NUMBER DEFAULT 10
  ) IS
    v_t_start TIMESTAMP;
  BEGIN
    v_t_start := SYSTIMESTAMP;
    DBMS_OUTPUT.PUT_LINE('===== Generation du jeu de test CY Tech =====');

    init_referentiels;

    -- 1) Referentiels
    peupler_sites;
    peupler_hierarchy_level;
    peupler_localisations;
    peupler_fabricants;
    peupler_etats;
    peupler_types_ordi;
    peupler_modeles;
    peupler_profils;
    peupler_groupes;

    -- 2) Utilisateurs (2620 par defaut, repartis par profil)
    peupler_utilisateurs(p_nb_etudiants, p_nb_profs, p_nb_admins, p_nb_techs);

    -- 3) Materiel
    peupler_pc_fixes_cauchy;   -- 140 PC fixes a Cauchy etage 2
    peupler_pc_portables;       -- 1 portable par utilisateur
    peupler_peripheriques;      -- souris+clavier+videoprojs+imprimantes
    peupler_telephones;         -- 30 fixes (admins)
    peupler_logiciels;
    peupler_installations;

    -- 4) Reseau (switchs, routeurs WiFi, bornes WiFi)
    peupler_reseau;

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('===== Termine en ' ||
      EXTRACT(SECOND FROM (SYSTIMESTAMP - v_t_start)) || ' s =====');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('ERREUR : ' || SQLERRM);
      RAISE;
  END generer_tout;

  PROCEDURE reset_donnees IS
  BEGIN
    -- ordre inverse des FK
    DELETE FROM historique;
    DELETE FROM installations_logiciels;
    DELETE FROM versions_logiciel;
    DELETE FROM logiciels;
    DELETE FROM ports_reseau;
    DELETE FROM equipements_reseau;
    DELETE FROM types_equip_reseau;
    DELETE FROM telephones;
    DELETE FROM peripheriques;
    DELETE FROM ordinateurs;
    DELETE FROM groupes;
    DELETE FROM utilisateurs;
    DELETE FROM profils;
    DELETE FROM modeles_ordinateur;
    DELETE FROM types_ordinateur;
    DELETE FROM etats;
    DELETE FROM fabricants;
    DELETE FROM localisations;
    DELETE FROM hierarchy_level;
    DELETE FROM sites;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Donnees supprimees.');
  END reset_donnees;

END pkg_jeu_test;
/

-- -----------------------------------------------------------------------------
-- EXECUTION
-- -----------------------------------------------------------------------------
-- Pour generer le jeu de test par defaut (structure CY Tech reelle) :
--   EXEC pkg_jeu_test.generer_tout;
--
-- Pour augmenter les volumes (tests de perf) :
--   EXEC pkg_jeu_test.generer_tout(p_nb_etudiants => 10000, p_nb_profs => 200);
--
-- Pour repartir de zero :
--   EXEC pkg_jeu_test.reset_donnees;
-- -----------------------------------------------------------------------------

BEGIN
  pkg_jeu_test.generer_tout;
END;
/
