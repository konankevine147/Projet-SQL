-- =============================================================================
-- QUERIES.SQL — Requêtes de manipulation — Pharmacie Centrale
-- =============================================================================
-- Ce fichier simule les opérations quotidiennes sur la base :
--   - INSERT : ajout de nouvelles données
--   - UPDATE : modification de données existantes
--   - DELETE : suppression de données
-- =============================================================================


-- =============================================================================
-- 1. FOURNISSEUR
-- =============================================================================

-- Ajouter un nouveau fournisseur
INSERT INTO FOURNISSEUR (nom_fournisseur, contact, telephone, email, pays, ville)
VALUES ('Sanofi France', 'Marie Dupont', '+33 1 53 77 40 00', 'mariedupont@sanofifrance.com', 'France', 'Paris');

-- Modifier l'email et le contact d'un fournisseur
UPDATE FOURNISSEUR
SET contact = 'Pierre Martin',
    email   = 'pierre.martin@ferrand.com'
WHERE id_fournisseur = 1;

-- Supprimer un fournisseur (uniquement s'il n'a aucun produit associé)
DELETE FROM FOURNISSEUR
WHERE id_fournisseur = 1;


-- =============================================================================
-- 2. PRODUIT
-- =============================================================================
-- La PK est composite (code_produit, numero_lot).
-- Un même médicament peut exister avec plusieurs lots différents.
-- Les UPDATE et DELETE doivent toujours préciser les deux colonnes.
-- =============================================================================

-- Ajouter un nouveau produit avec son lot
INSERT INTO PRODUIT (code_produit, numero_lot, nom_produit, type_pathologie,
                     unite_conditionnement, date_limite_consommation,
                     prix_achat, prix_vente, id_fournisseur)
VALUES ('PA00999', 'LOT2024001', 'Artemether 20mg', 'PALUDISME',
        'boite de 30', '2027-06-30', 1500.00, 2200.00, 2);

-- Ajouter un deuxième lot pour le même médicament
INSERT INTO PRODUIT (code_produit, numero_lot, nom_produit, type_pathologie,
                     unite_conditionnement, date_limite_consommation,
                     prix_achat, prix_vente, id_fournisseur)
VALUES ('PA00999', 'LOT2024002', 'Artemether 20mg', 'PALUDISME',
        'boite de 30', '2028-03-15', 1500.00, 2200.00, 2);

-- Modifier le prix de vente d'un lot précis
UPDATE PRODUIT
SET prix_vente = 2500.00
WHERE code_produit = 'PA00999'
  AND numero_lot   = 'LOT2024001';

-- Modifier la date limite de consommation d'un lot précis
UPDATE PRODUIT
SET date_limite_consommation = '2027-12-31'
WHERE code_produit = 'PA00999'
  AND numero_lot   = 'LOT2024001';

-- Supprimer un lot précis d'un produit
-- (uniquement s'il n'a aucune ligne de commande ni stock associé)
DELETE FROM PRODUIT
WHERE code_produit = 'PA00999'
  AND numero_lot   = 'LOT2024001';

-- Supprimer tous les lots d'un produit
DELETE FROM PRODUIT
WHERE code_produit = 'PA00999';


-- =============================================================================
-- 3. CLIENT
-- =============================================================================

-- Ajouter un nouveau client
INSERT INTO CLIENT (code_client, nom_client, type_client, telephone, email, ville, region)
VALUES ('C9999', 'Hôpital Saint-Louis de Paris', 'hopital',
        '+33 1 42 49 49 49', 'contact@hopital-saintlouis.fr', 'Paris', 'Île-de-France');

-- Modifier le téléphone et l'email d'un client
UPDATE CLIENT
SET telephone = '+33 1 42 49 50 00',
    email     = 'direction@hopital-saintlouis.fr'
WHERE code_client = 'C9999';

-- Changer le type d'un client
UPDATE CLIENT
SET type_client = 'clinique'
WHERE code_client = 'C9999';

-- Supprimer un client (uniquement s'il n'a aucune commande)
DELETE FROM CLIENT
WHERE code_client = 'C9999';


-- =============================================================================
-- 4. COMMANDE
-- =============================================================================

-- Ajouter une nouvelle commande normale
INSERT INTO COMMANDE (code_client, date_commande, mois, annee,
                      type_commande, statut)
VALUES ('C0001', '2024-11-01', 11, 2024, 'normale', 'en_attente');

-- Ajouter une commande urgente
INSERT INTO COMMANDE (code_client, date_commande, mois, annee,
                      type_commande, statut)
VALUES ('C0042', '2024-11-15', 11, 2024, 'urgente', 'en_attente');

-- Approuver une commande
UPDATE COMMANDE
SET statut           = 'approuvee',
    date_approbation = '2024-11-03'
WHERE id_commande = 12001;

-- Enregistrer la livraison d'une commande
UPDATE COMMANDE
SET statut                   = 'livree',
    date_livraison_prevue    = '2024-11-20',
    date_livraison_effective = '2024-11-19'
WHERE id_commande = 12001;

-- Annuler une commande
UPDATE COMMANDE
SET statut = 'annulee'
WHERE id_commande = 12002;

-- Supprimer une commande en attente
-- (les lignes de commande associées sont supprimées automatiquement via CASCADE)
DELETE FROM COMMANDE
WHERE id_commande = 12002
  AND statut = 'en_attente';


-- =============================================================================
-- 5. PRODUIT_INUTILISABLE
-- =============================================================================

-- Déclarer des produits inutilisables (périmés)
INSERT INTO PRODUIT_INUTILISABLE (id_stock, quantite, date_constat, motif)
VALUES (3, 120, '2024-11-30', 'perime');

-- Déclarer des produits endommagés
INSERT INTO PRODUIT_INUTILISABLE (id_stock, quantite, date_constat, motif)
VALUES (7, 45, '2024-11-15', 'endommage');

-- Mettre à jour le stock après déclaration de produits inutilisables
UPDATE STOCK
SET quantite_disponible = quantite_disponible - 120,
    date_derniere_maj   = '2024-11-30'
WHERE id_stock = 3;

-- Corriger la quantité d'un constat saisi par erreur
UPDATE PRODUIT_INUTILISABLE
SET quantite = 100
WHERE id_inutilisable = 1;

-- Supprimer un constat saisi par erreur
DELETE FROM PRODUIT_INUTILISABLE
WHERE id_inutilisable = 1;