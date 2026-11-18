#!/bin/sh
set -e

python /app/src/run_daily_weather.py || {
    echo "run_daily_weather.py failed"
    FAILED=1
}

# create-grid.py uses paths relative to prepare/ and is a no-op once radolan_geometry is filled
(cd /app/prepare && python create-grid.py) && python /app/src/run_harvester.py || {
    echo "create-grid.py or run_harvester.py failed"
    FAILED=1
}

if [ "$FAILED" = "1" ]; then
    exit 1
fi
