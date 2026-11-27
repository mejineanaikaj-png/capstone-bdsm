-- =====================================================================
-- Capstone · 3 requêtes OLAP correspondant aux KPI (couche Gold)
-- =====================================================================
SET search_path TO capstone;

-- ---------------------------------------------------------------------
-- Requête A — KPI 1 et KPI 2 : boîtes d'antibiotiques pour 1 000 habitants
-- et dépense remboursée par habitant, par région et par année.
-- Opérations : slice (ATC2 = J01) + roll-up (CIP13 → ATC2, âge/sexe → région)
-- + drill-across (fact_dispensation ⋈ fact_population sur année × région).
-- Chaque fait est agrégé AVANT la jointure pour ne pas multiplier les lignes.
-- ---------------------------------------------------------------------
WITH antibio AS (
  SELECT f.time_id, f.region_id,
         SUM(f.boxes)             AS boxes,
         SUM(f.amount_reimbursed) AS amount
  FROM fact_dispensation f
  JOIN dim_product p ON p.product_id = f.product_id
  JOIN dim_atc5   a5 ON a5.atc5_code = p.atc5_code
  JOIN dim_atc4   a4 ON a4.atc4_code = a5.atc4_code
  JOIN dim_atc3   a3 ON a3.atc3_code = a4.atc3_code
  WHERE a3.atc2_code = 'J01'
  GROUP BY f.time_id, f.region_id
),
pop AS (
  SELECT time_id, region_id, SUM(population) AS population
  FROM fact_population
  GROUP BY time_id, region_id
)
SELECT t.year, r.region_name,
       a.boxes, p.population,
       ROUND(1000.0 * a.boxes / p.population, 1) AS boxes_per_1000_inhab,
       ROUND(a.amount / p.population, 2)         AS reimbursed_eur_per_inhab
FROM antibio a
JOIN pop        p USING (time_id, region_id)
JOIN dim_time   t ON t.time_id   = a.time_id
JOIN dim_region r ON r.region_id = a.region_id
ORDER BY t.year, boxes_per_1000_inhab DESC;

-- ---------------------------------------------------------------------
-- Requête B — KPI 3 et KPI 6 : évolution annuelle du taux par région
-- et écart entre la région la plus et la moins consommatrice.
-- Opérations : même cube que A, puis fonction de fenêtre LAG sur l'année.
-- ---------------------------------------------------------------------
WITH antibio AS (
  SELECT f.time_id, f.region_id, SUM(f.boxes) AS boxes
  FROM fact_dispensation f
  JOIN dim_product p ON p.product_id = f.product_id
  JOIN dim_atc5   a5 ON a5.atc5_code = p.atc5_code
  JOIN dim_atc4   a4 ON a4.atc4_code = a5.atc4_code
  JOIN dim_atc3   a3 ON a3.atc3_code = a4.atc3_code
  WHERE a3.atc2_code = 'J01'
  GROUP BY f.time_id, f.region_id
),
pop AS (
  SELECT time_id, region_id, SUM(population) AS population
  FROM fact_population GROUP BY time_id, region_id
),
rate AS (
  SELECT t.year, r.region_name,
         1000.0 * a.boxes / p.population AS rate
  FROM antibio a
  JOIN pop        p USING (time_id, region_id)
  JOIN dim_time   t ON t.time_id   = a.time_id
  JOIN dim_region r ON r.region_id = a.region_id
)
SELECT year, region_name,
       ROUND(rate, 1) AS boxes_per_1000_inhab,
       ROUND(100.0 * (rate - LAG(rate) OVER (PARTITION BY region_name ORDER BY year))
             / LAG(rate) OVER (PARTITION BY region_name ORDER BY year), 1) AS yoy_change_pct,
       ROUND(MAX(rate) OVER (PARTITION BY year) - MIN(rate) OVER (PARTITION BY year), 1) AS gap_max_min
FROM rate
ORDER BY region_name, year;

-- ---------------------------------------------------------------------
-- Requête C — KPI 5 : répartition des boîtes d'antibiotiques par spécialité
-- du prescripteur et par tranche d'âge, en 2025, avec sous-totaux.
-- Opérations : slice (année = 2025, ATC2 = J01) + ROLLUP (spécialité, âge)
-- + part de chaque ligne dans le total national (fonction de fenêtre).
-- ---------------------------------------------------------------------
WITH antibio_2025 AS (
  SELECT pr.specialty_label, ag.age_band_label, f.boxes
  FROM fact_dispensation f
  JOIN dim_time       t  ON t.time_id        = f.time_id
  JOIN dim_prescriber pr ON pr.prescriber_id = f.prescriber_id
  JOIN dim_age_band   ag ON ag.age_band_id   = f.age_band_id
  JOIN dim_product    p  ON p.product_id     = f.product_id
  JOIN dim_atc5       a5 ON a5.atc5_code     = p.atc5_code
  JOIN dim_atc4       a4 ON a4.atc4_code     = a5.atc4_code
  JOIN dim_atc3       a3 ON a3.atc3_code     = a4.atc3_code
  WHERE t.year = 2025 AND a3.atc2_code = 'J01'
)
SELECT specialty_label, age_band_label,
       SUM(boxes) AS boxes,
       ROUND(100.0 * SUM(boxes) / (SELECT SUM(boxes) FROM antibio_2025), 1) AS pct_of_national
FROM antibio_2025
GROUP BY ROLLUP (specialty_label, age_band_label)
ORDER BY specialty_label NULLS LAST, age_band_label NULLS LAST;
