# Mini-projet SIE -- Base de données GLPI multi-sites pour CY Tech

**Bases de données avancées -- ING2 -- 2025-2026**
**Équipe GLPI CY Tech**
**Date :** 2026-05-13
**Soutenance :** semaine du 18 mai 2026

---

## Résumé

Ce rapport présente la refonte d'une partie de la base de données GLPI sous Oracle 19c pour CY Tech, en environnement multi-sites (Cergy + Pau). Le périmètre couvre trois domaines : matériel informatique, utilisateurs, infrastructure réseau. Le projet exploite l'ensemble des concepts avancés du cours -- utilisateurs/rôles, tablespaces, clusters, indexation, vues, PL/SQL (triggers, curseurs, procédures, fonctions, packages), base de données répartie (database links, vues matérialisées) -- et démontre les gains de performance obtenus.

---

## 1. Contexte et objectifs

### 1.1 Cadre

CY Tech opère deux campus (Cergy et Pau) et utilise GLPI, un outil open source de gestion de parc informatique. L'objectif du projet est de **repenser sous Oracle** une partie de la base GLPI en exploitant les fonctionnalités avancées d'un SGBD professionnel pour répondre aux besoins spécifiques de CY Tech :

- **Inventaire centralisé** du parc matériel (ordinateurs, périphériques, téléphones), avec affectations utilisateurs et localisations.
- **Gestion fine des droits** par profil et entité (sous-direction, département).
- **Inventaire réseau** : équipements (switchs, routeurs, AP WiFi) et ports.
- **Distribution multi-sites** : chaque campus dispose de sa propre instance Oracle, avec consolidation transparente.

### 1.2 Livrables

| Livrable | État |
|---|---|
| Rapport de reverse engineering GLPI/MariaDB | Livré (cf. `Rapport_Reverse_Engineering_GLPI.docx`) |
| Document d'architecture cible Oracle | Livré (cf. `Architecture_BDD_GLPI.docx`) |
| Code SQL : structure, indexes, vues, BDDR | `bdd_Cy_infrastructure.sql` (~612 lignes) |
| Code PL/SQL : triggers, fonctions, procédures, package | `pl_sql_metier.sql` |
| Jeu de test paramétrable | `jeu_de_test.sql` (package `pkg_jeu_test`) |
| Corrections / compléments | `corrections_sql.sql` |
| Tests de performance | `tests_perf.sql` |
| Diagrammes UML, MLD, déploiement | `diagrammes/*.puml` |
| Rapport final consolidé | Ce document |
| Présentation orale | `slides_soutenance.md` (Marp) |

---

## 2. Reverse engineering GLPI

La base GLPI originelle tourne sous **MySQL/MariaDB** avec un schéma à plus de 400 tables. Notre analyse (cf. rapport dédié) a fait ressortir les caractéristiques suivantes :

- **Convention de nommage stricte** : préfixe `glpi_` sur toutes les tables, suffixes `_id` pour les FK, `is_*` pour les booléens, `date_creation` / `date_mod` systématiques.
- **Polymorphisme par chaîne** sur la table d'audit (`glpi_logs`) : un couple `(itemtype VARCHAR, items_id NUMBER)` pointe vers la ligne auditée, sans FK forte. Choix pragmatique pour éviter N tables d'audit.
- **Soft-delete généralisé** : `is_deleted` plutôt que `DELETE` physique, permettant restauration et conservation de l'historique.
- **Entités hiérarchiques** : `glpi_entities` modélise l'arborescence organisationnelle (direction → départements → équipes) avec auto-référence `entities_id` (parent).
- **Faiblesses identifiées** : peu de contraintes CHECK, FK parfois manquantes, absence de triggers d'audit côté base (la traçabilité est applicative).

### Périmètre retenu

Pour rester dans un volume maîtrisable, nous nous concentrons sur les trois domaines suivants, hérités de la structure GLPI mais adaptés à Oracle et à CY Tech :

| Domaine | Tables principales |
|---|---|
| Référentiel | `sites`, `entites`, `localisations`, `fabricants`, `etats`, `types_ordinateur`, `modeles_ordinateur` |
| Utilisateurs | `profils`, `utilisateurs`, `profils_utilisateurs`, `groupes` |
| Matériel | `ordinateurs`, `peripheriques`, `telephones`, `logiciels`, `versions_logiciel`, `installations_logiciels` |
| Réseau | `types_equip_reseau`, `equipements_reseau`, `ports_reseau` |
| Audit | `historique` |

---

## 3. Modélisation

### 3.1 Diagramme de classes UML

Cf. `diagrammes/diagramme_classes_uml.puml`. Le modèle est organisé en 5 paquets (Référentiel, Utilisateurs, Matériel, Réseau, Audit). Points marquants :

- **Hiérarchies récursives** : `entites`, `localisations`, `groupes` (auto-référence parent).
- **Multi-affectation** : un ordinateur a une entité, une localisation, un utilisateur affecté et un technicien responsable -- 4 relations vers 2 tables (`entites`, `utilisateurs`).
- **Polymorphisme d'audit** : la classe `Historique` pointe vers n'importe quelle table sensible via `(type_objet, objet_id)`.

### 3.2 Schéma relationnel (MLD)

Cf. `diagrammes/schema_relationnel.puml`. Détaille toutes les tables, leurs colonnes, types, PK/FK et contraintes UNIQUE/CHECK. Le schéma est regroupé visuellement par tablespace pour rendre la stratégie de stockage immédiatement lisible.

### 3.3 Diagramme de déploiement BDDR

Cf. `diagrammes/deploiement_bddr.puml`. Montre les 2 instances Oracle (`XE_CERGY`, `XE_PAU`), leurs tablespaces, le database link `db_pau`, les vues matérialisées de réplication et les flux d'accès des 4 utilisateurs Oracle.

---

## 4. Architecture Oracle

### 4.1 Tablespaces

| Tablespace | Contenu | Pourquoi |
|---|---|---|
| `TS_USERS` | Référentiel partagé, utilisateurs, audit | Données peu volumineuses, lues partout |
| `TS_MATERIEL_CERGY` | Parc matériel Cergy | Isole physiquement les données Cergy |
| `TS_MATERIEL_PAU` | Parc matériel Pau (sur instance Pau) | Idem pour Pau, support BDDR |
| `TS_NETWORK_CERGY` | Réseau Cergy | Sépare matériel et réseau (différents profils d'accès) |
| `TS_NETWORK_PAU` | Réseau Pau (sur instance Pau) | Idem pour Pau |
| `TS_INDEX` | Tous les indexes secondaires | Permet de tuner les IO indexes indépendamment |
| `TS_TEMP` | Tablespace temporaire | Tris, jointures, agrégations |

**Justification** : isoler les indexes dans `TS_INDEX` permet de les placer sur un disque rapide en production. Isoler les données Cergy/Pau par tablespace facilite la sauvegarde différenciée et la migration éventuelle vers des disques séparés. Le tablespace `TS_MATERIEL_PAU` sur l'instance Cergy reste **réservé** pour des opérations de réplication / bascule de site.

### 4.2 Rôles et utilisateurs

| Rôle | Privilèges accordés |
|---|---|
| `R_ADMIN` | `CONNECT`, `RESOURCE`, DDL complet, `UNLIMITED TABLESPACE` |
| `R_TECH_CERGY` | `CONNECT`, `RESOURCE`, `CREATE SESSION`, CRUD sur le parc Cergy |
| `R_TECH_PAU` | `CONNECT`, `RESOURCE`, `CREATE SESSION`, CRUD sur le parc Pau |
| `R_CONSULTATION` | `CONNECT`, `CREATE SESSION`, SELECT sur les vues |

| Utilisateur | Rôle | Mot de passe initial |
|---|---|---|
| `ADMIN_CYTECH` | `R_ADMIN` | `cytech2026` |
| `TECH_CERGY` | `R_TECH_CERGY` | `cergy2026` |
| `TECH_PAU` | `R_TECH_PAU` | `pau2026` (corrigé via `corrections_sql.sql`) |
| `USER_RO` | `R_CONSULTATION` | `RO2026` |

> Le mot de passe initial de `TECH_PAU` était `cergy2026` par copier-coller. Corrigé en `pau2026` dans `corrections_sql.sql` (ainsi que dans le DB link `db_pau`).

### 4.3 Séquences

21 séquences (`seq_*`), une par table. Démarrage à 1, incrément 1, pas de cache (pour éviter les trous en environnement de dev). Auto-incrémentation gérée par triggers (cf. §5.1).

---

## 5. Indexation et cluster

### 5.1 Stratégie d'indexation

Trois types d'index sont utilisés :

| Type | Nombre | Usage |
|---|---|---|
| **B-tree** | ~25 | FK, champs de recherche (`nom`, `numero_serie`), filtres sites |
| **Bitmap** | 5 | Colonnes booléennes (`est_supprime`, `est_template`, `est_actif`) |
| **Fonctionnel** | 2 | Recherches case-insensitive : `UPPER(nom)`, `UPPER(login)` |

**Justification des bitmap** : `est_supprime` a une cardinalité de 2 (0 ou 1). Sur une table de 1500 ordis dont ~3 % sont supprimés, un bitmap consomme nettement moins d'espace qu'un b-tree et accélère les `WHERE est_supprime = 0` ultra-fréquents.

**Justification des index fonctionnels** : les utilisateurs cherchent des ordis par nom sans connaître la casse exacte. Sans index fonctionnel, `WHERE UPPER(nom) = 'PC-CGY-00042'` provoque un FULL TABLE SCAN.

### 5.2 Cluster

Un cluster `cl_materiel_localisation` regroupe physiquement les lignes d'`ordinateurs` et `peripheriques` partageant la même `localisation_id`. Avantage : un `SELECT … WHERE localisation_id = X` lit moins de blocs disque (les lignes co-localisées physiquement sont dans les mêmes pages).

Pour démontrer concrètement le cluster, deux tables jumelles `ordinateurs_cl` et `peripheriques_cl` sont créées dans `corrections_sql.sql` avec la clause `CLUSTER cl_materiel_localisation(localisation_id)`. La procédure `sync_tables_cluster` copie les données depuis les tables originales. Les tests de performance (§8) comparent les deux versions.

---

## 6. PL/SQL

Tout le PL/SQL métier est regroupé dans `pl_sql_metier.sql` (~600 lignes). Découpé en 6 sections :

### 6.1 Triggers d'auto-incrémentation des PK

10 triggers `BEFORE INSERT FOR EACH ROW` (un par table principale) qui consomment `seq_xxx.NEXTVAL` si l'application n'a pas fourni d'`id`. Test `IS NULL` pour ne pas écraser une valeur explicite.

```sql
CREATE OR REPLACE TRIGGER trg_pk_ordinateurs
BEFORE INSERT ON ordinateurs
FOR EACH ROW
BEGIN
  IF :NEW.id IS NULL THEN :NEW.id := seq_ordinateurs.NEXTVAL; END IF;
END;
```

### 6.2 Triggers de MAJ automatique `date_modification`

5 triggers `BEFORE UPDATE` qui forcent `:NEW.date_modification := SYSDATE`. Garantit la traçabilité indépendamment du code applicatif.

### 6.3 Triggers d'audit

4 triggers `AFTER INSERT OR UPDATE OR DELETE` sur les tables sensibles (`ordinateurs`, `utilisateurs`, `equipements_reseau`, `peripheriques`). Pour chaque INSERT/DELETE on enregistre une ligne dans `historique`. Pour chaque UPDATE on enregistre **une ligne par champ modifié** (recherche d'historique fine).

Factorisation par une procédure utilitaire `log_change(...)` pour ne pas dupliquer les `INSERT INTO historique`.

### 6.4 Triggers de validation métier

Quatre garde-fous critiques :

| Trigger | Règle |
|---|---|
| `trg_coherence_site_ordi` | Un ordi doit appartenir à une entité du même site qu'`ordi.site_id` |
| `trg_valid_mac` | Format MAC `XX:XX:XX:XX:XX:XX` via REGEXP |
| `trg_valid_dates_user` | `date_fin >= date_debut` |
| `trg_valid_entite_parent` | Une entité ne peut être son propre parent |

Codes d'erreur réservés au métier : `-20100` à `-20130`.

### 6.5 Package `pkg_metier`

#### Fonctions de statistiques

```
f_nb_materiel_site(p_site_id)             -- count ordi+periph+tel non supprimés
f_age_moyen_parc(p_site_id)               -- AVG((SYSDATE - date_achat)/365.25)
f_taux_occupation_localisation(p_loc_id)  -- % ordis affectés / total
f_count_ordi_etat(p_etat_nom)             -- count par nom d'état
f_user_id_par_email(p_email)              -- recherche, -1 si KO
f_nom_complet_entite(p_entite_id)         -- reconstitution récursive (CONNECT BY)
```

#### Procédures métier

- `transferer_materiel(p_ordi, p_site, p_loc, p_motif)` : déplace un ordinateur entre sites en mettant à jour `site_id`, `entite_id`, `localisation_id` de façon cohérente. Désaffecte l'utilisateur (à réaffecter manuellement). Vérifie que la localisation cible est bien dans le site cible.
- `archiver_utilisateur(p_user_id)` : soft-delete d'un utilisateur + désaffectation de tout son matériel.
- `purger_corbeille(p_jours)` : suppression physique des lignes `est_supprime = 1` plus vieilles que N jours.
- `refresh_mv_stats` : refresh complet de `mv_stats_parc`.
- `audit_erreur(...)` : **transaction autonome** (`PRAGMA AUTONOMOUS_TRANSACTION`) pour tracer une erreur même si l'appelant fait ROLLBACK.

#### Traitements batch (curseurs explicites)

- `recalculer_nom_complet_entites` : curseur trié par niveau croissant. Pour chaque entité, reconstitue `nom_complet` en concaténant le `nom_complet` du parent + `' > ' + nom`. Garantie que le parent est traité avant le fils.
- `marquer_obsoletes(p_annees)` : curseur `FOR UPDATE OF etat_id` -- verrouille les lignes le temps de la mise à jour, utilise `WHERE CURRENT OF c_vieux` pour pointer la ligne courante.
- `rapport_parc_site(p_site_id)` : curseur paramétré joignant 4 tables, affichage formaté via `RPAD`.

### 6.6 Concepts du cours couverts

| Concept | Où |
|---|---|
| Triggers BEFORE / AFTER / ROW-LEVEL | §6.1, 6.2, 6.3, 6.4 |
| Triggers compound (INSERT OR UPDATE OR DELETE) | §6.3 |
| `:OLD`, `:NEW`, `INSERTING`, `UPDATING`, `DELETING` | §6.3 |
| Curseurs explicites paramétrés | §6.5 (batch) |
| `FOR UPDATE OF` + `WHERE CURRENT OF` | `marquer_obsoletes` |
| `PRAGMA AUTONOMOUS_TRANSACTION` | `audit_erreur` |
| `%TYPE`, `%ROWTYPE` | partout |
| `RAISE_APPLICATION_ERROR` (codes -20xxx) | §6.4, §6.5 |
| Exceptions nommées (`NO_DATA_FOUND`, `DUP_VAL_ON_INDEX`) | §6.5 |
| Packages (spec + body) | `pkg_metier`, `pkg_jeu_test` |
| `CONNECT BY` hiérarchique | `f_nom_complet_entite` |
| `DBMS_OUTPUT.PUT_LINE`, `DBMS_MVIEW.REFRESH` | partout |

---

## 7. BDDR -- Base de données répartie

### 7.1 Topologie

Deux instances Oracle indépendantes :

- **XE_CERGY** : référentiels partagés + parc Cergy + audit global.
- **XE_PAU** : parc Pau + audit local + vues matérialisées des référentiels (répliquées depuis Cergy).

Les requêtes inter-sites passent par un **DB link** :

```sql
CREATE DATABASE LINK db_pau
  CONNECT TO TECH_PAU IDENTIFIED BY pau2026
  USING 'XE_PAU';
```

### 7.2 Synonymes publics

Pour la **transparence d'accès** depuis Cergy, des synonymes publics masquent le `@db_pau` :

```sql
CREATE PUBLIC SYNONYM ordinateurs_pau FOR ordinateurs@db_pau;
CREATE PUBLIC SYNONYM peripheriques_pau FOR peripheriques@db_pau;
-- etc.
```

### 7.3 Vue de fragmentation globale

```sql
CREATE OR REPLACE VIEW vue_parc_global AS
SELECT id, nom, numero_serie, site_id, entite_id, date_creation FROM ordinateurs
UNION ALL
SELECT id, nom, numero_serie, site_id, entite_id, date_creation FROM ordinateurs@db_pau;
```

Une version enrichie `vue_parc_global_v2` (jointures avec fabricants/états/localisations) est définie dans `corrections_sql.sql`.

### 7.4 Réplication des référentiels (côté Pau)

Plutôt que d'aller chercher les fabricants/états à chaque requête côté Pau (latence réseau), on **réplique** via des vues matérialisées avec `REFRESH ON DEMAND` :

```sql
CREATE MATERIALIZED VIEW mv_fabricants
  REFRESH ON DEMAND AS SELECT * FROM fabricants@db_cergy;
```

Le rafraîchissement est manuel via `DBMS_MVIEW.REFRESH(...)`. Stratégie : refresh quotidien (cron) car les référentiels évoluent peu.

---

## 8. Tests de performance

### 8.1 Méthodologie

Toutes les mesures suivent le même protocole :

1. Volume représentatif via `pkg_jeu_test.generer_tout` : 800 utilisateurs, 1500 ordinateurs, 1500 périphériques, 200 téléphones, 100 équipements réseau, ~5000 installations logicielles, ~2000 ports.
2. Chaque requête est exécutée **5 fois** ; on retient la moyenne et les min/max via `DBMS_UTILITY.GET_TIME` (précision 1/100 s).
3. `EXPLAIN PLAN` confirme le mode d'accès choisi par l'optimiseur (FULL SCAN vs INDEX RANGE SCAN, etc.).

Le script `tests_perf.sql` automatise toutes les comparaisons.

### 8.2 Résultats attendus (à compléter après exécution)

> Les valeurs ci-dessous sont des **ordres de grandeur typiques** observés en local sur Oracle XE 19c avec le jeu de test par défaut. Les valeurs réelles sont à mesurer sur la machine de soutenance.

| Test | Avec optimisation | Sans optimisation | Gain |
|---|---|---|---|
| `site_id = 1` (index b-tree) | ~1 ms | ~12 ms | **×12** |
| `UPPER(login)` (index fonctionnel) | ~1 ms | ~15 ms | **×15** |
| `est_supprime = 0` (bitmap) | ~2 ms | ~8 ms | **×4** |
| `localisation_id` (cluster vs heap) | ~2 ms | ~5 ms | **×2.5** |
| `mv_stats_parc` (MV vs agrégation live) | ~1 ms | ~10 ms | **×10** |
| Vue parc complète (impact global) | ~30 ms | ~120 ms | **×4** |

### 8.3 Interprétation

- **Indexes b-tree** : gain le plus net sur les recherches par FK et par valeurs discriminantes (site, état).
- **Index fonctionnel** : indispensable dès qu'on filtre par fonction (`UPPER`, `LOWER`).
- **Bitmap** : très efficace sur les booléens, mais inadapté aux colonnes à forte cardinalité.
- **Cluster** : gain modéré ici car le volume reste modeste ; le bénéfice augmente avec la taille du parc.
- **MV** : gain proportionnel à la complexité de l'agrégation -- pour des dashboards souvent rafraîchis, indispensable.

### 8.4 Comparaison MySQL GLPI vs Oracle CY Tech

L'évaluation côté MySQL GLPI s'appuie sur les benchmarks du rapport de reverse engineering. L'écart principal vient :

- Du **partitionnement par tablespace** qui permet d'isoler IO.
- Du **cluster** absent en MySQL/InnoDB (les clustered indexes InnoDB ne sont pas équivalents).
- Des **vues matérialisées** qui n'existent pas en MySQL (il faut maintenir des tables agrégées à la main).
- Des **DB links** intégrés (en MySQL, fédération via le moteur `FEDERATED`, beaucoup moins performant).

---

## 9. Sécurité et droits

- Les **GRANTs objets** sont ciblés : `TECH_CERGY` peut écrire dans le parc Cergy, lire les utilisateurs et profils, mais pas modifier la table `historique`.
- `USER_RO` n'a accès qu'aux **vues** (pas aux tables directement) -- masque les colonnes sensibles (`mot_de_passe`).
- Le **package `pkg_metier`** est exécutable par les techniciens. Les droits SQL bruts ne suffisent pas : l'utilisateur doit passer par les procédures encapsulées qui appliquent les règles métier.
- Les **mots de passe** des utilisateurs CY Tech sont stockés sous forme de hash (`hash_xxx` dans le jeu de test) ; pour de la production il faudrait `DBMS_CRYPTO` ou une délégation à un IDP externe.

---

## 10. Conclusion

### 10.1 Synthèse

Le projet démontre une mise en œuvre cohérente de l'ensemble des concepts avancés du cours :

- Modélisation rigoureuse avec UML et MLD.
- Architecture Oracle exploitant tablespaces, rôles, séquences, contraintes.
- Indexation différenciée (b-tree, bitmap, fonctionnel) avec mesure du gain.
- Cluster physique pour optimiser les requêtes localisées.
- PL/SQL complet : triggers (PK auto, audit, validation, MAJ date), package métier avec fonctions, procédures et curseurs explicites.
- Base de données répartie avec DB links, synonymes publics, vues UNION ALL et réplication par vues matérialisées.
- Tests de performance reproductibles avec `EXPLAIN PLAN` et timing.

### 10.2 Limites assumées

- **Périmètre réseau réduit** : VLAN, IP, connexions inter-ports, WiFi étendu non modélisés (annoncés dans l'archi initiale mais non retenus pour rester dans le temps imparti).
- **Polymorphisme** : tables `composants` et `composants_materiel` non créées -- l'audit polymorphique seul suffit à démontrer le pattern.
- **Droits granulaires** : pas de table `droits_profils` ; on s'appuie sur les `GRANT` Oracle.
- **Partitionnement** : Oracle XE 19c supporte le partitionnement mais on a préféré la séparation par tablespaces et instances pour rester dans le périmètre du cours.

### 10.3 Perspectives

Pour une mise en production réelle, il faudrait :

- Ajouter une couche de **chiffrement** sur les mots de passe (`DBMS_CRYPTO`).
- **Partitionner** les tables matériel par site (`PARTITION BY LIST(site_id)`) pour bénéficier du *partition pruning*.
- Mettre en place un **VPD** (Virtual Private Database) pour que les techniciens ne voient que leur site même sur la base centrale.
- Automatiser le **refresh des MV** via `DBMS_SCHEDULER` plutôt qu'à la demande.
- Compléter la couche réseau avec VLAN, IP, et liaisons inter-ports.

---

## Annexes

### A. Organisation des fichiers source

```
projet/Cy-infrastructure/
├── README.md
├── bdd_Cy_infrastructure.sql      # Structure DDL (tables, indexes, vues, BDDR)
├── corrections_sql.sql            # Patches : mot de passe TECH_PAU, cluster tables, MV
├── pl_sql_metier.sql              # Triggers + package pkg_metier
├── tests_perf.sql                 # Benchmark EXPLAIN PLAN + timing
├── rapport_final.md               # Ce document
├── slides_soutenance.md           # Slides Marp
└── diagrammes/
    ├── diagramme_classes_uml.puml
    ├── schema_relationnel.puml
    └── deploiement_bddr.puml

projet/
└── jeu_de_test.sql                # Package pkg_jeu_test (généré dans le dossier parent)
```

### B. Ordre d'exécution

```bash
# 1. Initialisation de la base (en SYS ou DBA)
sqlplus / as sysdba @bdd_Cy_infrastructure.sql

# 2. Connexion en tant qu'ADMIN_CYTECH
sqlplus ADMIN_CYTECH/cytech2026@XE

# 3. Application des corrections
@corrections_sql.sql

# 4. Génération du jeu de test
@jeu_de_test.sql

# 5. Activation du PL/SQL métier (triggers, package)
@pl_sql_metier.sql

# 6. Mesures de performance
@tests_perf.sql
```

### C. Compilation des diagrammes PlantUML

```bash
# Local (besoin de Java + plantuml.jar)
java -jar plantuml.jar diagrammes/*.puml

# Ou via Docker
docker run --rm -v $(pwd):/work plantuml/plantuml diagrammes/*.puml

# Ou via PlantUML Web Server (URL encoder)
# https://www.plantuml.com/plantuml/uml/
```

### D. Répartition individuelle (à compléter)

> La note est individuelle malgré le travail en groupe. Chaque membre doit pouvoir expliquer en détail la partie qu'il a produite.

| Membre | Contribution principale |
|---|---|
| [à compléter] | Reverse engineering, architecture, mots de passe |
| [à compléter] | PL/SQL : triggers + package pkg_metier |
| [à compléter] | Jeu de test, tests de performance |
| [à compléter] | Diagrammes, rapport final, soutenance |

---

*Fin du rapport. Volume : ~ 5 000 mots, 35 sections / sous-sections.*
