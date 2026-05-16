# Projet GLPI CY Tech - Document d'explication

Ce document détaille chaque partie du code, les choix techniques et la stratégie de reverse engineering. Il sert de **support à la rédaction du rapport final** et à la préparation de la soutenance.

---

## 0. Alignement avec l'énoncé

L'énoncé (MiniProjetSIE2026) demande sept concepts. Voici où chacun est implémenté.

| Concept demandé | État | Fichier |
|---|---|---|
| Users et rôles | OK (4 rôles, 4 users) | [bdd_Cy_infrastructure.sql](bdd_Cy_infrastructure.sql) §2 |
| Tablespaces | OK (7 tablespaces) | [bdd_Cy_infrastructure.sql](bdd_Cy_infrastructure.sql) §1 |
| Clusters | **Abandonné** (à justifier) | voir §12.1 ci-dessous |
| Index | OK (B-tree, bitmap, fonctionnels) | [bdd_Cy_infrastructure.sql](bdd_Cy_infrastructure.sql) §9 |
| Vues | OK (6 vues + 1 MV) | [bdd_Cy_infrastructure.sql](bdd_Cy_infrastructure.sql) §10 |
| PL/SQL (triggers/curseurs/proc/fonctions) | OK (41+11+6 + 4 packages) | [pl_sql_*.sql](.) |
| BDDR | OK (db link, synonymes, vue répartie) | [bdd_Cy_infrastructure.sql](bdd_Cy_infrastructure.sql) §11 |
| Plan de requêtes | OK (EXPLAIN PLAN) | [tests_perf.sql](tests_perf.sql) |
| Jeu de test conséquent | OK (~13 000 lignes) | [jeu_de_test.sql](jeu_de_test.sql) |
| Tests de performance | OK | [tests_perf.sql](tests_perf.sql) |
| **Comparaison ancienne base** | **À ajouter dans le rapport** | analyse théorique GLPI |
| **Diagrammes UML / relationnels** | À finaliser | [diagrammes/](diagrammes/) (.puml) |

**Manques à combler avant le rendu :**
1. Justifier dans le rapport pourquoi le cluster a été abandonné (ou le réintégrer).
2. Mettre à jour les `.puml` dans [diagrammes/](diagrammes/) (encore au schéma `entites`/`profils_utilisateurs`).
3. Tracer les graphiques de perf à partir des résultats §11.
4. Présenter la comparaison "avant/après" : structure GLPI brute vs notre version refactorée.

---

## 1. Stratégie de reverse engineering

### 1.1 Sources analysées

- Doc officielle GLPI : https://github.com/glpi-project/glpi
- Schéma physique GLPI : tables `glpi_computers`, `glpi_users`, `glpi_profiles`, `glpi_entities`, `glpi_locations`, `glpi_networkequipments`, `glpi_softwares`, etc.
- [Architecture_BDD_GLPI.docx](Architecture_BDD_GLPI.docx) et [Rapport_Reverse_Engineering_GLPI.docx](Rapport_Reverse_Engineering_GLPI.docx) déjà dans le dépôt.

### 1.2 Constats sur la BDD GLPI brute

GLPI est conçu pour la généricité (n'importe quel parc, n'importe quelle organisation). Cela se traduit par :

- **Forte normalisation** : ~370 tables, beaucoup de tables de liaison M:N peu utilisées.
- **Tables polymorphes** : `glpi_items_*` qui peuvent référencer n'importe quel type (computers, peripherals, phones...) via un couple `itemtype/items_id`. Très souple mais peu performant et difficile à indexer.
- **Pas de partitionnement multi-sites natif** : tout est dans une seule instance, avec une notion d'**entité** (organisationnelle) qui sert de filtre logique.
- **Profils complexes** : un user peut avoir plusieurs profils par entité avec récursivité (`glpi_profiles_users`). Pour CY Tech cette flexibilité est inutile (un user = un profil).
- **Audit dispersé** : pas de table d'historique unique, chaque table a ses propres colonnes `date_creation`, `date_mod`.

### 1.3 Décisions de simplification

Trois axes de simplification, justifiés par le périmètre CY Tech :

1. **Pas de polymorphisme** : on a une table par type de matériel (`ordinateurs`, `peripheriques`, `telephones`) avec leurs colonnes propres. Plus simple à indexer, et le coût en duplication est faible (3 tables au lieu d'une polymorphe).
2. **Hiérarchie unique `hierarchy_level`** : on garde le concept d'entité de GLPI (CY Tech > Cergy/Pau > Département) parce que c'est central à la gestion multi-sites. Mais on supprime la table de jointure `profils_utilisateurs` (M:N) puisqu'un user a toujours un seul profil → on met `profil_id` directement sur `utilisateurs`.
3. **Audit centralisé** : une seule table `historique` qui log toute opération sur les tables sensibles via triggers et une procédure factorisée `log_change`.

### 1.4 Décisions multi-sites

Sur le périmètre fonctionnel "matériel + réseau + utilisateurs", deux options étaient possibles :

- **A.** Une seule instance, un colonne `site_id` partout. Avantage : simple. Inconvénient : pas de vraie BDDR, pas de gain de perf, vulnérabilité unique.
- **B.** Deux instances (une par campus), liées par db link. Avantage : indépendance des sites, charge répartie, BDDR au sens du cours. Inconvénient : complexité de déploiement et de synchronisation.

**Choix : option B.** Le terme "multi-sites" + l'exigence BDDR de l'énoncé poussent vers une vraie répartition. Concrètement :
- L'instance **Cergy** porte les matériels du site Cergy dans `TS_MATERIEL_CERGY` et `TS_NETWORK_CERGY`.
- L'instance **Pau** porte les matériels du site Pau dans `TS_MATERIEL_PAU` et `TS_NETWORK_PAU`.
- Les **référentiels** (sites, fabricants, états, hierarchy_level, profils, utilisateurs) sont sur les deux instances pour préserver l'intégrité référentielle.
- Une **vue répartie** `vue_parc_global_v2` permet à un utilisateur de Cergy de voir le parc global en `UNION ALL` local + distant via `db_pau`.

---

## 2. Architecture physique

```
+--------------------+         +--------------------+
|     XE_CERGY       |         |      XE_PAU        |
|  (PDB sur XE)      | <-----> |  (PDB sur XE)      |
|                    |  db_pau |                    |
| TS_MATERIEL_CERGY  | <-----> | TS_MATERIEL_PAU    |
| TS_NETWORK_CERGY   | db_cergy| TS_NETWORK_PAU     |
| TS_USERS, TS_INDEX |         | TS_USERS, TS_INDEX |
+--------------------+         +--------------------+
        |                                ^
        | TECH_CERGY ecrit               | TECH_PAU lit/ecrit
        | TECH_PAU lit                   |
        v                                |
   ADMIN_CYTECH (admin)
   USER_RO (lecture seule via vues)
```

Sur Oracle XE 21c en environnement de test, les deux campus sont matérialisés par deux **PDB** (Pluggable Databases) dans le même CDB. En production, ce seraient deux instances Oracle physiques distinctes sur deux serveurs.

---

## 3. Modèle de données

### 3.1 Tables référentielles (TS_USERS)

| Table | Rôle | Clés étrangères |
|---|---|---|
| `sites` | CY Tech Cergy, CY Tech Pau | - |
| `hierarchy_level` | Structure organisationnelle (CY Tech > Cergy/Pau > Dept) | `hierarchy_level_parent_id`, `site_id` |
| `localisations` | Bâtiment, étage, salle | `hierarchy_level_id`, `localisation_parent_id` |
| `fabricants` | Dell, HP, Apple, Cisco... (20 lignes) | - |
| `etats` | En service, En réparation, Réformé... (8) | - |
| `types_ordinateur` | Desktop, Laptop, Serveur... (5) | - |
| `modeles_ordinateur` | Modèles précis avec ref produit | `fabricant_id` |
| `profils` | Admin, Technicien, Enseignant, Étudiant, Administration | - |

**Pourquoi `hierarchy_level` est récursive** : la hiérarchie peut avoir des niveaux variables (CY Tech, puis Cergy ou Pau, puis Service ou Département, puis sous-département). Une auto-référence `hierarchy_level_parent_id` permet de modéliser ça sans table de jointure et de naviguer avec `CONNECT BY` (cf. fonction `f_nom_complet_hierarchy_level`).

### 3.2 Tables utilisateurs (TS_USERS)

| Table | Rôle |
|---|---|
| `utilisateurs` | Tous les comptes applicatifs (~2620 dans le jeu de test) |
| `groupes` | Regroupements logiques de matériel ("PC salle TP Cauchy") |

`utilisateurs.profil_id` → `profils(id)` : remplace la jointure M:N de GLPI.

### 3.3 Tables matériel (TS_MATERIEL_CERGY ou _PAU)

| Table | Rôle | Cardinalité (jeu de test) |
|---|---|---|
| `ordinateurs` | PC fixes + portables | 2 719 |
| `peripheriques` | Imprimantes, souris, claviers, vidéoprojecteurs | 383 |
| `telephones` | Téléphones fixes (admin) | 29 |
| `logiciels` | Office, Adobe, IDEs... | 20 |
| `versions_logiciel` | Plusieurs versions par logiciel | ~70 |
| `installations_logiciels` | Quel ordi a quel logiciel/version | 7 854 |

Chaque table matériel a `site_id`, `hierarchy_level_id`, `localisation_id`, `etat_id`, `fabricant_id` pour permettre les jointures référentielles et les filtres par site.

### 3.4 Tables réseau (TS_NETWORK_CERGY ou _PAU)

| Table | Rôle | Cardinalité |
|---|---|---|
| `types_equip_reseau` | Switch, Routeur WiFi, Borne WiFi | 3 |
| `equipements_reseau` | Le matériel actif | 143 |
| `ports_reseau` | Ports ethernet/wifi avec MAC, vitesse, état | 3 120 |

### 3.5 Table d'audit (TS_USERS)

| Table | Rôle |
|---|---|
| `historique` | Journal de toutes les modifs sensibles (INSERT/UPDATE/DELETE) |

Colonnes : `type_objet`, `objet_id`, `champ_modifie`, `ancienne_valeur`, `nouvelle_valeur`, `type_action`, `utilisateur_id`, `date_action`.

---

## 4. Utilisateurs et rôles Oracle

Voir [bdd_Cy_infrastructure.sql](bdd_Cy_infrastructure.sql) §2.

### 4.1 Rôles

| Rôle | Privilèges système |
|---|---|
| `R_ADMIN` | CONNECT, RESOURCE, CREATE TABLE/VIEW/PROC/TRIGGER/SEQUENCE/SYNONYM/DATABASE LINK/CLUSTER/MATERIALIZED VIEW |
| `R_TECH_CERGY` | CONNECT, RESOURCE, CREATE SESSION |
| `R_TECH_PAU` | CONNECT, RESOURCE, CREATE SESSION |
| `R_CONSULTATION` | CONNECT, CREATE SESSION |

### 4.2 Utilisateurs

| User | Rôle | Mot de passe | Rôle métier |
|---|---|---|---|
| `ADMIN_CYTECH` | R_ADMIN | cytech2026 | Propriétaire du schéma applicatif |
| `TECH_CERGY` | R_TECH_CERGY | cergy2026 | Technicien Cergy (R/W matériel + réseau Cergy) |
| `TECH_PAU` | R_TECH_PAU | pau2026 | Technicien Pau, sert aussi de compte de connexion pour le db link |
| `USER_RO` | R_CONSULTATION | RO2026 | Lecture seule sur les vues + MV |

### 4.3 Privilèges objet

- `TECH_CERGY` a SELECT/INSERT/UPDATE/DELETE sur ordinateurs, peripheriques, telephones, logiciels, equipements_reseau, ports_reseau.
- `TECH_PAU` a SELECT sur toutes les tables consommées par le DB link, plus EXECUTE sur les packages métier.
- `USER_RO` n'a SELECT que sur les **vues** et la MV (pas sur les tables sous-jacentes) : protection des données détaillées, exposition uniquement de l'agrégat.

**Note pédagogique** : `UNLIMITED TABLESPACE` ne peut pas être granté à un rôle (ORA-01931), seulement à un user. C'est pour ça qu'il est accordé directement à `ADMIN_CYTECH`.

---

## 5. Tablespaces

Voir [bdd_Cy_infrastructure.sql](bdd_Cy_infrastructure.sql) §1.

| Tablespace | Stocke | Taille init / max | Justification |
|---|---|---|---|
| `TS_MATERIEL_CERGY` | ordinateurs/periph/tel locaux Cergy | 100M / 500M | Volume principal côté Cergy |
| `TS_MATERIEL_PAU` | équiv. côté Pau (sur instance Pau) | 100M / 500M | Volume principal côté Pau |
| `TS_NETWORK_CERGY` | equipements_reseau + ports Cergy | 50M / 200M | Séparation logique réseau |
| `TS_NETWORK_PAU` | équiv. côté Pau | 50M / 200M | idem |
| `TS_USERS` | référentiels + utilisateurs + historique | 50M / 200M | Tables partagées, peu mises à jour |
| `TS_INDEX` | tous les index B-tree, bitmap, fonctionnels | 50M / 200M | Sépare data et index → I/O parallélisables |
| `TS_TEMP` | tri, hash join | 50M / 200M | TEMPORARY tablespace |

**Pourquoi cette séparation** :

1. **Performance** : séparer index et data permet à Oracle de paralléliser les lectures.
2. **Maintenance** : sauvegarde différenciée possible (les index sont reconstructibles, pas les data).
3. **Multi-sites** : un tablespace par site/type rend explicite l'appartenance des données. Sur la vraie instance Pau, seuls `TS_MATERIEL_PAU` et `TS_NETWORK_PAU` portent du data ; les autres sont des copies des référentiels.

---

## 6. Index

Voir [bdd_Cy_infrastructure.sql](bdd_Cy_infrastructure.sql) §9.

### 6.1 Index B-tree (FK + recherche)

Sur **chaque clé étrangère** des tables volumineuses (ordinateurs, peripheriques, telephones, equipements_reseau, ports_reseau, utilisateurs) :
- `hierarchy_level_id`, `localisation_id`, `utilisateur_id`, `fabricant_id`, `etat_id`, `site_id`
- Plus quelques champs de recherche : `nom`, `numero_serie`

**Pourquoi** : sans index sur FK, les requêtes avec jointure font des FULL TABLE SCAN. Avec, on a un INDEX RANGE SCAN qui est O(log n).

### 6.2 Index Bitmap (faible cardinalité)

Sur les colonnes booléennes :
- `ordinateurs(est_supprime)`, `ordinateurs(est_template)`
- `utilisateurs(est_actif)`, `utilisateurs(est_supprime)`
- `ports_reseau(type_port)` (cardinalité 2 : ethernet/wifi)

**Pourquoi** : un bitmap stocke 1 bit par ligne par valeur. Pour 2 valeurs distinctes (0/1), c'est ultra-compact et rapide pour les AND/OR.

### 6.3 Index fonctionnels

- `ordinateurs(UPPER(nom))`
- `utilisateurs(UPPER(login))`

**Pourquoi** : sans, une recherche `WHERE UPPER(login) = 'XXX'` masque l'index classique sur `login` → FULL SCAN. L'index fonctionnel permet à l'optimiseur d'utiliser un INDEX RANGE SCAN sur le b-tree de la valeur transformée.

### 6.4 Index composite

- `historique(type_objet, objet_id)` : les requêtes d'audit filtrent toujours sur ces deux colonnes ensemble.

---

## 7. Vues

Voir [bdd_Cy_infrastructure.sql](bdd_Cy_infrastructure.sql) §10.

| Vue | Rôle | Site filtré |
|---|---|---|
| `vue_parc_cergy` | Tout le parc Cergy avec libellés humains (fabricant, état, localisation, user) | 1 |
| `vue_parc_pau` | Idem côté Pau | 2 |
| `vue_peripheriques_site` | Tous les périphériques | les deux |
| `vue_reseau_site` | Équipements réseau + ports | les deux |
| `vue_utilisateurs_droits` | Utilisateurs + profil + hierarchy_level | les deux |
| `vue_parc_global` | Cergy + Pau via UNION ALL (BDDR simple) | les deux (db_pau) |
| `vue_parc_global_v2` | Idem avec jointures sur tous les référentiels | les deux (db_pau) |

### 7.1 Vue matérialisée `mv_stats_parc`

```sql
SELECT s.nom AS site, e.nom AS etat, COUNT(*) AS nb_ordinateurs
  FROM ordinateurs o JOIN sites s ON o.site_id = s.id
  LEFT JOIN etats e ON o.etat_id = e.id
 WHERE o.est_supprime = 0
 GROUP BY s.nom, e.nom;
```

**Mode `REFRESH ON DEMAND`** : on rafraîchit manuellement via `pkg_maintenance.refresh_mv_stats`. Avantage : pas d'overhead à chaque INSERT. Inconvénient : peut être périmée. C'est acceptable pour un tableau de bord ; pour une stat critique, on passerait à `REFRESH FAST ON COMMIT` (qui demande un MATERIALIZED VIEW LOG).

### 7.2 Trigger INSTEAD OF

`trg_insert_vue_parc_global` ([pl_sql_triggers.sql](pl_sql_triggers.sql)) : trigger spécial qui permet d'**INSERT dans une vue UNION ALL**. Sans ce trigger, Oracle refuse parce qu'il ne sait pas quelle table cibler. Le trigger redirige selon `site_id` :
- `site_id = 1` → INSERT sur `ordinateurs` (local Cergy)
- `site_id = 2` → INSERT sur `ordinateurs@db_pau` (distant)

C'est un cas d'école qu'on peut présenter à l'oral.

---

## 8. PL/SQL

### 8.1 Triggers ([pl_sql_triggers.sql](pl_sql_triggers.sql)) — 41 triggers

| Catégorie | Nombre | Rôle |
|---|---|---|
| Auto-incrément PK | 10 | Pour les tables sans `IDENTITY` (compatibilité Oracle ≤ 11) |
| MAJ `date_modification` | 11 | `BEFORE UPDATE` met `:NEW.date_modification := SYSDATE` |
| Audit | 8 | `AFTER INSERT/UPDATE/DELETE` appelle `log_change` qui INSERT dans `historique` |
| Cohérence site/hierarchy_level | 5 | Empêche d'affecter un matériel Cergy à une entité Pau (et inversement) |
| Validation métier | 6 | Format MAC, dates date_fin ≥ date_debut, anti-suppression d'ordi avec logiciels, anti-suppression d'équipement avec ports actifs, unicité numéro de série par site, anti-auto-référence hiérarchique |
| INSTEAD OF sur vue UNION ALL | 1 | Bonus pédagogique (cf. §7.2) |

**Procédure factorisée `log_change`** : tous les triggers d'audit appellent une procédure unique qui INSERT dans `historique`. Évite ~200 lignes de code dupliqué.

**À noter dans le rapport** : les triggers d'audit utilisent la transaction normale (rollback de l'audit si la transaction métier rollback). Pour un audit qui survit aux rollbacks, voir `pkg_maintenance.audit_erreur` qui utilise `PRAGMA AUTONOMOUS_TRANSACTION`.

### 8.2 Fonctions standalone ([pl_sql_functions.sql](pl_sql_functions.sql)) — 11 fonctions

Fonctions utilitaires appelables depuis SQL ou PL/SQL :

| Fonction | Rôle |
|---|---|
| `f_nb_ordinateurs_site(p_site_id)` | Compte ordis d'un site |
| `f_nb_materiel_site(p_site_id)` | Compte tout matériel d'un site |
| `f_nom_site(p_site_id)` | Nom du site |
| `f_taux_utilisation_site(p_site_id)` | % d'ordis affectés à un user |
| `f_age_moyen_parc(p_site_id)` | Âge moyen en années |
| `f_utilisateur_actif(p_user_id)` | Boolean |
| `f_nb_logiciels_ordinateur(p_ordi_id)` | Combien de logiciels sur un ordi |
| `f_age_materiel_jours(p_ordi_id)` | Âge en jours |
| `f_nb_ports_actifs(p_equip_id)` | Combien de ports up sur un équipement |
| `f_user_id_par_email(p_email)` | Lookup |
| `f_nom_complet_hierarchy_level(p_id)` | "CY Tech > Cergy > Dept Info" via CONNECT BY + LISTAGG |

### 8.3 Procédures standalone ([pl_sql_procedures.sql](pl_sql_procedures.sql)) — 5 procédures

| Procédure | Rôle | Concepts démontrés |
|---|---|---|
| `p_ajouter_ordinateur` | Ajoute un ordi avec validations | RAISE_APPLICATION_ERROR, PRAGMA EXCEPTION_INIT |
| `p_transferer_ordinateur` | Transfère un ordi entre sites | Cohérence FK |
| `p_desactiver_utilisateur` | Désactive + libère le matériel | **Curseur explicite** sur ordis |
| `p_installer_logiciel` | Installe un logiciel sur un ordi | DUP_VAL_ON_INDEX |
| `p_supprimer_materiel` | Soft delete par type | CASE WHEN |

### 8.4 Packages ([pl_sql_packages.sql](pl_sql_packages.sql)) — 4 packages

| Package | Contenu | Concept clé |
|---|---|---|
| `pkg_parc_info` | 3 fonctions + 6 procédures (rapport_parc_site, marquer_obsoletes...) | **SYS_REFCURSOR** retourné, **FOR UPDATE OF + WHERE CURRENT OF**, constantes, exceptions custom |
| `pkg_stats` | 3 fonctions + 3 procédures (rapport_logiciels_site, rapport_activite_recente, rapport_utilisateurs_sans_materiel) | Sous-requêtes corrélées, **NOT EXISTS** |
| `pkg_reseau` | 1 fonction + 5 procédures (ajouter_equipement_reseau, creer_ports_equipement, taux_occupation_ports) | Boucle FOR pour créer les 48 ports |
| `pkg_maintenance` | 6 procédures (audit_erreur, purger_corbeille, refresh_mv_stats, transferer_materiel, archiver_utilisateur) | **PRAGMA AUTONOMOUS_TRANSACTION**, **%ROWTYPE**, CONNECT BY indirect |

**Concepts du cours couverts** :
- Spec + body de packages
- Constantes et exceptions custom (`PRAGMA EXCEPTION_INIT`)
- `PRAGMA AUTONOMOUS_TRANSACTION` (audit qui survit au rollback)
- Curseurs explicites paramétrés (OPEN/FETCH/CLOSE, FOR..IN, FOR UPDATE OF + WHERE CURRENT OF)
- `SYS_REFCURSOR`
- `%ROWTYPE`, `%TYPE`
- Exceptions nominées : `NO_DATA_FOUND`, `DUP_VAL_ON_INDEX`
- `RAISE_APPLICATION_ERROR` (codes -20000 à -20999)
- `SQL%ROWCOUNT`, `SQLCODE`, `SQLERRM`

---

## 9. Base de données répartie (BDDR)

Voir [bdd_Cy_infrastructure.sql](bdd_Cy_infrastructure.sql) §11.

### 9.1 Database link

```sql
CREATE DATABASE LINK db_pau
  CONNECT TO TECH_PAU IDENTIFIED BY pau2026
  USING 'XE_PAU';
```

**Stratégie de réplication** :
- Pas de réplication automatique entre les deux instances : chaque site est maître de ses propres matériels.
- Les **référentiels** (sites, hierarchy_level, profils, fabricants, etats, utilisateurs) sont dupliqués sur les deux instances. En production, ils seraient maintenus synchronisés via des **vues matérialisées REFRESH ON DEMAND** côté Pau qui pointent sur Cergy (voir le bloc commenté §13 du fichier principal).
- Les **matériels distants** sont accessibles depuis Cergy via `ordinateurs@db_pau` (et symétriquement depuis Pau via `db_cergy`).

### 9.2 Synonymes publics

Deux séries de synonymes :

**Série 1 : transparence d'accès cross-DB**
```sql
CREATE OR REPLACE PUBLIC SYNONYM ordinateurs_pau FOR ordinateurs@db_pau;
```
Permet de faire `SELECT * FROM ordinateurs_pau` au lieu de `SELECT * FROM ordinateurs@db_pau`. Cache la BDDR aux applis clientes.

**Série 2 : résolution de schéma (ajoutée pour le test)**
```sql
CREATE OR REPLACE PUBLIC SYNONYM ordinateurs FOR admin_cytech.ordinateurs;
```
Quand `TECH_PAU` se connecte via le db link et reçoit une requête `SELECT FROM ordinateurs`, son schéma n'a pas cette table. Le synonyme public la résout vers `admin_cytech.ordinateurs` à laquelle TECH_PAU a accès en SELECT.

### 9.3 Vue répartie

```sql
CREATE OR REPLACE FORCE VIEW vue_parc_global_v2 AS
SELECT 'CERGY' AS source, o.id, o.nom, ..., f.nom AS fabricant, ...
  FROM ordinateurs o
  LEFT JOIN fabricants f ON f.id = o.fabricant_id
  ...
 WHERE o.est_supprime = 0
UNION ALL
SELECT 'PAU' AS source, o.id, o.nom, ..., f.nom, ...
  FROM ordinateurs@db_pau o
  LEFT JOIN fabricants@db_pau f ON f.id = o.fabricant_id
  ...
 WHERE o.est_supprime = 0;
```

**Le `FORCE`** permet à la vue d'être créée comme INVALID si `db_pau` n'est pas accessible au moment du déploiement. Quand l'instance Pau est en place, un `ALTER VIEW vue_parc_global_v2 COMPILE` la rend VALID.

**Test BDDR validé** :
1. INSERT d'une ligne marqueur sur XE_PAU
2. `SELECT * FROM sites@db_pau WHERE nom = 'MARKER-PAU'` depuis XE_CERGY → la ligne est récupérée → le link transporte bien les données entre PDB.

---

## 10. Plan de requêtes

Voir [tests_perf.sql](tests_perf.sql).

Chaque test fait un `EXPLAIN PLAN FOR <requête>` puis `SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY)` pour visualiser le plan choisi par l'optimiseur (FULL SCAN, INDEX RANGE SCAN, NESTED LOOPS, HASH JOIN…).

Exemple, avant/après index sur `site_id` :
- **Sans index** : `TABLE ACCESS FULL` sur `ordinateurs` → balaye toutes les lignes.
- **Avec index** : `INDEX RANGE SCAN` sur `idx_ordi_site` + `TABLE ACCESS BY INDEX ROWID` → lit le b-tree puis ne va chercher que les bonnes lignes.

À mettre dans le rapport : capture d'écran d'un plan AVEC index et SANS, côte à côte.

---

## 11. Tests de performance

### 11.1 Méthodologie

[tests_perf.sql](tests_perf.sql) définit une procédure `bench_query(libelle, requete, nb_runs)` qui :
1. Exécute la requête `p_nb_runs` fois (5 par défaut)
2. Mesure le temps en centisecondes via `DBMS_UTILITY.GET_TIME`
3. Calcule moyenne, min, max

Pour chaque test, on compare AVEC et SANS l'optimisation (en droppant temporairement l'index/MV, puis en le recréant).

### 11.2 Résultats sur le jeu de test actuel

(Centisecondes. Jeu de test = 2 719 ordinateurs, ~13 000 lignes au total.)

| Test | AVEC optim | SANS | Gain |
|---|---|---|---|
| `ordinateurs WHERE site_id = 1` (B-tree) | 0,6 | ~0 | trop petit pour différencier |
| `UPPER(login) = 'X'` (idx fonctionnel) | ~0 | 0,2 | léger |
| `est_supprime = 0` (bitmap) | ~0 | ~0 | trop petit |
| MV `mv_stats_parc` vs requête live | ~0 | 0,4 | MV gagne |
| **Local vs db_pau** | ~0 | **2,4** | **local ~10× plus rapide** |
| `vue_parc_cergy` (impact global indexes) | 0,4 | ~0 | n/a (jeu trop petit) |

**Interprétation** : la différence local/distant est la mesure la plus parlante avec ce jeu. Les autres tests demandent un jeu plus gros pour montrer la différence (la table tient en mémoire à 2719 lignes, donc le FULL SCAN est ~aussi rapide qu'un index).

### 11.3 Comment amplifier les écarts pour le rapport

Relancer `jeu_de_test.sql` avec des volumes plus gros :

```sql
EXEC pkg_jeu_test.reset_donnees;
EXEC pkg_jeu_test.generer_tout(p_nb_etudiants => 50000, p_nb_profs => 500, p_nb_admins => 100, p_nb_techs => 30);
```

Avec 50 000 étudiants, on aurait ~50 000 portables + 140 fixes + tout le périph → un dataset qui dépasse le cache mémoire et où les index font une vraie différence.

### 11.4 Comparaison avec l'ancienne base (GLPI brut)

L'énoncé demande explicitement cette comparaison. **À rédiger dans le rapport** (analyse théorique faute d'instance GLPI live) :

| Aspect | GLPI brut | Notre version | Gain |
|---|---|---|---|
| Polymorphisme `glpi_items_*` | Filtre sur `itemtype` + `items_id` (FULL SCAN typique) | Table dédiée par type | Index direct sur la FK |
| `glpi_profiles_users` (M:N) | Jointure obligatoire pour avoir le profil | Colonne `profil_id` sur `utilisateurs` | Pas de jointure |
| Pas d'audit central | Logs dispersés | Table `historique` unique | Reporting simple |
| Pas de cluster multi-sites | Tout sur une instance | BDDR Cergy/Pau | Charge répartie, latence locale |
| Pas d'index bitmap | Beaucoup d'index B-tree sur booléens | Bitmap où pertinent | Compact + AND/OR rapides |

---

## 12. Choix techniques justifiés

### 12.1 Cluster abandonné

Le cluster Oracle a été créé puis retiré. Raisons documentées :

- Un cluster co-localise physiquement les lignes de plusieurs tables partageant une clé. Pertinent quand on lit TOUJOURS les tables ensemble.
- Dans notre cas, `ordinateurs` et `peripheriques` partagent `localisation_id` mais sont rarement consultés ensemble dans les vues métier (on a une vue par type).
- Le gain est marginal sur des tables de quelques milliers de lignes ; il deviendrait visible à 100K+ lignes.
- En contrepartie, le cluster complique la maintenance (impossibilité de `TRUNCATE` indépendant, plan d'exécution moins prévisible).

**Décision finale** : ne pas l'inclure. **À justifier oralement** comme un choix éclairé après analyse, pas comme un oubli.

**Si on veut le réintégrer** (l'énoncé l'attend explicitement), il faudrait :
1. Recréer le cluster `cl_materiel_localisation` dans le fichier principal.
2. Créer deux tables `ordinateurs_cl` et `peripheriques_cl` qui utilisent le cluster.
3. Ajouter un TEST 4 dans `tests_perf.sql` qui compare un SELECT par localisation sur les versions cluster vs heap.

### 12.2 `profils` restaurée

La table `profils` avait été supprimée initialement (proposition de simplification). Elle a été restaurée parce que :
- Tout le code (triggers d'audit, jeu de test, packages) y faisait référence.
- C'est un référentiel métier indispensable, au même titre que `etats` ou `fabricants`.
- La sémantique "Admin / Technicien / Enseignant / Étudiant / Administration" est centrale au reporting.

En revanche, la jointure M:N `profils_utilisateurs` a été supprimée définitivement : dans CY Tech un user a toujours un seul profil, donc cette table ajoutait de la complexité pour rien.

### 12.3 Schéma applicatif sous `ADMIN_CYTECH` (pas SYS)

Initialement le script tentait de tout créer sous `SYS`. Oracle refuse : `ORA-04089: cannot create triggers on objects owned by SYS`. C'est intentionnel — SYS est protégé.

Le script fait donc un `CONNECT ADMIN_CYTECH/cytech2026@<pdb>` mid-script pour basculer dans le bon schéma avant de créer tables/index/vues/triggers/etc.

### 12.4 Oracle Managed Files pour les datafiles

Les `CREATE TABLESPACE TS_X DATAFILE 'ts_x.dbf'` avec chemin relatif causaient un conflit `ORA-01537` quand on déployait sur les deux PDBs (les deux essayaient d'écrire dans le même répertoire `database/`).

**Solution** : `ALTER SESSION SET db_create_file_dest = <chemin du PDB courant>` au début du script, puis `CREATE TABLESPACE ... DATAFILE SIZE 100M ...` sans nom de fichier. Oracle génère un nom unique dans le bon dossier.

### 12.5 Synonymes publics double couche

Pour que le db link fonctionne, deux résolutions sont nécessaires :
1. **Cergy → Pau** : `ordinateurs@db_pau` part vers XE_PAU comme TECH_PAU.
2. **Sur XE_PAU côté TECH_PAU** : la requête arrive avec un nom non qualifié `ordinateurs`. TECH_PAU n'a pas cette table. Il faut un synonyme public `ordinateurs FOR admin_cytech.ordinateurs` pour que TECH_PAU puisse résoudre le nom.

C'est subtil — à mentionner à l'oral comme "piège classique" de la BDDR avec users séparés.

### 12.6 `SET DEFINE OFF` dans le jeu de test

`jeu_de_test.sql` contient des chaînes comme `'Dept Biotech & Chimie'`. Sans `SET DEFINE OFF`, SQL*Plus interprète le `&` comme un appel à une variable de substitution et bloque sur un prompt. Le `SET DEFINE OFF` désactive ce comportement.

### 12.7 Refacto des INSERTs dans le jeu de test

Oracle interdit deux choses dans une `INSERT VALUES` :
- L'accès à des **collections PL/SQL** (`v_fabricants(idx)`, `v_fabricants.COUNT`).
- L'appel à des **fonctions qui lisent l'état d'un package** (`random_hl_site` qui lit `v_cergy_dpt_min` du package).

Erreurs : `PLS-00231`, `ORA-00984`. Solution : assigner toutes les valeurs à des variables PL/SQL **avant** l'INSERT, puis utiliser uniquement des variables dans le VALUES. Une dizaine de procédures ont été refactorées dans ce sens.

---

## 13. Difficultés rencontrées (à mentionner à l'oral)

| Problème | Cause | Solution |
|---|---|---|
| `CREATE OR REPLACE TABLE` invalide | Oracle ne supporte `OR REPLACE` que pour VIEW/PROC/FUNC/TRIGGER/PACKAGE/SYNONYM/TYPE | Retiré, idempotence via DROP PDB + CREATE PDB |
| `CREATE ROLE` ignoré | Commentaire `--` inline après le `;` parasitait le parseur SQL*Plus | Commentaires sur ligne séparée |
| `UNLIMITED TABLESPACE` à un rôle | Privilège réservé aux users (ORA-01931) | Granté directement à `ADMIN_CYTECH` |
| `ORA-04089` triggers SYS | Oracle refuse de créer des triggers sur tables SYS | `CONNECT ADMIN_CYTECH` mid-script |
| Datafile name conflict entre PDBs | Chemin relatif → résolu pareil sur les deux | Oracle Managed Files via `db_create_file_dest` |
| sqlplus bloqué sans output | Pas de `/` après les `END;` des blocs PL/SQL | Script de patch automatique : ajout `/` après chaque `END;` outer |
| `Entrez une valeur pour chimie` | `&` dans la chaîne `'Biotech & Chimie'` interprété comme variable | `SET DEFINE OFF` |
| `PLS-00231` sur fonctions | Fonctions lisant l'état du package non SQL-callable | Affectation à variables PL/SQL avant l'INSERT |
| `ORA-02291` FK violation après rollback | Séquences Oracle ne rollback pas → décalage entre IDs réels et constantes `c_site_cergy=1` | Drop+recreate PDB pour repartir propre |
| `ORA-20103` cohérence site | `Bureau_PAU_01` ne matchait pas `LIKE 'PAU%'` mais son hierarchy_level pointait Pau | Site lu via `SELECT site_id FROM hierarchy_level WHERE id = …` au lieu du parsing de nom |

---

## 14. Procédure de déploiement (testée bout-en-bout)

### 14.1 Prérequis

- Oracle XE 21c installé
- Service `OracleServiceXE` démarré
- Listener `OracleOraDB21Home1TNSListener` démarré
- Mot de passe SYS connu

### 14.2 Étapes

```sql
-- ETAPE 1 : Comme SYS dans CDB$ROOT, creer les 2 PDBs
sqlplus sys/<pwd>@//localhost:1521/XE as sysdba

CREATE PLUGGABLE DATABASE XE_CERGY ADMIN USER pdbadmin IDENTIFIED BY pdbpass
  FILE_NAME_CONVERT = ('<chemin>/PDBSEED/', '<chemin>/XE_CERGY/');
CREATE PLUGGABLE DATABASE XE_PAU ADMIN USER pdbadmin IDENTIFIED BY pdbpass
  FILE_NAME_CONVERT = ('<chemin>/PDBSEED/', '<chemin>/XE_PAU/');
ALTER PLUGGABLE DATABASE XE_CERGY OPEN;
ALTER PLUGGABLE DATABASE XE_PAU OPEN;
ALTER PLUGGABLE DATABASE XE_CERGY SAVE STATE;
ALTER PLUGGABLE DATABASE XE_PAU SAVE STATE;
```

### 14.3 tnsnames.ora

Ajouter dans `<ORACLE_HOME>/network/admin/tnsnames.ora` :

```
XE_CERGY = (DESCRIPTION = (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1521))
            (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = XE_CERGY)))
XE_PAU   = (DESCRIPTION = (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1521))
            (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = XE_PAU)))
```

### 14.4 Déploiement sur chaque PDB

Sur **XE_CERGY** puis sur **XE_PAU**, dans cet ordre :

```bash
sqlplus sys/<pwd>@XE_CERGY as sysdba @bdd_Cy_infrastructure.sql
# Le script bascule automatiquement en ADMIN_CYTECH au bon moment
```

Puis comme `ADMIN_CYTECH` :

```bash
sqlplus ADMIN_CYTECH/cytech2026@XE_CERGY @pl_sql_triggers.sql
sqlplus ADMIN_CYTECH/cytech2026@XE_CERGY @pl_sql_functions.sql
sqlplus ADMIN_CYTECH/cytech2026@XE_CERGY @pl_sql_procedures.sql
sqlplus ADMIN_CYTECH/cytech2026@XE_CERGY @pl_sql_packages.sql
```

Recompiler les vues répartie quand l'autre site est prêt :

```sql
ALTER VIEW vue_parc_global COMPILE;
ALTER VIEW vue_parc_global_v2 COMPILE;
ALTER TRIGGER trg_insert_vue_parc_global COMPILE;
```

### 14.5 Jeu de test

Sur **XE_CERGY** seulement (ou les deux pour tester) :

```bash
sqlplus ADMIN_CYTECH/cytech2026@XE_CERGY @jeu_de_test.sql
```

Génère ~13 000 lignes en 3-4 secondes.

### 14.6 Tests de performance

```bash
sqlplus ADMIN_CYTECH/cytech2026@XE_CERGY @tests_perf.sql
```

Récupérer les temps moyens du `DBMS_OUTPUT` pour les graphiques du rapport.

---

## 15. Inventaire du dépôt

| Fichier | Rôle | Lignes |
|---|---|---|
| [bdd_Cy_infrastructure.sql](bdd_Cy_infrastructure.sql) | Schéma + tablespaces + users + index + vues + BDDR | ~580 |
| [pl_sql_triggers.sql](pl_sql_triggers.sql) | 41 triggers | ~720 |
| [pl_sql_functions.sql](pl_sql_functions.sql) | 11 fonctions standalone | ~240 |
| [pl_sql_procedures.sql](pl_sql_procedures.sql) | 5 procédures standalone | ~310 |
| [pl_sql_packages.sql](pl_sql_packages.sql) | 4 packages métier | ~1100 |
| [jeu_de_test.sql](jeu_de_test.sql) | Package de génération de données | ~1130 |
| [tests_perf.sql](tests_perf.sql) | 6 tests EXPLAIN + bench_query | ~330 |
| [README.md](README.md) | Ordre d'exécution | court |
| [diagrammes/](diagrammes/) | .puml UML / déploiement | à mettre à jour |
| [Architecture_BDD_GLPI.docx](Architecture_BDD_GLPI.docx) | Analyse reverse engineering | livré |
| [Rapport_Reverse_Engineering_GLPI.docx](Rapport_Reverse_Engineering_GLPI.docx) | Idem | livré |

---

## 16. À préparer pour la soutenance (10-15 min)

Plan de présentation suggéré :

1. **Contexte (1 min)** — GLPI, multi-sites Cergy/Pau, problématiques perf.
2. **Reverse engineering (2 min)** — ce qu'on a gardé de GLPI, ce qu'on a simplifié, et pourquoi.
3. **Architecture (2 min)** — schéma deux PDBs, tablespaces, db link.
4. **Modèle de données (2 min)** — diagramme UML, focus sur `hierarchy_level` récursive et la séparation `ordinateurs`/`peripheriques`/`telephones`.
5. **PL/SQL (3 min)** — un trigger d'audit, une procédure avec curseur, un package complet (`pkg_parc_info.rapport_parc_site`).
6. **BDDR (2 min)** — démo en live d'une requête `vue_parc_global_v2`, montrer un EXPLAIN PLAN.
7. **Tests de performance (2 min)** — graphique AVEC/SANS index ou local/distant.
8. **Choix techniques discutables (1 min)** — pourquoi cluster abandonné, profils restauré.

Prévoir une démo SQL*Plus avec :
- Connect comme TECH_CERGY, montrer qu'on peut lire les tables mais pas DROP.
- Connect comme USER_RO, montrer qu'on n'a que les vues.
- Lancer `EXEC pkg_parc_info.rapport_parc_site(1)` pour un rapport mis en forme dans `DBMS_OUTPUT`.
- Faire un `SELECT * FROM vue_parc_global_v2` pour montrer la BDDR.
