#!/bin/bash
WITTYPI_DIR=/home/pi/wittypi
TARGET=custom_2ms_every_hour_workhours.wpi

echo "Switching to NORMAL schedule..."

# Find the file's position in the alphabetical listing — same order wittyPi.sh uses
file_num=0
i=0
for f in "$WITTYPI_DIR/schedules/"*.wpi; do
    i=$((i+1))
    if [[ "${f##*/}" == "$TARGET" ]]; then
        file_num=$i
        break
    fi
done

if [ "$file_num" -eq 0 ]; then
    echo "Error: $TARGET not found in $WITTYPI_DIR/schedules/"
    exit 1
fi

printf "6\n%s\n13\n" "$file_num" | bash "$WITTYPI_DIR/wittyPi.sh"
