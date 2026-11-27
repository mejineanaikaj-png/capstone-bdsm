-- =====================================================================
-- Capstone · Consommation d'antibiotiques en ville (ODD 3)
-- Couche GOLD : entrepôt de données (constellation de faits,
-- dimension Médicament en flocon selon la hiérarchie ATC)
-- PostgreSQL · schéma dédié "capstone" (pas de conflit avec le TP OLAP)
-- =====================================================================
DROP SCHEMA IF EXISTS capstone CASCADE;
CREATE SCHEMA capstone;
SET search_path TO capstone;

-- ---------- Dimension Temps (grain annuel : Open Medic est publié par année)
CREATE TABLE dim_time (
  time_id SMALLINT PRIMARY KEY,
  year    SMALLINT NOT NULL UNIQUE
);

-- ---------- Dimension Médicament, en flocon (classification ATC de l'OMS)
CREATE TABLE dim_atc1 (atc1_code CHAR(1) PRIMARY KEY, atc1_label TEXT NOT NULL);
CREATE TABLE dim_atc2 (atc2_code CHAR(3) PRIMARY KEY, atc2_label TEXT NOT NULL,
                       atc1_code CHAR(1) NOT NULL REFERENCES dim_atc1);
CREATE TABLE dim_atc3 (atc3_code CHAR(4) PRIMARY KEY, atc3_label TEXT NOT NULL,
                       atc2_code CHAR(3) NOT NULL REFERENCES dim_atc2);
CREATE TABLE dim_atc4 (atc4_code CHAR(5) PRIMARY KEY, atc4_label TEXT NOT NULL,
                       atc3_code CHAR(4) NOT NULL REFERENCES dim_atc3);
CREATE TABLE dim_atc5 (atc5_code CHAR(7) PRIMARY KEY, atc5_label TEXT NOT NULL,   -- molécule
                       atc4_code CHAR(5) NOT NULL REFERENCES dim_atc4);
CREATE TABLE dim_product (
  product_id    BIGINT PRIMARY KEY,                                              -- code CIP13
  product_label TEXT   NOT NULL,
  atc5_code     CHAR(7) NOT NULL REFERENCES dim_atc5
);

-- ---------- Dimensions partagées par les deux faits (axes de jointure)
CREATE TABLE dim_region (
  region_id   SMALLINT PRIMARY KEY,                                              -- code officiel INSEE
  region_name TEXT NOT NULL
);
CREATE TABLE dim_age_band (
  age_band_id    SMALLINT PRIMARY KEY,
  age_band_label TEXT NOT NULL,
  age_min        SMALLINT NOT NULL,
  age_max        SMALLINT                                                        -- NULL = sans borne haute
);
CREATE TABLE dim_sex (
  sex_id    SMALLINT PRIMARY KEY,
  sex_label TEXT NOT NULL
);

-- ---------- Dimension propre à la délivrance
CREATE TABLE dim_prescriber (
  prescriber_id   SMALLINT PRIMARY KEY,
  specialty_label TEXT NOT NULL
);

-- ---------- Fait 1 : délivrances de médicaments en pharmacie de ville (Open Medic)
-- Grain : année × présentation (CIP13) × région × tranche d'âge × sexe × spécialité du prescripteur
CREATE TABLE fact_dispensation (
  dispensation_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  time_id           SMALLINT NOT NULL REFERENCES dim_time,
  product_id        BIGINT   NOT NULL REFERENCES dim_product,
  region_id         SMALLINT NOT NULL REFERENCES dim_region,
  age_band_id       SMALLINT NOT NULL REFERENCES dim_age_band,
  sex_id            SMALLINT NOT NULL REFERENCES dim_sex,
  prescriber_id     SMALLINT NOT NULL REFERENCES dim_prescriber,
  boxes             INTEGER  NOT NULL CHECK (boxes >= 0),                       -- additif
  amount_reimbursed NUMERIC(14,2) NOT NULL,                                     -- additif (€)
  reimbursable_base NUMERIC(14,2) NOT NULL,                                     -- additif (€)
  source_release    TEXT NOT NULL                                               -- traçabilité vers le Silver
);

-- ---------- Fait 2 : population (INSEE) — dénominateur de tous les taux
-- Grain : année × région × tranche d'âge × sexe. Mesure semi-additive : jamais sommée sur les années.
CREATE TABLE fact_population (
  time_id     SMALLINT NOT NULL REFERENCES dim_time,
  region_id   SMALLINT NOT NULL REFERENCES dim_region,
  age_band_id SMALLINT NOT NULL REFERENCES dim_age_band,
  sex_id      SMALLINT NOT NULL REFERENCES dim_sex,
  population  INTEGER  NOT NULL CHECK (population > 0),
  PRIMARY KEY (time_id, region_id, age_band_id, sex_id)
);

CREATE INDEX ON fact_dispensation (time_id);
CREATE INDEX ON fact_dispensation (region_id);
CREATE INDEX ON fact_dispensation (product_id);
CREATE INDEX ON fact_dispensation (prescriber_id);

-- =====================================================================
-- Jeu d'essai SYNTHÉTIQUE (valeurs fictives, pour tester les requêtes).
-- Les vraies données viendront de la couche Silver (Open Medic + INSEE).
-- =====================================================================
INSERT INTO dim_time VALUES (1, 2024), (2, 2025);

INSERT INTO dim_atc1 VALUES ('J', 'Anti-infectieux généraux à usage systémique'),
                            ('N', 'Système nerveux');
INSERT INTO dim_atc2 VALUES ('J01', 'Antibactériens à usage systémique', 'J'),
                            ('N02', 'Analgésiques', 'N');
INSERT INTO dim_atc3 VALUES ('J01C', 'Bêtalactamines, pénicillines', 'J01'),
                            ('J01F', 'Macrolides, lincosamides et streptogramines', 'J01'),
                            ('N02B', 'Autres analgésiques et antipyrétiques', 'N02');
INSERT INTO dim_atc4 VALUES ('J01CA', 'Pénicillines à large spectre', 'J01C'),
                            ('J01FA', 'Macrolides', 'J01F'),
                            ('N02BE', 'Anilides', 'N02B');
INSERT INTO dim_atc5 VALUES ('J01CA04', 'Amoxicilline', 'J01CA'),
                            ('J01FA10', 'Azithromycine', 'J01FA'),
                            ('N02BE01', 'Paracétamol', 'N02BE');
INSERT INTO dim_product VALUES
  (3400000000001, 'Amoxicilline 500 mg (fictif)',   'J01CA04'),
  (3400000000002, 'Amoxicilline 1 g (fictif)',      'J01CA04'),
  (3400000000003, 'Azithromycine 250 mg (fictif)',  'J01FA10'),
  (3400000000004, 'Paracétamol 1 g (fictif)',       'N02BE01');

INSERT INTO dim_region VALUES (11, 'Île-de-France'), (84, 'Auvergne-Rhône-Alpes'), (76, 'Occitanie');
INSERT INTO dim_age_band VALUES (1, '0-19 ans', 0, 19), (2, '20-59 ans', 20, 59), (3, '60 ans et plus', 60, NULL);
INSERT INTO dim_sex VALUES (1, 'Homme'), (2, 'Femme');
INSERT INTO dim_prescriber VALUES (1, 'Médecine générale'), (2, 'Pédiatrie'), (3, 'Chirurgie dentaire');

-- Population fictive (ordre de grandeur réaliste, valeurs inventées)
INSERT INTO fact_population (time_id, region_id, age_band_id, sex_id, population)
SELECT t.time_id, r.region_id, a.age_band_id, s.sex_id,
       ((CASE r.region_id WHEN 11 THEN 12300000 WHEN 84 THEN 8100000 ELSE 6100000 END)
        * (CASE a.age_band_id WHEN 1 THEN 0.24 WHEN 2 THEN 0.50 ELSE 0.26 END) * 0.5
        * (1 + 0.004 * (t.time_id - 1)))::int
FROM dim_time t, dim_region r, dim_age_band a, dim_sex s;

-- Délivrances fictives (formule déterministe pour obtenir des écarts entre régions et années)
INSERT INTO fact_dispensation (time_id, product_id, region_id, age_band_id, sex_id, prescriber_id,
                               boxes, amount_reimbursed, reimbursable_base, source_release)
SELECT t.time_id, p.product_id, r.region_id, a.age_band_id, s.sex_id, pr.prescriber_id,
       b.boxes, ROUND(b.boxes * 2.10, 2), ROUND(b.boxes * 3.00, 2),
       'synthetic-' || t.year
FROM dim_time t, dim_product p, dim_region r, dim_age_band a, dim_sex s, dim_prescriber pr,
LATERAL (SELECT ((CASE r.region_id WHEN 11 THEN 52000 WHEN 84 THEN 41000 ELSE 36000 END)
          * (CASE a.age_band_id WHEN 1 THEN 1.3 WHEN 2 THEN 0.8 ELSE 1.1 END)
          * (CASE pr.prescriber_id WHEN 1 THEN 1.0 WHEN 2 THEN (CASE a.age_band_id WHEN 1 THEN 0.6 ELSE 0.02 END) ELSE 0.08 END)
          * (CASE WHEN p.product_id IN (3400000000001, 3400000000002) THEN 1.0 WHEN p.product_id = 3400000000003 THEN 0.4 ELSE 2.5 END)
          * (CASE WHEN t.time_id = 2 AND r.region_id = 76 THEN 1.04 WHEN t.time_id = 2 THEN 0.97 ELSE 1 END)
          * (CASE s.sex_id WHEN 2 THEN 1.12 ELSE 1 END))::int AS boxes) b;
