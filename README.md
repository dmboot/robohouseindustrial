# robohouseindustrial

Instructions for the RoboHouse industrial hardware demo.

Currently this covers controlling a **Faulhaber MCDC3006** motion controller
from a Linux PC over RS232, using plain ASCII commands from a bash script.

## Contents

| File           | Purpose                                                                 |
| -------------- | ----------------------------------------------------------------------- |
| `faulhaber.sh` | Demo: enables the drive, spins at 300 rpm for 5 s, reads speed and position, stops and disables. |
| `diag.sh`      | Diagnostics: checks permissions, serial devices, USB adapter, kernel log, and prints the raw reply to `0VER`. |

## Requirements

- Linux PC (tested on Ubuntu)
- USB-to-RS232 adapter (FTDI, PL2303, CH34x or CP210x)
- Faulhaber MCDC3006 with motor, powered by a suitable supply
- `bash`, `stty`, `hexdump`, `lsusb`, `fuser` (standard on Ubuntu; `lsusb` is in `usbutils`, `fuser` in `psmisc`)

## Hardware setup

> **TODO:** wiring and pinout instructions (RS232 cable, power, motor and
> encoder connections) will be added later.

## Software setup

1. Clone the repository:

   ```bash
   git clone git@github.com:dmboot/robohouseindustrial.git
   cd robohouseindustrial
   ```

2. Give your user access to serial ports (log out and back in afterwards):

   ```bash
   sudo usermod -aG dialout $USER
   ```

3. On Ubuntu, `brltty` (braille display daemon) often grabs USB-serial
   adapters, so `/dev/ttyUSB0` disappears right after plugging in. Remove it
   if you don't need it:

   ```bash
   sudo apt remove brltty
   ```

4. Plug in the USB-RS232 adapter and check that the port shows up:

   ```bash
   ls -l /dev/ttyUSB*
   ```

## Usage

The controller is expected at 9600 baud, 8N1, no flow control, node
address 0. Both scripts use `/dev/ttyUSB0` by default; override it with the
`PORT` environment variable.

Run the diagnostics first to confirm communication (some steps use `sudo`):

```bash
./diag.sh
```

A working setup shows a firmware version string in the hex dump under
`send 0VER`. Then run the demo:

```bash
./faulhaber.sh
```

With a different port:

```bash
PORT=/dev/ttyUSB1 ./faulhaber.sh
```

> **Caution:** the demo spins the motor. Make sure it is mounted securely and
> nothing is attached to the shaft that could cause harm.

### Sending your own commands

Each command is ASCII text terminated by a carriage return (`\r`), prefixed
with the node address. Commands used in the demo:

| Command | Meaning                  |
| ------- | ------------------------ |
| `0VER`  | Read firmware version    |
| `0EN`   | Enable drive             |
| `0DI`   | Disable drive            |
| `0V300` | Run at 300 rpm (`0V0` stops) |
| `0GN`   | Read actual speed        |
| `0POS`  | Read actual position     |

See the Faulhaber MCDC3006 communication/command reference manual for the full
command set.

## Troubleshooting

- **No reply:** check baud rate (controller default may differ), cabling,
  and that the controller is powered. Run `./diag.sh` and inspect the kernel
  log section.
- **Permission denied on `/dev/ttyUSB0`:** you're not in the `dialout` group
  yet, or haven't logged out and back in.
- **Port busy:** another program (serial monitor, `brltty`, ModemManager) has
  it open; `diag.sh` shows which process via `fuser`.
