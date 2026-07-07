import argparse
import logging
import os
import sys

if __name__ == "__main__" and __package__ is None:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if repo_root not in sys.path:
        sys.path.insert(0, repo_root)

from code.metrosign.app import MetroSignApp
from code.metrosign.config import load_config


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="MetroSign LED matrix display for WMATA train predictions"
    )
    parser.add_argument("--config", default=None, help="Path to config file")
    parser.add_argument("--station", default=None, help="WMATA station code")
    parser.add_argument(
        "--refresh-interval",
        type=int,
        default=None,
        help="Refresh interval in seconds",
    )
    parser.add_argument(
        "--console",
        action="store_true",
        help="Output text to the console instead of the LED matrix",
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
        help="Logging verbosity",
    )
    return parser


def configure_logging(level: str) -> None:
    logging.basicConfig(
        level=getattr(logging, level),
        format="%(asctime)s %(levelname)s %(message)s",
    )


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    configure_logging(args.log_level)

    try:
        config = load_config(args.config)
        if args.station:
            config["station_code"] = args.station
        if args.refresh_interval is not None:
            config["refresh_interval"] = args.refresh_interval
        config["console_mode"] = args.console

        app = MetroSignApp(config)
        app.start()
        return 0
    except Exception:
        logging.exception("MetroSign failed to start")
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
