#!/usr/bin/env bash
echo "=== user / groups ==="; id
echo "=== serial devices ==="; ls -l /dev/ttyUSB* /dev/ttyACM* 2>&1
echo "=== USB devices ==="; lsusb
echo "=== kernel log (serial) ==="; sudo dmesg | grep -iE 'tty|pl2303|ftdi|ch34|cp210|usb' | tail -25
echo "=== brltty ==="; systemctl is-active brltty 2>&1; dpkg -l brltty 2>/dev/null | tail -1
echo "=== port in use? ==="; sudo fuser -v /dev/ttyUSB0 2>&1
echo "=== send 0VER, raw reply (hex) ==="
PORT=${PORT:-/dev/ttyUSB0}
stty -F "$PORT" 9600 cs8 -cstopb -parenb raw -echo -ixon -crtscts
( timeout 2 cat "$PORT" | hexdump -C ) &
sleep 0.3; printf '0VER\r' > "$PORT"; wait
echo "=== done ==="

