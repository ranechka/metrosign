import logging
import requests
from requests.exceptions import RequestException

WMATA_URL = "https://api.wmata.com/StationPrediction.svc/json/GetPrediction/{station_code}"


def fetch_train_data(api_key: str, station_code: str) -> list[dict]:
    headers = {
        "Cache-Control": "no-cache",
        "api_key": api_key,
    }
    url = WMATA_URL.format(station_code=station_code)

    try:
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()
        payload = response.json()
        trains = payload.get("Trains", [])
        return trains
    except RequestException as exc:
        logging.warning("WMATA request failed: %s", exc)
        raise
    except ValueError as exc:
        logging.warning("Failed to parse WMATA response: %s", exc)
        raise


def normalize_train_data(trains: list[dict]) -> dict[str, list[str]]:
    grouped: dict[str, list[str]] = {}
    destination_group: dict[str, int] = {}

    for train in trains:
        destination = train.get("Destination") or "Unknown"
        minutes = train.get("Min")
        if minutes is None:
            minutes = "N/A"
        grouped.setdefault(destination, []).append(str(minutes))

        group = train.get("Group")
        if group is None:
            group = float("inf")
        destination_group[destination] = min(destination_group.get(destination, group), group)

    return dict(
        sorted(
            grouped.items(),
            key=lambda item: (
                destination_group.get(item[0], float("inf")),
                item[0],
            ),
        )
    )
