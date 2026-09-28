#!/usr/bin/env python3
"""
Detecta si el GTFS del Cabildo ha cambiado desde la última construcción.

Compara `last_modified` y `size` del recurso en el CKAN con un estado guardado
(`data/source_state.json`). Pensado para CI:
  - imprime "CHANGED" y sale con código 0 si hay que reconstruir,
  - imprime "UNCHANGED" y sale con código 0 si no,
  - usa código 2 ante errores de red/API.

Uso en CI (GitHub Actions):
    python tools/check_source_update.py && ...   # decide con la salida estándar
"""
import json
import sys
import urllib.request
from pathlib import Path

RESOURCE_ID = "9f291323-8b78-453a-9008-4f0e3bfb3ce3"
CKAN = "https://datos.tenerife.es/ckan/api/3/action/resource_show?id=" + RESOURCE_ID
STATE = Path(__file__).resolve().parent.parent / "data" / "source_state.json"


def fetch():
    with urllib.request.urlopen(CKAN, timeout=30) as r:
        res = json.load(r).get("result", {})
    return {"last_modified": res.get("last_modified"), "size": res.get("size")}


def main():
    try:
        current = fetch()
    except Exception as e:
        print(f"ERROR consultando CKAN: {e}", file=sys.stderr)
        return 2

    previous = {}
    if STATE.exists():
        previous = json.loads(STATE.read_text(encoding="utf-8"))

    changed = (current["last_modified"] != previous.get("last_modified")
               or current["size"] != previous.get("size"))

    if changed:
        STATE.parent.mkdir(parents=True, exist_ok=True)
        STATE.write_text(json.dumps(current, indent=2), encoding="utf-8")
        print("CHANGED")
    else:
        print("UNCHANGED")
    # Exponer para GitHub Actions
    print(f"changed={'true' if changed else 'false'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
