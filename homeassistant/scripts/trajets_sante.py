"""Prépare l'import des tracés de l'export Santé dans l'historique des trajets (plan P9-M, M0).

    python3 homeassistant/scripts/trajets_sante.py <dossier workout-routes> <sortie.jsonl>

Lit chaque GPX (un point par seconde), retire les points imprécis, garde un point tous les 10 m environ et écrit un
point par ligne. Copier ensuite la sortie dans le dossier d'AppDaemon (`/config/trajets_import.jsonl`) et déclencher
l'événement `aiguillage_trajets_importer` avec {"fichier": "/config/trajets_import.jsonl", "source": "sante"}.
"""

from pathlib import Path
import json
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "appdaemon" / "apps"))
import aiguillage_trajets as trajets  # noqa: E402


def main(dossier, sortie):
    total = gardes = traces = 0
    with open(sortie, "w", encoding="utf-8") as out:
        for gpx in sorted(Path(dossier).glob("*.gpx")):
            points = trajets.lire_gpx(gpx.read_text(encoding="utf-8", errors="ignore"))
            garde = trajets.eclaircir(points)
            total, gardes, traces = total + len(points), gardes + len(garde), traces + 1
            for p in garde:
                out.write(json.dumps(p, separators=(",", ":")) + "\n")
    print(f"{traces} tracé(s), {total} point(s) lus, {gardes} gardés")


if __name__ == "__main__":
    main(*sys.argv[1:3])
