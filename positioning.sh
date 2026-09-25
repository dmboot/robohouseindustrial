#!/usr/bin/env bash
# Interactive positioning / speed demo for a Faulhaber MCDC3006 over RS232.
# Type an angle and the shaft goes there; the script reports how precisely
# it arrived. Angles are motor-shaft degrees, 0 = 12 o'clock on the pointer.
PORT=${PORT:-/dev/ttyUSB0}

stty -F "$PORT" 9600 cs8 -cstopb -parenb raw -echo -ixon -crtscts
exec 3<>"$PORT"                      # keep the port open on fd 3

SPEED=1000                           # max positioning speed (rpm)
ACCEL=100                            # acceleration/deceleration (rev/s^2)
TARGET=0                             # last commanded target (counts)

flush() { while IFS= read -r -t 0.05 -u 3 _; do :; done; }

raw() { printf '0%s\r' "$1" >&3; }   # send without waiting for a reply

ask() {                              # send, put reply in $R ("" if none)
    flush
    raw "$1"
    R=
    IFS= read -r -t 1 -u 3 R && R=${R%$'\r'}
}

calc() { awk "BEGIN { $1 }"; }       # bash has no floating point

deg2cnt() { calc "printf \"%d\", ($1) * $CPR / 360 + (($1) < 0 ? -0.5 : 0.5)"; }
cnt2deg() { calc "printf \"%.2f\", ($1) * 360 / $CPR"; }

clock() {                            # where the pointer should be, in words
    calc "a = ($1) % 360; if (a < 0) a += 360
          h = int(a / 30 + 0.5) % 12; if (h == 0) h = 12
          printf \"%.1f deg on the dial (~%d o'clock)\", a, h"
}

getpos() { ask POS; P=${R//[^0-9-]/}; P=${P:-0}; }

set_profile() {                      # set_profile <rpm> <rev/s^2>
    ask "SP$1"; ask "AC$2"; ask "DEC$2"
}

move_to() {                          # move_to <counts>; sets $DT (seconds)
    local dist t0 timeout line end
    TARGET=$1
    ask "LA$TARGET"
    getpos
    dist=$(( TARGET - P )); dist=${dist#-}
    # travel time + ramp time + margin
    timeout=$(calc "printf \"%d\", $dist/$CPR / ($SPEED/60) + ($SPEED/60)/$ACCEL + 3")
    flush
    raw NP                           # notify with "p" when target is reached
    t0=$(date +%s.%N)
    raw M
    end=$(( SECONDS + timeout ))
    while (( SECONDS < end )); do
        IFS= read -r -t 1 -u 3 line || continue
        if [[ ${line%$'\r'} == p ]]; then
            DT=$(calc "printf \"%.2f\", $(date +%s.%N) - $t0")
            return 0
        fi
    done
    DT=timeout
    echo "  ! no 'position reached' within ${timeout}s"
    return 1
}

report() {                           # print where we are vs. where we wanted
    local err
    sleep 0.2                        # let it settle
    getpos
    err=$(( P - TARGET ))
    printf '  target %d  actual %d  error %+d counts (%s deg)  time %ss\n' \
        "$TARGET" "$P" "$err" "$(cnt2deg "$err")" "$DT"
    echo "  pointer: $(clock "$(cnt2deg "$P")")"
}

repeat_test() {                      # bounce 0 <-> 180 deg, collect errors
    local n=${1:-10} i e max=0 half
    half=$(deg2cnt 180)
    echo "  $n round trips 0 <-> 180 deg at $SPEED rpm..."
    for (( i = 1; i <= n; i++ )); do
        for tgt in "$half" 0; do
            move_to "$tgt" || return
            sleep 0.2; getpos
            e=$(( P - tgt )); e=${e#-}
            (( e > max )) && max=$e
        done
        printf '  trip %2d: back at %+d counts\n' "$i" "$P"
    done
    echo "  worst error over $((2 * n)) stops: $max counts ($(cnt2deg "$max") deg)"
}

race() {                             # same 10-turn move, slow vs. fast
    local s=$SPEED a=$ACCEL start
    getpos; start=$P
    for profile in "300 10 slow" "3000 500 fast"; do
        set -- $profile
        SPEED=$1; ACCEL=$2; set_profile "$1" "$2"
        echo "  $3: 10 turns at $1 rpm, ramp $2 rev/s^2"
        move_to $(( start + 10 * CPR )) && report
        echo "  back..."
        move_to "$start" && report
    done
    SPEED=$s; ACCEL=$a; set_profile "$s" "$a"
}

spin() {                             # velocity mode, compare set vs measured
    local sum=0 i v
    ask "V$1"
    echo "  spinning at $1 rpm, measuring..."
    sleep 2
    for i in 1 2 3 4 5; do
        ask GN; printf '  measured %s rpm\n' "$R"
        v=${R//[^0-9-]/}; sum=$(( sum + ${v:-0} ))
        sleep 0.5
    done
    echo "  set $1 rpm, average $(( sum / 5 )) rpm (type 'stop' to stop)"
}

help() {
    cat <<'EOF'
  <deg>        go to absolute angle, e.g. 90, -45, 720, 12.5
  r <deg>      move relative, e.g. r 30, r -1.8
  home         go back to 0 deg
  zero         make the current position 0 deg (align pointer to 12 first)
  speed <rpm>  max positioning speed
  acc <r/s^2>  acceleration and deceleration
  repeat [n]   repeatability test: n round trips 0 <-> 180 deg (default 10)
  race         10 turns slow vs. fast, compare time and landing error
  spin <rpm>   free-running speed mode, compares set vs. measured speed
  stop         stop spinning
  status       show position, speed and profile
  q            quit (stops and disables the drive)
EOF
}

cleanup() { raw V0; sleep 0.1; raw DI; exec 3>&-; echo; echo "drive disabled"; }
trap cleanup EXIT
trap 'exit 130' INT

ask ANSW2                            # confirm every command, allow async "p"
ask VER; echo "controller: $R"
ask GENCRES; CPR=${R//[^0-9]/}
CPR=${CPR_OVERRIDE:-${CPR:-2048}}
echo "encoder: $CPR counts/rev = $(calc "printf \"%.3f\", 360/$CPR") deg per count"
ask EN
ask HO                               # current position becomes 0
set_profile "$SPEED" "$ACCEL"
echo "drive enabled, current position is 0 deg. Type 'help' for commands."

while IFS= read -r -e -p "> " line; do
    set -- $line
    case $1 in
        "")      ;;
        q|quit)  break ;;
        help|h)  help ;;
        home)    move_to 0 && report ;;
        zero)    ask HO; TARGET=0; echo "  current position is now 0 deg" ;;
        r)       [[ $2 ]] && move_to $(( TARGET + $(deg2cnt "$2") )) && report ;;
        speed)   SPEED=${2:-$SPEED}; set_profile "$SPEED" "$ACCEL"; echo "  $SPEED rpm" ;;
        acc)     ACCEL=${2:-$ACCEL}; set_profile "$SPEED" "$ACCEL"; echo "  $ACCEL rev/s^2" ;;
        repeat)  repeat_test "$2" ;;
        race)    race ;;
        spin)    [[ $2 ]] && spin "$2" ;;
        stop)    ask V0; echo "  stopped" ;;
        status)  getpos; ask GN
                 echo "  position $P counts = $(cnt2deg "$P") deg, speed $R rpm"
                 echo "  profile: $SPEED rpm, $ACCEL rev/s^2" ;;
        *)       if [[ $1 =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
                     move_to "$(deg2cnt "$1")" && report
                 else
                     echo "  unknown command, type 'help'"
                 fi ;;
    esac
done
