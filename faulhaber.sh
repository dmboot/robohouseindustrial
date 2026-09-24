#!/usr/bin/env bash
# Simple ASCII control of a Faulhaber MCDC3006 over RS232 . 
PORT=${PORT:-/dev/ttyUSB0}

stty -F "$PORT" 9600 cs8 -cstopb -parenb raw -echo -ixon -crtscts
exec 3<>"$PORT"                      # keep the port open on fd 3

send() {                             # send "<cmd>\r", print reply
    printf '%s\r' "$1" >&3
    if IFS= read -r -t 1 -u 3 reply; then
        echo "$1 -> ${reply%$'\r'}"
    else
        echo "$1 -> (no reply)"
    fi
}

send 0VER       # version check
send 0EN        # enable drive
send 0V300      # run at 300 rpm
sleep 5
send 0GN        # read actual speed
send 0POS       # read actual position
send 0V0        # stop
send 0DI        # disable drive

exec 3>&-
