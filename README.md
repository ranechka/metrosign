# MetroSign

A train arrivals board for your local WMATA Metro stop.

MetroSign is a Raspberry Pi LED matrix display application that shows WMATA train arrival predictions on a MAX7219 panel. It started out with a local, messy script, and then I polished it up with Copilot to make it installable.

I used a Raspberry Pi Zero W with Raspbian 13 Headless for this project, and a panel of 4 displays.

## Before you start: enable SPI

The MAX7219 display communicates over SPI, which is **disabled by default** on Raspberry Pi OS. Enable it before running the installer:

```bash
sudo raspi-config
# Navigate to: Interface Options → SPI → Enable
```

Then **reboot** — this is required, since SPI won't actually activate until the kernel module reloads:

```bash
sudo reboot
```

`install_complete.sh` (see below) checks whether SPI is active and will warn you if it isn't, but it can't enable it for you or reboot on its own, so it's best to do this first.

## Install

`install_complete.sh` handles everything in one pass: system libraries, SPI status check, user permissions, Python dependencies, the WMATA API key, station selection, and the systemd service. You shouldn't need to run anything else manually.

1. Clone the repository:
   ```bash
   git clone https://github.com/ranechka/metrosign.git ~/metrosign
   cd ~/metrosign
   ```

2. Run the installer as root:
   ```bash
   sudo ./install_complete.sh
   ```

   You'll be prompted for your WMATA API key the first time. It's saved automatically to your `~/.bashrc` (so you never have to `export` it yourself again) and also wired into the systemd service.

   You'll also be prompted to search for and select your station interactively — by name, code, or line color (e.g. `Red`, `Blue`, `Silver`), or type `all` to list every station.

   A `.venv` virtual environment is created inside the repo automatically — no need to create or activate one yourself.

### Useful flags

```
--venv PATH            Use a specific virtualenv path instead of the repo's default ./.venv
--skip-service         Do not install or enable the systemd service
--run-now              Run MetroSign once immediately after setup, for testing
--skip-prompt-station  Skip interactive station selection (useful for unattended installs)
--no-deps              Skip Python dependency installation
--no-system-deps       Skip apt-based system library installation
```

For example, to test without installing the systemd service:

```bash
sudo ./install_complete.sh --skip-service --run-now
```

### Notes on install time

Some of these steps can take a while on a Raspberry Pi Zero W — multiple minutes for the system libraries and Python dependency installation, with no output in between to indicate progress. This is normal; be patient. A Pi with more processing power or RAM will be noticeably faster.

## Configuration

The installer creates:
- `config.json` in the project directory

Your WMATA API key is stored as the `WMATAKEY` environment variable — the installer adds it to `~/.bashrc` and to the systemd service automatically. Edit `config.json` directly for station, display, and polling settings.

### Prerequisites (only needed if something fails)

`install_complete.sh` already installs the system libraries this project needs — `build-essential`, `pkg-config`, `libssl-dev`, and the imaging libraries required by Pillow (`libopenjp2-7`, `libjpeg62-turbo`, `libtiff6`, `libfreetype6`, `liblcms2-2`, `libwebp7`, `zlib1g`). You shouldn't need to install these yourself.

**Rust is intentionally left out by default.** Most platforms get a precompiled wheel for `cbor2` (a `luma.core` dependency) via [piwheels](https://www.piwheels.org), so a Rust toolchain usually isn't needed. If a `pip install` step fails with an error mentioning Cargo or "can't find Rust compiler," open `install_complete.sh`, find the commented-out Rust install block (Step 4), uncomment one of the two options, and re-run:

```bash
# Option A (apt):
sudo apt install -y rustc cargo

# Option B (recommended for the latest toolchain):
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

If you see an error about Cargo or the Rust 2024 edition, your system Rust toolchain is too old and needs upgrading to Rust/Cargo 1.72 or later — Option B gets you the newest version.

If you'd rather avoid installing a system toolchain on the Pi entirely, build the virtualenv on a faster machine that provides prebuilt wheels (or use Docker) and copy the resulting `.venv` over to the Pi.

### Display Configuration

The `display` section in `config.json` controls how the LED matrix is initialized and how text scrolls. Common keys:

- `cascaded`: number of chained MAX7219 modules (e.g. `1` for 8x8, `4` for 32x8).
- `block_orientation`: rotation correction for physically-mounted modules. Valid values: `0`, `90`, `-90`, `180`.
- `rotate`: in-place device rotation (integer rotation states used by `luma.led_matrix`, commonly `0`, `1`, `2`, `3`).
- `reverse_order`: boolean; set to `true` if your modules are wired in reverse order.
- `contrast`: brightness level passed to the device (typically `0-255`; higher = brighter).
- `scroll_delay`: delay (seconds) between scroll steps when drawing text (smaller = faster).

Adjust these values in your `config.json` and test with `python3 code/main.py --config config.json --console` to preview changes in console mode.

## Systemd service

The app is installed as a systemd service named `metrosign`.

To manage it:
```bash
sudo systemctl restart metrosign
sudo systemctl status metrosign
sudo journalctl -u metrosign -f
```

> **Note:** If you just enabled SPI for the first time, `install_complete.sh` may have started the systemd service before the SPI reboot took effect — so a failed first start isn't necessarily a real problem. After rebooting, confirm the service actually came up clean:
> ```bash
> sudo reboot
> # after it comes back up:
> sudo systemctl status metrosign
> sudo journalctl -u metrosign -f
> ```

## Test run without systemd

You can run the app directly for a quick test without installing the systemd service:

```bash
sudo ./install_complete.sh --skip-service --run-now
```

This installs dependencies and config files, then starts the app immediately using the configured settings.

If you already have the config file and dependencies in place, and just want to run the app directly:

```bash
python3 code/main.py --config config.json
```

(`WMATAKEY` doesn't need to be passed inline if you've already run the installer, since it's in `~/.bashrc`.)

### Console output mode

To test the app on a device without actually writing to the LED matrix — and without needing SPI enabled at all — use:

```bash
python3 code/main.py --config config.json --console
```

This prints the formatted train arrival string to the console every refresh interval instead of using the LED display. It's a good first check after install, before testing on real hardware.

## Development

The app package is located under `code/metrosign/` and is launched from `code/main.py`.