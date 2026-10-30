#!/usr/bin/env bash
# Compila lo sniffer di probe request per ESP-01 (1MB, flash DOUT) con arduino-builder
# e il core ESP8266 installato in ~/.arduino15. Stesse impostazioni del progetto pwmeter.
#
#   ./firmware/build.sh          compila in firmware/build/
#   ./firmware/build.sh flash    compila e carica sull'ESP-01
#   ./firmware/build.sh monitor  legge la seriale e salva il log in captures/
#
# Per il flash l'ESP-01 deve essere in modalità bootloader:
# ponticello GPIO0-GND mentre si collega l'adattatore USB.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# SKETCH_NAME=fakeap per il finto access point (richiede FAKEAP_PASS)
SKETCH_NAME="${SKETCH_NAME:-probesniff}"
SKETCH="$HERE/$SKETCH_NAME/$SKETCH_NAME.ino"
EXTRA_FLAGS=""
[[ -n "${FAKEAP_PASS:-}" ]] && EXTRA_FLAGS="-DFAKEAP_PASS=\"$FAKEAP_PASS\""
BUILD="$HERE/build/$SKETCH_NAME"
PACKAGES="$HOME/.arduino15/packages"
CTAGS="$(ls -d "$PACKAGES"/builtin/tools/ctags/* | tail -1)"
PORT="${PORT:-/dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0}"

if [[ "${1:-}" == "monitor" ]]; then
  LOG="$HERE/../captures/$SKETCH_NAME-$(date +%Y%m%d-%H%M%S).log"
  mkdir -p "$(dirname "$LOG")"
  stty -F "$PORT" 115200 raw -echo
  echo "log in $LOG (Ctrl+C per uscire)"
  exec stdbuf -oL cat "$PORT" | tee "$LOG"
fi

OPTS="xtal=80,vt=flash,exception=legacy,ssl=all,ResetMethod=ck,CrystalFreq=26"
OPTS+=",FlashFreq=40,FlashMode=dout,eesz=1M,led=2,sdk=nonosdk_190703"
OPTS+=",ip=lm2f,dbg=Disabled,lvl=None____,wipe=none,baud=115200"

mkdir -p "$BUILD"
arduino-builder -compile \
  -hardware "$PACKAGES" \
  -tools "$PACKAGES" -tools /usr/share/arduino-builder \
  -prefs "tools.ctags.path=$CTAGS" \
  -prefs 'tools.ctags.cmd.path={path}/ctags' \
  -prefs 'tools.ctags.pattern="{cmd.path}" -u --language-force=c++ -f - --c++-kinds=svpf --fields=KSTtzns --line-directives "{source_file}"' \
  -prefs "compiler.cpp.extra_flags=$EXTRA_FLAGS" \
  -fqbn "esp8266:esp8266:generic:$OPTS" \
  -build-path "$BUILD" \
  "$SKETCH"

echo "Firmware: $BUILD/$SKETCH_NAME.ino.bin"

if [[ "${1:-}" == "flash" ]]; then
  uvx esptool --port "$PORT" --before no-reset --after no-reset \
    write-flash --flash-mode dout --flash-size 1MB 0x0 "$BUILD/$SKETCH_NAME.ino.bin"
  echo "Togli il ponticello GPIO0-GND e ricollega l'adattatore per avviare il firmware."
fi
