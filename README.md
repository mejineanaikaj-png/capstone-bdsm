# Consommation d'antibiotiques en ville en France — Capstone BDSM

**Cours :** Big Data Storage & Management (M2 HSIM, IAE Lyon) · Dr. Genoveva Vargas-Solar, Prof. Chirine Ghedira-Guégan
**Objectif de développement durable :** ODD 3 — Bonne santé et bien-être (lutte contre la résistance aux antibiotiques)

## Question de recherche

> Comment la consommation d'antibiotiques en ville varie-t-elle selon les régions, l'âge, le sexe et les prescripteurs, et comment évolue-t-elle d'une année sur l'autre ?

**Utilisateurs visés :** agences régionales de santé (ARS), Assurance Maladie, Santé publique France.

## Données

| Fournisseur | Jeu de données | Versions | Rôle dans l'entrepôt |
|---|---|---|---|
| Assurance Maladie | [Open Medic](https://www.data.gouv.fr/datasets/open-medic-base-complete-sur-les-depenses-de-medicaments-interregimes) : médicaments délivrés en pharmacie de ville | Bases annuelles 2024 et 2025 | `fact_dispensation` |
| INSEE | [Estimations de population](https://www.insee.fr/fr/statistiques/8721456) par région, sexe et âge quinquennal | Éditions 2025 et 2026 | `fact_population` |

Les deux sources sont publiées chaque année, ce qui permet le chargement incrémental de deux versions. Elles sont agrégées : elles ne contiennent aucune donnée personnelle.

---

## 1. Les KPI

| # | KPI | Formule | Ce qu'il permet de décider |
|---|---|---|---|
| KPI 1 | **Boîtes d'antibiotiques pour 1 000 habitants** | `SUM(boxes, ATC2 = J01) / SUM(population) × 1 000` | Où la consommation est la plus forte, à population égale |
| KPI 2 | **Dépense remboursée par habitant** | `SUM(amount_reimbursed, J01) / SUM(population)` | Le coût pour l'Assurance Maladie, comparable entre régions |
| KPI 3 | **Évolution annuelle** | `(KPI1 année N − KPI1 année N−1) / KPI1 année N−1` | Si la consommation baisse, comme le visent les plans nationaux |
| KPI 4 | **Part de chaque région** | `boxes région / boxes France` | Le poids de chaque région dans le total |
| KPI 5 | **Répartition par spécialité du prescripteur** | `boxes par spécialité / total` | Quels prescripteurs cibler par des actions de sensibilisation |
| KPI 6 | **Écart entre régions** | `max(KPI1) − min(KPI1)` sur l'ensemble des régions | L'ampleur des inégalités territoriales |

**Règle de calcul.** Un taux se calcule toujours comme une somme divisée par une somme, jamais comme la moyenne des taux régionaux. La population est une mesure semi-additive : on l'additionne sur les régions, les âges et les sexes, mais jamais sur les années.

---

## 2. Le schéma de l'entrepôt (couche Gold)

L'entrepôt est une **constellation de faits** : deux tables de faits partagent les dimensions Temps, Région, Tranche d'âge et Sexe. La dimension Médicament est **en flocon** : elle suit la hiérarchie ATC de l'OMS, ce qui permet le drill-down de l'ensemble des antibiotiques jusqu'à une boîte précise.

```mermaid
erDiagram
    fact_dispensation }o--|| dim_time : "annee"
    fact_dispensation }o--|| dim_product : "presentation"
    fact_dispensation }o--|| dim_region : "region"
    fact_dispensation }o--|| dim_age_band : "tranche d'age"
    fact_dispensation }o--|| dim_sex : "sexe"
    fact_dispensation }o--|| dim_prescriber : "prescripteur"
    fact_population  }o--|| dim_time : "annee"
    fact_population  }o--|| dim_region : "region"
    fact_population  }o--|| dim_age_band : "tranche d'age"
    fact_population  }o--|| dim_sex : "sexe"
    dim_product }o--|| dim_atc5 : "molecule"
    dim_atc5 }o--|| dim_atc4 : ""
    dim_atc4 }o--|| dim_atc3 : ""
    dim_atc3 }o--|| dim_atc2 : "classe (J01)"
    dim_atc2 }o--|| dim_atc1 : "groupe"

    fact_dispensation {
        BIGINT dispensation_id PK
        SMALLINT time_id FK
        BIGINT product_id FK
        SMALLINT region_id FK
        SMALLINT age_band_id FK
        SMALLINT sex_id FK
        SMALLINT prescriber_id FK
        INTEGER boxes "additif"
        NUMERIC amount_reimbursed "additif"
        NUMERIC reimbursable_base "additif"
        TEXT source_release "tracabilite"
    }
    fact_population {
        SMALLINT time_id PK
        SMALLINT region_id PK
        SMALLINT age_band_id PK
        SMALLINT sex_id PK
        INTEGER population "semi-additif"
    }
    dim_time {
        SMALLINT time_id PK
        SMALLINT year
    }
    dim_region {
        SMALLINT region_id PK "code INSEE"
        TEXT region_name
    }
    dim_age_band {
        SMALLINT age_band_id PK
        TEXT age_band_label
        SMALLINT age_min
        SMALLINT age_max
    }
    dim_sex {
        SMALLINT sex_id PK
        TEXT sex_label
    }
    dim_prescriber {
        SMALLINT prescriber_id PK
        TEXT specialty_label
    }
    dim_product {
        BIGINT product_id PK "CIP13"
        TEXT product_label
        CHAR atc5_code FK
    }
    dim_atc5 {
        CHAR atc5_code PK
        TEXT atc5_label
        CHAR atc4_code FK
    }
    dim_atc4 {
        CHAR atc4_code PK
        TEXT atc4_label
        CHAR atc3_code FK
    }
    dim_atc3 {
        CHAR atc3_code PK
        TEXT atc3_label
        CHAR atc2_code FK
    }
    dim_atc2 {
        CHAR atc2_code PK
        TEXT atc2_label
        CHAR atc1_code FK
    }
    dim_atc1 {
        CHAR atc1_code PK
        TEXT atc1_label
    }
```

| Table | Rôle | Grain (que représente une ligne ?) |
|---|---|---|
| `fact_dispensation` | Fait : délivrances (Open Medic) | année × présentation (CIP13) × région × tranche d'âge × sexe × spécialité du prescripteur |
| `fact_population` | Fait : population (INSEE) | année × région × tranche d'âge × sexe |
| `dim_time` | Temps | une année (Open Medic n'a pas de grain plus fin) |
| `dim_product` → `dim_atc5` → … → `dim_atc1` | Médicament, en flocon | une présentation, puis la molécule, puis les niveaux de classe ATC |
| `dim_region` | Territoire | une région (code officiel INSEE) |
| `dim_age_band`, `dim_sex` | Profil du bénéficiaire | une tranche d'âge, un sexe |
| `dim_prescriber` | Prescripteur | une spécialité médicale |

**Choix de conception**
- **Deux faits plutôt qu'un.** La population n'a pas le grain des délivrances (pas de médicament, pas de prescripteur). La garder dans sa propre table évite de la répéter sur chaque ligne et de la compter plusieurs fois.
- **Dimensions conformes.** Temps, Région, Tranche d'âge et Sexe sont partagées par les deux faits : c'est ce qui rend possible le *drill-across* (croiser les deux faits).
- **Tranches d'âge harmonisées en Silver.** Les tranches de 5 ans de l'INSEE sont regroupées dans les tranches d'Open Medic avant le chargement, pour que les deux faits utilisent la même dimension.
- **Flocon sur la seule dimension Médicament.** C'est la seule vraie hiérarchie profonde (5 niveaux ATC) ; les autres dimensions restent dénormalisées, comme dans un schéma en étoile.

Le script complet est dans [`sql/01_gold_schema.sql`](sql/01_gold_schema.sql) (tables et jeu d'essai synthétique).

---

## 3. Les requêtes OLAP en langage naturel

Chaque KPI devient une requête sur le schéma en suivant le même raisonnement : **filtrer** (slice / dice), **agréger** au bon niveau (roll-up), puis **croiser** avec la population quand il faut un taux (drill-across).

| KPI | Question en langage naturel | Traduction sur le schéma | Opérations OLAP |
|---|---|---|---|
| KPI 1 | « Combien de boîtes d'antibiotiques sont délivrées pour 1 000 habitants dans chaque région, chaque année ? » | Garder les produits dont la classe ATC2 est J01 en remontant le flocon `dim_product` → `dim_atc5` → `dim_atc4` → `dim_atc3`. Sommer `boxes` par (année, région). Sommer `population` par (année, région) dans `fact_population`. Joindre les deux résultats sur (année, région) et diviser. | Slice (ATC2 = J01), roll-up (CIP13 → ATC2 ; âge et sexe → région), drill-across |
| KPI 2 | « Combien l'Assurance Maladie rembourse-t-elle en antibiotiques par habitant, dans chaque région ? » | Même requête que le KPI 1, avec `SUM(amount_reimbursed)` au numérateur. | Slice, roll-up, drill-across |
| KPI 3 | « La consommation d'antibiotiques baisse-t-elle d'une année sur l'autre dans chaque région ? » | Calculer le KPI 1 par (année, région), puis comparer chaque année à la précédente avec `LAG` sur une fenêtre partitionnée par région et ordonnée par année. | Slice, roll-up, fonction de fenêtre sur la dimension Temps |
| KPI 4 | « Quelle part du total national chaque région représente-t-elle ? » | Sommer `boxes` (J01) par région pour une année, puis diviser par le total national calculé avec `SUM(...) OVER ()`. | Slice (année, J01), roll-up vers la région, part du total |
| KPI 5 | « Quelles spécialités prescrivent le plus d'antibiotiques, et pour quelles tranches d'âge ? » | Filtrer une année et J01, sommer `boxes` par (spécialité, tranche d'âge) avec `ROLLUP` pour obtenir les sous-totaux par spécialité et le total, puis calculer la part de chaque ligne. | Dice (année × J01), ROLLUP (spécialité, âge), drill-down vers l'âge |
| KPI 6 | « Quel est l'écart entre la région qui consomme le plus et celle qui consomme le moins ? » | Calculer le KPI 1 par région pour chaque année, puis `MAX(...) − MIN(...)` sur une fenêtre partitionnée par année. | Roll-up, fonction de fenêtre |
| Drill-down | « Quelles molécules expliquent la consommation dans une région ? » | Partir du KPI 1 d'une région, puis descendre la hiérarchie ATC : J01 → J01C (pénicillines) → J01CA04 (amoxicilline). | Drill-down le long du flocon ATC |

**Bonus.** Trois de ces requêtes sont écrites en SQL et testées dans [`sql/02_kpi_queries.sql`](sql/02_kpi_queries.sql) et dans le notebook :
- **Requête A** : KPI 1 et KPI 2 par région et par année ;
- **Requête B** : KPI 3 et KPI 6, évolution annuelle et écart entre régions ;
- **Requête C** : KPI 5, répartition par spécialité et tranche d'âge, avec `ROLLUP`.

---

## Contenu du dépôt

| Fichier | Contenu |
|---|---|
| `README.md` | Ce document : KPI, schéma Gold, requêtes OLAP en langage naturel |
| `notebook/OLAP_challenge_and_capstone.ipynb` | Le notebook de la séance (challenge OLAP T1 à T10), complété par le schéma Gold du projet et les 3 requêtes KPI |
| `sql/01_gold_schema.sql` | Création du schéma Gold et jeu d'essai synthétique |
| `sql/02_kpi_queries.sql` | Les 3 requêtes OLAP des KPI |

**Exécution.** Les scripts SQL tournent sur PostgreSQL (Aiven). Le schéma est créé dans un schéma dédié `capstone`, pour ne pas écraser les tables du challenge OLAP.

## Limites

- **Jeu d'essai synthétique.** Les valeurs actuellement chargées sont fictives et servent à tester les requêtes. Elles seront remplacées par les données réelles issues de la couche Silver.
- **Ville uniquement.** Open Medic ne couvre pas les médicaments délivrés à l'hôpital.
- **Une boîte n'est pas une dose.** La mesure de référence internationale est la dose définie journalière (DDD) de l'OMS.
- **Petits effectifs masqués** dans Open Medic (secret statistique).
- **Grain annuel et régional** : pas d'analyse saisonnière ni départementale.
