# pg_flashback: Flashback Query pour PostgreSQL

**pg_flashback** est une extension PostgreSQL qui permet de remonter le temps sur vos tables, à la manière de la fonctionnalité "Flashback" d'Oracle. Elle capture automatiquement les modifications (INSERT, UPDATE, DELETE) via la réplication logique et permet de restaurer une table à un état antérieur ou de consulter les données telles qu'elles étaient dans le passé.

## Fonctionnalités Principales

*   **Time Travel Query** : Voir l'état d'une ligne ou d'une table à un instant T précis.
*   **Flashback Table** : Restaurer une table entière à son état passé (annule les erreurs accidentelles).
*   **Flashback to New Table** : Cloner une table telle qu'elle était dans le passé sans toucher à la table originale.
*   **Audit et Historique** : Consulter l'historique des modifications (qui a fait quoi, quand).
*   **Rétention Configurable** : Définir combien de temps l'historique est conservé (par défaut 1 heure).

---

## Installation

### Prérequis
*   PostgreSQL 14, 15, ou 16.
*   Plugin de décodage logique `wal2json` installé (`postgresql-16-wal2json` sous Linux).
*   Outils de compilation (`gcc`, `make`, `postgresql-server-dev-16`).

### Compilation

```bash
cd pg_flashback
make clean
make
sudo make install
```

### Configuration (postgresql.conf)

Ajoutez ou modifiez ces lignes dans votre fichier `postgresql.conf` :

```ini
# Chargement de l'extension
shared_preload_libraries = 'pg_flashback'

# Niveau de WAL requis pour la réplication logique
wal_level = logical

# Augmenter le nombre max de worker si nécessaire (au moins +1 pour pg_flashback)
max_worker_processes = 16

# (Optionnel) Nom de la base à surveiller (défaut: postgres)
pg_flashback.database_name = 'ma_base_de_donnees'

# (Optionnel) Stockage des logs : 'logged' (sûr) ou 'unlogged' (rapide mais volatil)
pg_flashback.table_storage_type = 'logged'
```

Redémarrez PostgreSQL pour appliquer les changements.

---

## Utilisation

Connectez-vous à votre base de données et activez l'extension :

```sql
CREATE EXTENSION pg_flashback;
```

### 1. Activer le Flashback sur une Table

Pour commencer à enregistrer l'historique d'une table :

```sql
-- Activer avec une rétention de 1 jour
SELECT flashback.enable_table('public.ma_table', '1 day');
```

*Cela va automatiquement configurer `REPLICA IDENTITY FULL` sur la table pour capturer les anciennes valeurs lors des mises à jour.*

### 2. Time Travel (Voyage dans le temps)

Voir à quoi ressemblait une ligne spécifique il y a 10 minutes :

```sql
-- Voir l'état de la ligne ID=1 il y a 10 minutes
SELECT flashback.get_row_at(
    'public.ma_table', 
    '{"id": 1}', 
    now() - interval '10 minutes'
);
```

Voir tous les changements entre deux dates :

```sql
SELECT * FROM flashback.changes_between(
    'public.ma_table',
    '2023-10-27 10:00:00',
    '2023-10-27 11:00:00'
);
```

### 3. Flashback (Restauration)

**ATTENTION** : Cette opération modifie les données actuelles de la table pour revenir en arrière.

```sql
-- Revenir à l'état d'il y a 30 minutes
SELECT flashback.flashback_table('public.ma_table', now() - interval '30 minutes');
```

Pour plus de sécurité, vous pouvez restaurer dans une **nouvelle table** séparée :

```sql
-- Créer 'ma_table_restored' avec les données d'il y a 1 heure
SELECT flashback.flashback_to_new_table(
    'public.ma_table', 
    'public.ma_table_restored', 
    now() - interval '1 hour'
);
```

### 4. Configuration et Maintenance

Modifier la durée de rétention pour une table :

```sql
SELECT flashback.set_table_undo_retention('public.ma_table', '7 days');
```

Désactiver le flashback sur une table (arrête l'enregistrement et permet le nettoyage) :

```sql
SELECT flashback.disable_table('public.ma_table');
```

Voir les statistiques de stockage :

```sql
SELECT * FROM flashback.storage_stats;
```

---

## Architecture Interne

L'extension se compose de deux parties :

1.  **Background Worker (C)** :
    *   Se connecte à la base en arrière-plan.
    *   Crée un slot de réplication logique (`flashback_slot`).
    *   Consomme les WAL via le plugin `wal2json`.
    *   Insère les événements de changement dans la table `flashback_internal.fb_event`.
    *   Gère le nettoyage automatique des vieilles partitions d'événements.

2.  **API SQL (PL/pgSQL)** :
    *   Fournit les fonctions utilisateur (`flashback.*`).
    *   Gère la logique de "rejeu inversé" (Reverse Replay) pour reconstruire les données passées.

Les données d'historique sont stockées dans la table partitionnée `flashback_internal.fb_event`.

---

## ⚠️ Limitations Connues

*   Nécessite que les tables aient une **Clé Primaire**.
*   Le mode `REPLICA IDENTITY FULL` peut impacter légèrement les performances des UPDATE/DELETE sur la table source (plus de données écrites dans les WAL).
*   Ne capture pas les changements de structure (DDL) comme `ALTER TABLE` (si vous changez la structure, l'historique précédent peut devenir illisible).
