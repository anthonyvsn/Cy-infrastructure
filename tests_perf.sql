/* 
	TESTS DE PERFORMANCE -- Projet GLPI CY Tech multi-sites

	A executer en tant que ADMIN_CYTECH, APRES :
	1) bdd_Cy_infrastructure.sql
	2) pl_sql_triggers.sql + pl_sql_functions.sql + pl_sql_procedures.sql
		+ pl_sql_packages.sql
	3) jeu_de_test.sql (volume representatif)

	Objectif : mesurer et comparer les performances pour justifier les choix
	d'indexation et de BDDR dans le rapport.

	Methodologie :
	* EXPLAIN PLAN : montre le plan choisi par l'optimiseur (FULL SCAN,
		INDEX RANGE SCAN, NESTED LOOPS...) -> indique la qualite du plan.
	* SET TIMING ON + DBMS_UTILITY.GET_TIME : mesure le wall-clock time
		d'execution.
	* On execute chaque requete 3 fois pour amortir le cold cache.

	Comparaisons couvertes :
	1. Avec / sans index sur ordinateurs.site_id
	2. Avec / sans index fonctionnel sur UPPER(login)
	3. Avec / sans index bitmap sur est_supprime
	4. Cluster (ordinateurs_cl) vs heap (ordinateurs) pour SELECT par localisation
	5. Vue materialisee (mv_stats_parc) vs agregation live
	6. Local vs distant (parc global via db_pau)
	7. Impact global des indexes B-TREE sur ordinateurs

*/

SET SERVEROUTPUT ON SIZE UNLIMITED;
SET TIMING ON;
SET LINESIZE 200;
SET PAGESIZE 100;
SET AUTOTRACE OFF;
ALTER SESSION SET STATISTICS_LEVEL = 'ALL';

-- Verification des prerequis
PROMPT ===== Verifications prerequis =====
SELECT COUNT(*) AS nb_ordis   FROM ordinateurs;
SELECT COUNT(*) AS nb_periph  FROM peripheriques;
SELECT COUNT(*) AS nb_users   FROM utilisateurs;

/* 
	HELPER : procedure de mesure repetee

	Execute une requete N fois et affiche le temps moyen et la variance.
	Utilise DBMS_UTILITY.GET_TIME (precision 1/100s).
	Pourquoi : une mesure unique n'est pas fiable (cache effects).
*/

CREATE OR REPLACE PROCEDURE bench_query(
  p_libelle    VARCHAR2,
  p_requete    VARCHAR2,
  p_nb_runs    NUMBER DEFAULT 5
) IS
  v_t0       NUMBER;
  v_t1       NUMBER;
  v_total    NUMBER := 0;
  v_min      NUMBER := NULL;
  v_max      NUMBER := NULL;
  v_dummy    NUMBER;
  v_sql      VARCHAR2(4000) := 'SELECT COUNT(*) FROM (' || p_requete || ')';
BEGIN
  DBMS_OUTPUT.PUT_LINE('  [' || p_libelle || '] (' || p_nb_runs || ' runs)');
  FOR i IN 1..p_nb_runs LOOP
    v_t0 := DBMS_UTILITY.GET_TIME;
    EXECUTE IMMEDIATE v_sql INTO v_dummy;
    v_t1 := DBMS_UTILITY.GET_TIME;
    v_total := v_total + (v_t1 - v_t0);
    IF v_min IS NULL OR (v_t1 - v_t0) < v_min THEN v_min := v_t1 - v_t0; END IF;
    IF v_max IS NULL OR (v_t1 - v_t0) > v_max THEN v_max := v_t1 - v_t0; END IF;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('      moy=' || ROUND(v_total / p_nb_runs, 2)
    || ' min=' || v_min || ' max=' || v_max || ' (centisecondes)');
END;
/

/*
	HELPER : synchronise les tables clusterisees avec les originales

	Copie ordinateurs/peripheriques vers ordinateurs_cl/peripheriques_cl pour
	que la comparaison cluster vs heap soit sur les memes donnees.
*/

CREATE OR REPLACE PROCEDURE sync_tables_cluster IS
  v_nb_o NUMBER;
  v_nb_p NUMBER;
BEGIN
  -- DELETE au lieu de TRUNCATE : Oracle interdit TRUNCATE sur table clusterisee
  -- (ORA-03292). Plus lent que TRUNCATE mais necessaire ici.
  DELETE FROM ordinateurs_cl;
  DELETE FROM peripheriques_cl;
  INSERT INTO ordinateurs_cl   SELECT * FROM ordinateurs;
  v_nb_o := SQL%ROWCOUNT;
  INSERT INTO peripheriques_cl SELECT * FROM peripheriques;
  v_nb_p := SQL%ROWCOUNT;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Copies clusterisees : ' || v_nb_o
    || ' ordis, ' || v_nb_p || ' periph.');
END;
/

PROMPT ===== Synchronisation des tables clusterisees =====
EXEC sync_tables_cluster;

/*
	TEST 1 : INDEX SUR site_id

	Requete typique : "tous les ordinateurs du site Cergy".
	Sans index -> FULL TABLE SCAN. Avec index -> INDEX RANGE SCAN + ROWID.
*/

PROMPT
PROMPT ========== TEST 1 : ordinateurs WHERE site_id = 1 ==========

-- 1.a) AVEC l'index (etat normal)
PROMPT ----- Plan AVEC index idx_ordi_site -----
EXPLAIN PLAN FOR
  SELECT id, nom FROM ordinateurs WHERE site_id = 1 AND est_supprime = 0;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

BEGIN bench_query('AVEC index site_id', 'SELECT id, nom FROM ordinateurs WHERE site_id = 1 AND est_supprime = 0'); END;
/

-- 1.b) SANS index : on drop temporairement
PROMPT ----- Drop index idx_ordi_site -----
DROP INDEX idx_ordi_site;

PROMPT ----- Plan SANS index -----
EXPLAIN PLAN FOR
  SELECT id, nom FROM ordinateurs WHERE site_id = 1 AND est_supprime = 0;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

BEGIN bench_query('SANS index site_id', 'SELECT id, nom FROM ordinateurs WHERE site_id = 1 AND est_supprime = 0'); END;
/

-- On recree l'index pour ne pas casser la suite
PROMPT ----- Recreation index idx_ordi_site -----
CREATE INDEX idx_ordi_site ON ordinateurs(site_id) TABLESPACE TS_INDEX;

/*
	TEST 2 : INDEX FONCTIONNEL UPPER(login)

	Recherche case-insensitive sur un login.
	Sans index fonctionnel : FULL SCAN car UPPER(col) cache le b-tree classique.
	Avec index fonctionnel : INDEX RANGE SCAN sur le b-tree de la fonction.
*/
PROMPT
PROMPT ========== TEST 2 : utilisateurs WHERE UPPER(login) = 'ALICEMARTIN' ==========

-- 2.a) AVEC index fonctionnel
PROMPT ----- Plan AVEC idx_user_login_upper -----
EXPLAIN PLAN FOR
  SELECT id, login, nom FROM utilisateurs WHERE UPPER(login) = 'ALICEMARTIN10';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

BEGIN bench_query('AVEC index fonctionnel UPPER(login)',
  'SELECT id, login, nom FROM utilisateurs WHERE UPPER(login) = ''ALICEMARTIN10'''); END;
/

-- 2.b) SANS index fonctionnel
DROP INDEX idx_user_login_upper;

PROMPT ----- Plan SANS index fonctionnel -----
EXPLAIN PLAN FOR
  SELECT id, login, nom FROM utilisateurs WHERE UPPER(login) = 'ALICEMARTIN10';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

BEGIN bench_query('SANS index fonctionnel UPPER(login)',
  'SELECT id, login, nom FROM utilisateurs WHERE UPPER(login) = ''ALICEMARTIN10'''); END;
/

CREATE INDEX idx_user_login_upper ON utilisateurs(UPPER(login)) TABLESPACE TS_INDEX;

/*
	TEST 3 : BITMAP INDEX sur est_supprime

	Cardinalite 2 (0/1) -> bitmap optimal. Mesure le filtrage rapide
	des "non supprimes".
*/

PROMPT
PROMPT ========== TEST 3 : ordinateurs WHERE est_supprime = 0 ==========

EXPLAIN PLAN FOR
  SELECT COUNT(*) FROM ordinateurs WHERE est_supprime = 0;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

BEGIN bench_query('AVEC bitmap est_supprime',
  'SELECT COUNT(*) FROM ordinateurs WHERE est_supprime = 0'); END;
/

DROP INDEX idx_bmp_ordi_supprime;

EXPLAIN PLAN FOR
  SELECT COUNT(*) FROM ordinateurs WHERE est_supprime = 0;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

BEGIN bench_query('SANS bitmap',
  'SELECT COUNT(*) FROM ordinateurs WHERE est_supprime = 0'); END;
/

CREATE BITMAP INDEX idx_bmp_ordi_supprime ON ordinateurs(est_supprime) TABLESPACE TS_INDEX;

/*
	TEST 4 : CLUSTER vs HEAP

	Requete typique : "tous les ordis et peripheriques d'une meme localisation".
	Avec cluster : les lignes ordi + periph partageant localisation_id sont
	co-localisees physiquement => moins de blocs lus.
	Sans cluster (tables heap classiques) : les lignes sont eparpillees
	=> plus d'I/O.
*/

PROMPT
PROMPT ========== TEST 4 : SELECT par localisation -- cluster vs heap ==========

-- 4.a) AVEC cluster (ordinateurs_cl + peripheriques_cl)
PROMPT ----- Plan AVEC cluster -----
EXPLAIN PLAN FOR
  SELECT o.id, o.nom, p.id AS periph_id, p.nom AS periph_nom
    FROM ordinateurs_cl o
    LEFT JOIN peripheriques_cl p ON p.localisation_id = o.localisation_id
   WHERE o.localisation_id = 10;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

BEGIN bench_query('AVEC cluster',
  'SELECT o.id, o.nom, p.id, p.nom FROM ordinateurs_cl o LEFT JOIN peripheriques_cl p ON p.localisation_id = o.localisation_id WHERE o.localisation_id = 10');
END;
/

-- 4.b) SANS cluster (tables heap classiques)
PROMPT ----- Plan SANS cluster -----
EXPLAIN PLAN FOR
  SELECT o.id, o.nom, p.id AS periph_id, p.nom AS periph_nom
    FROM ordinateurs o
    LEFT JOIN peripheriques p ON p.localisation_id = o.localisation_id
   WHERE o.localisation_id = 10;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

BEGIN bench_query('SANS cluster (heap)',
  'SELECT o.id, o.nom, p.id, p.nom FROM ordinateurs o LEFT JOIN peripheriques p ON p.localisation_id = o.localisation_id WHERE o.localisation_id = 10');
END;
/

/*
	TEST 5 : VUE MATERIALISEE vs AGREGATION LIVE
	mv_stats_parc precompute COUNT(*) GROUP BY (site, etat).
	Acces direct a la MV : trivial.
	Agregation live : doit scanner ordinateurs et faire le GROUP BY.
*/


PROMPT
PROMPT ========== TEST 5 : stats parc -- MV vs requete live ==========

-- 5.a) Via la MV
EXPLAIN PLAN FOR
  SELECT * FROM mv_stats_parc;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

BEGIN bench_query('MV mv_stats_parc',
  'SELECT site, etat, nb_ordinateurs FROM mv_stats_parc'); END;
/

-- 4.b) Live (recalcul a la volee)
EXPLAIN PLAN FOR
  SELECT s.nom AS site, e.nom AS etat, COUNT(*) AS nb_ordinateurs
    FROM ordinateurs o
    JOIN sites s ON o.site_id = s.id
    LEFT JOIN etats e ON o.etat_id = e.id
   WHERE o.est_supprime = 0
   GROUP BY s.nom, e.nom;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

BEGIN bench_query('Aggregation live',
  'SELECT s.nom, e.nom, COUNT(*) FROM ordinateurs o JOIN sites s ON o.site_id = s.id LEFT JOIN etats e ON o.etat_id = e.id WHERE o.est_supprime = 0 GROUP BY s.nom, e.nom'); END;
/

/*
	TEST 6 : ACCES LOCAL vs DISTANT (db link)

	Compare le cout d'un SELECT local vs un SELECT via db_pau@.
	NE FONCTIONNE QUE SI le serveur Pau est joignable.
*/


PROMPT
PROMPT ========== TEST 6 : SELECT local vs SELECT distant ==========

BEGIN
  bench_query('Local : ordinateurs Cergy',
    'SELECT COUNT(*) FROM ordinateurs WHERE site_id = 1');

  -- Si db_pau ne resout pas, on attrape l'erreur pour ne pas casser le script.
  BEGIN
    bench_query('Distant : ordinateurs Pau via db_pau',
      'SELECT COUNT(*) FROM ordinateurs@db_pau');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('  (db link db_pau non joignable : ' || SQLERRM || ')');
  END;
END;
/

/*
	TEST 7 : RECAPITULATIF -- impact des indexes (drop tous puis recreer)

	Test global : on mesure une requete complexe (vue_parc_cergy) avec et sans
	les indexes b-tree principaux.
	Attention : long si on rebuild tous les indexes. 
*/
PROMPT
PROMPT ========== TEST 7 : impact global indexes sur vue_parc_cergy ==========

BEGIN
  bench_query('Vue parc Cergy -- AVEC indexes',
    'SELECT * FROM vue_parc_cergy');
END;
/

-- Drop des index principaux (b-tree sur ordinateurs)
PROMPT ---- Drop indexes ordinateurs -----

BEGIN
  FOR ind IN (SELECT index_name FROM user_indexes
               WHERE table_name = 'ORDINATEURS'
                 AND index_type IN ('NORMAL', 'FUNCTION-BASED NORMAL')
                 AND uniqueness = 'NONUNIQUE') LOOP
    EXECUTE IMMEDIATE 'DROP INDEX ' || ind.index_name;
  END LOOP;
END;
/

BEGIN
  bench_query('Vue parc Cergy -- SANS indexes',
    'SELECT * FROM vue_parc_cergy');
END;
/

-- Recreation des indexes principaux
PROMPT ----- Recreation indexes -----
CREATE INDEX idx_ordi_hierarchy_level ON ordinateurs(hierarchy_level_id) TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_localisation    ON ordinateurs(localisation_id)    TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_utilisateur     ON ordinateurs(utilisateur_id)     TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_fabricant       ON ordinateurs(fabricant_id)       TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_etat            ON ordinateurs(etat_id)            TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_site            ON ordinateurs(site_id)            TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_nom             ON ordinateurs(nom)                TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_serie           ON ordinateurs(numero_serie)       TABLESPACE TS_INDEX;
CREATE INDEX idx_ordi_nom_upper       ON ordinateurs(UPPER(nom))         TABLESPACE TS_INDEX;

PROMPT ===== Tests de performance termines =====
