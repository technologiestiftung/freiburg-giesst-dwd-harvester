# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Freiburg-Kopie von `giessdenkiez-de-dwd-harvester` (Upstream-Remote `upstream`). Workspace-Regeln (Branches, PRs, Secrets): `../../CLAUDE.md`.

## Was der Harvester tut

Ein Docker-Job (`harvester/run_harvest.sh`) startet nacheinander zwei unabhängige Python-Skripte; scheitert eins, läuft das andere trotzdem, der Job endet aber mit Exit 1:

1. `src/run_daily_weather.py` – holt stündliche Wetterdaten von der BrightSky-API (kein Key) für `WEATHER_HARVEST_LAT/LNG`, aggregiert pro Tag in `daily_weather_data` (ca. 3 Jahre rückwirkend; Tage mit `day_finished = false` werden beim nächsten Lauf neu geholt).
2. `src/run_harvester.py` – Regen-Pipeline:
   - `radolan_db_utils.get_start_end_harvest_dates` liest Stand aus `radolan_harvester`
   - `dwd_harvest.harvest_dwd`: RADOLAN-Tagesarchive vom DWD laden → in Stundendateien entpacken → je Stunde `gdalwarp` (Zuschnitt auf `SURROUNDING_SHAPE_FILE`) + `gdal_polygonize.py` → Werte über `radolan_temp` per Zentroid-Join in `radolan_data` → alte Einträge löschen (`LIMIT_DAYS`) → `build_radolan_grid` aus `radolan_geometry`
   - `update_trees_in_database`: setzt `trees.radolan_days`/`radolan_sum` per `ST_CoveredBy` je Gitterzelle (2. Pass mit Buffer für Bäume am Rand). Deaktiviert dafür Trigger und refresht danach Materialized Views – Namen sind hart codiert und müssen zum Schema im postgres-api-Repo passen.
   - ohne `SKIP_MAPBOX=True`: `mapbox_tree_update` baut `trees.csv` aus der DB, lädt sie in den Supabase-Bucket, erzeugt mit `tippecanoe` ein Tileset und lädt es zu Mapbox; danach `trees_watered.included_in_map_layer` setzen.

Einmalige Vorbereitung (`harvester/prepare/`):
- `create-buffer.py`: erzeugt `buffer.shp` (2 km Buffer, EPSG:3857) neben `SURROUNDING_SHAPE_FILE`. Läuft auch im Dockerfile beim Build (Build-Arg `SURROUNDING_SHAPE_FILE`).
- `create-grid.py`: füllt `radolan_geometry` aus `assets/grid-germany.asc` + `buffer.shp`. Ohne diese Tabelle findet der Harvester keine Zellen.

Freiburg-Gebiet: `harvester/assets/freiburg.shp`. Die Berlin-Shapefiles bleiben für Upstream-Kompatibilität liegen.

## Entwicklung

DB/Supabase kommt aus dem Nachbar-Repo `freiburg-giesst-postgres-api` (`supabase start`, DB-Port 54322, API 54321). Ein eigenes Schema gibt es hier nicht.

Lokal (braucht systemweit GDAL-CLI, z. B. `brew install gdal`, und `tippecanoe` für den Mapbox-Schritt):
```bash
cd harvester
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-mac.txt   # Linux: requirements.txt
cp sample.env .env                     # Werte anpassen, SKIP_MAPBOX=True zum Testen
cd prepare && SHAPE_RESTORE_SHX=YES SURROUNDING_SHAPE_FILE=../assets/freiburg.shp python create-buffer.py && python create-grid.py
cd ../src && python run_daily_weather.py && python run_harvester.py
```
Die Skripte importieren Geschwister-Module direkt, also aus `harvester/src` starten.

Docker: `docker-compose up` startet nur einen Container mit `tail -f /dev/null` (Mapbox aus, DB über `host.docker.internal`); Skripte dann per `docker exec -it <id> /bin/sh` manuell ausführen.

## Tests & Release

- Keine Unit-Tests, kein Linter für Python. Einziger Test ist `.github/workflows/test-harvest.yml`: checkt `freiburg-giesst-postgres-api` aus (Branch je nach Ziel `main`/`staging`), startet Supabase, baut das Image und lässt den kompletten Harvest mit `SKIP_MAPBOX=True` laufen.
- Release über semantic-release (`npm ci && npx semantic-release` in CI) → Commit-Messages im Conventional-Commits-Format (`feat:`, `fix:`, `chore:` …), sie bestimmen die Version.
- Prettier-Config in `package.json` (Tabs, YAML mit Spaces).

## Fallstricke

- README ist teils noch Berlin-Stand: `docker-compose.postgres.yml` existiert nicht, und die Env-Variable heißt `SUPABASE_SERVICE_ROLE_KEY` (nicht `SUPABASE_SERVICE_ROLE`). Maßgeblich sind `harvester/sample.env` und `action.yml`.
- `action.yml` (Docker-Action, genutzt aus anderen Repos/Workflows) und `test-harvest.yml` listen die Env-Variablen separat – neue Variablen in beiden sowie in `sample.env`/`docker-compose.yml` nachtragen.
- Dockerfile basiert auf `python:3.8.1-slim-buster`; Python-Features/Abhängigkeiten danach richten.
