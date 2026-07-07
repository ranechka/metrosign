import json
import os
import tempfile
import unittest
from unittest.mock import patch

from code.metrosign.config import DEFAULT_CONFIG, load_config, validate_config


class TestConfig(unittest.TestCase):
    def test_load_default_config(self):
        with patch.dict(os.environ, {"WMATAKEY": "dummy-key"}):
            config = load_config(None)

        self.assertEqual(config["wmata_api_key"], "dummy-key")
        self.assertEqual(config["station_code"], "B04")
        self.assertEqual(config["refresh_interval"], 10)
        self.assertEqual(config["display"]["cascaded"], DEFAULT_CONFIG["display"]["cascaded"])

    def test_load_config_file_overrides(self):
        data = {
            "station_code": "A01",
            "refresh_interval": 20,
            "display": {
                "cascaded": 2,
                "block_orientation": 90,
                "rotate": 1,
                "reverse_order": True,
                "contrast": 7,
                "scroll_delay": 0.08,
            },
        }

        with tempfile.NamedTemporaryFile(mode="w+", suffix=".json", delete=False) as f:
            json.dump(data, f)
            config_path = f.name

        try:
            with patch.dict(os.environ, {"WMATAKEY": "env-key"}):
                config = load_config(config_path)

            self.assertEqual(config["wmata_api_key"], "env-key")
            self.assertEqual(config["station_code"], "A01")
            self.assertEqual(config["refresh_interval"], 20)
            self.assertEqual(config["display"]["cascaded"], 2)
            self.assertEqual(config["display"]["block_orientation"], 90)
            self.assertTrue(config["display"]["reverse_order"])
        finally:
            os.remove(config_path)

    def test_validate_config_missing_api_key(self):
        config = DEFAULT_CONFIG.copy()
        config["wmata_api_key"] = ""
        config["station_code"] = "B04"

        with self.assertRaises(ValueError):
            validate_config(config)

    def test_validate_config_invalid_refresh(self):
        config = DEFAULT_CONFIG.copy()
        config["wmata_api_key"] = "dummy"
        config["refresh_interval"] = 0

        with self.assertRaises(ValueError):
            validate_config(config)


if __name__ == "__main__":
    unittest.main()
