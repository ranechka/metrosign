import logging
import time
from threading import Thread, Event

from .display import create_device, show_startup_message, show_text
from .format import format_train_message
from .wmata import fetch_train_data, normalize_train_data


class MetroSignApp:
    def __init__(self, config: dict):
        self.config = config
        self.console_mode = config.get("console_mode", False)
        self.device = None
        if not self.console_mode:
            try:
                self.device = create_device(config["display"])
            except ModuleNotFoundError as exc:
                logging.warning(
                    "Hardware display unavailable (%s); falling back to console mode.",
                    exc,
                )
                self.console_mode = True
        self.stop_event = Event()
        self.message = config.get("startup_message", "Welcome to MetroSign")
        self.last_update = None

    def start(self):
        logging.info("Starting MetroSign app")
        self.show_startup_message()
        self.poll_thread = Thread(target=self._poll_loop, daemon=True)
        self.poll_thread.start()
        self._display_loop()

    def show_startup_message(self):
        if self.console_mode:
            print("[MetroSign] " + self.message)
        else:
            show_startup_message(self.device, self.message, self.config["display"]["scroll_delay"])

    def _poll_loop(self):
        while not self.stop_event.is_set():
            try:
                trains = fetch_train_data(self.config["wmata_api_key"], self.config["station_code"])
                grouped = normalize_train_data(trains)
                if grouped:
                    self.message = format_train_message(grouped)
                    self.last_update = time.time()
                else:
                    self.message = self.config.get("fallback_message", "No train data available")
            except Exception:
                logging.exception("Failed to refresh train data")
                if self.last_update is None:
                    self.message = self.config.get("fallback_message", "No train data available")
            time.sleep(self.config.get("refresh_interval", 10))

    def _display_loop(self):
        try:
            while not self.stop_event.is_set():
                if self._is_stale():
                    stale_message = self.config.get("stale_message", "Stale data. Check connection.")
                    self._output_message(stale_message)
                else:
                    self._output_message(self.message)

                if self.console_mode:
                    time.sleep(self.config.get("refresh_interval", 10))
        except KeyboardInterrupt:
            self.stop()
        finally:
            self.cleanup()

    def _output_message(self, message: str):
        if self.console_mode:
            print(f"[MetroSign] {message}")
        else:
            show_text(self.device, message, self.config["display"]["scroll_delay"])

    def _is_stale(self) -> bool:
        if self.last_update is None:
            return False
        return (time.time() - self.last_update) > self.config.get("stale_threshold", 60)

    def stop(self):
        logging.info("Stopping MetroSign app")
        self.stop_event.set()

    def cleanup(self):
        logging.info("Cleaning up display")
        if self.console_mode:
            return
        try:
            self.device.cleanup()
        except Exception:
            logging.exception("Failed to cleanup device")
