import unittest

from code.metrosign.format import format_train_message


class TestFormat(unittest.TestCase):
    def test_format_train_message_single_destination(self):
        grouped = {"Greenbelt": ["3", "12"]}
        message = format_train_message(grouped)
        self.assertEqual(message, "Greenbelt: 3, 12")

    def test_format_train_message_duplicate_destination_times(self):
        grouped = {"Greenbelt": ["3", "3", "12"]}
        message = format_train_message(grouped)
        self.assertEqual(message, "Greenbelt: 3, 3, 12")

    def test_format_train_message_multiple_destinations(self):
        grouped = {
            "Greenbelt": ["3", "12"],
            "Branch Ave": ["5"],
        }
        message = format_train_message(grouped)
        self.assertIn("Greenbelt: 3, 12", message)
        self.assertIn("Branch Ave: 5", message)
        self.assertTrue("    " in message)


if __name__ == "__main__":
    unittest.main()
