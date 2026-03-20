#!/bin/sh
set -eu

if ! command -v rauc >/dev/null 2>&1; then
    exit 0
fi

logger -t tempercrate-rauc-mark-good "Starting mark-good"

if rauc status mark-good; then
    logger -t tempercrate-rauc-mark-good "Current slot marked good successfully"
else
    logger -t tempercrate-rauc-mark-good "mark-good failed"
fi

exit 0