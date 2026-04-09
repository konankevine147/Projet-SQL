-- =============================================================================
-- ANALYSIS.SQL — Requêtes d'analyse — Pharmacie Centrale
-- =============================================================================


-- =============================================================================
-- MISE À JOUR DMM — À exécuter en fin de mois
-- =============================================================================
-- Calcule la distribution moyenne mensuelle sur les 6 mois précédant
-- le mois de référence (ici fixé au 31 décembre 2024 pour les tests).
-- =============================================================================

UPDATE STOCK
SET
    distribution_moyenne_mensuelle = (
        SELECT ROUND(
            CAST(SUM(lc.quantite_commandee) AS REAL)
            / NULLIF(COUNT(DISTINCT c.annee || '-' || c.mois), 0),2)
        FROM LIGNE_COMMANDE lc
        JOIN COMMANDE c ON c.id_commande = lc.id_commande
        WHERE lc.code_produit = STOCK.code_produit
          AND lc.numero_lot   = STOCK.numero_lot
          AND c.statut IN ('approuvee', 'livree')
          AND (c.annee * 100 + c.mois) < 202412
          AND (c.annee * 100 + c.mois) >= 202407),
    date_derniere_maj = '2026-04-08';


-- =============================================================================
-- REQUÊTE 1 : PRODUITS PÉRIMÉS AVEC QUANTITÉ ET VALEUR PERDUE
-- =============================================================================

SELECT
    p.code_produit,
    p.numero_lot,
    p.nom_produit,
    p.date_limite_consommation,
    CAST(julianday('now') - julianday(p.date_limite_consommation) AS INTEGER)
                                                AS jours_depuis_peremption,
    SUM(pi.quantite)                            AS quantite_perimee,
    ROUND(SUM(pi.quantite) * p.prix_achat, 2)   AS valeur_perdue_euro
FROM PRODUIT_INUTILISABLE pi
JOIN STOCK s   ON s.id_stock     = pi.id_stock
JOIN PRODUIT p ON p.code_produit = s.code_produit
              AND p.numero_lot   = s.numero_lot
WHERE pi.motif = 'perime'
GROUP BY p.code_produit, p.numero_lot
ORDER BY p.date_limite_consommation ASC;


-- =============================================================================
-- REQUÊTE 2 : MOTIFS DES PRODUITS INUTILISABLES — RÉPARTITION ET PERTES
-- =============================================================================

SELECT
    pi.motif,
    COUNT(*)                                  AS nb_constats,
    SUM(pi.quantite)                          AS quantite_totale_retiree,
    ROUND(SUM(pi.quantite * p.prix_achat), 2) AS valeur_pertes_euro,
    ROUND(
        CAST(COUNT(*) AS REAL)
        / (SELECT COUNT(*) FROM PRODUIT_INUTILISABLE) * 100, 2) AS part_pct
FROM PRODUIT_INUTILISABLE pi
JOIN STOCK s   ON s.id_stock     = pi.id_stock
JOIN PRODUIT p ON p.code_produit = s.code_produit
              AND p.numero_lot   = s.numero_lot
GROUP BY pi.motif
ORDER BY quantite_totale_retiree DESC;


-- =============================================================================
-- REQUÊTE 3 : PRODUITS LES PLUS COMMANDÉS (TOUTES PÉRIODES)
-- =============================================================================

SELECT
    p.code_produit,
    p.numero_lot,
    p.nom_produit,
    p.type_pathologie,
    COUNT(DISTINCT lc.id_commande)             AS nb_commandes,
    SUM(lc.quantite_commandee)                 AS total_commande,
    SUM(lc.quantite_livree)                    AS total_livre,
    ROUND(
        CAST(SUM(lc.quantite_livree) AS REAL)
        / NULLIF(SUM(lc.quantite_commandee), 0) * 100, 2)  AS taux_satisfaction_pct
FROM LIGNE_COMMANDE lc
JOIN PRODUIT p  ON p.code_produit = lc.code_produit
               AND p.numero_lot   = lc.numero_lot
JOIN COMMANDE c ON c.id_commande  = lc.id_commande
WHERE c.statut IN ('approuvee', 'livree')
GROUP BY lc.code_produit, lc.numero_lot
ORDER BY total_commande DESC;


-- =============================================================================
-- REQUÊTE 4 : TAUX DE SATISFACTION DES PRODUITS SUR UN MOIS DONNÉ
-- =============================================================================
-- Modifier mois et annee selon la période souhaitée.
-- =============================================================================

SELECT
    p.code_produit,
    p.numero_lot,
    p.nom_produit,
    p.type_pathologie,
    SUM(lc.quantite_commandee)                             AS total_commande,
    SUM(lc.quantite_livree)                                AS total_livre,
    SUM(lc.quantite_commandee) - SUM(lc.quantite_livree)   AS ecart_non_livre,
    ROUND(
        CAST(SUM(lc.quantite_livree) AS REAL)
        / NULLIF(SUM(lc.quantite_commandee), 0) * 100, 2)  AS taux_satisfaction_pct,
    CASE
        WHEN ROUND(CAST(SUM(lc.quantite_livree) AS REAL)
            / NULLIF(SUM(lc.quantite_commandee), 0) * 100, 2) >= 95
            THEN 'Excellent'
        WHEN ROUND(CAST(SUM(lc.quantite_livree) AS REAL)
            / NULLIF(SUM(lc.quantite_commandee), 0) * 100, 2) >= 80
            THEN 'Satisfaisant'
        WHEN ROUND(CAST(SUM(lc.quantite_livree) AS REAL)
            / NULLIF(SUM(lc.quantite_commandee), 0) * 100, 2) >= 60
            THEN 'Insuffisant'
        ELSE 'Critique'
    END                                                     AS niveau_service
FROM LIGNE_COMMANDE lc
JOIN PRODUIT p  ON p.code_produit = lc.code_produit
               AND p.numero_lot   = lc.numero_lot
JOIN COMMANDE c ON c.id_commande  = lc.id_commande
WHERE c.mois   = 7      -- << modifier le mois ici
  AND c.annee  = 2024   -- << modifier l'année ici
  AND c.statut IN ('approuvee', 'livree')
GROUP BY lc.code_produit, lc.numero_lot
ORDER BY taux_satisfaction_pct ASC;


-- =============================================================================
-- REQUÊTE 5 : ACHATS DU MOIS — FOURNISSEURS, PRODUITS, QUANTITÉS, MONTANTS
-- =============================================================================
-- Modifier mois et annee selon la période souhaitée.
-- =============================================================================

SELECT
    f.nom_fournisseur,
    f.pays                                      AS pays_fournisseur,
    p.code_produit,
    p.numero_lot,
    p.nom_produit,
    p.type_pathologie,
    p.unite_conditionnement,
    SUM(ms.quantite)                            AS quantite_recue,
    ROUND(p.prix_achat, 2)                      AS prix_unitaire_achat,
    ROUND(SUM(ms.quantite) * p.prix_achat, 2)   AS montant_achat_euro
FROM MOUVEMENT_STOCK ms
JOIN STOCK s       ON s.id_stock       = ms.id_stock
JOIN PRODUIT p     ON p.code_produit   = s.code_produit
                  AND p.numero_lot     = s.numero_lot
JOIN FOURNISSEUR f ON f.id_fournisseur = p.id_fournisseur
WHERE ms.type_mouvement = 'entree_fournisseur'
  AND strftime('%m', ms.date_mouvement) = '06'   -- << modifier le mois (format 2 chiffres)
  AND strftime('%Y', ms.date_mouvement) = '2024' -- << modifier l'année
GROUP BY p.code_produit, p.numero_lot, f.id_fournisseur
ORDER BY montant_achat_euro DESC;