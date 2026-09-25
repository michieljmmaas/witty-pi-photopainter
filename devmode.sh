#!/bin/bash
echo "Switching to DEV MODE — disabling WittyPi schedule..."
printf "12\n3\n13\n" | bash /home/pi/wittypi/wittyPi.sh
