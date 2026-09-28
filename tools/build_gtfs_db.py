#!/usr/bin/env python3
"""
Convierte el GTFS oficial de TITSA (Cabildo de Tenerife, CC-BY) en una base de
datos SQLite compacta y lista para la app.

Estrategia de tamano: en lugar de guardar los 1,4 M de stop_times crudos,
agrupa las expediciones por PATRON (secuencia de paradas + offsets de tiempo).
Muchas expediciones comparten patron y solo cambia la hora de salida, asi que
guardamos cada patron una vez y por cada expedicion solo (patron, hora_salida,
service_id). Esto reduce el fichero de decenas de MB a unos pocos.

Salida: data/guaguas.sqlite

Uso:
    python build_gtfs_db.py            # descarga el GTFS y construye la BD
    python build_gtfs_db.py --zip X    # usa un zip local ya descargado
    python build_gtfs_db.py --src DIR  # usa una carpeta con los .txt ya extraidos
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import io
import json
import os
import sqlite3
import sys
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path

CKAN_RESOURCE_ID = "9f291323-8b78-453a-9008-4f0e3bfb3ce3"
CKAN_RESOURCE_SHOW = (
    "https://datos.tenerife.es/ckan/api/3/action/resource_show?id=" + CKAN_RESOURCE_ID
)

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
DEFAULT_GTFS_URL = (
    "https://datos.tenerife.es/ckan/dataset/36c2e26f-0d18-4b5a-b214-1636168e0765/"
    "resource/9f291323-8b78-453a-9008-4f0e3bfb3ce3/download/fichero-zip-de-google-transit.zip"
)


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def read_csv(source, name):
    """Devuelve un iterador de dicts para el fichero `name` del GTFS."""
    if isinstance(source, zipfile.ZipFile):
        raw = source.read(name)
        text = io.TextIOWrapper(io.BytesIO(raw), encoding="utf-8-sig")
    else:
        text = open(Path(source) / name, encoding="utf-8-sig")
    with text:
        yield from csv.DictReader(text)


def time_to_seconds(hms: str) -> int:
    """'25:30:00' -> segundos desde medianoche (GTFS admite >24h)."""
    h, m, s = hms.split(":")
    return int(h) * 3600 + int(m) * 60 + int(s)


def simplify(points, tol_deg=0.00008):
    """Douglas-Peucker sobre [(lat,lon,dist), ...]. tol ~9 m. Iterativo."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        i0, i1 = stack.pop()
        ax, ay = points[i0][1], points[i0][0]
        bx, by = points[i1][1], points[i1][0]
        dx, dy = bx - ax, by - ay
        norm = (dx * dx + dy * dy) ** 0.5 or 1e-12
        dmax, idx = 0.0, -1
        for i in range(i0 + 1, i1):
            px, py = points[i][1], points[i][0]
            # distancia perpendicular punto-recta (en grados, suficiente aqui)
            d = abs((px - ax) * dy - (py - ay) * dx) / norm
            if d > dmax:
                dmax, idx = d, i
        if dmax > tol_deg and idx != -1:
            keep[idx] = True
            stack.append((i0, idx))
            stack.append((idx, i1))
    return [p for p, k in zip(points, keep) if k]


def build(source, db_path: Path):
    if db_path.exists():
        db_path.unlink()
    db = sqlite3.connect(db_path)
    db.executescript(
        """
        PRAGMA journal_mode=OFF;
        PRAGMA synchronous=OFF;

        CREATE TABLE stops (
            stop_id   INTEGER PRIMARY KEY,
            name      TEXT NOT NULL,
            lat       REAL NOT NULL,
            lon       REAL NOT NULL
        );

        CREATE TABLE routes (
            route_id     INTEGER PRIMARY KEY,
            short_name   TEXT,
            long_name    TEXT,
            color        TEXT,
            text_color   TEXT
        );

        -- Un patron = una secuencia concreta de paradas de una linea/sentido.
        CREATE TABLE patterns (
            pattern_id   INTEGER PRIMARY KEY,
            route_id     INTEGER NOT NULL,
            headsign     TEXT,
            shape_id     TEXT,
            n_stops      INTEGER NOT NULL
        );

        -- Paradas ordenadas de cada patron, con el offset de tiempo (seg) desde
        -- la salida y la distancia recorrida (m) para la alarma de bajada.
        CREATE TABLE pattern_stops (
            pattern_id   INTEGER NOT NULL,
            seq          INTEGER NOT NULL,
            stop_id      INTEGER NOT NULL,
            time_offset  INTEGER NOT NULL,
            dist_m       REAL,
            PRIMARY KEY (pattern_id, seq)
        );

        -- Expediciones: solo hora de salida + calendario, referidas a un patron.
        CREATE TABLE trips (
            trip_id      INTEGER PRIMARY KEY,
            pattern_id   INTEGER NOT NULL,
            service_id   INTEGER NOT NULL,
            start_time   INTEGER NOT NULL   -- seg desde medianoche
        );

        -- Dias concretos en que opera cada service_id (GTFS calendar_dates).
        CREATE TABLE service_dates (
            service_id   INTEGER NOT NULL,
            date         INTEGER NOT NULL,  -- AAAAMMDD
            PRIMARY KEY (service_id, date)
        );

        -- Trazados para dibujar en el mapa.
        CREATE TABLE shape_points (
            shape_id     TEXT NOT NULL,
            seq          INTEGER NOT NULL,
            lat          REAL NOT NULL,
            lon          REAL NOT NULL,
            dist_m       REAL,
            PRIMARY KEY (shape_id, seq)
        );
        """
    )

    # --- stops ---
    rows = []
    for r in read_csv(source, "stops.txt"):
        try:
            rows.append((int(r["stop_id"]), r["stop_name"].strip(),
                         float(r["stop_lat"]), float(r["stop_lon"])))
        except (ValueError, KeyError):
            continue
    db.executemany("INSERT OR REPLACE INTO stops VALUES (?,?,?,?)", rows)
    log(f"stops: {len(rows)}")

    # --- routes ---
    rows = []
    for r in read_csv(source, "routes.txt"):
        rows.append((int(r["route_id"]), r.get("route_short_name", ""),
                     r.get("route_long_name", ""),
                     (r.get("route_color") or "").strip(),
                     (r.get("route_text_color") or "").strip()))
    db.executemany("INSERT OR REPLACE INTO routes VALUES (?,?,?,?,?)", rows)
    log(f"routes: {len(rows)}")

    # --- shapes (agrupadas por shape_id y simplificadas) ---
    shapes: dict[str, list] = {}
    raw = 0
    for r in read_csv(source, "shapes.txt"):
        shapes.setdefault(r["shape_id"], []).append(
            (int(r["shape_pt_sequence"]), float(r["shape_pt_lat"]),
             float(r["shape_pt_lon"]), float(r.get("shape_dist_traveled") or 0)))
        raw += 1
    n = 0
    for shape_id, pts in shapes.items():
        pts.sort()
        simp = simplify([(lat, lon, dist) for _seq, lat, lon, dist in pts])
        rows = [(shape_id, i, lat, lon, dist) for i, (lat, lon, dist) in enumerate(simp)]
        db.executemany("INSERT OR REPLACE INTO shape_points VALUES (?,?,?,?,?)", rows)
        n += len(rows)
    log(f"shape_points: {n} (de {raw} crudos, {len(shapes)} trazados)")

    # --- service_dates ---
    rows = []
    for r in read_csv(source, "calendar_dates.txt"):
        if r.get("exception_type") == "1":  # 1 = servicio anadido (TITSA solo usa este)
            rows.append((int(r["service_id"]), int(r["date"])))
    db.executemany("INSERT OR REPLACE INTO service_dates VALUES (?,?)", rows)
    log(f"service_dates: {len(rows)}")

    # --- trips + stop_times -> patterns ---
    # 1) info de cada trip
    trip_info = {}
    for r in read_csv(source, "trips.txt"):
        trip_info[r["trip_id"]] = {
            "route_id": int(r["route_id"]),
            "service_id": int(r["service_id"]),
            "headsign": (r.get("trip_headsign") or "").strip(),
            "shape_id": (r.get("shape_id") or "").strip(),
            "stops": [],  # (seq, stop_id, arrival_sec)
        }
    log(f"trips leidos: {len(trip_info)}")

    # 2) volcar stop_times en cada trip (ordenados luego)
    st_count = 0
    for r in read_csv(source, "stop_times.txt"):
        t = trip_info.get(r["trip_id"])
        if t is None:
            continue
        t["stops"].append((int(r["stop_sequence"]),
                           int(r["stop_id"]),
                           time_to_seconds(r["arrival_time"])))
        st_count += 1
    log(f"stop_times: {st_count}")

    # 3) construir patrones unicos
    pattern_key_to_id: dict[tuple, int] = {}
    next_pattern = 1
    trips_rows = []
    pattern_rows = []
    pattern_stops_rows = []

    for trip_id, t in trip_info.items():
        seq = sorted(t["stops"])
        if not seq:
            continue
        start = seq[0][2]
        stop_ids = tuple(s[1] for s in seq)
        offsets = tuple(s[2] - start for s in seq)
        key = (t["route_id"], t["headsign"], stop_ids, offsets)
        pid = pattern_key_to_id.get(key)
        if pid is None:
            pid = next_pattern; next_pattern += 1
            pattern_key_to_id[key] = pid
            pattern_rows.append((pid, t["route_id"], t["headsign"],
                                 t["shape_id"], len(stop_ids)))
            for i, (sid, off) in enumerate(zip(stop_ids, offsets)):
                pattern_stops_rows.append((pid, i, sid, off, None))
        trips_rows.append((int(trip_id), pid, t["service_id"], start))

    db.executemany("INSERT INTO patterns VALUES (?,?,?,?,?)", pattern_rows)
    db.executemany("INSERT INTO pattern_stops VALUES (?,?,?,?,?)", pattern_stops_rows)
    db.executemany("INSERT INTO trips VALUES (?,?,?,?)", trips_rows)
    log(f"patterns: {len(pattern_rows)}  (de {len(trips_rows)} expediciones)")

    # indices utiles para la app
    db.executescript(
        """
        CREATE INDEX idx_trips_pattern ON trips(pattern_id);
        CREATE INDEX idx_trips_service ON trips(service_id);
        CREATE INDEX idx_ps_stop       ON pattern_stops(stop_id);
        CREATE INDEX idx_patterns_route ON patterns(route_id);
        CREATE INDEX idx_stops_latlon  ON stops(lat, lon);
        """
    )
    db.commit()
    db.execute("VACUUM")
    db.commit()
    db.close()
    size = db_path.stat().st_size / 1_000_000
    log(f"OK -> {db_path}  ({size:.1f} MB)")


def _ckan_source_last_modified():
    """last_modified/size del recurso en el CKAN del Cabildo (best-effort)."""
    try:
        with urllib.request.urlopen(CKAN_RESOURCE_SHOW, timeout=25) as r:
            res = json.load(r).get("result", {})
            return res.get("last_modified"), res.get("size")
    except Exception as e:
        log(f"aviso: no se pudo consultar CKAN ({e})")
        return None, None


def write_manifest(db_path: Path, out: Path, hosting_base: str):
    """Genera manifest.json a partir de la BD construida."""
    db = sqlite3.connect(db_path)
    row = db.execute(
        "SELECT MIN(date), MAX(date) FROM service_dates").fetchone()
    db.close()
    valid_from, valid_to = row[0], row[1]

    sha = hashlib.sha256(db_path.read_bytes()).hexdigest()
    size = db_path.stat().st_size
    src_last_mod, _src_size = _ckan_source_last_modified()

    # La "version" es la fecha del dato de origen (o de construcción si no hay).
    version = (src_last_mod or datetime.now(timezone.utc).isoformat())[:10]
    fname = f"guaguas-{version}.sqlite"

    manifest = {
        "version": version,
        "built_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source_last_modified": src_last_mod,
        "valid_from": str(valid_from) if valid_from is not None else None,
        "valid_to": str(valid_to) if valid_to is not None else None,
        "sqlite_url": hosting_base.rstrip("/") + "/" + fname,
        "sqlite_sha256": sha,
        "sqlite_size": size,
        "min_app_version": "0.1.0",
    }
    out.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    log(f"manifest -> {out}  (version {version}, valida {valid_from}..{valid_to})")
    return manifest


def get_source(args):
    if args.src:
        return args.src
    zip_path = Path(args.zip) if args.zip else DATA / "gtfs.zip"
    if not zip_path.exists():
        DATA.mkdir(parents=True, exist_ok=True)
        log(f"Descargando GTFS -> {zip_path} ...")
        urllib.request.urlretrieve(args.url, zip_path)
    return zipfile.ZipFile(zip_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zip", help="ruta a un gtfs.zip local")
    ap.add_argument("--src", help="carpeta con los .txt del GTFS ya extraidos")
    ap.add_argument("--url", default=os.environ.get("GTFS_URL", DEFAULT_GTFS_URL))
    ap.add_argument("--out", default=str(DATA / "guaguas.sqlite"))
    ap.add_argument("--manifest", default=str(DATA / "manifest.json"),
                    help="ruta de salida del manifest.json")
    ap.add_argument("--hosting-base",
                    default=os.environ.get("HOSTING_BASE", "https://REEMPLAZAR.example/gtfs"),
                    help="URL base donde se alojará el .sqlite publicado")
    args = ap.parse_args()

    DATA.mkdir(parents=True, exist_ok=True)
    source = get_source(args)
    out = Path(args.out)
    build(source, out)
    write_manifest(out, Path(args.manifest), args.hosting_base)


if __name__ == "__main__":
    main()
