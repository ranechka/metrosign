#!/usr/bin/env bash
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
AUTO_VENV_CREATED=false

choose_station_code() {
  WMATAKEY="${WMATAKEY:-}"

  if [[ -z "$WMATAKEY" ]]; then
    read -rp "Enter WMATA API key to fetch stations: " WMATAKEY
    if [[ -z "$WMATAKEY" ]]; then
      echo "WMATA API key is required to look up stations." >&2
      exit 1
    fi
  fi

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
  --no-deps              Skip dependency installation
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

# Temporarily allow non-root execution for local testing.
# WARNING: default install paths still target /etc and may require root.
# if [[ "$EUID" -ne 0 ]]; then
#  echo "This installer must be run as root." >&2
#  exit 1
#fi

if ! command -v "$PYTHON" >/dev/null 2>&1; then
  echo "Python interpreter not found: $PYTHON" >&2
  exit 1
fi

if ! python3 -m venv --help >/dev/null 2>&1; then
  echo "The system does not appear to support Python virtual environments."
  echo "Install the Raspberry Pi prerequisites and rerun:"
  echo "  sudo apt update"
  echo "  sudo apt install -y python3-venv python3-pip curl"
  exit 1
fi

if [[ "$USE_VENV" == true ]]; then
  if ! command -v "$PYTHON" >/dev/null 2>&1; then
    echo "Python interpreter for virtualenv not found: $PYTHON" >&2
    exit 1
  fi
  echo "Creating virtualenv at $VENV_DIR"
  mkdir -p "$(dirname "$VENV_DIR")"
  "$PYTHON" -m venv "$VENV_DIR"
  PYTHON="$VENV_DIR/bin/python"
fi

PIP_COMMAND=("$PYTHON" -m pip)

create_fallback_venv() {
  if [[ "$USE_VENV" == false && "$AUTO_VENV_CREATED" == false ]]; then
    echo "Falling back to a local virtualenv at $AUTO_VENV_DIR"
    python3 -m venv "$AUTO_VENV_DIR"
    PYTHON="$AUTO_VENV_DIR/bin/python"

    if ! "$PYTHON" -m pip --version >/dev/null 2>&1; then
      echo "Bootstrapping pip into the fallback virtualenv..."
      if ! "$PYTHON" -m ensurepip --upgrade >/dev/null 2>&1; then
        if command -v curl >/dev/null 2>&1; then
          curl -sS https://bootstrap.pypa.io/get-pip.py -o "$AUTO_VENV_DIR/get-pip.py"
          "$PYTHON" "$AUTO_VENV_DIR/get-pip.py" || {
            echo "Failed to bootstrap pip into the fallback virtualenv." >&2
            return 1
          }
        else
          echo "Failed to bootstrap pip: curl is not available." >&2
          return 1
        fi
      fi
    fi

    PIP_COMMAND=("$PYTHON" -m pip)
    AUTO_VENV_CREATED=true
    return 0
  fi
  return 1
}

pip_install_failed() {
  cat <<EOF >&2
Python package installation failed.
This can happen on Debian/Ubuntu systems when the Python environment is "externally managed".
Use a virtual environment instead of installing system-wide packages.

Examples:
  python3 -m venv .venv
  source .venv/bin/activate
  ./install.sh --venv .venv --skip-service --run-now

Or let the installer create a fallback venv automatically by rerunning:
  ./install.sh --skip-service --run-now

If the failure is from a package like cbor2 and mentions Cargo or Rust, install a newer Rust toolchain:
  sudo apt install -y rustc cargo
or
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
EOF
  exit 1
}

check_build_toolchain() {
  # Detect common build tools that are needed when packages fall back to source builds.
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
  else
    rustc_version=$(rustc --version 2>/dev/null | awk '{print $2}')
    if [[ "$rustc_version" =~ ^([0-9]+)\.([0-9]+) ]]; then
      rustc_major=${BASH_REMATCH[1]}
      rustc_minor=${BASH_REMATCH[2]}
      if (( rustc_major < 1 || (rustc_major == 1 && rustc_minor < 72) )); then
        versions+=("rustc $rustc_version (needs >=1.72 for Rust 2024 edition)")
      fi
    fi
  fi

  if ! command -v gcc >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
    missing+=("build-essential (gcc/make)")
  fi

  if ! command -v pkg-config >/dev/null 2>&1; then
    missing+=("pkg-config")
  fi

  if [[ ${#missing[@]} -gt 0 || ${#versions[@]} -gt 0 ]]; then
    echo
    echo "==== Build toolchain check ===="
    echo "Some Python packages may need to compile native extensions or Rust code."
    if [[ ${#missing[@]} -gt 0 ]]; then
      echo "Missing tools: ${missing[*]}"
    fi
    if [[ ${#versions[@]} -gt 0 ]]; then
      echo "Toolchain versions need update: ${versions[*]}"
    fi
    echo
    echo "On Debian/Ubuntu/Raspbian you can install the common prerequisites with:"
    echo "  sudo apt update"
    echo "  sudo apt install -y build-essential pkg-config libssl-dev"
    echo "If you need Rust (for packages like cbor2), install a newer Rust toolchain:"
    echo "  sudo apt install -y rustc cargo"
    echo "or (recommended for the latest toolchain):"
    echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    echo
    echo "The installer will still attempt to create and use a virtualenv, but if you hit build failures"
    echo "you will likely need the packages above to compile from source."
    echo "================================"
    echo
  fi
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
  echo "Installing package dependencies..."
  check_build_toolchain
  if ! install_dependencies; then
    if create_fallback_venv; then
      echo "Retrying dependency installation inside the fallback venv..."
      install_dependencies || pip_install_failed
    else
      pip_install_failed
    fi
  fi
fi

if [[ -f "$REPO_ROOT/pyproject.toml" || -f "$REPO_ROOT/setup.py" ]]; then
  echo "Installing the app package from source..."
  "${PIP_COMMAND[@]}" install --upgrade "$REPO_ROOT"
fi

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
  echo "Created config file at: $CONFIG_FILE"
fi

if [[ "$PROMPT_STATION" == true ]]; then
  choose_station_code
  python - <<PY
import json
from pathlib import Path
config_path = Path("$CONFIG_FILE")
config = json.loads(config_path.read_text(encoding="utf-8"))
config["station_code"] = "$STATION_CODE"
config_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
PY
  echo "Updated station code in $CONFIG_FILE to $STATION_CODE"
fi

SERVICE_ENV_LINE=""
if [[ -n "${WMATAKEY:-}" ]]; then
  SERVICE_ENV_LINE="Environment=WMATAKEY=$WMATAKEY"
fi

if [[ "$SKIP_SERVICE" == false ]]; then
  echo "Installing systemd service: $SERVICE_FILE"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Metro Sign LED Matrix Display
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=$REPO_ROOT
$SERVICE_ENV_LINE
ExecStart=$PYTHON -m code.main --config "$CONFIG_FILE"
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user-target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
  echo "Enabled and started systemd service: $SERVICE_NAME"
fi

if [[ "$RUN_NOW" == true ]]; then
  echo "Running MetroSign once for testing..."
  exec "$PYTHON" -m code.main --config "$CONFIG_FILE"
fi

echo "Install complete."
echo "Set WMATAKEY in the service environment if needed and edit $CONFIG_FILE, then use 'systemctl restart $SERVICE_NAME' if needed."
