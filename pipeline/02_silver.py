"""SILVER : nettoyage, typage, harmonisation des codes, contrôles qualité avec seuils.
Sorties (dans data/silver/) :
  openmedic_j01.csv.gz   faits de délivrance J01, typés
  population.csv         population INSEE au grain année x région x tranche d'âge x sexe
  ref_atc.csv            hiérarchie ATC J01 (codes + libellés)
  rejects.csv            lignes rejetées + motif
  quality_report.json    indicateurs et résultat des contrôles
"""
import json
import pandas as pd
from config import (LAKE, SILVER, YEARS, REGIONS, INSEE_TO_REGION, INSEE_AGE_TO_BAND)

SILVER.mkdir(parents=True, exist_ok=True)
BRONZE = LAKE / "bronze"
INSEE_XLSX = next((LAKE / "archive").glob("estim-pop-nreg-sexe-gca*.xlsx"))

def to_number(s):
    """'5.464,46' -> 5464.46 : point = séparateur de milliers, virgule = décimale."""
    return pd.to_numeric(s.str.replace(".", "", regex=False).str.replace(",", ".", regex=False), errors="coerce")

# ---------------- Open Medic
om = pd.concat(pd.read_csv(BRONZE / f"openmedic_{y}_J01.csv", sep=";", dtype=str) for y in YEARS)
bronze_rows = len(om)
om["year"] = om["_release"].astype(int)
om["boxes"] = pd.to_numeric(om["BOITES"], errors="coerce")
bronze_boxes = int(om["boxes"].sum())
om["amount_reimbursed"] = to_number(om["REM"])
om["reimbursable_base"] = to_number(om["BSE"])
for src, dst in [("age", "age_band_id"), ("sexe", "sex_id"), ("BEN_REG", "region_id"), ("PSP_SPE", "prescriber_id")]:
    om[dst] = pd.to_numeric(om[src], errors="coerce").astype("Int64")
om["product_id"] = om["CIP13"].astype("int64")

# Règles de rejet
reasons = pd.Series("", index=om.index)
reasons[om[["boxes", "amount_reimbursed", "reimbursable_base"]].isna().any(axis=1)] = "mesure non numérique"
reasons[(om["boxes"] < 0)] = "nombre de boîtes négatif"
reasons[~om["region_id"].isin(list(REGIONS))] = "code région inconnu du référentiel"
rejects = om[reasons != ""].assign(reject_reason=reasons[reasons != ""])
om = om[reasons == ""]

# Référentiel ATC : libellés pris dans la release 2024 (accents de la release 2025 altérés)
ref_atc = (om.sort_values("year")
             .drop_duplicates("ATC5")[["ATC1", "l_ATC1", "ATC2", "L_ATC2", "ATC3", "L_ATC3", "ATC4", "L_ATC4", "ATC5", "L_ATC5"]])
products = om.sort_values("year").drop_duplicates("product_id")[["product_id", "l_cip13", "ATC5"]]

facts = om[["year", "product_id", "region_id", "age_band_id", "sex_id", "prescriber_id",
            "boxes", "amount_reimbursed", "reimbursable_base", "_release"]].rename(columns={"_release": "source_release"})
facts.to_csv(SILVER / "openmedic_j01.csv.gz", index=False, compression="gzip")
ref_atc.to_csv(SILVER / "ref_atc.csv", index=False)
products.to_csv(SILVER / "ref_product.csv", index=False)
rejects.to_csv(SILVER / "rejects.csv", index=False)

# ---------------- INSEE : format large -> long, tranches regroupées, régions recodées
rows = []
for year in YEARS:
    raw = pd.read_excel(INSEE_XLSX, sheet_name=str(year), header=None)
    ages = raw.iloc[4, 1:].tolist()
    sexes = raw.iloc[3, 1:].ffill().tolist()
    for _, r in raw.iloc[5:].iterrows():
        name = str(r[0]).strip()
        if name not in INSEE_TO_REGION:
            continue                                 # totaux France / DOM / notes ignorés
        for age, sex, val in zip(ages, sexes, r[1:]):
            if sex in ("Hommes", "Femmes") and age in INSEE_AGE_TO_BAND:
                rows.append((year, INSEE_TO_REGION[name], INSEE_AGE_TO_BAND[age], 1 if sex == "Hommes" else 2, int(val)))
pop = (pd.DataFrame(rows, columns=["year", "region_id", "age_band_id", "sex_id", "population"])
         .groupby(["year", "region_id", "age_band_id", "sex_id"], as_index=False)["population"].sum())
pop.to_csv(SILVER / "population.csv", index=False)

# ---------------- Contrôles qualité (seuils)
known = facts[(facts.region_id != 99) & (facts.age_band_id != 99) & (facts.sex_id != 9)]
key = ["year", "region_id", "age_band_id", "sex_id"]
join_rate = known.merge(pop[key], on=key, how="left", indicator=True)["_merge"].eq("both").mean()
unknown_region_share = 100 * facts.loc[facts.region_id == 99, "boxes"].sum() / facts["boxes"].sum()
gates = {
    "invalid_rows_pct": round(100 * len(rejects) / bronze_rows, 3),
    "unknown_region_boxes_pct": round(float(unknown_region_share), 2),
    "join_rate_pct": round(100 * float(join_rate), 2),
    "reconciliation_boxes": int(bronze_boxes - facts["boxes"].sum() - rejects["boxes"].fillna(0).sum()),
}
gates["status"] = {
    "invalid_rows == 0 % (rejet)": bool(gates["invalid_rows_pct"] == 0),
    "unknown_region < 2 % des boîtes (avertissement)": bool(gates["unknown_region_boxes_pct"] < 2),
    "join_rate > 98 % (bloquant)": bool(gates["join_rate_pct"] > 98),
    "reconciliation == 0 (bloquant)": bool(gates["reconciliation_boxes"] == 0),
}
report = {
    "bronze_rows": bronze_rows, "silver_rows": len(facts), "rejected_rows": len(rejects),
    "rows_per_year": facts.groupby("year").size().to_dict(),
    "boxes_per_year": facts.groupby("year")["boxes"].sum().to_dict(),
    "reimbursed_eur_per_year": facts.groupby("year")["amount_reimbursed"].sum().round(2).to_dict(),
    "distinct_cip13": int(facts.product_id.nunique()), "distinct_atc5": int(ref_atc.ATC5.nunique()),
    "population_per_year": pop.groupby("year")["population"].sum().to_dict(),
    "quality_gates": gates,
    "notes": [
        "REM et BSE : point = séparateur de milliers, virgule = décimale (70 683 valeurs J01 concernées).",
        "Release 2025 : accents des libellés ATC altérés ; libellés repris de la release 2024.",
        "BEN_REG : Corse regroupée avec la région 93, DOM regroupés sous le code 5 ; INSEE recodé de même.",
        "Codes inconnus conservés (âge 99, sexe 9, région 99) mais exclus des taux.",
    ],
}
(SILVER / "quality_report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False, default=int))
print(json.dumps(report, indent=2, ensure_ascii=False, default=int))
