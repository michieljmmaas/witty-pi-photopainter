#!/bin/bash

echo "Restoring normal schedule..."
/home/pi/normalmode.sh

echo "Shutting down via WittyPi..."
sudo shutdown -h now
