# Lancement et interpretation des resultats — Projet GLPI CY Tech

## Sequence de lancement complete depuis zero

```powershell
# === 1. Listener Oracle (si arrete) ===
Start-Service OracleOraDB21Home1TNSListener

# === 2. Drop + recreation des PDBs (CDB en bequeath) ===
$env:ORACLE_SID = "XE"
sqlplus / as sysdba
```

Puis dans SQL*Plus :

```sql
ALTER PLUGGABLE DATABASE XE_CERGY CLOSE IMMEDIATE;
DROP PLUGGABLE DATABASE XE_CERGY INCLUDING DATAFILES;
ALTER PLUGGABLE DATABASE XE_PAU CLOSE IMMEDIATE;
DROP PLUGGABLE DATABASE XE_PAU INCLUDING DATAFILES;

@"c:\Users\VM-Analysis\Desktop\tad\Cy-infrastructure\create_pdb_xe_cergy.sql"
@"c:\Users\VM-Analysis\Desktop\tad\Cy-infrastructure\create_pdb_xe_pau.sql"
ALTER SYSTEM REGISTER;
EXIT
```

```powershell
# === 3. Deploiement schema + PL/SQL + jeu de test + tests perf ===
cd c:\Users\VM-Analysis\Desktop\tad\Cy-infrastructure
sqlplus sys/1006@//localhost:1521/XE_CERGY as sysdba "@launch_all.sql"
sqlplus sys/1006@//localhost:1521/XE_PAU as sysdba "@launch_all.sql"

# === 4. Activation BDDR (lien PAU -> CERGY) ===
sqlplus ADMIN_CYTECH/cytech2026@//localhost:1521/XE_PAU "@setup_bddr.sql"

# === 5. Tests de performance avec BDDR active (recommande) ===
sqlplus ADMIN_CYTECH/cytech2026@//localhost:1521/XE_CERGY "@tests_perf.sql"
```

### Notes
- Mot de passe SYS : `1006`
- ADMIN_CYTECH : `cytech2026`
- Hostname machine : `Antonin`
- Le parametre `local_listener` a ete corrige en SPFILE (persistant apres reboot) pour que PMON enregistre correctement les PDBs aupres du listener.

---

## Interpretation des resultats des tests de performance

Volume du jeu de test : **~2700 ordinateurs par site**. A cette echelle, les **timings wall-clock** sont quasi tous a 0 centiseconde — la dataset est trop petite pour distinguer les indexes en chronometre. C'est l'**EXPLAIN PLAN** (cout estime par l'optimiseur) qui est lisible.

| Test | Comparaison | Resultat | Interpretation |
|---|---|---|---|
| **1 — B-tree `site_id`** | avec / sans index | plan non capture (`Error: cannot fetch last explain plan` — bug du script) | A 2700 lignes, l'optimiseur prefere souvent un FULL SCAN car le filtre `site_id=1` retourne ~50% de la table. L'index ne devient gagnant qu'a partir de ~100k lignes. |
| **2 — Index fonctionnel `UPPER(login)`** | avec / sans | plan non capture (meme bug) | Memes remarques. Theoriquement l'index fonctionnel devient indispensable des que les utilisateurs depassent quelques milliers. |
| **3 — Bitmap `est_supprime`** | avec / sans | **Cout 1 (BITMAP INDEX FAST FULL SCAN) vs 17 (TABLE ACCESS FULL)** | **Gain net x17 sur le cout**, deja visible. Bitmap est ideal pour colonne a faible cardinalite (0/1). C'est le test le plus probant a ce volume. |
| **4 — Cluster vs heap** | par localisation | TABLE ACCESS FULL **dans les deux cas** (cout 17) | A ce volume, l'optimiseur ignore le cluster et fait un full scan. Le cluster apporte un gain seulement sur **JOIN co-localise**, pas sur un SELECT simple. A documenter dans le rapport. |
| **5 — MV vs live** | `mv_stats_parc` vs requete avec JOIN+GROUP BY | **MV : `MAT_VIEW ACCESS FULL` cout 2** vs **live : `HASH GROUP BY + NESTED LOOPS` cout 5**, et timing live = **0.8 cs vs 0 cs** pour MV | MV gagne en cout (precalcule) et c'est mesurable au timing. Plus le nombre d'agregats grossit, plus l'ecart se creuse. |
| **6 — Local vs distant** | ordis Cergy vs `ordinateurs@db_pau` | **Local 0 cs / Distant 1.4 cs avg (pic 7 cs)** | Latence reseau du db link clairement visible meme en localhost. Sur reseau reel l'ecart serait x10-x100. Justifie le synchronisme des donnees critiques en local plutot que via db link sur le chemin critique. |
| **7 — Vue parc avec/sans indexes B-tree** | drop puis recreate tous les indexes B-tree | Timing 0 dans les deux cas | Volume trop petit pour mesurer. Faudrait ~50k lignes pour voir l'effet cumule. |

---

## Pour le rapport — ce qui est defendable

Trois tests donnent des **mesures concretes** a 2700 lignes :

1. **Test 3 (bitmap)** — gain de cout x17 visible immediatement. Meilleur exemple pour justifier le bitmap sur les colonnes a faible cardinalite.
2. **Test 5 (MV)** — gain de timing mesurable (0.8 cs -> 0 cs) ET gain de cout (5 -> 2). Justifie la MV pour les tableaux de bord stats.
3. **Test 6 (BDDR)** — latence distante mesurable (1.4 cs avg, pic 7 cs vs 0 cs en local). Justifie l'architecture symetrique (chaque site a sa BDD locale, distant uniquement pour vue globale).

Pour les tests 1, 2, 4, 7 : conclusion honnete a faire — **a ce volume, les indexes B-tree et le cluster ne sont pas mesurables** et il faudrait extrapoler a une production reelle (50k+ entites). C'est une conclusion qui montre que les limites de la mesure sont comprises.
