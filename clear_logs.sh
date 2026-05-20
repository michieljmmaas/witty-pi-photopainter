#!/bin/bash

echo "Clearing all log files..."

# Battery log CSV
> /home/pi/battery_log.csv
echo "  Cleared: /home/pi/battery_log.csv"

# Display script output log
> /home/pi/display_picture.log
echo "  Cleared: /home/pi/display_picture.log"

# Photo state file (tracks which images have been shown)
> /home/pi/photo_state.txt
echo "  Cleared: /home/pi/photo_state.txt"

echo "Done."