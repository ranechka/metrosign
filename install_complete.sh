#!/usr/bin/env bash
# MetroSign — complete installer
# Combines: system library setup, SPI check, user permissions, Rust toolchain
# (optional), Python dependency installation, package installation, config
# creation, interactive station selection, and systemd service setup.
#
# Run with: sudo ./install_complete.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
SERVICE_NAME="metrosign"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
CONFIG_FILE="$REPO_ROOT/config.json"
VENV_DIR="/opt/metrosign/venv"
AUTO_VENV_DIR="$REPO_ROOT/.venv"
PYTHON="python3"
USE_VENV=false
SKIP_SERVICE=false
RUN_NOW=false
PROMPT_STATION=true
INSTALL_DEPS=true
INSTALL_SYSTEM_DEPS=true
# The user whose home directory / .bashrc we should update, even though this
# script itself must run as root (via sudo). Falls back to whoami if not
# run under sudo (e.g. already root shell).
TARGET_USER="${SUDO_USER:-$(whoami)}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

# ---------------------------------------------------------------------------
# Helper: persist an environment variable to the target user's .bashrc so it
# survives future logins without the user having to do it manually.
# ---------------------------------------------------------------------------
persist_env_var() {
  local var_name="$1"
  local var_value="$2"
  local bashrc="$TARGET_HOME/.bashrc"

  if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    echo "Could not determine home directory for user '$TARGET_USER'; skipping .bashrc update for $var_name." >&2
    return 1
  fi

  touch "$bashrc"

  if grep -q "^export ${var_name}=" "$bashrc" 2>/dev/null; then
    sed -i "s|^export ${var_name}=.*|export ${var_name}='${var_value}'|" "$bashrc"
    echo "Updated ${var_name} in $bashrc"
  else
    {
      echo ""
      echo "# Added by MetroSign installer"
      echo "export ${var_name}='${var_value}'"
    } >> "$bashrc"
    echo "Added ${var_name} to $bashrc"
  fi

  chown "$TARGET_USER":"$TARGET_USER" "$bashrc" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Helper: ensure WMATAKEY is set for this script run, prompting once if
# needed, and always persisting it to .bashrc so future shells/service runs
# have it without re-entering it. Also exports it into the current script's
# environment so downstream steps (station lookup, systemd Environment=)
# can use it immediately.
# ---------------------------------------------------------------------------
ensure_wmata_key() {
  WMATAKEY="${WMATAKEY:-}"

  if [[ -z "$WMATAKEY" ]]; then
    read -rp "Enter your WMATA API key: " WMATAKEY
    if [[ -z "$WMATAKEY" ]]; then
      echo "WMATA API key is required. Get one at https://developer.wmata.com/" >&2
      exit 1
    fi
  fi

  export WMATAKEY
  persist_env_var "WMATAKEY" "$WMATAKEY"
}

choose_station_code() {
  echo "Downloading WMATA station list..."
  station_data=$("$PYTHON" - "$WMATAKEY" <<PY
import json, sys, urllib.request
key = sys.argv[1]
req = urllib.request.Request(
    "https://api.wmata.com/Rail.svc/json/jStations",
    headers={"api_key": key}
)
with urllib.request.urlopen(req, timeout=15) as resp:
    data = json.load(resp)
    stations = data.get("Stations", [])
    for s in stations:
        code = s.get("Code", "").strip()
        name = s.get("Name", "").strip()
        line_codes = sorted({l.strip() for l in (
            s.get("LineCode1"), s.get("LineCode2"),
            s.get("LineCode3"), s.get("LineCode4"),
        ) if l})
        print(f"{code}\t{name}\t{','.join(line_codes)}")
PY
)

  if [[ -z "$station_data" ]]; then
    echo "Failed to fetch station list from WMATA." >&2
    exit 1
  fi

  while true; do
    read -rp "Search stations by name, code, or line (e.g. Red, BL); type 'all' to list every station: " filter
    filter_lower=$(printf '%s' "$filter" | tr '[:upper:]' '[:lower:]')

    if [[ "$filter_lower" == "all" ]]; then
      filtered="$station_data"
    else
      line_code="$filter_lower"
      case "$filter_lower" in
        red) line_code=rd ;;
        blue) line_code=bl ;;
        green) line_code=gr ;;
        yellow) line_code=yl ;;
        orange) line_code=or ;;
        silver) line_code=sv ;;
        purple) line_code=pr ;;
      esac

      filtered=$(printf '%s\n' "$station_data" | awk -F'\t' -v q="$filter_lower" -v line="$line_code" '
        BEGIN { filter = tolower(q); linecode = tolower(line) }
        {
          code = tolower($1)
          name = tolower($2)
          lines = tolower($3)
          if (filter == "" || index(code, filter) || index(name, filter) || index(lines, filter) || (linecode != "" && index(lines, linecode))) print
        }
      ')
    fi

    if [[ -z "$filtered" ]]; then
      echo "No stations matched '$filter'. Try another search."
      continue
    fi

    choices=()
    while IFS=$'\t' read -r code name lines; do
      if [[ -n "$lines" ]]; then
        display_lines="${lines//,/ , }"
        choices+=("$code - $name ($display_lines)")
      else
        choices+=("$code - $name")
      fi
    done < <(printf '%s\n' "$filtered")

    echo "Choose a station:"
    select choice in "${choices[@]}" "Search again"; do
      if [[ "$REPLY" -eq $(( ${#choices[@]} + 1 )) ]]; then
        break
      elif [[ "$REPLY" -ge 1 && "$REPLY" -le ${#choices[@]} ]]; then
        STATION_CODE=$(printf '%s' "$choice" | cut -d' ' -f1)
        echo "Selected station code: $STATION_CODE"
        return
      else
        echo "Invalid selection."
      fi
    done
  done
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --python PATH          Python interpreter to use (default: python3)
  --venv PATH            Create and use a virtualenv at PATH
  --service-name NAME    Systemd service name (default: metrosign)
  --config PATH          Config file path (default: $REPO_ROOT/config.json)
  --skip-service         Do not install or enable the systemd service
  --run-now              Run MetroSign once after setup for testing
  --prompt-station       Prompt to choose a station code during install (default behavior)
  --skip-prompt-station  Skip station selection during install
  --no-deps              Skip Python dependency installation
  --no-system-deps       Skip apt-based system library installation
  -h, --help             Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --python)
      PYTHON="$2"
      shift 2
      ;;
    --venv)
      USE_VENV=true
      VENV_DIR="$2"
      shift 2
      ;;
    --service-name)
      SERVICE_NAME="$2"
      SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
      shift 2
      ;;
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --skip-service)
      SKIP_SERVICE=true
      shift
      ;;
    --run-now)
      RUN_NOW=true
      SKIP_SERVICE=true
      shift
      ;;
    --prompt-station)
      PROMPT_STATION=true
      shift
      ;;
    --skip-prompt-station|--no-prompt-station)
      PROMPT_STATION=false
      shift
      ;;
    --no-deps)
      INSTALL_DEPS=false
      shift
      ;;
    --no-system-deps)
      INSTALL_SYSTEM_DEPS=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$EUID" -ne 0 ]]; then
 echo "This installer must be run as root (use sudo)." >&2
 exit 1
fi

echo "=========================================="
echo "MetroSign Complete Installation"
echo "=========================================="
echo ""

# ---------------------------------------------------------------------------
# Step 1: System libraries (apt)
# ---------------------------------------------------------------------------
if [[ "$INSTALL_SYSTEM_DEPS" == true ]]; then
  echo "[1/8] Installing system libraries..."
  apt update
  apt install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    python3-venv \
    python3-pip \
    curl \
    git \
    libopenjp2-7 \
    libjpeg62-turbo \
    libtiff6 \
    libfreetype6 \
    liblcms2-2 \
    libwebp7 \
    zlib1g
  echo "      ✓ System libraries installed"
else
  echo "[1/8] Skipping system library installation (--no-system-deps)"
fi

# ---------------------------------------------------------------------------
# Step 2: SPI check (I2C is not used by this project — MAX7219 is SPI-only)
# ---------------------------------------------------------------------------
echo ""
echo "[2/8] Checking SPI status..."

SPI_ACTIVE=false
if ls /dev/spidev* >/dev/null 2>&1 && lsmod | grep -q spi_bcm; then
  echo "      ✓ SPI is active (kernel module loaded, /dev/spidev* present)"
  SPI_ACTIVE=true
elif grep -qs "^dtparam=spi=on" /boot/firmware/config.txt /boot/config.txt 2>/dev/null; then
  echo "      ⚠ SPI is enabled in config.txt but not yet active — a reboot is required"
else
  echo "      ⚠ SPI not enabled. Run: sudo raspi-config"
  echo "        Navigate to: Interface Options → SPI → Enable, then reboot."
fi

# ---------------------------------------------------------------------------
# Step 3: User permissions (spi, gpio groups)
# ---------------------------------------------------------------------------
echo ""
echo "[3/8] Setting user permissions for '$TARGET_USER'..."
if id -Gn "$TARGET_USER" 2>/dev/null | grep -q spi; then
  echo "      ✓ User '$TARGET_USER' already in spi group"
else
  usermod -a -G spi,gpio "$TARGET_USER"
  echo "      ✓ Added '$TARGET_USER' to spi, gpio groups"
  echo "      ⚠ User may need to log out and back in for changes to take effect"
fi

# ---------------------------------------------------------------------------
# Step 4: Rust toolchain — commented out by default.
# Uncomment this block only if a Python package (e.g. cbor2) actually fails
# to install because no prebuilt wheel is available for your platform and it
# needs to compile from source. Most Raspberry Pi installs get a prebuilt
# wheel via piwheels and never need this.
# ---------------------------------------------------------------------------
echo ""
echo "[4/8] Rust toolchain (skipped by default — see script comments)..."
# apt install -y rustc cargo
# echo "      ✓ Rust installed via apt"
#
# Or, for a newer toolchain:
# curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
# echo "      ✓ Rust installed via rustup"
echo "      (not installed — uncomment the rust step in this script if a"
echo "       package build fails asking for a Rust/Cargo compiler)"

check_build_toolchain() {
  missing=()
  versions=()

  if ! command -v cargo >/dev/null 2>&1; then
    missing+=("cargo")
  else
    cargo_version=$(cargo --version 2>/dev/null | awk '{print $2}')
    if [[ "$cargo_version" =~ ^([0-9]+)\.([0-9]+) ]]; then
      cargo_major=${BASH_REMATCH[1]}
      cargo_minor=${BASH_REMATCH[2]}
      if (( cargo_major < 1 || (cargo_major == 1 && cargo_minor < 72) )); then
        versions+=("cargo $cargo_version (needs >=1.72 for Rust 2024 edition)")
      fi
    fi
  fi

  if ! command -v rustc >/dev/null 2>&1; then
    missing+=("rustc")
  fi

  if [[ ${#missing[@]} -gt 0 || ${#versions[@]} -gt 0 ]]; then
    echo
    echo "==== Build toolchain note ===="
    echo "No Rust toolchain detected. This is fine unless a package build"
    echo "fails asking for Cargo/Rust — in that case, uncomment the rust"
    echo "install step near the top of this script (Step 4) and re-run."
    echo "==============================="
    echo
  fi
}
check_build_toolchain

# ---------------------------------------------------------------------------
# Step 5: WMATA API key — prompt once, persist to .bashrc automatically
# ---------------------------------------------------------------------------
echo ""
echo "[5/8] WMATA API key..."
ensure_wmata_key
echo "      ✓ WMATAKEY is set for this session and saved to $TARGET_HOME/.bashrc"

# ---------------------------------------------------------------------------
# Step 6: Python virtual environment + dependencies
# ---------------------------------------------------------------------------
echo ""
echo "[6/8] Python dependencies..."

if ! python3 -m venv --help >/dev/null 2>&1; then
  echo "The system does not appear to support Python virtual environments." >&2
  echo "This should have been installed in Step 1. Try: sudo apt install -y python3-venv" >&2
  exit 1
fi

if [[ "$USE_VENV" == true ]]; then
  echo "      Creating virtualenv at $VENV_DIR"
  mkdir -p "$(dirname "$VENV_DIR")"
  "$PYTHON" -m venv "$VENV_DIR"
  PYTHON="$VENV_DIR/bin/python"
elif [[ -d "$AUTO_VENV_DIR" ]]; then
  echo "      ✓ Virtual environment found at $AUTO_VENV_DIR"
  PYTHON="$AUTO_VENV_DIR/bin/python"
else
  echo "      Creating virtualenv at $AUTO_VENV_DIR"
  python3 -m venv "$AUTO_VENV_DIR"
  PYTHON="$AUTO_VENV_DIR/bin/python"
fi

PIP_COMMAND=("$PYTHON" -m pip)

pip_install_failed() {
  cat <<EOF >&2
Python package installation failed.
This can happen on Debian/Ubuntu systems when the Python environment is "externally managed".

If the failure mentions Cargo or Rust, uncomment the rust install step near
the top of this script (Step 4) and re-run.
EOF
  exit 1
}

install_dependencies() {
  if [[ -f "$REPO_ROOT/requirements.txt" ]]; then
    "${PIP_COMMAND[@]}" install --upgrade pip && \
      "${PIP_COMMAND[@]}" install -r "$REPO_ROOT/requirements.txt"
  else
    "${PIP_COMMAND[@]}" install --upgrade pip && \
      "${PIP_COMMAND[@]}" install requests luma.led_matrix
  fi
}

if [[ "$INSTALL_DEPS" == true ]]; then
  install_dependencies || pip_install_failed
  echo "      ✓ Python packages installed"
else
  echo "      Skipping Python dependency installation (--no-deps)"
fi

if [[ -f "$REPO_ROOT/pyproject.toml" || -f "$REPO_ROOT/setup.py" ]]; then
  echo "      Installing the app package from source..."
  "${PIP_COMMAND[@]}" install --upgrade "$REPO_ROOT"
  echo "      ✓ metrosign package installed"
fi

# ---------------------------------------------------------------------------
# Step 7: Config file + station selection
# ---------------------------------------------------------------------------
echo ""
echo "[7/8] Configuration..."

mkdir -p "$(dirname "$CONFIG_FILE")"
if [[ ! -f "$CONFIG_FILE" ]]; then
  if [[ -f "$REPO_ROOT/code/config.example.json" ]]; then
    cp "$REPO_ROOT/code/config.example.json" "$CONFIG_FILE"
  else
    cat > "$CONFIG_FILE" <<EOF
{
  "station_code": "B04",
  "refresh_interval": 10,
  "display": {
    "cascaded": 4,
    "block_orientation": -90,
    "rotate": 0,
    "reverse_order": false,
    "contrast": 1,
    "scroll_delay": 0.04
  },
  "startup_message": "Welcome to MetroSign",
  "fallback_message": "No train data available"
}
EOF
  fi
  echo "      ✓ Created config file at: $CONFIG_FILE"
else
  echo "      ✓ Config file already exists at: $CONFIG_FILE"
fi

if [[ "$PROMPT_STATION" == true ]]; then
  choose_station_code
  "$PYTHON" - <<PY
import json
from pathlib import Path
config_path = Path("$CONFIG_FILE")
config = json.loads(config_path.read_text(encoding="utf-8"))
config["station_code"] = "$STATION_CODE"
config_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
PY
  echo "      ✓ Updated station code in $CONFIG_FILE to $STATION_CODE"
fi

# ---------------------------------------------------------------------------
# Step 8: Systemd service
# ---------------------------------------------------------------------------
echo ""
echo "[8/8] Systemd service..."

SERVICE_ENV_LINE="Environment=WMATAKEY=$WMATAKEY"

if [[ "$SKIP_SERVICE" == false ]]; then
  echo "      Installing systemd service: $SERVICE_FILE"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Metro Sign LED Matrix Display
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$TARGET_USER
Group=$TARGET_USER
WorkingDirectory=$REPO_ROOT
$SERVICE_ENV_LINE
ExecStart=$PYTHON -m code.main --config "$CONFIG_FILE"
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
  echo "      ✓ Enabled and started systemd service: $SERVICE_NAME"
else
  echo "      Skipped (--skip-service)"
fi

if [[ "$RUN_NOW" == true ]]; then
  echo ""
  echo "Running MetroSign once for testing..."
  exec "$PYTHON" -m code.main --config "$CONFIG_FILE"
fi

echo ""
echo "=========================================="
echo "✅ Installation Complete!"
echo "=========================================="
echo ""
if [[ "$SPI_ACTIVE" == false ]]; then
  echo "⚠ SPI was not detected as active. If you just enabled it via"
  echo "  raspi-config, reboot now: sudo reboot"
  echo "  Then check status with: sudo systemctl status $SERVICE_NAME"
  echo ""
fi
echo "WMATAKEY has been saved to $TARGET_HOME/.bashrc — new shells will have"
echo "it automatically. The systemd service also has it via Environment=."
echo ""
echo "Manage the service with:"
echo "  sudo systemctl restart $SERVICE_NAME"
echo "  sudo systemctl status $SERVICE_NAME"
echo "  sudo journalctl -u $SERVICE_NAME -f"
echo "=========================================="
