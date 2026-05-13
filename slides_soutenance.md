---
marp: true
title: GLPI CY Tech -- BDD multi-sites Oracle
description: Mini-projet SIE -- ING2 -- 2025-2026
theme: default
paginate: true
size: 16:9
backgroundColor: #fdfefe
header: 'GLPI CY Tech -- BDD multi-sites Oracle'
footer: 'ING2 SIE -- 2025-2026 -- Équipe GLPI'
style: |
  section {
    font-family: "Helvetica", "Arial", sans-serif;
    font-size: 24px;
  }
  h1 { color: #1A5276; }
  h2 { color: #2874A6; border-bottom: 2px solid #AED6F1; padding-bottom: 4px; }
  code { background: #FCF3CF; padding: 2px 6px; border-radius: 3px; }
  pre code { background: #F4F6F6; }
  table { font-size: 18px; }
  th { background: #D6EAF8; }
---

<!-- _class: lead -->
<!-- _paginate: false -->

# GLPI CY Tech
## Base de données multi-sites sous Oracle

**Mini-projet SIE -- ING2 Bases de données avancées**
2025-2026 -- Soutenance semaine du 18 mai 2026

Équipe GLPI CY Tech

---

## Plan de la présentation

1. **Contexte** et objectifs
2. **Reverse engineering** GLPI
3. **Modélisation** : UML, MLD, BDDR
4. **Architecture Oracle** : tablespaces, rôles, séquences
5. **Indexation et cluster**
6. **PL/SQL** : triggers, package métier, curseurs
7. **BDDR** : DB links, vues matérialisées
8. **Tests de performance**
9. **Démo** (si temps)
10. **Conclusion**

⏱️ 10-15 minutes + questions

---

## 1. Contexte

- **CY Tech** : 2 campus (Cergy + Pau)
- **GLPI** : outil open source de gestion de parc IT
- **Mission** : repenser une partie de la BDD sous Oracle pour exploiter les concepts avancés du SGBD professionnel

**Périmètre retenu**

| Domaine | Tables clés |
|---|---|
| Matériel | ordinateurs, périphériques, téléphones, logiciels |
| Utilisateurs | utilisateurs, profils, groupes, entités |
| Réseau | équipements, ports |
| Audit | historique (polymorphique) |

---

## 2. Reverse engineering GLPI

- GLPI tourne sur **MySQL/MariaDB** -- 400+ tables, préfixe `glpi_*`
- **Pattern clé** : polymorphisme par chaîne pour l'audit
  ```
  glpi_logs(itemtype VARCHAR, items_id NUMBER, ...)
  ```
- **Soft-delete** systématique (`is_deleted`)
- **Entités hiérarchiques** (auto-référence parent)
- **Faiblesses identifiées** :
  - Peu de contraintes CHECK
  - Pas de triggers d'audit côté BDD
  - Traçabilité applicative (fragile)

→ Notre version Oracle **renforce** la couche base de données.

---

## 3. Diagramme de classes UML

![h:520](diagrammes/diagramme_classes_uml.puml)

> 5 paquets : Référentiel, Utilisateurs, Matériel, Réseau, Audit
> Hiérarchies récursives + polymorphisme audit

---

## 3. Schéma relationnel (MLD)

- 21 tables, groupées par tablespace
- PK numériques + séquences `seq_*`
- FK explicites, contraintes CHECK sur les enums
- UNIQUE composites (`profils_utilisateurs(user, profil, entite)`)

![h:380](diagrammes/schema_relationnel.puml)

---

## 3. Déploiement BDDR

```
[Cergy : XE_CERGY]               [Pau : XE_PAU]
  ├── Référentiels                  ├── Matériel Pau
  ├── Utilisateurs                  ├── Réseau Pau
  ├── Matériel Cergy   ─db_pau─►    └── MV répliquées
  ├── Réseau Cergy                       (depuis Cergy)
  └── Audit global
        ▲
        │
   USER_RO, TECH_CERGY, TECH_PAU, ADMIN_CYTECH
```

- DB link `db_pau` + synonymes publics → transparence d'accès
- Vue `vue_parc_global` (UNION ALL Cergy + Pau)

---

## 4. Tablespaces

| Tablespace | Rôle |
|---|---|
| `TS_USERS` | Référentiel partagé + audit |
| `TS_MATERIEL_CERGY` / `_PAU` | Parc matériel par site |
| `TS_NETWORK_CERGY` / `_PAU` | Réseau par site |
| `TS_INDEX` | Tous les indexes |
| `TS_TEMP` | Tris, jointures |

**Pourquoi isoler ?**
- IO différenciés (placer `TS_INDEX` sur disque rapide)
- Sauvegarde sélective par site
- Support BDDR (un tablespace par instance Pau)

---

## 4. Rôles et utilisateurs

| Rôle | Privilèges |
|---|---|
| `R_ADMIN` | DDL + DML complet |
| `R_TECH_CERGY` | CRUD parc Cergy |
| `R_TECH_PAU` | CRUD parc Pau |
| `R_CONSULTATION` | SELECT sur les vues |

→ 4 utilisateurs Oracle :
`ADMIN_CYTECH`, `TECH_CERGY`, `TECH_PAU`, `USER_RO`

- **GRANT objets ciblés** : `TECH_CERGY` n'écrit pas dans `historique`
- `USER_RO` ne voit que les vues (masque `mot_de_passe`)

---

## 5. Indexation -- trois stratégies

| Type | Usage | Exemple |
|---|---|---|
| **B-tree** | FK, recherches discriminantes | `idx_ordi_site` |
| **Bitmap** | Booléens (cardinalité 2) | `idx_bmp_ordi_supprime` |
| **Fonctionnel** | Recherches case-insensitive | `idx_ordi_nom_upper` |

```sql
CREATE INDEX idx_user_login_upper
  ON utilisateurs(UPPER(login))
  TABLESPACE TS_INDEX;
```

→ ~25 indexes b-tree + 5 bitmap + 2 fonctionnels

---

## 5. Cluster physique

```sql
CREATE CLUSTER cl_materiel_localisation (localisation_id NUMBER)
  SIZE 512 TABLESPACE TS_MATERIEL_CERGY;

CREATE TABLE ordinateurs_cl (...)
  CLUSTER cl_materiel_localisation(localisation_id);
CREATE TABLE peripheriques_cl (...)
  CLUSTER cl_materiel_localisation(localisation_id);
```

**Effet** : les lignes `ordinateurs` et `peripheriques` qui partagent une même `localisation_id` sont **physiquement co-localisées** sur le disque.

→ `SELECT … WHERE localisation_id = X` lit moins de blocs.

---

## 6. PL/SQL -- triggers

**4 catégories de triggers** :

1. **Auto-PK** -- 10 triggers `BEFORE INSERT` consomment `seq_*.NEXTVAL`
2. **MAJ `date_modification`** -- 5 triggers `BEFORE UPDATE`
3. **Audit** -- 4 triggers compound `AFTER INSERT/UPDATE/DELETE`
   - 1 ligne `historique` par champ modifié
   - Factorisation : procédure `log_change(...)`
4. **Validation** -- BEFORE INSERT/UPDATE
   - Cohérence `site_id` (ordi vs entité)
   - Format MAC via `REGEXP_LIKE`
   - Dates user (`date_fin >= date_debut`)
   - Auto-référence entité interdite

---

## 6. PL/SQL -- package `pkg_metier`

**Fonctions de statistiques**

```
f_nb_materiel_site, f_age_moyen_parc,
f_taux_occupation_localisation, f_count_ordi_etat,
f_user_id_par_email, f_nom_complet_entite
```

**Procédures métier**

```
transferer_materiel, archiver_utilisateur,
purger_corbeille, refresh_mv_stats,
audit_erreur  (PRAGMA AUTONOMOUS_TRANSACTION)
```

**Traitements batch (curseurs explicites)**

```
recalculer_nom_complet_entites,
marquer_obsoletes (FOR UPDATE / WHERE CURRENT OF),
rapport_parc_site
```

---

## 6. PL/SQL -- exemple curseur explicite

```sql
PROCEDURE marquer_obsoletes(p_annees NUMBER DEFAULT 7) IS
  CURSOR c_vieux(cp_seuil DATE) IS
    SELECT id FROM ordinateurs
     WHERE date_achat < cp_seuil
       AND est_supprime = 0
     FOR UPDATE OF etat_id;  -- verrou des lignes
  v_etat_reforme NUMBER;
  v_seuil DATE := ADD_MONTHS(SYSDATE, -12 * p_annees);
BEGIN
  SELECT id INTO v_etat_reforme FROM etats
   WHERE UPPER(nom) = 'REFORME' AND ROWNUM = 1;

  FOR ordi IN c_vieux(v_seuil) LOOP
    UPDATE ordinateurs SET etat_id = v_etat_reforme
     WHERE CURRENT OF c_vieux;  -- ligne courante du curseur
  END LOOP;
END;
```

---

## 7. BDDR -- réplication

**Vues matérialisées côté Pau** (référentiels lus depuis Cergy)

```sql
CREATE MATERIALIZED VIEW mv_fabricants
  REFRESH ON DEMAND
AS SELECT * FROM fabricants@db_cergy;
```

**Pourquoi ?**
- Évite les aller-retours réseau pour les référentiels stables (fabricants, états, sites)
- Rafraîchissement périodique (`DBMS_MVIEW.REFRESH('mv_fabricants', 'C')`)
- Lecture locale ultra-rapide

**Vue de fragmentation globale**

```sql
CREATE VIEW vue_parc_global AS
  SELECT … FROM ordinateurs
  UNION ALL
  SELECT … FROM ordinateurs@db_pau;
```

---

## 8. Tests de performance -- méthodologie

- **Volume** : 800 utilisateurs, 1500 ordis, 1500 périphs, 100 équipements réseau
- **Outils** :
  - `EXPLAIN PLAN` → vérifier le plan choisi
  - `DBMS_UTILITY.GET_TIME` → mesurer le wall-clock
  - 5 runs par requête → amortir le cache effect

**Scénarios couverts**

1. site_id (b-tree)
2. UPPER(login) (fonctionnel)
3. est_supprime (bitmap)
4. localisation_id (cluster vs heap)
5. Vue matérialisée vs agrégation live
6. SELECT local vs distant (db link)
7. Impact global indexes sur `vue_parc_cergy`

---

## 8. Résultats (ordres de grandeur)

| Test | Avec | Sans | Gain |
|---|---|---|---|
| site_id (b-tree) | ~1 ms | ~12 ms | **×12** |
| UPPER(login) | ~1 ms | ~15 ms | **×15** |
| est_supprime (bitmap) | ~2 ms | ~8 ms | **×4** |
| localisation_id (cluster) | ~2 ms | ~5 ms | **×2.5** |
| MV vs aggregation | ~1 ms | ~10 ms | **×10** |
| Vue complète (global) | ~30 ms | ~120 ms | **×4** |

→ Les indexes paient leur coût d'écriture dès la première dizaine de lectures.
→ La MV est gagnante dès qu'on agrège souvent les mêmes données.

---

## 8. Comparaison Oracle vs MySQL GLPI

| Critère | MySQL GLPI | Oracle CY Tech |
|---|---|---|
| Partitionnement par stockage | ❌ | ✅ (tablespaces) |
| Cluster physique multi-tables | ❌ | ✅ |
| Vues matérialisées | ❌ (tables agrégées manuelles) | ✅ |
| DB links natifs | ⚠️ (`FEDERATED`, lent) | ✅ |
| Triggers d'audit base | ❌ (couche app) | ✅ (base + autonomous) |
| Index bitmap | ❌ | ✅ |
| Index fonctionnels | ⚠️ (limité) | ✅ |

→ Oracle apporte une **base structurellement plus robuste** pour un parc multi-sites.

---

## 9. Démo (si temps)

1. **EXEC pkg_metier.rapport_parc_site(1)**
   → rapport formaté Cergy
2. **INSERT** dans `ordinateurs` → trigger audit visible dans `historique`
3. **EXEC pkg_metier.transferer_materiel(...)**
   → vérification des règles de cohérence + audit
4. **EXPLAIN PLAN** sur une requête, DROP de l'index, EXPLAIN PLAN à nouveau
5. **SELECT * FROM vue_parc_global** → mix Cergy + Pau via db link

---

## 10. Conclusion

**Ce qui a été démontré**

- ✅ Modélisation complète (UML, MLD, déploiement)
- ✅ Architecture Oracle production-ready (tablespaces, rôles)
- ✅ Indexation différenciée + cluster
- ✅ PL/SQL complet (triggers, package, curseurs, transactions autonomes)
- ✅ BDDR fonctionnelle (DB link, MV, fragmentation)
- ✅ Tests de performance reproductibles avec analyse

**Limites assumées**

- Périmètre réseau réduit (pas de VLAN, IP)
- Pas de chiffrement des mots de passe
- Pas de partitionnement effectif (séparation par tablespaces seulement)

---

## Perspectives

- **Chiffrement** : `DBMS_CRYPTO` sur les mots de passe
- **Partitionnement** : `PARTITION BY LIST(site_id)` sur les tables matériel
- **VPD** (Virtual Private Database) : filtrage automatique par site
- **Scheduler** : `DBMS_SCHEDULER` pour refresh MV automatique
- **Couche réseau** : VLAN, IP, connexions inter-ports
- **Polymorphisme** : tables `composants` (HD, RAM, cartes…)

---

<!-- _class: lead -->
<!-- _paginate: false -->

# Merci !

**Questions ?**

📦 Code : github.com/anthonyvsn/Cy-infrastructure
📄 Rapport : `rapport_final.md`
🖼️ Diagrammes : `diagrammes/*.puml`

Équipe GLPI CY Tech -- ING2 SIE 2025-2026

---

<!-- _class: lead -->
<!-- _paginate: false -->

## Annexes

(Slides de réserve pour les questions techniques)

---

## A. Code -- trigger compound audit

```sql
CREATE OR REPLACE TRIGGER trg_audit_ordinateurs
AFTER INSERT OR UPDATE OR DELETE ON ordinateurs
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    log_change('ordinateurs', :NEW.id, NULL, NULL, :NEW.nom, 'INSERT');
  ELSIF DELETING THEN
    log_change('ordinateurs', :OLD.id, NULL, :OLD.nom, NULL, 'DELETE');
  ELSIF UPDATING THEN
    IF NVL(:OLD.localisation_id,-1) <> NVL(:NEW.localisation_id,-1) THEN
      log_change('ordinateurs', :NEW.id, 'localisation_id',
                 TO_CHAR(:OLD.localisation_id),
                 TO_CHAR(:NEW.localisation_id), 'UPDATE');
    END IF;
    -- … autres champs sensibles
  END IF;
END;
```

---

## B. Code -- transaction autonome

```sql
PROCEDURE audit_erreur(p_type_objet VARCHAR2,
                      p_objet_id NUMBER,
                      p_message VARCHAR2) IS
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  INSERT INTO historique(id, type_objet, objet_id,
                         champ_modifie, nouvelle_valeur,
                         type_action, date_action)
  VALUES (seq_historique.NEXTVAL, p_type_objet, p_objet_id,
          'ERREUR', SUBSTR(p_message, 1, 4000),
          'UPDATE', SYSDATE);
  COMMIT;  -- obligatoire avant fin transaction autonome
END;
```

→ Le trace survit même si l'appelant fait ROLLBACK.

---

## C. Code -- EXPLAIN PLAN

```sql
EXPLAIN PLAN FOR
  SELECT id, nom FROM ordinateurs
   WHERE site_id = 1 AND est_supprime = 0;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

Résultat type (AVEC index) :
```
| Id | Operation                    | Name           |
|  0 | SELECT STATEMENT             |                |
|  1 |  TABLE ACCESS BY INDEX ROWID | ORDINATEURS    |
|  2 |   INDEX RANGE SCAN           | IDX_ORDI_SITE  |
```

vs SANS index :
```
|  0 | SELECT STATEMENT             |                |
|  1 |  TABLE ACCESS FULL           | ORDINATEURS    |
```

---

## D. Compilation des diagrammes

```bash
# Java + jar
java -jar plantuml.jar diagrammes/*.puml

# Docker
docker run --rm -v $(pwd):/work plantuml/plantuml \
  diagrammes/*.puml

# Web (URL encoder)
https://www.plantuml.com/plantuml/uml/
```

Pour rendre les slides Marp :
```bash
npx @marp-team/marp-cli slides_soutenance.md \
  --pdf -o soutenance.pdf
```
