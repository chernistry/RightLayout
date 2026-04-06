#!/usr/bin/env python3
"""
Generate reverse keycode mapping from layouts.json.
Creates char → (keycode, shift) for each layout.
"""

import json
from pathlib import Path

LAYOUTS_JSON = Path(__file__).parent.parent / "OMFK/Sources/Resources/layouts.json"
OUTPUT = Path(__file__).parent / "keycodes.json"

# Physical keycodes (from KeyboardMapper/main.swift)
KEYCODES = {
    "Digit1": 18, "Digit2": 19, "Digit3": 20, "Digit4": 21, "Digit5": 23,
    "Digit6": 22, "Digit7": 26, "Digit8": 28, "Digit9": 25, "Digit0": 29,
    "Minus": 27, "Equal": 24,
    "KeyQ": 12, "KeyW": 13, "KeyE": 14, "KeyR": 15, "KeyT": 17,
    "KeyY": 16, "KeyU": 32, "KeyI": 34, "KeyO": 31, "KeyP": 35,
    "BracketLeft": 33, "BracketRight": 30, "Backslash": 42,
    "KeyA": 0, "KeyS": 1, "KeyD": 2, "KeyF": 3, "KeyG": 5,
    "KeyH": 4, "KeyJ": 38, "KeyK": 40, "KeyL": 37, "Semicolon": 41, "Quote": 39,
    "KeyZ": 6, "KeyX": 7, "KeyC": 8, "KeyV": 9, "KeyB": 11,
    "KeyN": 45, "KeyM": 46, "Comma": 43, "Period": 47, "Slash": 44,
    "Backquote": 50,
}

# Special keys
SPECIAL_KEYCODES = {
    " ": (49, False),   # Space
    "\t": (48, False),  # Tab
    "\n": (36, False),  # Return
}

def main():
    with open(LAYOUTS_JSON) as f:
        data = json.load(f)
    
    # Build reverse mapping: layout → char → (keycode, shift)
    result = {}
    
    for layout_info in data["layouts"]:
        layout_id = layout_info["id"]
        result[layout_id] = dict(SPECIAL_KEYCODES)
    
    for key_name, layouts in data["map"].items():
        keycode = KEYCODES.get(key_name)
        if keycode is None:
            continue
        
        for layout_id, mapping in layouts.items():
            if layout_id not in result:
                result[layout_id] = dict(SPECIAL_KEYCODES)
            
            # n = normal, s = shift
            if mapping.get("n"):
                result[layout_id][mapping["n"]] = (keycode, False)
            if mapping.get("s"):
                result[layout_id][mapping["s"]] = (keycode, True)
    
    with open(OUTPUT, "w") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    
    # Stats
    print(f"Generated keycodes for {len(result)} layouts")
    for lid, chars in sorted(result.items()):
        print(f"  {lid}: {len(chars)} chars")

if __name__ == "__main__":
    main()
