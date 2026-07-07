import unittest

from code.metrosign.wmata import normalize_train_data


class TestWMATAGrouping(unittest.TestCase):
    def test_normalize_train_data_orders_by_group(self):
        trains = [
            {"Group": 2, "Destination": "Greenbelt", "Min": 3},
            {"Group": 1, "Destination": "Branch Ave", "Min": 5},
            {"Group": 2, "Destination": "Greenbelt", "Min": 12},
            {"Group": None, "Destination": "Unknown", "Min": 0},
        ]

        grouped = normalize_train_data(trains)

        self.assertEqual(
            list(grouped.keys()),
            ["Branch Ave", "Greenbelt", "Unknown"],
        )
        self.assertEqual(grouped["Branch Ave"], ["5"])
        self.assertEqual(grouped["Greenbelt"], ["3", "12"])
        self.assertEqual(grouped["Unknown"], ["0"])


if __name__ == "__main__":
    unittest.main()
