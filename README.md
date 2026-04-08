# Pharmacie Centrale — Base de données SQL

## Contexte et problème résolu

La **Pharmacie Centrale** est l'organisme public chargé de l'achat, du stockage et de la distribution de produits pharmaceutiques sur l'ensemble du territoire français. Elle dispose d'un entrepôt central unique depuis lequel elle approvisionne ses clients : hôpitaux, cliniques et districts sanitaires régionaux.

Les commandes sont passées **mensuellement** par les clients. La Pharmacie Centrale passe elle-même des commandes auprès de ses fournisseurs en fonction du stock restant en fin de mois, calculé à partir de la **distribution moyenne mensuelle (DMM)** — la moyenne des quantités commandées sur les 6 derniers mois.

Cette base de données permet de :
- Suivre le stock en temps réel et détecter les ruptures avant qu'elles surviennent
- Tracer toutes les entrées et sorties de stock (livraisons, réapprovisionnements, mises au rebut)
- Gérer les commandes mensuelles des clients et calculer les taux de satisfaction
- Identifier les produits périmés ou inutilisables et estimer les pertes financières
- Analyser le chiffre d'affaires par client, par produit et par période

---

## Utilisateurs cibles

| Profil | Usage principal |
|---|---|
| **Gestionnaire de stock** | Consulte les alertes (sous-stock, sur-stock), calcule les quantités à commander, enregistre les produits inutilisables |
| **Responsable des approvisionnements** | Suit les entrées fournisseurs, compare les prix d'achat, analyse les montants par produit et par mois |
| **Responsable facturation** | Suit les commandes clients, calcule les montants des factures, analyse le chiffre d'affaires mensuel |
| **Directeur général** | Consulte les tableaux de bord : produits les plus commandés, taux de satisfaction, pertes sur périmés |
| **Auditeur interne** | Vérifie la traçabilité des mouvements de stock, contrôle les pertes par motif |
| **Clients** (hôpitaux, cliniques, districts sanitaires) | Consultent l'état de leurs commandes et leur historique de livraisons |
| **Ministère de la Santé** | Accès aux statistiques nationales par pathologie, région et période |

---

## Sources de données

| Table | Source | Détail |
|---|---|---|
| `FOURNISSEUR` | Généré — LLM | 20 fournisseurs européens fictifs |
| `PRODUIT` | Généré — LLM | 198 médicaments réels répartis sur 9 pathologies |
| `CLIENT` | Généré — LLM | 500 établissements de santé français (villes et régions réelles) |
| `STOCK` | Généré — LLM | Initialisé depuis les produits, DMM calculée depuis les commandes |
| `COMMANDE` | Généré — LLM | 12 000 commandes mensuelles sur 2023–2024 |
| `LIGNE_COMMANDE` | Généré — LLM | 65 802 lignes avec quantités et montants calculés |
| `MOUVEMENT_STOCK` | Généré — LLM | 68 846 mouvements (sorties, entrées fournisseurs, mises au rebut) |
| `PRODUIT_INUTILISABLE` | Généré — LLM | 300 constats répartis sur 4 motifs |

---

## Structure du dépôt

```
pharmacie-centrale/
├── README.md                  ← Ce fichier
├── DESIGN.md                  ← Conception, diagramme ER, choix et limitations
├── schema.sql                 ← Création des tables, index et vues
├── seed.sql                   ← Données (INSERT INTO) générées depuis les CSV
├── queries.sql                ← Requêtes de manipulation quotidienne
├── analysis.sql               ← Requêtes d'analyse
└── data/
    ├── fournisseur.csv
    ├── produit.csv
    ├── client.csv
    ├── stock.csv
    ├── commande.csv
    ├── ligne_commande.csv
    ├── mouvement_stock.csv
    └── produit_inutilisable.csv
```

---

## Schéma de la base

La base contient **8 tables** :

| Table | Rôle |
|---|---|
| `FOURNISSEUR` | Entreprises qui approvisionnent la Pharmacie Centrale |
| `PRODUIT` | Catalogue des médicaments avec prix achat/vente et pathologie |
| `CLIENT` | Hôpitaux, cliniques et districts sanitaires |
| `COMMANDE` | Commandes mensuelles passées par les clients |
| `LIGNE_COMMANDE` | Détail des commandes (un produit par ligne) |
| `STOCK` | Stock disponible et distribution moyenne mensuelle par produit |
| `MOUVEMENT_STOCK` | Historique de toutes les entrées et sorties de stock |
| `PRODUIT_INUTILISABLE` | Archive des produits retirés du stock (périmés, endommagés…) |

---

## Mise en route

### Prérequis

- [DB Browser for SQLite](https://sqlitebrowser.org/) — interface graphique recommandée

### 1. Créer la base et le schéma

Dans DB Browser :
1. `Fichier → Nouvelle base de données` — nommer le fichier `pharmacie_centrale.db`
2. `Outils → Exécuter le SQL` — charger et exécuter `schema.sql`

### 2. Peupler la base

**Option A — via `seed.sql` (recommandé) :**
```
Outils → Exécuter le SQL → charger seed.sql → Exécuter
```

**Option B — via les CSV :**
```
Fichier → Importer → Table depuis un fichier CSV
→ Sélectionner le CSV → Cliquer OK sur le message d'erreur
→ Confirmer l'import dans la table existante
```
Respecter l'ordre d'import : `FOURNISSEUR` → `PRODUIT` → `CLIENT` → `STOCK` → `COMMANDE` → `LIGNE_COMMANDE` → `MOUVEMENT_STOCK` → `PRODUIT_INUTILISABLE`

### 3. Calculer la distribution moyenne mensuelle

Exécuter dans DB Browser (version test sur les données 2023–2024) :

```sql
UPDATE STOCK
SET distribution_moyenne_mensuelle = (
    SELECT ROUND(
        CAST(SUM(lc.quantite_commandee) AS REAL)
        / NULLIF(COUNT(DISTINCT c.annee || '-' || c.mois), 0), 2)
    FROM LIGNE_COMMANDE lc
    JOIN COMMANDE c ON c.id_commande = lc.id_commande
    WHERE lc.code_produit = STOCK.code_produit
      AND lc.numero_lot   = STOCK.numero_lot
      AND c.statut IN ('approuvee', 'livree')
      AND (c.annee * 100 + c.mois) < 202412
      AND (c.annee * 100 + c.mois) >= 202407
),
date_derniere_maj = '2024-12-31';
```

---

## Vues disponibles

| Vue | Description |
|---|---|
| `vue_etat_stock` | Stock actuel + alerte (Sous-stock / Bien stocké / Sur-stock) + quantité à commander |
| `vue_distribution_mensuelle` | Distribution par produit et par mois |
| `vue_distribution_client` | Distribution par client, produit et mois |
| `vue_factures_client` | Montant des factures par client et par mois |
| `vue_taux_satisfaction` | Taux de satisfaction et niveau de service par produit et par mois |

---

## Moteur de base de données

**SQLite** — aucune installation de serveur requise. Le fichier `.db` est portable et s'ouvre directement dans DB Browser for SQLite.

---

## Pathologies couvertes

| Code | Pathologie |
|---|---|
| CA | Cancer |
| PA | Paludisme |
| SI | SIDA |
| TB | Tuberculose |
| MC | Maladies Cardio-neurovasculaires |
| PP | Pathologies Psychiatriques |
| MM | Maladies Métaboliques |
| MN | Maladies Neurodégénératives |
| AR | Pathologies Articulaires et Musculaires |
