import json
import os
from pathlib import Path


def _candidate_config_paths(config_path: str | None = None) -> list[Path]:
    if config_path:
        return [Path(config_path)]

    cwd = Path.cwd()
    return [
        cwd / "config.json",
        cwd / "code" / "config.json",
    ]


DEFAULT_CONFIG = {
    "station_code": "C04",
    "refresh_interval": 10,
    "display": {
        "cascaded": 4,
        "block_orientation": -90,
        "rotate": 0,
        "reverse_order": False,
        "contrast": 1,
        "scroll_delay": 0.03,
    },
    "startup_message": "Welcome to MetroSign",
    "fallback_message": "No train data available",
    "stale_threshold": 60,
    "stale_message": "Stale data. Check connection.",
}


def load_config(config_path: str | None = None) -> dict:
    config = DEFAULT_CONFIG.copy()
    config["display"] = DEFAULT_CONFIG["display"].copy()

    for path in _candidate_config_paths(config_path):
        if path.exists():
            with path.open("r", encoding="utf-8") as f:
                config.update(json.load(f))
            break

    config["wmata_api_key"] = os.environ.get("WMATAKEY", "")
    config["station_code"] = config.get("station_code")
    config["refresh_interval"] = int(config.get("refresh_interval", 10))
    config["stale_threshold"] = int(config.get("stale_threshold", 60))
    config["stale_message"] = config.get("stale_message", "Stale data. Check connection.")

    display = config.get("display", {})
    display["cascaded"] = int(display.get("cascaded", 1))
    display["block_orientation"] = int(display.get("block_orientation", 0))
    display["rotate"] = int(display.get("rotate", 0))
    display["reverse_order"] = str(display.get("reverse_order", False)).lower() in ("1", "true", "yes")
    display["contrast"] = int(display.get("contrast", 5))
    display["scroll_delay"] = float(display.get("scroll_delay", 0.05))
    config["display"] = display

    validate_config(config)
    return config


def validate_config(config: dict) -> None:
    if not config.get("wmata_api_key"):
        raise ValueError("WMATA API key is required. Set WMATAKEY env var.")
    if not config.get("station_code"):
        raise ValueError("station_code is required in config.")
    if config.get("refresh_interval", 0) <= 0:
        raise ValueError("refresh_interval must be greater than zero.")
