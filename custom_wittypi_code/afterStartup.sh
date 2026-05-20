#!/bin/bash

LOG=/home/pi/display_picture.log

source /home/pi/wittypi/utilities.sh

reason=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_ACTION_REASON)

python3 /home/pi/display_picture.py >> $LOG 2>&1

if [ "$reason" == "$REASON_ALARM1" ] || [ "$reason" == "$REASON_ALARM1_DELAYED" ]; then
    echo "$(date): Scheduled wakeup, shutting down via WittyPi." >> $LOG
    sudo shutdown -h now

else
    echo "$(date): Manual wakeup, waiting for SSH login (2 min)..." >> $LOG
    for i in $(seq 1 24); do
        sleep 5
        if who | grep -q "pts/"; then
            echo "$(date): SSH session detected, staying alive." >> $LOG
            exit 0
        fi
    done
    echo "$(date): No SSH session, shutting down via WittyPi." >> $LOG
    sudo shutdown -h now
fi
