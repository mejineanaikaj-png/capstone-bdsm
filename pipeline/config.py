"""Paramètres communs du pipeline (chemins et référentiels de codes)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAKE = ROOT / "lake"                      # archive/ et bronze/ restent en local (trop volumineux pour GitHub)
SILVER = ROOT / "data" / "silver"         # sorties Silver versionnées dans le dépôt

YEARS = (2024, 2025)
ATC2_SCOPE = "J01"                        # antibactériens à usage systémique

# Régions Open Medic (BEN_REG). Le code 94 (Corse) n'existe pas dans Open Medic :
# la Corse est regroupée avec la région 93, et les DOM sont regroupés sous le code 5.
REGIONS = {
    11: "Île-de-France", 24: "Centre-Val de Loire", 27: "Bourgogne-Franche-Comté",
    28: "Normandie", 32: "Hauts-de-France", 44: "Grand Est", 52: "Pays de la Loire",
    53: "Bretagne", 75: "Nouvelle-Aquitaine", 76: "Occitanie", 84: "Auvergne-Rhône-Alpes",
    93: "Provence-Alpes-Côte d'Azur et Corse", 5: "Outre-mer (DOM)", 99: "Non renseigné",
}
# Libellés INSEE -> code région Open Medic
INSEE_TO_REGION = {
    "Auvergne-Rhône-Alpes": 84, "Bourgogne-Franche-Comté": 27, "Bretagne": 53,
    "Centre-Val-de-Loire": 24, "Corse": 93, "Grand Est": 44, "Hauts-de-France": 32,
    "Île-de-France": 11, "Normandie": 28, "Nouvelle-Aquitaine": 75, "Occitanie": 76,
    "Pays de la Loire": 52, "Provence-Alpes-Côte d'Azur": 93,
    "Guadeloupe": 5, "Martinique": 5, "Guyane": 5, "La Réunion": 5, "Mayotte": 5,
}
AGE_BANDS = {0: ("0-19 ans", 0, 19), 20: ("20-59 ans", 20, 59), 60: ("60 ans et plus", 60, None), 99: ("Non renseigné", None, None)}
# Grandes classes d'âge INSEE -> tranches Open Medic
INSEE_AGE_TO_BAND = {"0 à 19 ans": 0, "20 à 39 ans": 20, "40 à 59 ans": 20, "60 à 74 ans": 60, "75 ans et plus": 60}
SEXES = {1: "Homme", 2: "Femme", 9: "Non renseigné"}
