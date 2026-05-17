/*
	Creation du PDB XE_PAU (a exécuter sous SYSTEM).

	Commandes :
		sqlplus sys/<mdp>@//localhost:1521/XE as sysdba @create_pdb_xe_pau.sql
*/

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
  v_con_id NUMBER;
BEGIN
  SELECT SYS_CONTEXT('USERENV', 'CON_ID') INTO v_con_id FROM DUAL;
  IF v_con_id > 1 THEN
    RAISE_APPLICATION_ERROR(-20001,
      'Ce script doit etre lance depuis le CDB. '||
      'Connectez-vous via : sqlplus sys/<mdp>@//localhost:1521/XE as sysdba');
  END IF;
  DBMS_OUTPUT.PUT_LINE('OK : connexion CDB confirmee (con_id=' || v_con_id || ')');
END;
/

DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM v$pdbs WHERE UPPER(name) = 'XE_PAU';
  IF v_count > 0 THEN
    RAISE_APPLICATION_ERROR(-20002,
      'Le PDB XE_PAU existe deja. '||
      'Supprimez-le d''abord : ALTER PLUGGABLE DATABASE XE_PAU CLOSE IMMEDIATE; DROP PLUGGABLE DATABASE XE_PAU INCLUDING DATAFILES;');
  END IF;
  DBMS_OUTPUT.PUT_LINE('OK : XE_PAU n''existe pas encore.');
END;
/

DECLARE
  v_seed_dir  VARCHAR2(512);
  v_new_dir   VARCHAR2(512);
  v_sql       VARCHAR2(2000);
  v_sep       CHAR(1);
BEGIN
  SELECT name INTO v_seed_dir
  FROM v$datafile
  WHERE con_id = 2 AND ROWNUM = 1;

  IF INSTR(v_seed_dir, '\') > 0 THEN
    v_sep := '\';
  ELSE
    v_sep := '/';
  END IF;

  v_seed_dir := SUBSTR(v_seed_dir, 1, INSTR(v_seed_dir, v_sep, -1));
  v_new_dir  := REPLACE(v_seed_dir, 'PDBSEED', 'XE_PAU');

  DBMS_OUTPUT.PUT_LINE('Chemin pdbseed detecte : ' || v_seed_dir);
  DBMS_OUTPUT.PUT_LINE('Chemin XE_PAU cible    : ' || v_new_dir);

  v_sql :=
    'CREATE PLUGGABLE DATABASE XE_PAU ' ||
    'ADMIN USER pdbadmin IDENTIFIED BY pdbpass ' ||
    'FILE_NAME_CONVERT = (''' || v_seed_dir || ''', ''' || v_new_dir || ''')';

  DBMS_OUTPUT.PUT_LINE('Execution : ' || v_sql);
  EXECUTE IMMEDIATE v_sql;
  DBMS_OUTPUT.PUT_LINE('PDB XE_PAU cree avec succes.');
END;
/

ALTER PLUGGABLE DATABASE XE_PAU OPEN;
ALTER PLUGGABLE DATABASE XE_PAU SAVE STATE;

SELECT name, open_mode FROM v$pdbs WHERE UPPER(name) = 'XE_PAU';

PROMPT
PROMPT XE_PAU est pret. Lancez maintenant :
PROMPT   sqlplus sys/<mdp>@//localhost:1521/XE_PAU as sysdba @launch_all.sql
PROMPT
