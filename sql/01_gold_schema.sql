-- =====================================================================
-- Capstone · Consommation d'antibiotiques en ville (ODD 3)
-- Couche GOLD : entrepôt de données (constellation de faits,
-- dimension Médicament en flocon selon la hiérarchie ATC)
-- PostgreSQL · schéma dédié "capstone" (pas de conflit avec le TP OLAP)
-- Les tables sont remplies par pipeline/03_load_gold.py à partir de data/silver/.
-- =====================================================================
DROP SCHEMA IF EXISTS capstone CASCADE;
CREATE SCHEMA capstone;
SET search_path TO capstone;

-- ---------- Dimension Temps (grain annuel : Open Medic est publié par année)
CREATE TABLE dim_time (
  time_id SMALLINT PRIMARY KEY,                                                  -- = année
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
  age_min        SMALLINT,                                                       -- NULL = non renseigné
  age_max        SMALLINT                                                        -- NULL = sans borne haute
);
CREATE TABLE dim_sex (
  sex_id    SMALLINT PRIMARY KEY,
  sex_label TEXT NOT NULL
);

-- ---------- Dimension propre à la délivrance
CREATE TABLE dim_prescriber (
  prescriber_id   SMALLINT PRIMARY KEY,                                           -- code PSP_SPE d'Open Medic
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
