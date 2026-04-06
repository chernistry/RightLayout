#!/usr/bin/env python3
"""
Real keyboard typing simulation for OMFK tests.
Types characters via CGEventCreateKeyboardEvent using physical keycodes.
"""

import json
import time
from pathlib import Path

from Quartz import (
    CGEventCreateKeyboardEvent, CGEventPost, CGEventSetFlags,
    kCGHIDEventTap, kCGEventFlagMaskShift
)

KEYCODES_FILE = Path(__file__).parent / "keycodes.json"

# Load keycodes on import
_keycodes = {}
if KEYCODES_FILE.exists():
    with open(KEYCODES_FILE) as f:
        _keycodes = json.load(f)


def get_keycode(char: str, layout: str) -> tuple[int, bool] | None:
    """Get (keycode, shift) for a character in given layout."""
    layout_map = _keycodes.get(layout, {})
    return layout_map.get(char)


def press_key(keycode: int, shift: bool = False, delay: float = 0.015):
    """Press and release a key."""
    flags = kCGEventFlagMaskShift if shift else 0
    
    # Key down
    ev = CGEventCreateKeyboardEvent(None, keycode, True)
    if flags:
        CGEventSetFlags(ev, flags)
    CGEventPost(kCGHIDEventTap, ev)
    time.sleep(delay)
    
    # Key up
    ev = CGEventCreateKeyboardEvent(None, keycode, False)
    if flags:
        CGEventSetFlags(ev, flags)
    CGEventPost(kCGHIDEventTap, ev)
    time.sleep(delay)


def type_char(char: str, layout: str, delay: float = 0.02) -> bool:
    """Type a single character using the layout's keycode mapping."""
    kc = get_keycode(char, layout)
    if kc is None:
        return False
    keycode, shift = kc
    press_key(keycode, shift, delay)
    return True


def type_string(text: str, layout: str, char_delay: float = 0.02) -> tuple[bool, list[str]]:
    """
    Type a string character by character.
    Returns (success, list of chars that couldn't be typed).
    """
    failed = []
    for char in text:
        if not type_char(char, layout, char_delay):
            failed.append(char)
    return len(failed) == 0, failed


def type_word_and_space(word: str, layout: str, char_delay: float = 0.02, space_wait: float = 0.8) -> bool:
    """
    Type a word followed by space, then wait for OMFK to process.
    This is the main test function - simulates real user typing.
    """
    success, failed = type_string(word, layout, char_delay)
    if not success:
        print(f"Warning: couldn't type chars: {failed}")
    
    # Press space (keycode 49)
    press_key(49, False, char_delay)
    
    # Wait for OMFK to detect and correct
    time.sleep(space_wait)
    return success


def get_available_layouts() -> list[str]:
    """Return list of layouts with keycode mappings."""
    return list(_keycodes.keys())


def layout_supports_text(text: str, layout: str) -> tuple[bool, list[str]]:
    """Check if layout can type all characters in text."""
    layout_map = _keycodes.get(layout, {})
    missing = [c for c in text if c not in layout_map]
    return len(missing) == 0, missing


# Quick test
if __name__ == "__main__":
    print(f"Loaded {len(_keycodes)} layouts")
    
    # Test US layout
    print("\nUS layout samples:")
    for char in "hello":
        kc = get_keycode(char, "us")
        print(f"  '{char}' -> keycode {kc}")
    
    # Test Russian layout
    print("\nRussian layout samples:")
    for char in "привет":
        kc = get_keycode(char, "russianwin")
        print(f"  '{char}' -> keycode {kc}")
    
    # Test Hebrew layout
    print("\nHebrew layout samples:")
    for char in "שלום":
        kc = get_keycode(char, "hebrew")
        print(f"  '{char}' -> keycode {kc}")
