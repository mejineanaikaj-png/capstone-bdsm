"""ARCHIVE + BRONZE.
Archive : empreinte SHA-256 de chaque fichier source tel que téléchargé (lecture seule).
Bronze  : lecture brute (tout en texte, aucune correction), restreinte au périmètre ATC2 = J01,
          avec colonnes de traçabilité. Ingestion idempotente : un fichier déjà chargé
          (même empreinte) n'est pas rechargé.
Usage : placer OPEN_MEDIC_2024.CSV, OPEN_MEDIC_2025.CSV et le classeur INSEE dans lake/archive/.
"""
import hashlib, json, datetime as dt
import pandas as pd
from config import LAKE, YEARS, ATC2_SCOPE

ARCHIVE, BRONZE = LAKE / "archive", LAKE / "bronze"
BRONZE.mkdir(parents=True, exist_ok=True)
manifest_path = ARCHIVE / "archive_manifest.json"
manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()

for f in sorted(ARCHIVE.glob("*")):
    if f.name == manifest_path.name:
        continue
    manifest[f.name] = {"sha256": sha256(f), "size_bytes": f.stat().st_size,
                        "checked_at": dt.datetime.now().isoformat(timespec="seconds")}
manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False))

for year in YEARS:
    src = ARCHIVE / f"OPEN_MEDIC_{year}.CSV"
    out = BRONZE / f"openmedic_{year}_J01.csv"
    marker = BRONZE / f"openmedic_{year}.sha256"
    digest = manifest[src.name]["sha256"]
    if marker.exists() and marker.read_text() == digest:
        print(f"{year}: déjà chargé (même empreinte), rien à faire")
        continue
    parts = [c[c["ATC2"] == ATC2_SCOPE] for c in
             pd.read_csv(src, sep=";", encoding="latin-1", dtype=str, chunksize=400_000)]
    df = pd.concat(parts)
    df["_source_file"] = src.name
    df["_release"] = str(year)
    df["_ingested_at"] = dt.datetime.now().isoformat(timespec="seconds")
    df.to_csv(out, sep=";", index=False, encoding="utf-8")
    marker.write_text(digest)
    print(f"{year}: {len(df):,} lignes J01 -> {out.name}")
