from typing import Dict, List


def format_train_message(grouped_trains: Dict[str, List[str]]) -> str:
    """Format grouped WMATA train predictions into a display string.

    Example:
        {
            "Branch Ave": ["5"],
            "Greenbelt": ["3", "12"],
        }

    becomes:
        "Branch Ave: 5    Greenbelt: 3, 12"
    """
    parts = []
    for destination, times in grouped_trains.items():
        sorted_times = sorted(times, key=lambda t: int(t) if t.isdigit() else float('inf'))
        part = f"{destination}: {', '.join(sorted_times)}"
        parts.append(part)
    return "    ".join(parts)
