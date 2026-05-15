# Cy-infrastructure

Voici l'ordre d'exécution à effectuer sous la session SYSTEM de SQLPLUS:
1. @"bdd_Cy_infrastructure.sql"
2. @"corrections.sql" (EVENTUELLEMENT, ce fichier doit disparaitre a terme)
3. @"pl_sql_triggers.sql"
4. @"pl_sql_functions.sql"
5. @"pl_sql_procedures.sql"
6. @"pl_sql_packages.sql"
