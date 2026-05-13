-- =============================================================================
-- JEU DE TEST PL/SQL — Projet GLPI CY Tech multi-sites
-- =============================================================================
-- Genere un volume representatif pour valider les performances de la BDD.
-- Volumes par defaut :
--   - 2 sites, 11 entites, 60 localisations
--   - 20 fabricants, 8 etats, 5 types ordi, 30 modeles
--   - 5 profils, 20 groupes
--   - 800 utilisateurs
--   - 1500 ordinateurs, 1500 peripheriques, 200 telephones
--   - 50 logiciels, 150 versions, ~5000 installations
--   - 5 types equip reseau, 100 equipements reseau, ~2000 ports reseau
--
-- Utilise : procedures, fonctions, curseurs explicites, DBMS_RANDOM, boucles FOR.
-- A executer en tant que ADMIN_CYTECH (apres bdd_Cy_infrastructure.sql).
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD';

-- -----------------------------------------------------------------------------
-- SPECIFICATION DU PACKAGE
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_jeu_test AS

  -- Procedure maitresse : remplit toutes les tables dans le bon ordre
  PROCEDURE generer_tout(
    p_nb_users         NUMBER DEFAULT 800,
    p_nb_ordinateurs   NUMBER DEFAULT 1500,
    p_nb_peripheriques NUMBER DEFAULT 1500,
    p_nb_telephones    NUMBER DEFAULT 200,
    p_nb_equip_reseau  NUMBER DEFAULT 100
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

  -- Tableaux de noms de reference pour rendre les donnees realistes
  TYPE t_str_array IS TABLE OF VARCHAR2(100) INDEX BY PLS_INTEGER;

  v_prenoms     t_str_array;
  v_noms        t_str_array;
  v_fabricants  t_str_array;
  v_etats_lib   t_str_array;
  v_types_ordi  t_str_array;
  v_types_periph t_str_array;
  v_types_equip t_str_array;
  v_logiciels   t_str_array;
  v_os          t_str_array;

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
      v_mac := v_mac ||
               LPAD(TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(0, 256)), 'FM0X'), 2, '0');
      IF i < 6 THEN v_mac := v_mac || ':'; END IF;
    END LOOP;
    RETURN v_mac;
  END;

  FUNCTION random_serial(p_prefix VARCHAR2 DEFAULT 'SN') RETURN VARCHAR2 IS
  BEGIN
    RETURN p_prefix || '-' ||
           TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(100000, 999999))) ||
           '-' || random_string(3);
  END;

  FUNCTION random_date_passee(p_jours_max NUMBER DEFAULT 1825) RETURN DATE IS
  BEGIN
    RETURN SYSDATE - TRUNC(DBMS_RANDOM.VALUE(0, p_jours_max));
  END;

  -- Tire un id aleatoire dans une table en utilisant la valeur courante de sa seq
  FUNCTION random_id(p_seq_name VARCHAR2) RETURN NUMBER IS
    v_max NUMBER;
  BEGIN
    EXECUTE IMMEDIATE 'SELECT ' || p_seq_name || '.CURRVAL FROM dual' INTO v_max;
    RETURN TRUNC(DBMS_RANDOM.VALUE(1, v_max + 1));
  END;

  -- ---------------------------------------------------------------------------
  -- INITIALISATION DES TABLEAUX DE REFERENCE
  -- ---------------------------------------------------------------------------
  PROCEDURE init_referentiels IS
  BEGIN
    v_prenoms(1) := 'Alice';     v_prenoms(2) := 'Bob';      v_prenoms(3) := 'Camille';
    v_prenoms(4) := 'David';     v_prenoms(5) := 'Elena';    v_prenoms(6) := 'Florent';
    v_prenoms(7) := 'Gabriel';   v_prenoms(8) := 'Helene';   v_prenoms(9) := 'Ivan';
    v_prenoms(10):= 'Julie';     v_prenoms(11):= 'Karim';    v_prenoms(12):= 'Lucie';
    v_prenoms(13):= 'Mathieu';   v_prenoms(14):= 'Nadia';    v_prenoms(15):= 'Olivier';
    v_prenoms(16):= 'Pauline';   v_prenoms(17):= 'Quentin';  v_prenoms(18):= 'Rachel';
    v_prenoms(19):= 'Samir';     v_prenoms(20):= 'Theo';

    v_noms(1) := 'Martin';   v_noms(2) := 'Bernard';  v_noms(3) := 'Dubois';
    v_noms(4) := 'Petit';    v_noms(5) := 'Robert';   v_noms(6) := 'Richard';
    v_noms(7) := 'Durand';   v_noms(8) := 'Moreau';   v_noms(9) := 'Laurent';
    v_noms(10):= 'Simon';    v_noms(11):= 'Michel';   v_noms(12):= 'Lefevre';
    v_noms(13):= 'Leroy';    v_noms(14):= 'Roux';     v_noms(15):= 'David';
    v_noms(16):= 'Bertrand'; v_noms(17):= 'Morel';    v_noms(18):= 'Fournier';
    v_noms(19):= 'Girard';   v_noms(20):= 'Bonnet';

    v_fabricants(1) := 'Dell';      v_fabricants(2) := 'HP';        v_fabricants(3) := 'Lenovo';
    v_fabricants(4) := 'Apple';     v_fabricants(5) := 'Asus';      v_fabricants(6) := 'Acer';
    v_fabricants(7) := 'Cisco';     v_fabricants(8) := 'Aruba';     v_fabricants(9) := 'Ubiquiti';
    v_fabricants(10):= 'Netgear';   v_fabricants(11):= 'Logitech';  v_fabricants(12):= 'Microsoft';
    v_fabricants(13):= 'Samsung';   v_fabricants(14):= 'LG';        v_fabricants(15):= 'BenQ';
    v_fabricants(16):= 'Epson';     v_fabricants(17):= 'Brother';   v_fabricants(18):= 'Canon';
    v_fabricants(19):= 'Razer';     v_fabricants(20):= 'MSI';

    v_etats_lib(1) := 'En service';
    v_etats_lib(2) := 'En stock';
    v_etats_lib(3) := 'En reparation';
    v_etats_lib(4) := 'Reforme';
    v_etats_lib(5) := 'En commande';
    v_etats_lib(6) := 'En pret';
    v_etats_lib(7) := 'Hors service';
    v_etats_lib(8) := 'En test';

    v_types_ordi(1) := 'Desktop';
    v_types_ordi(2) := 'Laptop';
    v_types_ordi(3) := 'Serveur';
    v_types_ordi(4) := 'Workstation';
    v_types_ordi(5) := 'Tablette';

    v_types_periph(1) := 'imprimante';
    v_types_periph(2) := 'souris';
    v_types_periph(3) := 'clavier';
    v_types_periph(4) := 'videoprojecteur';
    v_types_periph(5) := 'ecran';
    v_types_periph(6) := 'autre';

    v_types_equip(1) := 'Switch';
    v_types_equip(2) := 'Routeur';
    v_types_equip(3) := 'Point d acces WiFi';
    v_types_equip(4) := 'Firewall';
    v_types_equip(5) := 'Borne IoT';

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
  -- PROCEDURES DE REMPLISSAGE PAR DOMAINE
  -- ---------------------------------------------------------------------------

  PROCEDURE peupler_sites IS
  BEGIN
    INSERT INTO sites(id, nom, adresse, ville, code_postal, telephone)
    VALUES (seq_sites.NEXTVAL, 'CY Tech Cergy', '95 rue de Sevres', 'Cergy', '95000', '0134256900');
    INSERT INTO sites(id, nom, adresse, ville, code_postal, telephone)
    VALUES (seq_sites.NEXTVAL, 'CY Tech Pau',   '2 avenue de l Universite', 'Pau', '64000', '0559405800');
    DBMS_OUTPUT.PUT_LINE('  Sites : 2');
  END peupler_sites;

  PROCEDURE peupler_entites IS
    v_id_racine NUMBER;
    v_id_cergy  NUMBER;
    v_id_pau    NUMBER;
  BEGIN
    -- Racine
    INSERT INTO entites(id, nom, entite_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_entites.NEXTVAL, 'CY Tech', NULL, 1, 0, 'CY Tech')
    RETURNING id INTO v_id_racine;

    -- Sites
    INSERT INTO entites(id, nom, entite_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_entites.NEXTVAL, 'Cergy', v_id_racine, 1, 1, 'CY Tech > Cergy')
    RETURNING id INTO v_id_cergy;

    INSERT INTO entites(id, nom, entite_parent_id, site_id, niveau, nom_complet)
    VALUES (seq_entites.NEXTVAL, 'Pau', v_id_racine, 2, 1, 'CY Tech > Pau')
    RETURNING id INTO v_id_pau;

    -- Sous-entites Cergy
    FOR nom_ent IN (SELECT 'Direction' AS n FROM dual UNION ALL
                    SELECT 'Informatique' FROM dual UNION ALL
                    SELECT 'Mecanique' FROM dual UNION ALL
                    SELECT 'Genie Civil' FROM dual)
    LOOP
      INSERT INTO entites(id, nom, entite_parent_id, site_id, niveau, nom_complet)
      VALUES (seq_entites.NEXTVAL, nom_ent.n, v_id_cergy, 1, 2,
              'CY Tech > Cergy > ' || nom_ent.n);
    END LOOP;

    -- Sous-entites Pau
    FOR nom_ent IN (SELECT 'Direction' AS n FROM dual UNION ALL
                    SELECT 'Informatique' FROM dual UNION ALL
                    SELECT 'Biotechnologie' FROM dual)
    LOOP
      INSERT INTO entites(id, nom, entite_parent_id, site_id, niveau, nom_complet)
      VALUES (seq_entites.NEXTVAL, nom_ent.n, v_id_pau, 2, 2,
              'CY Tech > Pau > ' || nom_ent.n);
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('  Entites : 9');
  END peupler_entites;

  PROCEDURE peupler_localisations IS
    v_site NUMBER;
    v_ent  NUMBER;
  BEGIN
    -- 30 salles par site (3 batiments x 10 salles)
    FOR s IN 1..2 LOOP
      FOR b IN 1..3 LOOP
        FOR sa IN 1..10 LOOP
          -- on rattache a une entite du meme site (id 2 = Cergy, 3 = Pau, ou sous-entites)
          v_ent := CASE WHEN s = 1 THEN TRUNC(DBMS_RANDOM.VALUE(2, 8))
                        ELSE TRUNC(DBMS_RANDOM.VALUE(8, 10)) END;
          INSERT INTO localisations(id, nom, nom_complet, entite_id, batiment, salle, etage)
          VALUES (seq_localisations.NEXTVAL,
                  'Salle ' || b || sa,
                  'Site ' || s || ' > Bat ' || CHR(64 + b) || ' > Salle ' || b || sa,
                  v_ent,
                  'Batiment ' || CHR(64 + b),
                  TO_CHAR(b) || LPAD(sa, 2, '0'),
                  TO_CHAR(MOD(sa - 1, 4)));
        END LOOP;
      END LOOP;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Localisations : 60');
  END peupler_localisations;

  PROCEDURE peupler_fabricants IS
  BEGIN
    FOR i IN 1..v_fabricants.COUNT LOOP
      INSERT INTO fabricants(id, nom) VALUES (seq_fabricants.NEXTVAL, v_fabricants(i));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Fabricants : ' || v_fabricants.COUNT);
  END peupler_fabricants;

  PROCEDURE peupler_etats IS
  BEGIN
    FOR i IN 1..v_etats_lib.COUNT LOOP
      INSERT INTO etats(id, nom, etat) VALUES (seq_etats.NEXTVAL, v_etats_lib(i), v_etats_lib(i));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Etats : ' || v_etats_lib.COUNT);
  END peupler_etats;

  PROCEDURE peupler_types_ordi IS
  BEGIN
    FOR i IN 1..v_types_ordi.COUNT LOOP
      INSERT INTO types_ordinateur(id, machine_type)
      VALUES (seq_types_ordinateur.NEXTVAL, v_types_ordi(i));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Types ordi : ' || v_types_ordi.COUNT);
  END peupler_types_ordi;

  PROCEDURE peupler_modeles IS
  BEGIN
    FOR i IN 1..30 LOOP
      INSERT INTO modeles_ordinateur(id, nom, ref_produit, fabricant_id)
      VALUES (seq_modeles_ordinateur.NEXTVAL,
              v_fabricants(MOD(i, v_fabricants.COUNT) + 1) || ' Model ' || i,
              'REF-' || LPAD(i, 4, '0'),
              MOD(i, v_fabricants.COUNT) + 1);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Modeles : 30');
  END peupler_modeles;

  PROCEDURE peupler_profils IS
  BEGIN
    INSERT INTO profils(id, nom, interface) VALUES (seq_profils.NEXTVAL, 'Super-Admin', 'central');
    INSERT INTO profils(id, nom, interface) VALUES (seq_profils.NEXTVAL, 'Admin', 'central');
    INSERT INTO profils(id, nom, interface) VALUES (seq_profils.NEXTVAL, 'Technicien', 'central');
    INSERT INTO profils(id, nom, interface) VALUES (seq_profils.NEXTVAL, 'Observateur', 'central');
    INSERT INTO profils(id, nom, interface) VALUES (seq_profils.NEXTVAL, 'Self-Service', 'helpdesk');
    DBMS_OUTPUT.PUT_LINE('  Profils : 5');
  END peupler_profils;

  PROCEDURE peupler_groupes IS
  BEGIN
    FOR i IN 1..20 LOOP
      INSERT INTO groupes(id, nom, entite_id, est_recursif, commentaire)
      VALUES (seq_groupes.NEXTVAL,
              'Groupe ' || i,
              TRUNC(DBMS_RANDOM.VALUE(1, 10)),
              CASE WHEN MOD(i, 3) = 0 THEN 1 ELSE 0 END,
              'Groupe genere automatiquement');
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Groupes : 20');
  END peupler_groupes;

  PROCEDURE peupler_utilisateurs(p_nb NUMBER) IS
    v_prenom  VARCHAR2(100);
    v_nom     VARCHAR2(100);
    v_login   VARCHAR2(255);
    v_site    NUMBER;
  BEGIN
    FOR i IN 1..p_nb LOOP
      v_prenom := v_prenoms(TRUNC(DBMS_RANDOM.VALUE(1, v_prenoms.COUNT + 1)));
      v_nom    := v_noms(TRUNC(DBMS_RANDOM.VALUE(1, v_noms.COUNT + 1)));
      v_login  := LOWER(SUBSTR(v_prenom, 1, 1) || v_nom) || i;
      v_site   := CASE WHEN DBMS_RANDOM.VALUE < 0.7 THEN 1 ELSE 2 END; -- 70% Cergy

      INSERT INTO utilisateurs(id, login, mot_de_passe, nom, prenom, email, telephone,
                               entite_id, localisation_id, profil_id, site_id,
                               langue, est_actif, est_supprime, type_auth,
                               date_debut, date_creation, date_modification)
      VALUES (seq_utilisateurs.NEXTVAL,
              v_login,
              'hash_' || random_string(16),
              v_nom, v_prenom,
              LOWER(v_prenom) || '.' || LOWER(v_nom) || '@cytech.fr',
              '06' || LPAD(TRUNC(DBMS_RANDOM.VALUE(0, 100000000)), 8, '0'),
              CASE WHEN v_site = 1 THEN TRUNC(DBMS_RANDOM.VALUE(2, 7))
                                   ELSE TRUNC(DBMS_RANDOM.VALUE(7, 10)) END,
              TRUNC(DBMS_RANDOM.VALUE(1, 61)),
              TRUNC(DBMS_RANDOM.VALUE(1, 6)),
              v_site,
              'fr_FR',
              CASE WHEN DBMS_RANDOM.VALUE < 0.95 THEN 1 ELSE 0 END,
              CASE WHEN DBMS_RANDOM.VALUE < 0.02 THEN 1 ELSE 0 END,
              1,
              random_date_passee(2000),
              random_date_passee(2000),
              SYSDATE);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Utilisateurs : ' || p_nb);
  END peupler_utilisateurs;

  PROCEDURE peupler_profils_utilisateurs IS
    v_count NUMBER := 0;
    -- Curseur explicite : on parcourt tous les utilisateurs actifs
    CURSOR c_users IS
      SELECT id, profil_id, entite_id FROM utilisateurs WHERE est_supprime = 0;
  BEGIN
    FOR u IN c_users LOOP
      BEGIN
        INSERT INTO profils_utilisateurs(id, utilisateur_id, profil_id, entite_id,
                                          est_recursif, est_dynamique)
        VALUES (seq_profils_utilisateurs.NEXTVAL, u.id, u.profil_id, u.entite_id,
                CASE WHEN DBMS_RANDOM.VALUE < 0.3 THEN 1 ELSE 0 END,
                0);
        v_count := v_count + 1;
      EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN NULL; -- contrainte uk_profil_user_entite
      END;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Profils-Utilisateurs : ' || v_count);
  END peupler_profils_utilisateurs;

  PROCEDURE peupler_ordinateurs(p_nb NUMBER) IS
    v_site NUMBER;
  BEGIN
    FOR i IN 1..p_nb LOOP
      v_site := CASE WHEN DBMS_RANDOM.VALUE < 0.7 THEN 1 ELSE 2 END;
      INSERT INTO ordinateurs(id, nom, numero_serie, numero_inventaire,
                              entite_id, localisation_id, type_ordinateur_id,
                              modele_id, fabricant_id, etat_id,
                              utilisateur_id, technicien_id, site_id,
                              commentaire, est_supprime, est_template,
                              date_achat, date_creation, date_modification)
      VALUES (seq_ordinateurs.NEXTVAL,
              'PC-' || CASE v_site WHEN 1 THEN 'CGY' ELSE 'PAU' END || '-' || LPAD(i, 5, '0'),
              random_serial('SN'),
              'INV-' || LPAD(i, 6, '0'),
              CASE WHEN v_site = 1 THEN TRUNC(DBMS_RANDOM.VALUE(2, 7))
                                   ELSE TRUNC(DBMS_RANDOM.VALUE(7, 10)) END,
              TRUNC(DBMS_RANDOM.VALUE(1, 61)),
              TRUNC(DBMS_RANDOM.VALUE(1, v_types_ordi.COUNT + 1)),
              TRUNC(DBMS_RANDOM.VALUE(1, 31)),
              TRUNC(DBMS_RANDOM.VALUE(1, v_fabricants.COUNT + 1)),
              TRUNC(DBMS_RANDOM.VALUE(1, v_etats_lib.COUNT + 1)),
              random_id('seq_utilisateurs'),
              random_id('seq_utilisateurs'),
              v_site,
              'Poste genere automatiquement',
              CASE WHEN DBMS_RANDOM.VALUE < 0.03 THEN 1 ELSE 0 END,
              0,
              random_date_passee(1825),
              random_date_passee(1825),
              SYSDATE);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Ordinateurs : ' || p_nb);
  END peupler_ordinateurs;

  PROCEDURE peupler_peripheriques(p_nb NUMBER) IS
    v_site NUMBER;
    v_type VARCHAR2(50);
  BEGIN
    FOR i IN 1..p_nb LOOP
      v_site := CASE WHEN DBMS_RANDOM.VALUE < 0.7 THEN 1 ELSE 2 END;
      v_type := v_types_periph(TRUNC(DBMS_RANDOM.VALUE(1, v_types_periph.COUNT + 1)));
      INSERT INTO peripheriques(id, nom, numero_serie, type_peripherique,
                                 entite_id, localisation_id, fabricant_id,
                                 etat_id, utilisateur_id, site_id,
                                 commentaire, est_supprime,
                                 date_creation, date_modification)
      VALUES (seq_peripheriques.NEXTVAL,
              INITCAP(v_type) || '-' || LPAD(i, 5, '0'),
              random_serial('PER'),
              v_type,
              CASE WHEN v_site = 1 THEN TRUNC(DBMS_RANDOM.VALUE(2, 7))
                                   ELSE TRUNC(DBMS_RANDOM.VALUE(7, 10)) END,
              TRUNC(DBMS_RANDOM.VALUE(1, 61)),
              TRUNC(DBMS_RANDOM.VALUE(1, v_fabricants.COUNT + 1)),
              TRUNC(DBMS_RANDOM.VALUE(1, v_etats_lib.COUNT + 1)),
              random_id('seq_utilisateurs'),
              v_site,
              NULL,
              CASE WHEN DBMS_RANDOM.VALUE < 0.05 THEN 1 ELSE 0 END,
              random_date_passee(1825),
              SYSDATE);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Peripheriques : ' || p_nb);
  END peupler_peripheriques;

  PROCEDURE peupler_telephones(p_nb NUMBER) IS
    v_site     NUMBER;
    v_services t_str_array;
  BEGIN
    v_services(1) := 'secretariat'; v_services(2) := 'accueil';
    v_services(3) := 'direction';   v_services(4) := 'helpdesk';
    v_services(5) := 'salle prof';

    FOR i IN 1..p_nb LOOP
      v_site := CASE WHEN DBMS_RANDOM.VALUE < 0.7 THEN 1 ELSE 2 END;
      INSERT INTO telephones(id, nom, numero_serie, numero_tel, type_telephone,
                              entite_id, localisation_id, fabricant_id, etat_id,
                              utilisateur_id, site_id, service, est_supprime,
                              date_creation, date_modification)
      VALUES (seq_telephones.NEXTVAL,
              'Tel-' || LPAD(i, 4, '0'),
              random_serial('TEL'),
              '01' || LPAD(TRUNC(DBMS_RANDOM.VALUE(0, 100000000)), 8, '0'),
              CASE TRUNC(DBMS_RANDOM.VALUE(0, 3))
                WHEN 0 THEN 'fixe' WHEN 1 THEN 'mobile' ELSE 'ip' END,
              CASE WHEN v_site = 1 THEN TRUNC(DBMS_RANDOM.VALUE(2, 7))
                                   ELSE TRUNC(DBMS_RANDOM.VALUE(7, 10)) END,
              TRUNC(DBMS_RANDOM.VALUE(1, 61)),
              TRUNC(DBMS_RANDOM.VALUE(1, v_fabricants.COUNT + 1)),
              TRUNC(DBMS_RANDOM.VALUE(1, v_etats_lib.COUNT + 1)),
              random_id('seq_utilisateurs'),
              v_site,
              v_services(TRUNC(DBMS_RANDOM.VALUE(1, v_services.COUNT + 1))),
              0,
              random_date_passee(1825),
              SYSDATE);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Telephones : ' || p_nb);
  END peupler_telephones;

  PROCEDURE peupler_logiciels IS
    v_log_id NUMBER;
  BEGIN
    -- Logiciels
    FOR i IN 1..v_logiciels.COUNT LOOP
      INSERT INTO logiciels(id, nom, editeur, fabricant_id, entite_id, est_supprime,
                             date_creation, date_modification)
      VALUES (seq_logiciels.NEXTVAL, v_logiciels(i),
              v_fabricants(TRUNC(DBMS_RANDOM.VALUE(1, v_fabricants.COUNT + 1))),
              TRUNC(DBMS_RANDOM.VALUE(1, v_fabricants.COUNT + 1)),
              1, 0, random_date_passee(1825), SYSDATE);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Logiciels : ' || v_logiciels.COUNT);

    -- Versions de logiciels (3 versions par logiciel en moyenne)
    FOR rec IN (SELECT id FROM logiciels) LOOP
      FOR v IN 1..TRUNC(DBMS_RANDOM.VALUE(2, 6)) LOOP
        INSERT INTO versions_logiciel(id, nom, logiciel_id, etat_id, date_creation)
        VALUES (seq_versions_logiciel.NEXTVAL,
                'v' || v || '.' || TRUNC(DBMS_RANDOM.VALUE(0, 10)),
                rec.id,
                TRUNC(DBMS_RANDOM.VALUE(1, v_etats_lib.COUNT + 1)),
                random_date_passee(1095));
      END LOOP;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Versions logiciel : creees');
  END peupler_logiciels;

  PROCEDURE peupler_installations IS
    v_count NUMBER := 0;
    -- Curseur explicite sur les ordinateurs : chacun recoit 3 a 6 logiciels
    CURSOR c_ordi IS SELECT id FROM ordinateurs WHERE est_supprime = 0;
    v_max_version NUMBER;
  BEGIN
    SELECT NVL(MAX(id), 1) INTO v_max_version FROM versions_logiciel;

    FOR rec IN c_ordi LOOP
      FOR k IN 1..TRUNC(DBMS_RANDOM.VALUE(3, 7)) LOOP
        BEGIN
          INSERT INTO installations_logiciels(id, ordinateur_id, version_logiciel_id,
                                                date_installation)
          VALUES (seq_install_logiciels.NEXTVAL, rec.id,
                  TRUNC(DBMS_RANDOM.VALUE(1, v_max_version + 1)),
                  random_date_passee(730));
          v_count := v_count + 1;
        EXCEPTION
          WHEN DUP_VAL_ON_INDEX THEN NULL; -- meme couple (ordi, version) deja installe
        END;
      END LOOP;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Installations logiciels : ' || v_count);
  END peupler_installations;

  PROCEDURE peupler_reseau(p_nb_equip NUMBER) IS
    v_site         NUMBER;
    v_nb_ports     NUMBER;
    v_count_ports  NUMBER := 0;
    v_id_equip     NUMBER;
  BEGIN
    -- Types d'equipement
    FOR i IN 1..v_types_equip.COUNT LOOP
      INSERT INTO types_equip_reseau(id, nom)
      VALUES (seq_types_equip_reseau.NEXTVAL, v_types_equip(i));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Types equip reseau : ' || v_types_equip.COUNT);

    -- Equipements + leurs ports (boucle imbriquee : un equipement a 16 a 48 ports)
    FOR i IN 1..p_nb_equip LOOP
      v_site := CASE WHEN DBMS_RANDOM.VALUE < 0.7 THEN 1 ELSE 2 END;
      v_nb_ports := TRUNC(DBMS_RANDOM.VALUE(16, 49));
      INSERT INTO equipements_reseau(id, nom, numero_serie, entite_id,
                                      localisation_id, type_equip_id,
                                      fabricant_id, etat_id, site_id,
                                      nb_ports, commentaire, est_supprime,
                                      date_creation, date_modification)
      VALUES (seq_equip_reseau.NEXTVAL,
              CASE v_site WHEN 1 THEN 'EQR-CGY-' ELSE 'EQR-PAU-' END || LPAD(i, 4, '0'),
              random_serial('NET'),
              CASE WHEN v_site = 1 THEN TRUNC(DBMS_RANDOM.VALUE(2, 7))
                                   ELSE TRUNC(DBMS_RANDOM.VALUE(7, 10)) END,
              TRUNC(DBMS_RANDOM.VALUE(1, 61)),
              TRUNC(DBMS_RANDOM.VALUE(1, v_types_equip.COUNT + 1)),
              TRUNC(DBMS_RANDOM.VALUE(1, v_fabricants.COUNT + 1)),
              TRUNC(DBMS_RANDOM.VALUE(1, v_etats_lib.COUNT + 1)),
              v_site, v_nb_ports, NULL, 0,
              random_date_passee(1825), SYSDATE)
      RETURNING id INTO v_id_equip;

      FOR p IN 1..v_nb_ports LOOP
        INSERT INTO ports_reseau(id, nom, equipement_id, adresse_mac, type_port,
                                  vitesse, est_actif, date_creation, date_modification)
        VALUES (seq_ports_reseau.NEXTVAL,
                'Port-' || LPAD(p, 2, '0'),
                v_id_equip,
                random_mac(),
                CASE WHEN DBMS_RANDOM.VALUE < 0.85 THEN 'ethernet' ELSE 'wifi' END,
                CASE TRUNC(DBMS_RANDOM.VALUE(0, 4))
                  WHEN 0 THEN 100 WHEN 1 THEN 1000
                  WHEN 2 THEN 2500 ELSE 10000 END,
                CASE WHEN DBMS_RANDOM.VALUE < 0.9 THEN 1 ELSE 0 END,
                random_date_passee(1825), SYSDATE);
        v_count_ports := v_count_ports + 1;
      END LOOP;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  Equipements reseau : ' || p_nb_equip);
    DBMS_OUTPUT.PUT_LINE('  Ports reseau : ' || v_count_ports);
  END peupler_reseau;

  -- ---------------------------------------------------------------------------
  -- ORCHESTRATION
  -- ---------------------------------------------------------------------------
  PROCEDURE generer_tout(
    p_nb_users         NUMBER DEFAULT 800,
    p_nb_ordinateurs   NUMBER DEFAULT 1500,
    p_nb_peripheriques NUMBER DEFAULT 1500,
    p_nb_telephones    NUMBER DEFAULT 200,
    p_nb_equip_reseau  NUMBER DEFAULT 100
  ) IS
    v_t_start TIMESTAMP;
  BEGIN
    v_t_start := SYSTIMESTAMP;
    DBMS_OUTPUT.PUT_LINE('===== Generation du jeu de test =====');

    init_referentiels;

    -- 1) Referentiels
    peupler_sites;
    peupler_entites;
    peupler_localisations;
    peupler_fabricants;
    peupler_etats;
    peupler_types_ordi;
    peupler_modeles;
    peupler_profils;
    peupler_groupes;

    -- 2) Utilisateurs
    peupler_utilisateurs(p_nb_users);
    peupler_profils_utilisateurs;

    -- 3) Materiel
    peupler_ordinateurs(p_nb_ordinateurs);
    peupler_peripheriques(p_nb_peripheriques);
    peupler_telephones(p_nb_telephones);
    peupler_logiciels;
    peupler_installations;

    -- 4) Reseau
    peupler_reseau(p_nb_equip_reseau);

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
    DELETE FROM profils_utilisateurs;
    DELETE FROM groupes;
    DELETE FROM utilisateurs;
    DELETE FROM profils;
    DELETE FROM modeles_ordinateur;
    DELETE FROM types_ordinateur;
    DELETE FROM etats;
    DELETE FROM fabricants;
    DELETE FROM localisations;
    DELETE FROM entites;
    DELETE FROM sites;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Donnees supprimees.');
  END reset_donnees;

END pkg_jeu_test;
/

-- -----------------------------------------------------------------------------
-- EXECUTION
-- -----------------------------------------------------------------------------
-- Pour generer le jeu de test par defaut :
--   EXEC pkg_jeu_test.generer_tout;
--
-- Pour un volume different :
--   EXEC pkg_jeu_test.generer_tout(p_nb_users => 2000, p_nb_ordinateurs => 5000);
--
-- Pour repartir de zero :
--   EXEC pkg_jeu_test.reset_donnees;
-- -----------------------------------------------------------------------------

BEGIN
  pkg_jeu_test.generer_tout;
END;
/
