# MetroSign

A train arrivals board for your local WMATA Metro stop.

MetroSign is a Raspberry Pi LED matrix display application that shows WMATA train arrival predictions on a MAX7219 panel. It started out with a local, messy script, and then I polished it up with Copilot to make it installable.

## Install

1. Clone the repository:
   ```bash
   git clone <repo-url> ~/metrosignproject
   cd ~/metrosignproject
   ```

2. Install system dependencies and Python:
   ```bash
   sudo apt update
   sudo apt install -y python3 python3-venv python3-pip curl
   ```

3. Create a local virtual environment and run the installer from it:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   ./install.sh --skip-service --run-now
   ```

   If you prefer not to activate the environment, use:
   ```bash
   ./install.sh --venv .venv --skip-service --run-now
   ```

   If the script detects an externally-managed Python environment, it will automatically create and use `./.venv` for dependency installation.

## Configuration

## Prerequisites

Some Python packages used by this project include native extensions or Rust-backed code and may require system build tools on Debian/Ubuntu/Raspbian (including Raspberry Pi OS). If a dependency fails to build during `pip install` with errors about missing compilers or "can't find Rust compiler", install the following packages and retry:

- Common build tools and headers:

```bash
sudo apt update
sudo apt install -y build-essential pkg-config libssl-dev
```

- Rust toolchain (required by packages such as `cbor2` when a prebuilt wheel is not available):

Option A (apt):
```bash
sudo apt install -y rustc cargo
```

Option B (recommended for latest toolchain):
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
# follow the rustup prompts, then reopen your shell or `source $HOME/.cargo/env`
```

Notes:
- You do not normally need these tools when a compatible wheel is available for your platform, but on ARM/Raspberry Pi images some packages may fall back to source builds.
- If you see an error about Cargo or the Rust 2024 edition, your system Rust toolchain is too old and needs upgrading to Rust/Cargo 1.72 or later.
- The installer includes a fallback virtualenv creation and prints hints when such build-toolchain packages appear to be missing.
- If you prefer to avoid installing system toolchains, run the installer on a machine that provides prebuilt wheels (or use Docker) and copy the created virtualenv to the Pi.


The installer creates:
- `config.json` in the project directory

Set the WMATA API key using the OS environment variable `WMATAKEY`, and edit `config.json` for station, display, and polling settings.

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

## Test run without systemd

You can run the app directly for a quick test without installing the systemd service:

```bash
sudo ./install.sh --skip-service --run-now
```

This installs dependencies and config files, then starts the app immediately using the configured settings.

Station selection is now interactive by default during install. During the prompt you can:

- search by station name or code
- type a metro line name (for example `Red`, `Blue`, `Green`, `Silver`) to list stations on that line
- type `all` to list every WMATA station

To skip the station prompt (useful for unattended installs), run:

```bash
sudo ./install.sh --skip-prompt-station
```

If you already have the config file in place, run:

```bash
WMATAKEY=your_api_key_here python3 code/main.py --config config.json
```

### Console output mode

To test the app on a device without actually writing to the LED matrix, use:

```bash
python3 code/main.py --config config.json --console
```

This prints the formatted train arrival string to the console every refresh interval instead of using the LED display.

## Development

The app package is located under `code/metrosign/` and is launched from `code/main.py`.

