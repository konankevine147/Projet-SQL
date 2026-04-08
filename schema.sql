-- =============================================================================
-- SCHEMA.SQL — Base de données Pharmacie Centrale
-- =============================================================================


-- -----------------------------------------------------------------------------
-- TABLE : FOURNISSEUR
-- Entreprises ou organismes qui approvisionnent la Pharmacie Centrale en produits
-- pharmaceutiques. Un fournisseur peut fournir plusieurs produits.
-- -----------------------------------------------------------------------------
CREATE TABLE FOURNISSEUR (
    id_fournisseur  INTEGER     PRIMARY KEY AUTOINCREMENT,
    nom_fournisseur VARCHAR(150) NOT NULL,
    contact         VARCHAR(100),
    telephone       VARCHAR(20),
    email           VARCHAR(100),
    pays            VARCHAR(80)  NOT NULL,
    ville           VARCHAR(80)
);


-- -----------------------------------------------------------------------------
-- TABLE : PRODUIT
-- Catalogue des médicaments et produits pharmaceutiques gérés par la Pharmacie Centrale.
-- Le code_produit est alphanumérique (ex : MED-001) et sert de clé primaire
-- car il est unique, stable et utilisé dans les opérations quotidiennes.
-- -----------------------------------------------------------------------------
CREATE TABLE PRODUIT (
    code_produit            VARCHAR(20)  NOT NULL,
    numero_lot              VARCHAR(50)  NOT NULL,
    nom_produit             VARCHAR(150) NOT NULL,
    type_pathologie         VARCHAR(100),
    unite_conditionnement   VARCHAR(50)  NOT NULL,
    date_limite_consommation DATE,
    prix_achat              REAL         NOT NULL CHECK (prix_achat >= 0),  -- Prix payé au fournisseur (FCFA)
    prix_vente              REAL         NOT NULL CHECK (prix_vente >= 0),  -- Prix facturé au client (FCFA)
    id_fournisseur          INTEGER      NOT NULL,

    -- Clé primaire composite : un produit est identifié par son code ET son lot.
    -- Permet de gérer plusieurs lots actifs pour un même médicament.
    PRIMARY KEY (code_produit, numero_lot),

    -- Un produit doit obligatoirement être rattaché à un fournisseur existant.
    -- ON DELETE RESTRICT : on ne peut pas supprimer un fournisseur tant qu'il
    -- a des produits associés.
    FOREIGN KEY (id_fournisseur)
        REFERENCES FOURNISSEUR(id_fournisseur)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);


-- -----------------------------------------------------------------------------
-- TABLE : CLIENT
-- Hôpitaux, cliniques et districts sanitaires clients de la Pharmacie Centrale.
-- Le code_client est attribué en interne (ex : CLI-001) et sert de clé primaire.
-- -----------------------------------------------------------------------------
CREATE TABLE CLIENT (
    code_client VARCHAR(20)  PRIMARY KEY,
    nom_client  VARCHAR(150) NOT NULL,
    type_client VARCHAR(50)  NOT NULL
        CHECK (type_client IN ('hopital', 'clinique', 'district_sanitaire')),
    telephone   VARCHAR(20),
    email       VARCHAR(100),
    ville       VARCHAR(80),
    region      VARCHAR(80)  NOT NULL
);


-- -----------------------------------------------------------------------------
-- TABLE : COMMANDE
-- Enregistre chaque commande mensuelle passée par un client.
-- mois et annee sont stockés explicitement pour simplifier les analyses
-- périodiques sans recourir à des fonctions d'extraction de date.
-- -----------------------------------------------------------------------------
CREATE TABLE COMMANDE (
    id_commande             INTEGER     PRIMARY KEY AUTOINCREMENT,
    code_client             VARCHAR(20) NOT NULL,
    date_commande           DATE        NOT NULL,
    mois                    INTEGER     NOT NULL CHECK (mois BETWEEN 1 AND 12),
    annee                   INTEGER     NOT NULL CHECK (annee >= 2000),
    type_commande           VARCHAR(20) NOT NULL
        CHECK (type_commande IN ('normale', 'urgente')),
    statut                  VARCHAR(30) NOT NULL DEFAULT 'en_attente'
        CHECK (statut IN ('en_attente', 'approuvee', 'livree', 'annulee')),
    date_approbation        DATE,
    date_livraison_prevue   DATE,
    date_livraison_effective DATE,

    -- Un client doit exister pour qu'une commande soit créée.
    -- ON DELETE RESTRICT : on ne supprime pas un client qui a des commandes.
    FOREIGN KEY (code_client)
        REFERENCES CLIENT(code_client)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);


-- -----------------------------------------------------------------------------
-- TABLE : LIGNE_COMMANDE
-- Détail d'une commande : une ligne par produit et par lot commandé.
-- Le taux_satisfaction est le ratio quantite_livree / quantite_commandee,
-- compris entre 0 et 1. Il peut être calculé ou saisi manuellement.
-- Le montant est calculé comme quantite_livree × prix_vente du produit.
-- numero_lot permet de tracer quel lot précis a été livré au client.
-- -----------------------------------------------------------------------------
CREATE TABLE LIGNE_COMMANDE (
    id_ligne            INTEGER     PRIMARY KEY AUTOINCREMENT,
    id_commande         INTEGER     NOT NULL,
    code_produit        VARCHAR(20) NOT NULL,
    numero_lot          VARCHAR(50) NOT NULL,
    quantite_commandee  INTEGER     NOT NULL CHECK (quantite_commandee > 0),
    quantite_livree     INTEGER     DEFAULT 0 CHECK (quantite_livree >= 0),
    taux_satisfaction   REAL        CHECK (taux_satisfaction BETWEEN 0 AND 1),
    montant             REAL        CHECK (montant >= 0),  -- quantite_livree × prix_vente du produit (FCFA)

    -- Chaque ligne appartient à une commande existante.
    -- ON DELETE CASCADE : si une commande est supprimée, ses lignes le sont aussi.
    FOREIGN KEY (id_commande)
        REFERENCES COMMANDE(id_commande)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    -- FK composite : le produit ET le lot doivent exister dans le catalogue.
    FOREIGN KEY (code_produit, numero_lot)
        REFERENCES PRODUIT(code_produit, numero_lot)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);


-- -----------------------------------------------------------------------------
-- TABLE : STOCK
-- État courant du stock pour chaque produit à l'entrepôt central.
-- Relation 1-à-1 avec PRODUIT : un (code_produit, numero_lot) = une ligne de stock.
-- quantite_disponible est mise à jour à chaque mouvement via MOUVEMENT_STOCK.
-- distribution_moyenne_mensuelle : moyenne des quantités commandées sur les
--   6 derniers mois, recalculée en fin de mois depuis LIGNE_COMMANDE.
-- Le seuil d'alerte n'est pas stocké : il est calculé dynamiquement via
--   la requête : ROUND(distribution_moyenne_mensuelle * 2)
-- -----------------------------------------------------------------------------
CREATE TABLE STOCK (
    id_stock                        INTEGER     PRIMARY KEY AUTOINCREMENT,
    code_produit                    VARCHAR(20) NOT NULL,
    numero_lot                      VARCHAR(50) NOT NULL,
    quantite_disponible             INTEGER     NOT NULL DEFAULT 0
        CHECK (quantite_disponible >= 0),
    distribution_moyenne_mensuelle  REAL        DEFAULT 0
        CHECK (distribution_moyenne_mensuelle >= 0),  -- Moy. quantités commandées sur 6 mois
    date_derniere_maj               DATE        NOT NULL,

    -- Un (code_produit, numero_lot) ne peut avoir qu'une seule ligne de stock.
    UNIQUE (code_produit, numero_lot),

    -- FK composite vers PRODUIT : chaque lot doit exister dans le catalogue.
    FOREIGN KEY (code_produit, numero_lot)
        REFERENCES PRODUIT(code_produit, numero_lot)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);


-- -----------------------------------------------------------------------------
-- TABLE : MOUVEMENT_STOCK
-- Historique complet de toutes les entrées et sorties de stock.
-- Permet de reconstituer le stock à n'importe quelle date et d'identifier
-- les causes de chaque variation.
-- id_commande est nullable : un mouvement peut ne pas être lié à une commande
-- (ex : entrée fournisseur, mise au rebut manuelle).
-- -----------------------------------------------------------------------------
CREATE TABLE MOUVEMENT_STOCK (
    id_mouvement    INTEGER     PRIMARY KEY AUTOINCREMENT,
    id_stock        INTEGER     NOT NULL,
    id_commande     INTEGER,    -- nullable : pas tous les mouvements viennent d'une commande
    type_mouvement  VARCHAR(30) NOT NULL
        CHECK (type_mouvement IN ('entree_fournisseur', 'sortie_commande', 'mise_au_rebut')),
    quantite        INTEGER     NOT NULL CHECK (quantite > 0),
    date_mouvement  DATE        NOT NULL,
    motif           VARCHAR(200),

    FOREIGN KEY (id_stock)
        REFERENCES STOCK(id_stock)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    -- Lien optionnel vers la commande ayant déclenché le mouvement.
    FOREIGN KEY (id_commande)
        REFERENCES COMMANDE(id_commande)
        ON DELETE SET NULL
        ON UPDATE CASCADE
);


-- -----------------------------------------------------------------------------
-- TABLE : PRODUIT_INUTILISABLE
-- Archive des produits retirés du stock actif car inutilisables
-- (périmés, endommagés, contaminés…).
-- Séparée de STOCK pour ne pas polluer le stock courant et conserver
-- un historique traçable des pertes à des fins d'audit.
-- -----------------------------------------------------------------------------
CREATE TABLE PRODUIT_INUTILISABLE (
    id_inutilisable INTEGER     PRIMARY KEY AUTOINCREMENT,
    id_stock        INTEGER     NOT NULL,
    quantite        INTEGER     NOT NULL CHECK (quantite > 0),
    date_constat    DATE        NOT NULL,
    motif           VARCHAR(200) NOT NULL
        CHECK (motif IN ('perime', 'endommage', 'contamine', 'autre')),

    FOREIGN KEY (id_stock)
        REFERENCES STOCK(id_stock)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);


-- =============================================================================
-- INDEX
-- Les index accélèrent les recherches fréquentes sans modifier la structure.
-- =============================================================================

-- Recherche rapide des commandes d'un client donné
CREATE INDEX idx_commande_client
    ON COMMANDE(code_client);

-- Filtrage des commandes par période mensuelle
CREATE INDEX idx_commande_periode
    ON COMMANDE(annee, mois);

-- Recherche des lignes d'une commande donnée
CREATE INDEX idx_ligne_commande
    ON LIGNE_COMMANDE(id_commande);

-- Recherche des mouvements d'une ligne de stock donnée
CREATE INDEX idx_mouvement_stock
    ON MOUVEMENT_STOCK(id_stock);

-- Recherche des mouvements par date (utile pour les bilans de fin de mois)
CREATE INDEX idx_mouvement_date
    ON MOUVEMENT_STOCK(date_mouvement);

-- Recherche des produits inutilisables par date de constat
CREATE INDEX idx_inutilisable_date
    ON PRODUIT_INUTILISABLE(date_constat);


-- =============================================================================
-- VUES d'analyse — Pharmacie Centrale
-- Les vues simplifient les requêtes fréquentes sans dupliquer les données.
-- =============================================================================


-- VUE 1 : ÉTAT DU STOCK AVEC ALERTE ET QUANTITÉ À COMMANDER
CREATE VIEW vue_etat_stock AS
SELECT
    p.code_produit,
    p.nom_produit,
    p.type_pathologie,
    s.quantite_disponible                                   AS stock_actuel,
    ROUND(s.distribution_moyenne_mensuelle, 2)              AS dmm,
    CASE
        WHEN s.quantite_disponible <= ROUND(s.distribution_moyenne_mensuelle * 2)
            THEN 'Sous-stock'
        WHEN s.quantite_disponible <= ROUND(s.distribution_moyenne_mensuelle * 6)
            THEN 'Bien stocké'
        ELSE 'Sur-stock'
    END                                                     AS alerte,
    CASE
        WHEN s.quantite_disponible <= ROUND(s.distribution_moyenne_mensuelle * 2)
            THEN MAX(0, ROUND(s.distribution_moyenne_mensuelle * 4) - s.quantite_disponible)
        ELSE 0
    END                                                     AS stock_a_commander
FROM STOCK s
JOIN PRODUIT p ON p.code_produit = s.code_produit
ORDER BY
    CASE
        WHEN s.quantite_disponible <= ROUND(s.distribution_moyenne_mensuelle * 2) THEN 1
        WHEN s.quantite_disponible <= ROUND(s.distribution_moyenne_mensuelle * 6) THEN 2
        ELSE 3
    END,
    p.type_pathologie,
    p.nom_produit;


-- VUE 2 : DISTRIBUTION PAR PRODUIT ET PAR MOIS
CREATE VIEW vue_distribution_mensuelle AS
SELECT
    c.annee,
    c.mois,
    p.code_produit,
    p.nom_produit,
    p.type_pathologie,
    SUM(lc.quantite_commandee)                              AS total_commande,
    SUM(lc.quantite_livree)                                 AS total_livre,
    ROUND(
        CAST(SUM(lc.quantite_livree) AS REAL)
        / NULLIF(SUM(lc.quantite_commandee), 0) * 100, 2)  AS taux_satisfaction_pct
FROM LIGNE_COMMANDE lc
JOIN COMMANDE c ON c.id_commande  = lc.id_commande
JOIN PRODUIT p  ON p.code_produit = lc.code_produit
WHERE c.statut IN ('approuvee', 'livree')
GROUP BY c.annee, c.mois, lc.code_produit
ORDER BY c.annee, c.mois, p.type_pathologie;


-- VUE 3 : DISTRIBUTION PAR PRODUIT ET PAR MOIS POUR CHAQUE CLIENT
CREATE VIEW vue_distribution_client AS
SELECT
    cl.code_client,
    cl.nom_client,
    c.annee,
    c.mois,
    p.code_produit,
    p.nom_produit,
    SUM(lc.quantite_commandee)                              AS total_commande,
    SUM(lc.quantite_livree)                                 AS total_livre,
    ROUND(
        CAST(SUM(lc.quantite_livree) AS REAL)
        / NULLIF(SUM(lc.quantite_commandee), 0) * 100, 2)  AS taux_satisfaction_pct
FROM LIGNE_COMMANDE lc
JOIN COMMANDE c  ON c.id_commande  = lc.id_commande
JOIN CLIENT cl   ON cl.code_client = c.code_client
JOIN PRODUIT p   ON p.code_produit = lc.code_produit
WHERE c.statut IN ('approuvee', 'livree')
GROUP BY cl.code_client, c.annee, c.mois, lc.code_produit
ORDER BY cl.code_client, c.annee, c.mois;


-- VUE 4 : MONTANT DES FACTURES PAR CLIENT ET PAR MOIS
CREATE VIEW vue_factures_client AS
SELECT
    cl.code_client,
    cl.nom_client,
    cl.type_client,
    cl.region,
    c.annee,
    c.mois,
    ROUND(SUM(lc.montant), 2)                               AS montant_total_euro
FROM LIGNE_COMMANDE lc
JOIN COMMANDE c ON c.id_commande  = lc.id_commande
JOIN CLIENT cl  ON cl.code_client = c.code_client
WHERE c.statut IN ('approuvee', 'livree')
GROUP BY cl.code_client, c.annee, c.mois
ORDER BY montant_total_euro DESC;


-- VUE 5 : TAUX DE SATISFACTION DES PRODUITS PAR MOIS
CREATE VIEW vue_taux_satisfaction AS
SELECT
    c.annee,
    c.mois,
    p.code_produit,
    p.nom_produit,
    p.type_pathologie,
    SUM(lc.quantite_commandee)                              AS total_commande,
    SUM(lc.quantite_livree)                                 AS total_livre,
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
JOIN COMMANDE c ON c.id_commande  = lc.id_commande
WHERE c.statut IN ('approuvee', 'livree')
GROUP BY c.annee, c.mois, lc.code_produit
ORDER BY c.annee, c.mois, taux_satisfaction_pct ASC;