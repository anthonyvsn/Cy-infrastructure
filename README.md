# Cy-infrastructure

Projet GLPI CY Tech multi-sites (Cergy + Pau) sur Oracle 21c Express Edition.

---

## Contenu du projet

| Fichier | Role |
|---|---|
| `create_pdb_xe_cergy.sql` | Cree le PDB XE_CERGY |
| `create_pdb_xe_pau.sql` | Cree le PDB XE_PAU |
| `launch_all.sql` | Lance tout en une commande (schema + PL/SQL + jeu de test + perf) |
| `bdd_Cy_infrastructure.sql` | Schema : tablespaces, roles, users, tables, index, vues, BDDR |
| `pl_sql_triggers.sql` | Triggers (auto-increment, audit, validations) |
| `pl_sql_functions.sql` | Fonctions standalone |
| `pl_sql_procedures.sql` | Procedures standalone |
| `pl_sql_packages.sql` | Packages metier (parc, stats, reseau, maintenance) |
| `jeu_de_test.sql` | Peuplement (~2600 utilisateurs, ~2700 ordis, ~7700 installations) |
| `tests_perf.sql` | Benchmarks EXPLAIN PLAN + mesures de temps |
| `setup_bddr.sql` | Lien symetrique PAU->CERGY + verification connectivite |
| `clean_all.sql` | Nettoyage manuel (rarement necessaire) |

---

## Deploiement depuis zero

### Prerequis

- Oracle Database 21c Express Edition installe
- SQL*Plus accessible dans le PATH
- Se placer dans le dossier du projet avant chaque commande

---

### Scenario 1 : Cergy seul (mode simple)

**Etape 1 — Creer le PDB** (une seule fois)

Depuis le CMD :
```
sqlplus sys/<mdp>@//localhost:1521/XE as sysdba @create_pdb_xe_cergy.sql
```
Depuis l'application SQL*Plus :
```sql
CONNECT sys/<mdp>@//localhost:1521/XE as sysdba
@"h:\Documents\ING 2\S2\TAD\Cy-infrastructure\create_pdb_xe_cergy.sql"
```

**Etape 2 — Deployer le projet**

Depuis le CMD :
```
sqlplus sys/<mdp>@//localhost:1521/XE_CERGY as sysdba @launch_all.sql
```
Depuis l'application SQL*Plus :
```sql
CONNECT sys/<mdp>@//localhost:1521/XE_CERGY as sysdba
@"h:\Documents\ING 2\S2\TAD\Cy-infrastructure\launch_all.sql"
```

`launch_all.sql` est **idempotent** : il peut etre relance autant de fois que necessaire,
il se nettoie automatiquement avant de recreer tous les objets.

---

### Scenario 2 : Cergy + Pau (mode BDDR complet)

**Etape 1 — Creer les deux PDBs** (une seule fois)

Depuis le CMD :
```
sqlplus sys/<mdp>@//localhost:1521/XE as sysdba @create_pdb_xe_cergy.sql
sqlplus sys/<mdp>@//localhost:1521/XE as sysdba @create_pdb_xe_pau.sql
```
Depuis l'application SQL*Plus :
```sql
CONNECT sys/<mdp>@//localhost:1521/XE as sysdba
@"h:\Documents\ING 2\S2\TAD\Cy-infrastructure\create_pdb_xe_cergy.sql"

CONNECT sys/<mdp>@//localhost:1521/XE as sysdba
@"h:\Documents\ING 2\S2\TAD\Cy-infrastructure\create_pdb_xe_pau.sql"
```

**Etape 2 — Deployer le schema sur chaque site**

Depuis le CMD :
```
sqlplus sys/<mdp>@//localhost:1521/XE_CERGY as sysdba @launch_all.sql
sqlplus sys/<mdp>@//localhost:1521/XE_PAU as sysdba @launch_all.sql
```
Depuis l'application SQL*Plus :
```sql
CONNECT sys/<mdp>@//localhost:1521/XE_CERGY as sysdba
@"h:\Documents\ING 2\S2\TAD\Cy-infrastructure\launch_all.sql"

CONNECT sys/<mdp>@//localhost:1521/XE_PAU as sysdba
@"h:\Documents\ING 2\S2\TAD\Cy-infrastructure\launch_all.sql"
```

**Etape 3 — Activer le lien symetrique PAU -> CERGY**

Depuis le CMD :
```
sqlplus ADMIN_CYTECH/cytech2026@//localhost:1521/XE_PAU @setup_bddr.sql
```
Depuis l'application SQL*Plus :
```sql
CONNECT ADMIN_CYTECH/cytech2026@//localhost:1521/XE_PAU
@"h:\Documents\ING 2\S2\TAD\Cy-infrastructure\setup_bddr.sql"
```

---

### Lancer les tests de performance

**Avec les deux sites actifs (TEST 6 fonctionnel) :**

Depuis le CMD :
```
sqlplus ADMIN_CYTECH/cytech2026@//localhost:1521/XE_CERGY @tests_perf.sql
```
Depuis l'application SQL*Plus :
```sql
CONNECT ADMIN_CYTECH/cytech2026@//localhost:1521/XE_CERGY
@"h:\Documents\ING 2\S2\TAD\Cy-infrastructure\tests_perf.sql"
```

**Avec Cergy seul (PAU ferme) :**

Depuis l'application SQL*Plus :
```sql
-- Fermer PAU
CONNECT sys/<mdp>@//localhost:1521/XE as sysdba
ALTER PLUGGABLE DATABASE XE_PAU CLOSE IMMEDIATE;

-- Lancer les tests
CONNECT ADMIN_CYTECH/cytech2026@//localhost:1521/XE_CERGY
@"h:\Documents\ING 2\S2\TAD\Cy-infrastructure\tests_perf.sql"

-- Reactiveer PAU apres
CONNECT sys/<mdp>@//localhost:1521/XE as sysdba
ALTER PLUGGABLE DATABASE XE_PAU OPEN;
```

**Avec Cergy seul (TEST 6 affiche "db link non joignable") :**
```
-- Fermer PAU temporairement
sqlplus sys/<mdp>@//localhost:1521/XE as sysdba
  ALTER PLUGGABLE DATABASE XE_PAU CLOSE IMMEDIATE;
  EXIT

-- Lancer les tests
sqlplus ADMIN_CYTECH/cytech2026@//localhost:1521/XE_CERGY @tests_perf.sql

-- Reactiveer PAU apres
sqlplus sys/<mdp>@//localhost:1521/XE as sysdba
  ALTER PLUGGABLE DATABASE XE_PAU OPEN;
  EXIT
```

---

## Gestion des PDBs

| Action | Commande (dans SQL*Plus connecte au CDB) |
|---|---|
| Ouvrir PAU | `ALTER PLUGGABLE DATABASE XE_PAU OPEN;` |
| Fermer PAU | `ALTER PLUGGABLE DATABASE XE_PAU CLOSE IMMEDIATE;` |
| Ouvrir CERGY | `ALTER PLUGGABLE DATABASE XE_CERGY OPEN;` |
| Fermer CERGY | `ALTER PLUGGABLE DATABASE XE_CERGY CLOSE IMMEDIATE;` |
| Voir l'etat | `SELECT name, open_mode FROM v$pdbs;` |
| Supprimer PAU | `ALTER PLUGGABLE DATABASE XE_PAU CLOSE IMMEDIATE;` puis `DROP PLUGGABLE DATABASE XE_PAU INCLUDING DATAFILES;` |

> Connexion au CDB : `sqlplus sys/<mdp>@//localhost:1521/XE as sysdba`

---

## Erreurs attendues (normales)

Ces erreurs apparaissent toujours car la configuration mono-site ne peut pas resoudre le DB link vers PAU :

| Objet | Raison |
|---|---|
| `vue_parc_global`, `vue_parc_global_v2` | Utilisent `ordinateurs@db_pau` |
| `trg_insert_vue_parc_global` | INSERT dans `ordinateurs@db_pau` |
| TEST 6 si PAU ferme | DB link `db_pau` non joignable |

Tout le reste (schema, PL/SQL, jeu de test, tests 1-5 et 7) passe sans erreur.

---

## Comptes Oracle crees

| Utilisateur | Mot de passe | Role |
|---|---|---|
| `ADMIN_CYTECH` | `cytech2026` | Administrateur general (tous droits) |
| `TECH_CERGY` | `cergy2026` | Technicien Cergy |
| `TECH_PAU` | `pau2026` | Technicien Pau |
| `USER_RO` | `RO2026` | Consultation seule (SELECT uniquement) |

---

## Acces aux donnees distribuees (apres setup BDDR)

| Depuis | Requete | Resultat |
|---|---|---|
| XE_CERGY | `SELECT * FROM ordinateurs` | Ordis Cergy (local) |
| XE_CERGY | `SELECT * FROM ordinateurs@db_pau` | Ordis Pau (distant) |
| XE_CERGY | `SELECT * FROM vue_parc_global` | Parc complet CERGY + PAU |
| XE_PAU | `SELECT * FROM ordinateurs` | Ordis Pau (local) |
| XE_PAU | `SELECT * FROM ordinateurs@db_cergy` | Ordis Cergy (distant) |
| XE_PAU | `SELECT * FROM vue_parc_global_pau` | Parc complet PAU + CERGY |

---

## Description des tests de performance

| Test | Ce qui est compare | Resultat attendu |
|---|---|---|
| 1 | Index B-tree sur `site_id` vs full scan | Index utile sur grand volume |
| 2 | Index fonctionnel `UPPER(login)` vs full scan | Index fonctionnel necessaire pour recherche insensible a la casse |
| 3 | Bitmap index `est_supprime` vs full scan | Bitmap optimal pour colonne a faible cardinalite (0/1) |
| 4 | Cluster vs table heap (par localisation) | Cluster reduit les I/O sur jointures co-localisees |
| 5 | Vue materialisee vs agregation live | MV nettement plus rapide (precalcule) |
| 6 | SELECT local vs SELECT distant (db link) | Acces distant 5-10x plus lent (latence reseau) |
| 7 | `vue_parc_cergy` avec/sans tous les indexes B-tree | Impact global des indexes sur requete complexe |
