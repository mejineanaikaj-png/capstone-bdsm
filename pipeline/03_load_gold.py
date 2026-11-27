"""GOLD : crée le schéma capstone et le remplit à partir des fichiers Silver.
Connexion par variables d'environnement : PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD (+ PGSSLMODE=require sur Aiven).
Source des fichiers : data/silver/ en local, ou l'URL GitHub du dépôt (argument --remote).
"""
import io, sys
from pathlib import Path
import pandas as pd
import psycopg2

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "pipeline"))
from config import REGIONS, AGE_BANDS, SEXES

REMOTE = "https://raw.githubusercontent.com/mejineanaikaj-png/capstone-bdsm/main/data/silver/"
base = REMOTE if "--remote" in sys.argv else str(ROOT / "data" / "silver") + "/"
read = lambda name, **kw: pd.read_csv(base + name, **kw)

facts = read("openmedic_j01.csv.gz", compression="gzip")
pop = read("population.csv")
atc = read("ref_atc.csv")
prod = read("ref_product.csv")

conn = psycopg2.connect()                                  # lit les variables PG*
cur = conn.cursor()
cur.execute((ROOT / "sql" / "01_gold_schema.sql").read_text(encoding="utf-8"))

def copy(table, df):
    buf = io.StringIO()
    df.to_csv(buf, index=False, header=False, na_rep="\\N")
    buf.seek(0)
    cur.copy_expert(f"COPY capstone.{table} ({', '.join(df.columns)}) FROM STDIN WITH (FORMAT csv, NULL '\\N')", buf)

years = sorted(set(facts.year) | set(pop.year))
copy("dim_time", pd.DataFrame({"time_id": years, "year": years}))
copy("dim_atc1", atc[["ATC1", "l_ATC1"]].drop_duplicates("ATC1").set_axis(["atc1_code", "atc1_label"], axis=1))
copy("dim_atc2", atc[["ATC2", "L_ATC2", "ATC1"]].drop_duplicates("ATC2").set_axis(["atc2_code", "atc2_label", "atc1_code"], axis=1))
copy("dim_atc3", atc[["ATC3", "L_ATC3", "ATC2"]].drop_duplicates("ATC3").set_axis(["atc3_code", "atc3_label", "atc2_code"], axis=1))
copy("dim_atc4", atc[["ATC4", "L_ATC4", "ATC3"]].drop_duplicates("ATC4").set_axis(["atc4_code", "atc4_label", "atc3_code"], axis=1))
copy("dim_atc5", atc[["ATC5", "L_ATC5", "ATC4"]].drop_duplicates("ATC5").set_axis(["atc5_code", "atc5_label", "atc4_code"], axis=1))
copy("dim_product", prod.set_axis(["product_id", "product_label", "atc5_code"], axis=1))
copy("dim_region", pd.DataFrame(list(REGIONS.items()), columns=["region_id", "region_name"]))
copy("dim_age_band", pd.DataFrame([(k, *v) for k, v in AGE_BANDS.items()],
                                   columns=["age_band_id", "age_band_label", "age_min", "age_max"]).astype({"age_min": "Int64", "age_max": "Int64"}))
copy("dim_sex", pd.DataFrame(list(SEXES.items()), columns=["sex_id", "sex_label"]))
codes = sorted(facts.prescriber_id.unique())
copy("dim_prescriber", pd.DataFrame({"prescriber_id": codes,
     "specialty_label": [f"Spécialité PSP_SPE {c}" for c in codes]}))   # libellés à compléter depuis le descriptif Open Medic
copy("fact_dispensation", facts.rename(columns={"year": "time_id"})[
     ["time_id", "product_id", "region_id", "age_band_id", "sex_id", "prescriber_id",
      "boxes", "amount_reimbursed", "reimbursable_base", "source_release"]])
copy("fact_population", pop.rename(columns={"year": "time_id"}))
conn.commit()

cur.execute("SELECT 'fact_dispensation', COUNT(*) FROM capstone.fact_dispensation UNION ALL "
            "SELECT 'fact_population', COUNT(*) FROM capstone.fact_population")
for t, n in cur.fetchall():
    print(f"{t}: {n:,} lignes")
