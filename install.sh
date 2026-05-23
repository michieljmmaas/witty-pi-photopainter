[ -z $BASH ] && { exec bash "$0" "$@" || exit; }

if [ "$(id -u)" != 0 ]; then
  echo 'Sorry, you need to run this script with sudo'
  exit 1
fi

if [ -z "$SUDO_USER" ] || ! id "$SUDO_USER" &>/dev/null; then
  echo 'Could not determine the target user.'
  echo 'Make sure you run this with sudo, e.g.:  sudo bash install.sh'
  exit 1
fi

# ── External URLs — update here if any go stale ────────────────────────────────
URL_WITTYPI="https://www.uugear.com/repo/WittyPi4/LATEST"
URL_UWI="https://www.uugear.com/repo/UWI/installUWI.sh"
URL_WAVESHARE="https://github.com/waveshare/e-Paper/archive/refs/heads/master.zip"
URL_WIRINGPI_BULLSEYE="https://github.com/WiringPi/WiringPi/releases/download/3.2/wiringpi_3.2-bullseye_armhf.deb"
URL_WIRINGPI_ARM64="https://github.com/WiringPi/WiringPi/releases/download/3.2/wiringpi_3.2_arm64.deb"
URL_WIRINGPI_ARMHF="https://github.com/WiringPi/WiringPi/releases/download/3.2/wiringpi_3.2_armhf.deb"

# ── Formatting helpers ─────────────────────────────────────────────────────────
BOLD='\033[1m'; DIM='\033[2m'
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; RESET='\033[0m'

TOTAL_STEPS=14
CURRENT_STEP=0
LOG_FILE="/tmp/wittypi_install.log"
ERR=0
> "$LOG_FILE"

step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  printf "\n${BOLD}${CYAN}  [%d/%d]${RESET}  ${BOLD}%s${RESET}\n" \
    "$CURRENT_STEP" "$TOTAL_STEPS" "$1"
}

ok()   { printf "         ${GREEN}✓${RESET}  %s\n" "$1"; }
skip() { printf "         ${DIM}–  %s (skipped)${RESET}\n" "$1"; }

# Run a command silently with a spinner; log all output; report pass/fail.
run_quiet() {
  local label="$1"; shift
  printf "         ·  %s" "$label"
  "$@" >>"$LOG_FILE" 2>&1 &
  local pid=$! i=0 sp='|/-\'
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r         %s  %s  " "${sp:$((i++ % 4)):1}" "$label"
    sleep 0.15
  done
  wait "$pid"; local rc=$?
  if [ $rc -eq 0 ]; then
    printf "\r         ${GREEN}✓${RESET}  %s\033[K\n" "$label"
  else
    printf "\r         ${RED}✗${RESET}  %s  ${DIM}(see %s)${RESET}\033[K\n" "$label" "$LOG_FILE"
    ERR=$((ERR+1))
  fi
  return $rc
}

# Download a file quietly with a spinner.
download() {
  local label="$1" url="$2" dest="$3"
  printf "         ·  %s" "$label"
  wget -q "$url" -O "$dest" >>"$LOG_FILE" 2>&1 &
  local pid=$! i=0 sp='|/-\'
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r         %s  %s  " "${sp:$((i++ % 4)):1}" "$label"
    sleep 0.15
  done
  wait "$pid"; local rc=$?
  if [ $rc -eq 0 ]; then
    printf "\r         ${GREEN}✓${RESET}  %s\033[K\n" "$label"
  else
    printf "\r         ${RED}✗${RESET}  %s  ${DIM}(see %s)${RESET}\033[K\n" "$label" "$LOG_FILE"
    ERR=$((ERR+1))
  fi
  return $rc
}

# ── Config ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WITTYPI_DIR="$SCRIPT_DIR/wittypi"
USER_HOME="/home/$SUDO_USER"

if [ "$(lsb_release -si)" == "Ubuntu" ]; then
  BOOT_CONFIG_FILE="/boot/firmware/usercfg.txt"
elif [ -e /boot/firmware/config.txt ]; then
  BOOT_CONFIG_FILE="/boot/firmware/config.txt"
else
  BOOT_CONFIG_FILE="/boot/config.txt"
fi

# ── Header ─────────────────────────────────────────────────────────────────────
printf "\n${BOLD}"
printf "  ╔════════════════════════════════════════════╗\n"
printf "  ║   Witty Pi PhotoPainter — Installation     ║\n"
printf "  ╚════════════════════════════════════════════╝\n"
printf "${RESET}  Log: ${DIM}%s${RESET}\n" "$LOG_FILE"

# ── [1/14] Enable I2C ──────────────────────────────────────────────────────────
step "Enable I2C"

grep -q 'i2c-bcm2708' /etc/modules \
  && skip "i2c-bcm2708 module" \
  || { echo 'i2c-bcm2708' >> /etc/modules && ok "Added i2c-bcm2708 module"; }

grep -q 'i2c-dev' /etc/modules \
  && skip "i2c-dev module" \
  || { echo 'i2c-dev' >> /etc/modules && ok "Added i2c-dev module"; }

i2c1=$(grep 'dtparam=i2c1=on' "$BOOT_CONFIG_FILE" | sed -e 's/^[[:space:]]*//')
if [[ -z "$i2c1" || "$i2c1" == "#"* ]]; then
  echo 'dtparam=i2c1=on' >> "$BOOT_CONFIG_FILE" && ok "Enabled dtparam=i2c1"
else skip "dtparam=i2c1"; fi

i2c_arm=$(grep 'dtparam=i2c_arm=on' "$BOOT_CONFIG_FILE" | sed -e 's/^[[:space:]]*//')
if [[ -z "$i2c_arm" || "$i2c_arm" == "#"* ]]; then
  echo 'dtparam=i2c_arm=on' >> "$BOOT_CONFIG_FILE" && ok "Enabled dtparam=i2c_arm"
else skip "dtparam=i2c_arm"; fi

miniuart=$(grep 'dtoverlay=miniuart-bt' "$BOOT_CONFIG_FILE" | sed -e 's/^[[:space:]]*//')
if [[ -z "$miniuart" || "$miniuart" == "#"* ]]; then
  echo 'dtoverlay=miniuart-bt' >> "$BOOT_CONFIG_FILE" && ok "Set Bluetooth to mini-UART"
else skip "miniuart-bt overlay"; fi

if [ -f /etc/modprobe.d/raspi-blacklist.conf ]; then
  sed -i 's/^blacklist spi-bcm2708/#blacklist spi-bcm2708/' /etc/modprobe.d/raspi-blacklist.conf
  sed -i 's/^blacklist i2c-bcm2708/#blacklist i2c-bcm2708/' /etc/modprobe.d/raspi-blacklist.conf
  ok "Updated raspi-blacklist.conf"
else skip "raspi-blacklist.conf (not present)"; fi

# ── [2/14] Enable SPI ──────────────────────────────────────────────────────────
step "Enable SPI"
spi=$(grep 'dtparam=spi=on' "$BOOT_CONFIG_FILE" | sed -e 's/^[[:space:]]*//')
if [[ -z "$spi" || "$spi" == "#"* ]]; then
  echo 'dtparam=spi=on' >> "$BOOT_CONFIG_FILE" && ok "Enabled dtparam=spi"
else skip "dtparam=spi"; fi

# ── [3/14] System packages ─────────────────────────────────────────────────────
step "Install system packages"
run_quiet "apt-get update" apt-get update -q
run_quiet "i2c-tools  python3-pip  python3-smbus  python3-rpi.gpio  python3-spidev" \
  apt-get install -y -q \
    i2c-tools python3-pip python3-smbus python3-rpi.gpio python3-spidev

# ── [4/14] Python packages ─────────────────────────────────────────────────────
step "Install Python packages  (pillow · pillow-heif · rich)"
os=$(lsb_release -r | grep 'Release:' | sed 's/Release:\s*//')
if [ "$os" -ge 12 ]; then
  run_quiet "pip install pillow pillow-heif rich" \
    pip3 install -q pillow pillow-heif rich --break-system-packages
else
  run_quiet "pip install pillow pillow-heif rich" \
    pip3 install -q pillow pillow-heif rich
fi

# ── [5/14] Locale ──────────────────────────────────────────────────────────────
step "Configure locale  (en_GB.UTF-8)"
locale_commentout=$(sed -n 's/\(#\).*en_GB.UTF-8 UTF-8/1/p' /etc/locale.gen)
if [[ $locale_commentout -ne 1 ]]; then
  skip "en_GB.UTF-8 locale"
else
  sed -i.bak 's/^.*\(en_GB.UTF-8[[:blank:]]\+UTF-8\)/\1/' /etc/locale.gen
  run_quiet "locale-gen" locale-gen
fi

# ── [6/14] WiringPi ────────────────────────────────────────────────────────────
step "Install WiringPi"
if hash gpio 2>/dev/null; then
  skip "WiringPi (gpio already present)"
else
  os=$(lsb_release -r | grep 'Release:' | sed 's/Release:\s*//')
  if [ "$os" -le 10 ]; then
    run_quiet "apt install wiringpi" apt-get install -y -q wiringpi
  else
    if [ "$os" -eq 11 ]; then
      WIRING_URL="$URL_WIRINGPI_BULLSEYE"
    else
      arch=$(dpkg --print-architecture)
      if [ "$arch" == "arm64" ]; then
        WIRING_URL="$URL_WIRINGPI_ARM64"
      else
        WIRING_URL="$URL_WIRINGPI_ARMHF"
      fi
    fi
    download "WiringPi .deb" "$WIRING_URL" wiringpi.deb \
      && run_quiet "Install WiringPi" apt-get install -y -q ./wiringpi.deb
    rm -f wiringpi.deb
  fi
fi

# ── [7–10] WittyPi 4 setup (skipped if earlier steps failed) ──────────────────
if [ $ERR -gt 0 ]; then
  printf "\n  ${DIM}  [7–10/%d]  WittyPi setup skipped due to earlier errors${RESET}\n" \
    "$TOTAL_STEPS"
  CURRENT_STEP=10
else
  # ── [7/14] WittyPi 4 ──────────────────────────────────────────────────────
  step "Download & install WittyPi 4"
  if [ -d "$WITTYPI_DIR" ]; then
    skip "WittyPi 4 (directory already exists)"
  else
    download "WittyPi 4 package" "$URL_WITTYPI" wittyPi.zip && {
      run_quiet "Unpack WittyPi 4" unzip -q wittyPi.zip -d wittypi
      cd wittypi
      chmod +x wittyPi.sh daemon.sh runScript.sh beforeScript.sh afterStartup.sh beforeShutdown.sh
      sed -e "s#/home/pi/wittypi#$WITTYPI_DIR#g" init.sh > /etc/init.d/wittypi
      chmod +x /etc/init.d/wittypi
      run_quiet "Register init.d service" update-rc.d wittypi defaults
      touch wittyPi.log schedule.log
      cd ..
      chown -R "$SUDO_USER:$(id -g -n $SUDO_USER)" wittypi || ERR=$((ERR+1))
      sleep 2
      rm -f wittyPi.zip
    }
  fi

  # ── [8/14] Custom startup hook ────────────────────────────────────────────
  step "Install startup hook  (afterStartup.sh)"
  cp "$SCRIPT_DIR/custom_wittypi_code/afterStartup.sh" "$WITTYPI_DIR/afterStartup.sh"
  chmod +x "$WITTYPI_DIR/afterStartup.sh"
  ok "afterStartup.sh installed"

  # ── [9/14] Custom schedules ───────────────────────────────────────────────
  step "Install custom schedules"
  mkdir -p "$WITTYPI_DIR/schedules"
  cp "$SCRIPT_DIR/custom_wittypi_code/schedules/"*.wpi "$WITTYPI_DIR/schedules/"
  cp "$WITTYPI_DIR/schedules/custom_2ms_every_waking_hour.wpi" "$WITTYPI_DIR/schedule.wpi"
  ok "Schedules copied"
  ok "Default: 2 min ON / 58 min OFF (every waking hour)"

  # ── [10/14] Sync RTC + low voltage protection ────────────────────────────
  step "Sync RTC with network time and set low voltage protection  (3.4 V)"
  run_quiet "Sync RTC + set voltage threshold" \
    bash -c "printf '3\n7\n3.4\n13\n' | bash '$WITTYPI_DIR/wittyPi.sh'"
fi

# ── [11/14] Waveshare 7.3" e-ink driver ───────────────────────────────────────
step "Install Waveshare 7.3\" e-ink driver"
WAVESHARE_LIB="$USER_HOME/RPi_Zero_PhotoPainter/7in3_e-Paper_E/python/lib"
if [ -f "$WAVESHARE_LIB/waveshare_epd/epd7in3e.py" ]; then
  skip "Waveshare driver"
else
  mkdir -p "$WAVESHARE_LIB"
  download "Waveshare e-Paper repo" \
    "$URL_WAVESHARE" \
    /tmp/waveshare.zip && {
    run_quiet "Unpack Waveshare library" unzip -q /tmp/waveshare.zip -d /tmp/waveshare_src
    cp -r /tmp/waveshare_src/e-Paper-master/RaspberryPi_JetsonNano/python/lib/waveshare_epd \
      "$WAVESHARE_LIB/" || ERR=$((ERR+1))
    rm -rf /tmp/waveshare.zip /tmp/waveshare_src
    chown -R "$SUDO_USER:$(id -g -n $SUDO_USER)" "$USER_HOME/RPi_Zero_PhotoPainter" \
      || ERR=$((ERR+1))
    ok "Waveshare driver installed"
  }
fi

# ── [12/14] Photo folders ──────────────────────────────────────────────────────
step "Create photo folders"
mkdir -p "$USER_HOME/my_photos" "$USER_HOME/photos_input"
chown "$SUDO_USER:$(id -g -n $SUDO_USER)" "$USER_HOME/my_photos" "$USER_HOME/photos_input"
ok "~/my_photos  and  ~/photos_input"

# ── [13/14] Configure .bashrc ──────────────────────────────────────────────────
step "Configure SSH dev mode  (.bashrc)"
BASHRC="$USER_HOME/.bashrc"
if grep -q 'devmode.sh' "$BASHRC" 2>/dev/null; then
  skip "SSH dev mode"
else
  cat >> "$BASHRC" << 'EOF'

# Auto-enable dev mode when SSH-ing in (keeps Pi awake for debugging)
if [ -n "$SSH_CONNECTION" ]; then
    sudo /home/pi/devmode.sh
fi
EOF
  chown "$SUDO_USER:$(id -g -n $SUDO_USER)" "$BASHRC"
  ok "SSH dev mode added"
fi

# ── [14/14] UUGear Web Interface ───────────────────────────────────────────────
step "Install UUGear Web Interface"
run_quiet "installUWI.sh" bash -c "curl -s '$URL_UWI' | bash"

# ── Summary ────────────────────────────────────────────────────────────────────
printf "\n${BOLD}${CYAN}  ════════════════════════════════════════════${RESET}\n"
if [ $ERR -eq 0 ]; then
  printf "  ${GREEN}${BOLD}All done!${RESET}  No errors.\n\n"
  printf "  Next steps:\n"
  printf "    1.  sudo reboot\n"
  printf "    2.  SSH back in — dev mode activates automatically\n"
  printf "    3.  Add photos into ~/photos_input/ and run:\n"
  printf "          python3 ~/convert_pictures.py\n"
  printf "    4.  python3 ~/display_picture.py   (test the display)\n"
  printf "    5.  ~/goodnight.sh                 (set schedule & shut down)\n"
else
  printf "  ${RED}${BOLD}Finished with %d error(s).${RESET}\n" "$ERR"
  printf "  Full log: ${BOLD}%s${RESET}\n" "$LOG_FILE"
fi
printf "${BOLD}${CYAN}  ════════════════════════════════════════════${RESET}\n\n"
