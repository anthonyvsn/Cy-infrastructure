# Cy-infrastructure

Projet GLPI CY Tech multi-sites (Cergy + Pau) sur Oracle.

## Ordre d'exécution

À effectuer sous la session SYSTEM de SQLPLUS, dans cet ordre :

1. `@"bdd_Cy_infrastructure.sql"`  — schéma (tablespaces, rôles, utilisateurs, tables, index, vues, BDDR)
2. `@"pl_sql_triggers.sql"`        — triggers (auto-incrément, audit, validations)
3. `@"pl_sql_functions.sql"`       — fonctions standalone
4. `@"pl_sql_procedures.sql"`      — procédures standalone
5. `@"pl_sql_packages.sql"`        — packages métier (parc, stats, réseau, maintenance)
6. `@"jeu_de_test.sql"`            — peuplement de données réalistes (~2600 utilisateurs, ~2900 ordis)
7. `@"tests_perf.sql"`             — benchmarks (optionnel, pour le rapport)

> Le fichier `corrections_sql.sql` a été supprimé : les corrections pertinentes ont été intégrées directement dans `bdd_Cy_infrastructure.sql`.
                                        