/*
	Creation du PDB XE_CERGY (a exécuter sous SYSTEM).
	a noter : affiche aussi la ligne a ajouter dans tnsnames.ora

	Commandes :
		sqlplus sys/<mdp>@//localhost:1521/XE as sysdba @create_pdb_xe_cergy.sql
*/

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- Verification : on doit etre dans le CDB (con_id = 0 ou 1)
DECLARE
  v_con_id NUMBER;
BEGIN
  SELECT SYS_CONTEXT('USERENV', 'CON_ID') INTO v_con_id FROM DUAL;
  IF v_con_id > 1 THEN
    RAISE_APPLICATION_ERROR(-20001,
      'Ce script doit etre lance depuis le CDB (con_id=1), pas depuis un PDB. '||
      'Connectez-vous via : sqlplus sys/<mdp>@//localhost:1521/XE as sysdba');
  END IF;
  DBMS_OUTPUT.PUT_LINE('OK : connexion CDB confirmee (con_id=' || v_con_id || ')');
END;
/

-- Verification : XE_CERGY ne doit pas deja exister
DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM v$pdbs WHERE UPPER(name) = 'XE_CERGY';
  IF v_count > 0 THEN
    RAISE_APPLICATION_ERROR(-20002,
      'Le PDB XE_CERGY existe deja. '||
      'Supprimez-le d''abord : ALTER PLUGGABLE DATABASE XE_CERGY CLOSE IMMEDIATE; DROP PLUGGABLE DATABASE XE_CERGY INCLUDING DATAFILES;');
  END IF;
  DBMS_OUTPUT.PUT_LINE('OK : XE_CERGY n''existe pas encore.');
END;
/

-- Creation du PDB avec detection automatique du chemin pdbseed
DECLARE
  v_seed_dir  VARCHAR2(512);
  v_new_dir   VARCHAR2(512);
  v_sql       VARCHAR2(2000);
  v_sep       CHAR(1);
BEGIN
  -- Detecte le separateur (Windows = \, Linux = /)
  SELECT name INTO v_seed_dir
  FROM v$datafile
  WHERE con_id = 2 AND ROWNUM = 1;

  IF INSTR(v_seed_dir, '\') > 0 THEN
    v_sep := '\';
  ELSE
    v_sep := '/';
  END IF;

  -- Extrait le repertoire : tout jusqu'au dernier separateur inclus
  -- INSTR avec position negative cherche depuis la fin de la chaine
  v_seed_dir := SUBSTR(v_seed_dir, 1, INSTR(v_seed_dir, v_sep, -1));

  -- Oracle stocke les chemins en majuscules dans v$datafile, PDBSEED est en maj
  v_new_dir := REPLACE(v_seed_dir, 'PDBSEED', 'XE_CERGY');

  DBMS_OUTPUT.PUT_LINE('Chemin pdbseed detecte : ' || v_seed_dir);
  DBMS_OUTPUT.PUT_LINE('Chemin XE_CERGY cible  : ' || v_new_dir);

  v_sql :=
    'CREATE PLUGGABLE DATABASE XE_CERGY ' ||
    'ADMIN USER pdbadmin IDENTIFIED BY pdbpass ' ||
    'FILE_NAME_CONVERT = (''' || v_seed_dir || ''', ''' || v_new_dir || ''')';

  DBMS_OUTPUT.PUT_LINE('Execution : ' || v_sql);
  EXECUTE IMMEDIATE v_sql;

  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('PDB XE_CERGY cree avec succes.');
END;
/

-- Ouverture et persistance
ALTER PLUGGABLE DATABASE XE_CERGY OPEN;
ALTER PLUGGABLE DATABASE XE_CERGY SAVE STATE;

-- Confirmation
SELECT name, open_mode FROM v$pdbs WHERE UPPER(name) = 'XE_CERGY';

-- Affichage de la config tnsnames
DECLARE
  v_host VARCHAR2(100);
BEGIN
  SELECT UTL_INADDR.GET_HOST_NAME INTO v_host FROM DUAL;
  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('================================================================');
  DBMS_OUTPUT.PUT_LINE(' AJOUTER dans tnsnames.ora (chercher avec : tnsping XE) :');
  DBMS_OUTPUT.PUT_LINE('================================================================');
  DBMS_OUTPUT.PUT_LINE('XE_CERGY =');
  DBMS_OUTPUT.PUT_LINE('  (DESCRIPTION=');
  DBMS_OUTPUT.PUT_LINE('    (ADDRESS=(PROTOCOL=TCP)(HOST=' || v_host || ')(PORT=1521))');
  DBMS_OUTPUT.PUT_LINE('    (CONNECT_DATA=(SERVICE_NAME=XE_CERGY)))');
  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE(' OU connectez-vous directement sans TNS :');
  DBMS_OUTPUT.PUT_LINE('   sqlplus sys/<mdp>@//localhost:1521/XE_CERGY as sysdba');
  DBMS_OUTPUT.PUT_LINE('================================================================');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('================================================================');
    DBMS_OUTPUT.PUT_LINE(' Connexion directe sans TNS (recommande) :');
    DBMS_OUTPUT.PUT_LINE('   sqlplus sys/<mdp>@//localhost:1521/XE_CERGY as sysdba');
    DBMS_OUTPUT.PUT_LINE('================================================================');
END;
/

PROMPT
PROMPT XE_CERGY est pret. Lancez maintenant :
PROMPT   sqlplus sys/<mdp>@//localhost:1521/XE_CERGY as sysdba @launch_all.sql
PROMPT
