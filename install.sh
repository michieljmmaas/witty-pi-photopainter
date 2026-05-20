[ -z $BASH ] && { exec bash "$0" "$@" || exit; }
#!/bin/bash
# file: install.sh
#
# Sets up the Witty Pi PhotoPainter from scratch on a fresh Raspberry Pi OS.
# Run with sudo from the repo directory (your home folder):
#
#   sudo apt install git -y
#   git clone <repo-url> ~
#   sudo ~/install.sh
#

# check if sudo is used
if [ "$(id -u)" != 0 ]; then
  echo 'Sorry, you need to run this script with sudo'
  exit 1
fi

# directories
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WITTYPI_DIR="$SCRIPT_DIR/wittypi"
USER_HOME="/home/$SUDO_USER"

# error counter
ERR=0

# boot config file location
if [ "$(lsb_release -si)" == "Ubuntu" ]; then
  BOOT_CONFIG_FILE="/boot/firmware/usercfg.txt"
else
  if [ -e /boot/firmware/config.txt ] ; then
    BOOT_CONFIG_FILE="/boot/firmware/config.txt"
  else
    BOOT_CONFIG_FILE="/boot/config.txt"
  fi
fi

echo '================================================================================'
echo '|                                                                              |'
echo '|                   Witty Pi PhotoPainter — Installation                       |'
echo '|                                                                              |'
echo '================================================================================'

# ── Enable I2C ────────────────────────────────────────────────────────────────
echo '>>> Enable I2C'
if grep -q 'i2c-bcm2708' /etc/modules; then
  echo 'Seems i2c-bcm2708 module already exists, skip this step.'
else
  echo 'i2c-bcm2708' >> /etc/modules
fi
if grep -q 'i2c-dev' /etc/modules; then
  echo 'Seems i2c-dev module already exists, skip this step.'
else
  echo 'i2c-dev' >> /etc/modules
fi

i2c1=$(grep 'dtparam=i2c1=on' ${BOOT_CONFIG_FILE})
i2c1=$(echo -e "$i2c1" | sed -e 's/^[[:space:]]*//')
if [[ -z "$i2c1" || "$i2c1" == "#"* ]]; then
  echo 'dtparam=i2c1=on' >> ${BOOT_CONFIG_FILE}
else
  echo 'Seems i2c1 parameter already set, skip this step.'
fi

i2c_arm=$(grep 'dtparam=i2c_arm=on' ${BOOT_CONFIG_FILE})
i2c_arm=$(echo -e "$i2c_arm" | sed -e 's/^[[:space:]]*//')
if [[ -z "$i2c_arm" || "$i2c_arm" == "#"* ]]; then
  echo 'dtparam=i2c_arm=on' >> ${BOOT_CONFIG_FILE}
else
  echo 'Seems i2c_arm parameter already set, skip this step.'
fi

miniuart=$(grep 'dtoverlay=miniuart-bt' ${BOOT_CONFIG_FILE})
miniuart=$(echo -e "$miniuart" | sed -e 's/^[[:space:]]*//')
if [[ -z "$miniuart" || "$miniuart" == "#"* ]]; then
  echo 'dtoverlay=miniuart-bt' >> ${BOOT_CONFIG_FILE}
else
  echo 'Seems setting Bluetooth to use mini-UART is done already, skip this step.'
fi

if [ -f /etc/modprobe.d/raspi-blacklist.conf ]; then
  sed -i 's/^blacklist spi-bcm2708/#blacklist spi-bcm2708/' /etc/modprobe.d/raspi-blacklist.conf
  sed -i 's/^blacklist i2c-bcm2708/#blacklist i2c-bcm2708/' /etc/modprobe.d/raspi-blacklist.conf
else
  echo 'File raspi-blacklist.conf does not exist, skip this step.'
fi

# ── Enable SPI (needed for the e-ink display) ─────────────────────────────────
echo '>>> Enable SPI'
spi=$(grep 'dtparam=spi=on' ${BOOT_CONFIG_FILE})
spi=$(echo -e "$spi" | sed -e 's/^[[:space:]]*//')
if [[ -z "$spi" || "$spi" == "#"* ]]; then
  echo 'dtparam=spi=on' >> ${BOOT_CONFIG_FILE}
else
  echo 'Seems SPI parameter already set, skip this step.'
fi

# ── System packages ───────────────────────────────────────────────────────────
echo '>>> Install system packages'
apt-get update -q
apt install -y \
  i2c-tools \
  python3-pip \
  python3-smbus \
  python3-rpi.gpio \
  python3-spidev \
  || ((ERR++))

# ── Python packages ───────────────────────────────────────────────────────────
echo '>>> Install Python packages'
os=$(lsb_release -r | grep 'Release:' | sed 's/Release:\s*//')
if [ "$os" -ge 12 ]; then
  pip3 install pillow pillow-heif rich --break-system-packages || ((ERR++))
else
  pip3 install pillow pillow-heif rich || ((ERR++))
fi

# ── Locale ────────────────────────────────────────────────────────────────────
echo '>>> Make sure en_GB.UTF-8 locale is installed'
locale_commentout=$(sed -n 's/\(#\).*en_GB.UTF-8 UTF-8/1/p' /etc/locale.gen)
if [[ $locale_commentout -ne 1 ]]; then
  echo 'Seems en_GB.UTF-8 locale has been installed, skip this step.'
else
  sed -i.bak 's/^.*\(en_GB.UTF-8[[:blank:]]\+UTF-8\)/\1/' /etc/locale.gen
  locale-gen
fi

# ── WiringPi ──────────────────────────────────────────────────────────────────
if hash gpio 2>/dev/null; then
  echo 'Seems wiringPi has been installed, skip this step.'
else
  os=$(lsb_release -r | grep 'Release:' | sed 's/Release:\s*//')
  if [ $os -le 10 ]; then
    apt install -y wiringpi || ((ERR++))
  elif [ $os -eq 11 ]; then
    wget https://github.com/WiringPi/WiringPi/releases/download/3.2/wiringpi_3.2-bullseye_armhf.deb -O wiringpi.deb || ((ERR++))
    apt install -y ./wiringpi.deb || ((ERR++))
    rm wiringpi.deb
  else
    arch=$(dpkg --print-architecture)
    if [ "$arch" == "arm64" ]; then
      wget https://github.com/WiringPi/WiringPi/releases/download/3.2/wiringpi_3.2_arm64.deb -O wiringpi.deb || ((ERR++))
    else
      wget https://github.com/WiringPi/WiringPi/releases/download/3.2/wiringpi_3.2_armhf.deb -O wiringpi.deb || ((ERR++))
    fi
    apt install -y ./wiringpi.deb || ((ERR++))
    rm wiringpi.deb
  fi
fi

# ── WittyPi 4 ─────────────────────────────────────────────────────────────────
if [ $ERR -eq 0 ]; then
  echo '>>> Install WittyPi 4'
  if [ -d "$WITTYPI_DIR" ]; then
    echo 'Seems wittypi is installed already, skip this step.'
  else
    wget https://www.uugear.com/repo/WittyPi4/LATEST -O wittyPi.zip || ((ERR++))
    unzip wittyPi.zip -d wittypi || ((ERR++))
    cd wittypi
    chmod +x wittyPi.sh daemon.sh runScript.sh beforeScript.sh afterStartup.sh beforeShutdown.sh
    sed -e "s#/home/pi/wittypi#$WITTYPI_DIR#g" init.sh >/etc/init.d/wittypi
    chmod +x /etc/init.d/wittypi
    update-rc.d wittypi defaults || ((ERR++))
    touch wittyPi.log schedule.log
    cd ..
    chown -R $SUDO_USER:$(id -g -n $SUDO_USER) wittypi || ((ERR++))
    sleep 2
    rm wittyPi.zip
  fi

  # ── Custom startup hook ──────────────────────────────────────────────────────
  echo '>>> Install custom startup hook (afterStartup.sh)'
  cp "$SCRIPT_DIR/custom_wittypi_code/afterStartup.sh" "$WITTYPI_DIR/afterStartup.sh"
  chmod +x "$WITTYPI_DIR/afterStartup.sh"

  # ── Custom schedules ─────────────────────────────────────────────────────────
  echo '>>> Install custom schedules'
  mkdir -p "$WITTYPI_DIR/schedules"
  cp "$SCRIPT_DIR/custom_wittypi_code/schedules/"*.wpi "$WITTYPI_DIR/schedules/"

  # Set default schedule: 2 min ON every hour during work hours (9am-5pm)
  cp "$WITTYPI_DIR/schedules/custom_2ms_every_waking_hour.wpi" "$WITTYPI_DIR/schedule.wpi"
  echo '    Default schedule: 2 min ON / 58 min OFF (every waking hour)'

  # ── Low voltage protection ───────────────────────────────────────────────────
  echo '>>> Set low voltage protection to 3.4V'
  printf "7\n3.4\n13\n" | bash "$WITTYPI_DIR/wittyPi.sh"
fi

# ── Waveshare 7.3" e-ink driver ───────────────────────────────────────────────
echo '>>> Install Waveshare 7.3" e-ink driver'
WAVESHARE_LIB="$USER_HOME/RPi_Zero_PhotoPainter/7in3_e-Paper_E/python/lib"
if [ -f "$WAVESHARE_LIB/waveshare_epd/epd7in3e.py" ]; then
  echo 'Seems Waveshare driver already installed, skip this step.'
else
  mkdir -p "$WAVESHARE_LIB"
  wget https://github.com/waveshare/e-Paper/archive/refs/heads/master.zip \
    -O /tmp/waveshare.zip || ((ERR++))
  unzip /tmp/waveshare.zip -d /tmp/waveshare_src || ((ERR++))
  cp -r /tmp/waveshare_src/e-Paper-master/RaspberryPi_JetsonNano/python/lib/waveshare_epd \
    "$WAVESHARE_LIB/" || ((ERR++))
  rm -rf /tmp/waveshare.zip /tmp/waveshare_src
  chown -R $SUDO_USER:$(id -g -n $SUDO_USER) "$USER_HOME/RPi_Zero_PhotoPainter" || ((ERR++))
fi

# ── Photo folders ─────────────────────────────────────────────────────────────
echo '>>> Create photo folders'
mkdir -p "$USER_HOME/my_photos"
mkdir -p "$USER_HOME/photos_input"
chown $SUDO_USER:$(id -g -n $SUDO_USER) "$USER_HOME/my_photos" "$USER_HOME/photos_input"

# ── Configure .bashrc for SSH dev mode ────────────────────────────────────────
echo '>>> Configure SSH dev mode in .bashrc'
BASHRC="$USER_HOME/.bashrc"
if grep -q 'devmode.sh' "$BASHRC" 2>/dev/null; then
  echo 'SSH dev mode already configured, skip this step.'
else
  cat >> "$BASHRC" << 'EOF'

# Auto-enable dev mode when SSH-ing in (keeps Pi awake for debugging)
if [ -n "$SSH_CONNECTION" ]; then
    sudo /home/pi/devmode.sh
fi
EOF
  chown $SUDO_USER:$(id -g -n $SUDO_USER) "$BASHRC"
fi

# ── UUGear Web Interface (optional) ───────────────────────────────────────────
echo '>>> Install UUGear Web Interface'
curl https://www.uugear.com/repo/UWI/installUWI.sh | bash

echo
if [ $ERR -eq 0 ]; then
  echo '>>> All done!'
  echo '>>>'
  echo '>>> Next steps:'
  echo '>>>   1. Reboot: sudo reboot'
  echo '>>>   2. Drop photos into ~/photos_input/ and run: python3 ~/convert_pictures.py'
  echo '>>>   3. SSH in again — the Pi will switch to dev mode automatically.'
  echo '>>>   4. Run: python3 ~/display_picture.py  (to test)'
  echo '>>>   5. Run: ~/goodnight.sh  (to apply normal schedule and shut down)'
else
  echo '>>> Something went wrong. Please check the messages above :-('
fi
