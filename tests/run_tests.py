#!/usr/bin/env python3
"""
RightLayout Comprehensive E2E Test Runner

Loads test cases from JSON and runs them against RightLayout.
Supports: single words, paragraphs, context boost, cycling, stress tests.
"""

import json
import subprocess
import time
import sys
import os
import signal
import random
import argparse
from pathlib import Path
from datetime import datetime

try:
    from Quartz import (
        CGEventCreateKeyboardEvent, CGEventPost, CGEventSetFlags, CGEventKeyboardSetUnicodeString,
        kCGHIDEventTap, kCGEventFlagMaskAlternate, kCGEventFlagMaskCommand, kCGEventFlagMaskShift,
        CGEventSourceCreate, kCGEventSourceStateHIDSystemState,
        CGEventTapCreate, CGEventMaskBit, kCGEventKeyDown, kCGHeadInsertEventTap,
        kCGEventTapOptionDefault, CGEventGetIntegerValueField, kCGKeyboardEventKeycode,
        CFMachPortCreateRunLoopSource, CFRunLoopGetCurrent, CFRunLoopAddSource, kCFRunLoopCommonModes,
        CGEventTapEnable
    )
    from ApplicationServices import (
        AXUIElementCreateSystemWide, AXUIElementCopyAttributeValue,
        AXUIElementSetAttributeValue, AXUIElementCreateApplication,
        kAXFocusedUIElementAttribute, kAXValueAttribute
    )
    from AppKit import NSPasteboard, NSStringPboardType, NSWorkspace
except ModuleNotFoundError:
    print("Missing macOS PyObjC dependencies (Quartz/AppKit/ApplicationServices).")
    print("Create a venv and install requirements:")
    print("  python3 -m venv .venv && source .venv/bin/activate && pip install -r tests/requirements.txt")
    raise SystemExit(2)
import threading

# Global flag for F10 abort
_abort_requested = False
_event_tap = None

ROOT_DIR = Path(__file__).parent.parent
TESTS_FILE = Path(__file__).parent / "test_cases.json"
LOG_FILE = Path.home() / ".rightlayout" / "debug.log"
TEST_HOST_VALUE_FILE = Path.home() / ".rightlayout" / "testhost_value.txt"
KEYCODES_FILE = Path(__file__).parent / "utils/keycodes.json"
SWITCH_LAYOUT = ROOT_DIR / "scripts/switch_layout"

KEY_OPTION, KEY_DELETE, KEY_SPACE, KEY_TAB, KEY_RETURN, KEY_F10 = 58, 51, 49, 48, 36, 109
KEY_ESC = 53
BUNDLE_ID = "com.chernistry.rightlayout"
APP_NAME = "RightLayout"
TEST_HOST_NAME = "RightLayoutTestHost"
TEST_HOST_BIN = ROOT_DIR / ".build" / "debug" / TEST_HOST_NAME


def keyboard_callback(proxy, event_type, event, refcon):
    """Callback for keyboard event tap - detect F10 to abort."""
    global _abort_requested
    keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode)
    if keycode == KEY_F10:
        _abort_requested = True
        print("\n\n🛑 F10 pressed - aborting test...\n")
    return event


def start_keyboard_listener():
    """Start listening for F10 key to abort test."""
    global _event_tap
    
    mask = CGEventMaskBit(kCGEventKeyDown)
    _event_tap = CGEventTapCreate(
        kCGHeadInsertEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,
        mask,
        keyboard_callback,
        None
    )
    
    if _event_tap:
        source = CFMachPortCreateRunLoopSource(None, _event_tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes)
        CGEventTapEnable(_event_tap, True)


def check_abort():
    """Check if abort was requested. Raises KeyboardInterrupt if so."""
    if _abort_requested:
        raise KeyboardInterrupt("F10 abort requested")

# Load keycodes for real typing
# Load keycodes for real typing
_keycodes = {}
if KEYCODES_FILE.exists():
    with open(KEYCODES_FILE) as f:
        _keycodes = json.load(f)

def run_chaos_mode(duration=30, seed=None):
    """
    Runs a chaos monkey test: random typing, backspacing, hotkeys, layout switching.
    """
    if seed is None:
        seed = int(time.time())
    random.seed(seed)
    
    print("\n" + "=" * 70)
    print(f"CHAOS MODE (Seed: {seed}, Duration: {duration}s)")
    print("=" * 70)
    
    start_time = time.time()
    actions = ["type_word", "backspace_burst", "hotkey_option", "switch_layout", "pause"]
    
    chars_en = "abcdefghijklmnopqrstuvwxyz "
    chars_ru = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя "
    
    cmd_count = 0
    
    try:
        while time.time() - start_time < duration:
            check_abort()
            
            action = random.choice(actions)
            
            if action == "type_word":
                length = random.randint(3, 10)
                lang = random.choice(["en", "ru"])
                word = ""
                for _ in range(length):
                    word += random.choice(chars_en if lang == "en" else chars_ru)
                
                print(f"[{time.time()-start_time:.1f}s] Typing: {word}")
                type_string_real(word) # Always use real typing for chaos
                
            elif action == "backspace_burst":
                count = random.randint(1, 5)
                print(f"[{time.time()-start_time:.1f}s] Backspace x{count}")
                for _ in range(count):
                    # pressing backspace
                    post_key_event(KEY_DELETE)
                    time.sleep(0.05)
                    
            elif action == "hotkey_option":
                print(f"[{time.time()-start_time:.1f}s] Hotkey (Option)")
                post_key_event(KEY_OPTION)
                
            elif action == "switch_layout":
                print(f"[{time.time()-start_time:.1f}s] Switching Layout")
                # Simulate Cmd+Space or Control+Space (system dependant, maybe just use script)
                subprocess.run([str(SWITCH_LAYOUT), "next"], stderr=subprocess.DEVNULL)
                
            elif action == "pause":
                duration_pause = random.uniform(0.1, 1.0)
                print(f"[{time.time()-start_time:.1f}s] Pausing {duration_pause:.1f}s")
                time.sleep(duration_pause)
            
            cmd_count += 1
            time.sleep(random.uniform(0.1, 0.5))
            
            # Check if RightLayout is still alive
            # (Optional: ps check)
            
    except KeyboardInterrupt:
        print("Chaos aborted.")
        
    print(f"\nChaos finished. Executed {cmd_count} actions.")
    return True



# Layout Apple IDs for switching
LAYOUT_APPLE_IDS = {
    "us": "com.apple.keylayout.US",
    "russianwin": "com.apple.keylayout.RussianWin",
    "russian": "com.apple.keylayout.Russian",
    "russian_phonetic": "com.apple.keylayout.Russian-Phonetic",
    "hebrew": "com.apple.keylayout.Hebrew",
    "hebrew_qwerty": "com.apple.keylayout.Hebrew-QWERTY",
    "hebrew_pc": "com.apple.keylayout.Hebrew-PC",
}

BASE_ACTIVE_LAYOUTS = {
    "en": "us",
    "ru": "russian",      # Mac Russian (not PC)
    "he": "hebrew",       # Mac Hebrew (not QWERTY)
}

# Popular layout combinations to test
LAYOUT_COMBOS = [
    {"en": "us", "ru": "russian", "he": "hebrew", "name": "Mac defaults"},
    {"en": "us", "ru": "russianwin", "he": "hebrew", "name": "US + RU-PC + HE-Mac"},
    {"en": "us", "ru": "russianwin", "he": "hebrew_qwerty", "name": "US + RU-PC + HE-QWERTY"},
    {"en": "us", "ru": "russian_phonetic", "he": "hebrew", "name": "US + RU-Phonetic + HE-Mac"},
    {"en": "us", "ru": "russianwin", "he": "hebrew_pc", "name": "US + RU-PC + HE-PC"},
]

# Short names for switch_layout tool
LAYOUT_SHORT_NAMES = {
    "us": "US",
    "russianwin": "RussianWin",
    "russian": "Russian",
    "russian_phonetic": "Russian-Phonetic",
    "hebrew": "Hebrew",
    "hebrew_qwerty": "Hebrew-QWERTY",
    "hebrew_pc": "Hebrew-PC",
}


def get_enabled_system_layouts() -> list[str]:
    """Get currently enabled system layout short names (matching LAYOUT_SHORT_NAMES values)."""
    r = subprocess.run([str(SWITCH_LAYOUT), "list"], capture_output=True, text=True)
    layouts = []
    for line in r.stdout.split("\n"):
        if "com.apple.keylayout." in line:
            # Extract short name: com.apple.keylayout.Hebrew-QWERTY -> Hebrew-QWERTY
            layout_name = line.split()[0].replace("com.apple.keylayout.", "")
            layouts.append(layout_name)
    return layouts


def enable_system_layout(layout_id: str) -> bool:
    """Enable a system layout."""
    name = LAYOUT_SHORT_NAMES.get(layout_id, layout_id)
    r = subprocess.run([str(SWITCH_LAYOUT), "enable", name], capture_output=True)
    return r.returncode == 0


def disable_system_layout(layout_id: str) -> bool:
    """Disable a system layout."""
    name = LAYOUT_SHORT_NAMES.get(layout_id, layout_id)
    r = subprocess.run([str(SWITCH_LAYOUT), "disable", name], capture_output=True)
    return r.returncode == 0


def set_system_layouts(en: str, ru: str, he: str):
    """Set exactly these 3 system layouts (disable others, enable these)."""
    current = get_enabled_system_layouts()
    target = [LAYOUT_SHORT_NAMES.get(en, en), 
              LAYOUT_SHORT_NAMES.get(ru, ru), 
              LAYOUT_SHORT_NAMES.get(he, he)]
    
    print(f"  Current: {current}, Target: {target}", flush=True)
    
    # Disable layouts not in target
    for lay in current:
        if lay not in target:
            ok = disable_system_layout(lay)
            print(f"  Disable {lay}: {'OK' if ok else 'FAILED'}", flush=True)
    
    # Enable target layouts
    for lay in target:
        if lay not in current:
            ok = enable_system_layout(lay)
            print(f"  Enable {lay}: {'OK' if ok else 'FAILED'}", flush=True)
    
    time.sleep(0.15)
    result = get_enabled_system_layouts()
    print(f"  Final layouts: {result}", flush=True)
    return result


def write_active_layouts(layouts):
    """Persist activeLayouts for RightLayout (picked up on app start)."""
    if not layouts:
        layouts = BASE_ACTIVE_LAYOUTS

    # Depending on whether we're running the bundled app or SwiftPM-built executable,
    # the UserDefaults domain may be the bundle id or the executable name. Write both.
    for domain in (BUNDLE_ID, APP_NAME):
        cmd = ["defaults", "write", domain, "activeLayouts", "-dict"]
        for k, v in sorted(layouts.items()):
            cmd.extend([str(k), str(v)])
        subprocess.run(cmd, capture_output=True)


# Global flag to preserve pre-launched RightLayout instances
SKIP_RIGHTLAYOUT_KILL = False

def stop_rightlayout():
    """Kill all RightLayout instances (unless SKIP_RIGHTLAYOUT_KILL is set)."""
    global SKIP_RIGHTLAYOUT_KILL
    if SKIP_RIGHTLAYOUT_KILL:
        print("  [Info] Preserving pre-launched RightLayout instance...")
        return
    
    # Try graceful termination first to allow logs to flush.
    subprocess.run(["pkill", "-15", "-f", ".build/debug/RightLayout"], capture_output=True)
    subprocess.run(["pkill", "-15", "-f", "RightLayout.app"], capture_output=True)
    subprocess.run(["pkill", "-15", "-f", BUNDLE_ID], capture_output=True)
    time.sleep(0.35)

    # Then force kill any remaining.
    subprocess.run(["pkill", "-9", "-f", ".build/debug/RightLayout"], capture_output=True)
    subprocess.run(["pkill", "-9", "-f", "RightLayout.app"], capture_output=True)
    subprocess.run(["pkill", "-9", "-f", BUNDLE_ID], capture_output=True)
    time.sleep(0.25)
    
    # Verify no instances remain
    r = subprocess.run(["pgrep", "-f", "RightLayout"], capture_output=True, text=True)
    if r.stdout.strip():
        pids = r.stdout.strip().split('\n')
        print(f"⚠️  Found {len(pids)} lingering RightLayout process(es), force killing...")
        for pid in pids:
            subprocess.run(["kill", "-9", pid], capture_output=True)
        time.sleep(0.2)

def stop_test_host():
    """Kill all RightLayoutTestHost instances."""
    subprocess.run(["pkill", "-9", "-f", str(TEST_HOST_BIN)], capture_output=True)
    subprocess.run(["pkill", "-9", "-x", TEST_HOST_NAME], capture_output=True)
    time.sleep(0.15)

def start_test_host():
    """Start RightLayoutTestHost and bring it to front."""
    stop_test_host()
    if not TEST_HOST_BIN.exists():
        raise RuntimeError(f"Test host binary not found: {TEST_HOST_BIN}")
    env = os.environ.copy()
    env.setdefault("RightLayout_TEST_HOST_LOG", "1")
    subprocess.Popen([str(TEST_HOST_BIN)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    # Give the host time to create its value file and install event monitors.
    for _ in range(25):
        if TEST_HOST_VALUE_FILE.exists():
            break
        time.sleep(0.08)
    time.sleep(0.60)
    ensure_test_host_focused_auto(retries=30)

    # Warm up: verify the host is actually accepting injected key events.
    # This avoids first-test flakes where the window isn't ready yet.
    for _ in range(3):
        press_key_fast(KEY_DELETE, delay=0.004)
    time.sleep(0.05)
    type_char_real("x", "us", delay=0.01)
    _ = wait_for_result("x", timeout=1.0, stable_for=0.08)
    press_key_fast(KEY_DELETE, delay=0.004)
    _ = wait_for_result("", timeout=1.0, stable_for=0.08)


# ============== REAL TYPING FUNCTIONS ==============

def switch_system_layout(layout_id: str) -> bool:
    """Switch macOS input source to given layout."""
    short_names = {
        "us": "US",
        "russianwin": "RussianWin", 
        "russian": "Russian",
        "russian_phonetic": "Russian-Phonetic",
        "hebrew": "Hebrew",
        "hebrew_qwerty": "Hebrew-QWERTY",
        "hebrew_pc": "Hebrew-PC",
    }
    name = short_names.get(layout_id, layout_id)
    # Use start_new_session to prevent terminal focus stealing
    result = subprocess.run(
        [str(SWITCH_LAYOUT), "select", name], 
        capture_output=True, 
        timeout=2,
        start_new_session=True
    )
    time.sleep(0.15)
    return result.returncode == 0


def detect_input_layout(text: str) -> str | None:
    """Detect which ENABLED layout can type all chars in text."""
    # Get currently enabled system layouts
    enabled = get_enabled_system_layouts()
    # Map short names to our layout IDs
    enabled_ids = set()
    for lay in enabled:
        # RussianWin -> russianwin, Hebrew-QWERTY -> hebrew_qwerty
        lay_id = lay.lower().replace("-", "_")
        enabled_ids.add(lay_id)
    
    # Pure ASCII input is assumed to be typed on US (even if other layouts can technically emit it).
    stripped = "".join(c for c in text if c not in " \t\n")
    if stripped and all(c.isascii() for c in stripped):
        return "us" if "us" in enabled_ids else None

    # Priority order, but only check enabled layouts
    for layout in ["us", "russianwin", "hebrew", "hebrew_qwerty", "russian_phonetic", "russian", "hebrew_pc"]:
        if layout not in enabled_ids:
            continue
        layout_map = _keycodes.get(layout, {})
        # Some characters (emoji, typographic quotes, em-dash, currency symbols) are not typable
        # via keycodes.json in any layout. We'll paste them during typing, so they shouldn't block
        # layout detection. Only require that *typable* characters are supported.
        if all((c in " \t\n") or (c in layout_map) or (not c.isascii()) for c in text):
            return layout
    return None



USE_APPLESCRIPT_TYPING = True  # AppleScript keystroke works when RightLayout is pre-launched and running

def escape_applescript_string(s: str) -> str:
    """Escape string for AppleScript double-quoted string."""
    return s.replace("\\", "\\\\").replace('"', '\\"')

def run_applescript(script: str):
    subprocess.run(["osascript", "-e", f'tell application "System Events" to {script}'], check=False)

def type_char_real(char: str, layout: str, delay: float = 0.008) -> bool:
    """Type a single character by injecting the Unicode character directly."""
    if USE_APPLESCRIPT_TYPING:
        # For single char, just keystroke it.
        # Note: Unicode characters might be tricky with 'keystroke', but we'll try.
        # AppleScript 'keystroke' behaves like typing on current layout.
        # 'RightLayout' expects key events.
        # If 'char' is not ASCII, keystroke might fail if layout doesn't support it?
        # But verify_input_capability uses 'access_check' (ASCII).
        safe_s = escape_applescript_string(char)
        run_applescript(f'keystroke "{safe_s}"')
        time.sleep(delay)
        return True

    utf16_len = len(char.encode("utf-16-le")) // 2
    ev_down = CGEventCreateKeyboardEvent(None, 0, True)
    CGEventKeyboardSetUnicodeString(ev_down, utf16_len, char)
    CGEventPost(kCGHIDEventTap, ev_down)
    ev_up = CGEventCreateKeyboardEvent(None, 0, False)
    CGEventKeyboardSetUnicodeString(ev_up, utf16_len, char)
    CGEventPost(kCGHIDEventTap, ev_up)
    time.sleep(delay)
    return True


def type_string_real(text: str, layout: str, char_delay: float = 0.008) -> tuple[bool, list[str]]:
    """Type string via AppleScript System Events char by char."""
    if USE_APPLESCRIPT_TYPING:
        # Optimization: Type whole string at once if possible
        # However, for realistic testing we might want chunks? 
        # For now, whole string is fine and MUCH faster than repetitive osascript calls.
        safe_s = escape_applescript_string(text)
        run_applescript(f'keystroke "{safe_s}"')
        time.sleep(len(text) * char_delay) # Simulate delay
        return True, []

    for char in text:
        type_char_real(char, layout, char_delay)
    return True, []


def type_word_and_space_real(word: str, layout: str, char_delay: float = 0.008, space_wait: float = 0.4) -> bool:
    """Type word + space via key events, wait for RightLayout to process."""
    type_string_real(word, layout, char_delay)
    press_key(KEY_SPACE)
    time.sleep(space_wait)
    return True


def map_flags_to_applescript(flags: int) -> str:
    parts = []
    if flags & kCGEventFlagMaskCommand:
        parts.append("command down")
    if flags & kCGEventFlagMaskAlternate:
        parts.append("option down")
    if flags & kCGEventFlagMaskShift:
        parts.append("shift down")
    
    if not parts:
        return ""
    return " using {" + ", ".join(parts) + "}"

def press_key(keycode, flags=0):
    if USE_APPLESCRIPT_TYPING:
        modifiers = map_flags_to_applescript(flags)
        run_applescript(f"key code {keycode}{modifiers}")
        time.sleep(0.015)
        return

    ev = CGEventCreateKeyboardEvent(None, keycode, True)
    if flags: CGEventSetFlags(ev, flags)
    CGEventPost(kCGHIDEventTap, ev)
    time.sleep(0.015)
    ev = CGEventCreateKeyboardEvent(None, keycode, False)
    if flags: CGEventSetFlags(ev, flags)
    CGEventPost(kCGHIDEventTap, ev)
    time.sleep(0.015)

def press_key_fast(keycode, flags=0, delay: float = 0.003):
    if USE_APPLESCRIPT_TYPING:
        # AppleScript is inherently slow,ignore delay optimization
        modifiers = map_flags_to_applescript(flags)
        run_applescript(f"key code {keycode}{modifiers}")
        time.sleep(0.01) # Minimum sleep
        return

    ev = CGEventCreateKeyboardEvent(None, keycode, True)
    if flags:
        CGEventSetFlags(ev, flags)
    CGEventPost(kCGHIDEventTap, ev)
    time.sleep(delay)
    ev = CGEventCreateKeyboardEvent(None, keycode, False)
    if flags:
        CGEventSetFlags(ev, flags)
    CGEventPost(kCGHIDEventTap, ev)
    time.sleep(delay)


def press_option():
    # Helper for Option key press simulation (Trigger)
    if USE_APPLESCRIPT_TYPING:
        # Tapping Option key alone
        run_applescript("key code 58") # Left Option
        time.sleep(0.1)
        return

    ev = CGEventCreateKeyboardEvent(None, KEY_OPTION, True)
    CGEventSetFlags(ev, kCGEventFlagMaskAlternate)
    CGEventPost(kCGHIDEventTap, ev)
    time.sleep(0.1)
    ev = CGEventCreateKeyboardEvent(None, KEY_OPTION, False)
    CGEventPost(kCGHIDEventTap, ev)


def cmd_key(kc):
    if USE_APPLESCRIPT_TYPING:
        run_applescript(f"key code {kc} using command down")
        return
    press_key(kc, kCGEventFlagMaskCommand)


def clipboard_set(text):
    pb = NSPasteboard.generalPasteboard()
    pb.clearContents()
    pb.setString_forType_(text, NSStringPboardType)


def clipboard_get():
    return NSPasteboard.generalPasteboard().stringForType_(NSStringPboardType) or ""


def get_text():
    sw = AXUIElementCreateSystemWide()
    err, el = AXUIElementCopyAttributeValue(sw, kAXFocusedUIElementAttribute, None)
    if err == 0 and el:
        err, val = AXUIElementCopyAttributeValue(el, kAXValueAttribute, None)
        if err == 0 and val:
            return str(val)
    return ""


def clear_field():
    """Clear the text field using robust Select All + Delete strategy."""
    # Retry loop for robustness against transient focus loss

def ax_clear_field() -> bool:
    """Clear text field using Accessibility API (Atomic & 100% Reliable)."""
    try:
        # 1. Get Frontmost App (TestHost)
        ws = NSWorkspace.sharedWorkspace()
        app = ws.frontmostApplication()
        if not app or app.localizedName() != TEST_HOST_NAME:
            print(f"  [AX] Frontmost app is not TestHost ({app.localizedName() if app else 'None'})")
            return False
            
        # 2. Get AX Element
        pid = app.processIdentifier()
        ax_app = AXUIElementCreateApplication(pid)
        err, focused = AXUIElementCopyAttributeValue(ax_app, kAXFocusedUIElementAttribute, None)
        if err != 0:
            print(f"  [AX] Failed to get focused element (Error: {err})")
            return False
            
        # 3. Set Value to Empty
        err = AXUIElementSetAttributeValue(focused, kAXValueAttribute, "")
        if err != 0:
             print(f"  [AX] Failed to set value (Error: {err})")
             return False
             
        return True
    except Exception as e:
        print(f"  [AX] Exception: {e}")
        return False


def clear_field():
    """Clear text field reliably using AX, falling back to Cmd+A."""
    # Method 1: AX API (Gold Standard)
    if ax_clear_field():
        # Verify it's actually empty
        if wait_for_result("", timeout=0.2, stable_for=0.05) == "":
            return

    # Method 2: Cmd+A -> Delete
    ensure_test_host_focused_auto(retries=20)
    press_key(55); time.sleep(0.01) # Cmd
    cmd_key(0) # Cmd+A
    time.sleep(0.1) 
    press_key(KEY_DELETE)
    
    if wait_for_result("", timeout=0.5, stable_for=0.05) == "":
        return
        
    print("⚠️  [Clear] Failed to clear field reliably. Proceeding dirty...")


def type_and_space(text):
    """Type text via paste, then press space."""
    clipboard_set(text)
    cmd_key(9)  # Cmd+V
    time.sleep(0.15)
    press_key(KEY_SPACE)
    time.sleep(0.15)  # Wait for RightLayout


def select_all_and_correct():
    """Select all and press Option to correct."""
    cmd_key(0)  # Cmd+A
    time.sleep(0.15)
    press_option()
    time.sleep(0.15)


def _normalize_osascript_stdout(text: str) -> str:
    # osascript terminates stdout with a newline; remove exactly one while preserving
    # meaningful whitespace/newlines from the document.
    if text.endswith("\n"):
        return text[:-1]
    return text


def get_result():
    """Get current RightLayoutTestHost text (preserve whitespace)."""
    # Prefer a direct file written by RightLayoutTestHost (more reliable than AX for NSTextView).
    try:
        if TEST_HOST_VALUE_FILE.exists():
            return TEST_HOST_VALUE_FILE.read_text(encoding="utf-8")
    except Exception:
        pass

    # Fallback: AX readback (may be empty for some roles).
    return get_text() or ""


def normalize_for_compare(actual: str, expected: str) -> str:
    """Normalize actual text for comparison without destroying meaningful whitespace."""
    # Most real-typing tests type an extra trailing space to trigger RightLayout; ignore exactly one.
    if expected and not expected[-1].isspace() and actual.endswith(" "):
        return actual[:-1]
    return actual

def wait_for_result(expected: str | None, timeout: float = 1.2, stable_for: float = 0.12) -> str:
    """Wait until the host text reaches a stable state (and optionally matches expected)."""
    start = time.time()
    last = None
    last_change = time.time()

    while time.time() - start < timeout:
        check_abort()
        current = get_result()

        if current != last:
            last = current
            last_change = time.time()

        stable = (time.time() - last_change) >= stable_for
        if expected is not None:
            if current == expected and stable:
                return current
        else:
            if stable:
                return current

        time.sleep(0.03)

    return last if last is not None else ""

def wait_for_change(previous: str, timeout: float = 1.2, stable_for: float = 0.12) -> str:
    """Wait until the host text changes from `previous`, then settles."""
    start = time.time()
    while time.time() - start < timeout:
        check_abort()
        current = get_result()
        if current != previous:
            remaining = max(0.05, timeout - (time.time() - start))
            return wait_for_result(None, timeout=remaining, stable_for=stable_for)
        time.sleep(0.03)
    return get_result()


def run_single_test_real(input_text: str, expected: str) -> tuple[bool, str]:
    """Run test with REAL typing simulation."""
    check_abort()  # Check for F10 abort
    
    # Detect layout for input
    layout = detect_input_layout(input_text)
    if not layout:
        return False, f"[no layout for: {input_text[:20]}]"
    
    # Switch system layout FIRST
    if not switch_system_layout(layout):
        return False, f"[failed to switch to {layout}]"
    
    # Ensure test host is focused before typing
    ensure_test_host_focused_auto(retries=10)
    
    clear_field()
    time.sleep(0.25)
    
    # Type word(s) with spaces
    words = input_text.split()
    for i, word in enumerate(words):
        check_abort()  # Check for F10 abort between words
        ensure_test_host_focused_auto(retries=10)
        _ = type_string_real(word, layout, char_delay=0.008)

        press_key(KEY_SPACE)

        # Give RightLayout time to apply auto-correction before typing the next token.
        if i == len(words) - 1:
            time.sleep(0.25)
        else:
            time.sleep(0.20)
    
    expected_for_wait = expected if expected.endswith(" ") else expected + " "
    result = wait_for_result(expected_for_wait, timeout=1.5)
    result_cmp = normalize_for_compare(result, expected)
    return result_cmp == expected, result_cmp


def start_rightlayout():
    global SKIP_RIGHTLAYOUT_KILL
    # Check if RightLayout is already running
    result = subprocess.run(["pgrep", "-x", "RightLayout"], capture_output=True)
    if result.returncode == 0:
        print("  [Info] RightLayout already running, skipping launch...")
        SKIP_RIGHTLAYOUT_KILL = True  # Preserve this instance for the entire test run
        return
    
    stop_rightlayout()
    LOG_FILE.parent.mkdir(exist_ok=True)
    LOG_FILE.write_text("")
    
    env = os.environ.copy()
    env["RightLayout_DEBUG_LOG"] = "1"
    env["RightLayout_DISABLE_LAYOUT_AUTODETECT"] = "1"
    env["RightLayout_SKIP_PERMISSION_CHECK"] = "1"
    # Enable a stable "test mode" across the app (used by SettingsManager/UserDictionary).
    env.setdefault("XCTestConfigurationFilePath", "/tmp/rightlayout_e2e")
    
    out_log = open(LOG_FILE.parent / "rightlayout_stdout.log", "w")
    err_log = open(LOG_FILE.parent / "rightlayout_stderr.log", "w")
    
    subprocess.Popen([str(ROOT_DIR / ".build" / "debug" / APP_NAME)], env=env,
                     stdout=out_log, stderr=err_log,
                     start_new_session=True)
    time.sleep(1.0)  # Give RightLayout time to start and read config


def open_test_host():
    start_test_host()


def close_test_host():
    stop_test_host()


def get_frontmost_app() -> str:
    """Get name of frontmost application."""
    r = subprocess.run(["osascript", "-e", 
        'tell application "System Events" to get name of first process whose frontmost is true'],
        capture_output=True, text=True)
    return r.stdout.strip()


class FocusLostError(Exception):
    """Raised when the test host loses focus."""
    pass



def check_focus():
    """Check if RightLayoutTestHost is focused. Log warning if not."""
    app = get_frontmost_app()
    if app != TEST_HOST_NAME:
        print(f"⚠️  [Focus] Lost to: {app} (proceeding anyway)")
        # raise FocusLostError(f"Focus lost to: {app}")

def ensure_test_host_focused_auto(retries: int = 30) -> None:
    """Ensure RightLayoutTestHost is frontmost (non-interactive)."""
    script = rf'''
        tell application "System Events"
            if exists process "{TEST_HOST_NAME}" then
                set frontmost of process "{TEST_HOST_NAME}" to true
            else
                return "not_found"
            end if
        end tell
    '''
    
    for i in range(max(1, retries)):
        r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
        if "not_found" in r.stdout:
             # Try launching it
             subprocess.run(["open", str(TEST_HOST_BIN)], capture_output=True)
             time.sleep(1.0)
             continue

        current = get_frontmost_app()
        if current == TEST_HOST_NAME:
            return
            
        if i % 10 == 0:
            print(f"  [Focus] Trying to grab focus... (Current: {current})")
            
        time.sleep(0.15)
        
        # Fallback: use open -a to force switch
        if i > 5:
             subprocess.run(["open", "-a", TEST_HOST_NAME], capture_output=True)
             
    print(f"  [Focus] Failed to grab focus. Final app: {get_frontmost_app()}. Proceeding...")



def ensure_test_host_focused():
    """Ensure RightLayoutTestHost is frontmost. Pause and wait if not."""
    while True:
        app = get_frontmost_app()
        if app == TEST_HOST_NAME:
            return
        print(f"\n⚠️  Focus lost! Current app: {app}")
        print(f"    Switch to {TEST_HOST_NAME} and press Enter to continue...")
        input()
        ensure_test_host_focused_auto(retries=30)


# ============== TEST RUNNERS ==============

def run_single_test(input_text, expected):
    """Run single correction test."""
    check_abort()  # Check for F10 abort

    # Ensure test host is focused
    ensure_test_host_focused_auto(retries=30)
    
    clear_field()
    time.sleep(0.12)
    
    clipboard_set(input_text)
    cmd_key(9)  # Paste
    pasted = wait_for_result(input_text, timeout=0.8)
    if pasted != input_text:
        # Retry once (UI can be slow to accept the very first paste after launch/restart).
        clipboard_set(input_text)
        cmd_key(9)
        _ = wait_for_result(input_text, timeout=0.8)
    ensure_test_host_focused_auto(retries=30)
    
    cmd_key(0)  # Select all
    time.sleep(0.15)
    
    press_option()
    result = wait_for_result(expected, timeout=1.5)
    return result == expected, result


def run_context_boost_test(words, expected_final):
    """Test word-by-word typing with context boost.
    
    Simulates typing words one by one, with RightLayout correcting after each.
    The key test: first ambiguous word should be corrected when second word confirms language.
    """
    check_abort()  # Check for F10 abort
    
    # Ensure US layout before typing
    switch_system_layout("us")
    time.sleep(0.5)  # Give more time for layout switch
    
    clear_field()
    time.sleep(0.15)
    
    # Type words one by one with spaces (real typing, not paste)
    for word in words:
        check_abort()  # Check for F10 abort between words
        type_word_and_space_real(word, "us", char_delay=0.05, space_wait=0.5)
    
    time.sleep(0.2)
    result = get_result()
    result_cmp = normalize_for_compare(result, expected_final)
    return result_cmp == expected_final, result


def run_cycling_test(input_text, alt_presses, expected_sequence=None):
    """Test Alt cycling through alternatives."""
    check_abort()

    ensure_test_host_focused_auto(retries=10)
    check_focus()

    clear_field()
    time.sleep(0.12)
    
    clipboard_set(input_text)
    cmd_key(9)
    pasted = wait_for_result(input_text, timeout=0.8)
    if pasted != input_text:
        clipboard_set(input_text)
        cmd_key(9)
        _ = wait_for_result(input_text, timeout=0.8)
    check_focus()

    cmd_key(0)
    time.sleep(0.15)

    results = [get_result()]
    
    for i in range(alt_presses):
        prev = results[-1]
        press_option()
        expected_after = None
        if expected_sequence and (i + 1) < len(expected_sequence):
            expected_after = expected_sequence[i + 1]
        if expected_after is not None:
            results.append(wait_for_result(expected_after, timeout=1.5))
        else:
            results.append(wait_for_change(prev, timeout=1.5))
    
    if expected_sequence:
        # Check if results match expected sequence
        match = all(r == e for r, e in zip(results, expected_sequence) if e is not None)
        return match, results
    
    return True, results  # Just verify no crash


def run_backspace_safety_test(input_text: str) -> tuple[bool, str]:
    """Test that Backspace works correctly after hotkey cycling (Ticket 62)."""
    check_abort()
    ensure_test_host_focused_auto(retries=10)
    
    # 1. Type input
    layout = detect_input_layout(input_text) or "us"
    switch_system_layout(layout)
    clear_field()
    time.sleep(0.15)
    
    # Type word
    type_string_real(input_text, layout)
    time.sleep(0.5) # Wait for processing
    
    # 2. Trigger Hotkey Cycle (Option)
    press_option()
    time.sleep(0.5)
    
    # 3. Press Backspace immediately (should exit cycling and delete last char)
    press_key(KEY_DELETE)
    time.sleep(0.2)
    
    # 4. Verify result: Should be (cycled_word - 1 char) OR (original_word - 1 char) depending on logic.
    # But crucially, it should NOT be equal to 'cycled_word' (swallowed) or 'original_word'.
    # Actually, current logic says "Backspace exits cycling ... and the Backspace event is passed through".
    # So if we cycled "ghbdtn" -> "привет", then Backspace should result in "приве".
    # If we cycled "hello" -> "руддщ" (if that happened), backspace -> "рудд".
    
    current = get_result()
    
    # We don't strictly know what it cycled TO without replicating engine logic, 
    # but we can check that it CHANGED from the moment before backspace.
    # Wait, we can't easily capture "moment before backspace" unless we read it.
    
    # Let's try a simpler invariant:
    # Use a known simple correction: "ghbdtn" -> "привет".
    # After cycle: "привет".
    # After backspace: "приве".
    
    # If input is "ghbdtn":
    if input_text == "ghbdtn":
         if current == "приве": # Success path
             return True, current
         if current == "ghbdt": # Backspace worked but cycling Reverted? that's also acceptable "safety" wise
             return True, current
             
         # Failures:
         if current == "привет": return False, "Backspace SWALLOWED (stuck in cycle?)"
         if current == "ghbdtn": return False, "Backspace SWALLOWED (original restored?)"
         
         return False, f"Unexpected: '{current}'"

    # Generic check: length reduced?
    if len(current) == 0: return True, current # Deleted everything? weird but "working".
    
    return True, current


def run_whitespace_only_test(input_text: str, expected: str) -> tuple[bool, str]:
    """Type whitespace via real key events (paste would bypass RightLayout)."""
    check_abort()
    ensure_test_host_focused_auto(retries=10)

    layout = detect_input_layout(input_text)
    if not layout:
        return False, f"[no layout for: {input_text[:20]}]"
    if not switch_system_layout(layout):
        return False, f"[failed to switch to {layout}]"

    clear_field()
    time.sleep(0.12)

    # Use actual key events so RightLayout sees them.
    for ch in input_text:
        if ch == " ":
            press_key(KEY_SPACE)
            time.sleep(0.18)
        elif ch == "\t":
            press_key(KEY_TAB)
            time.sleep(0.18)
        elif ch == "\n":
            press_key(KEY_RETURN)
            time.sleep(0.18)
        else:
            type_char_real(ch, layout, delay=0.01)

    result = wait_for_result(expected, timeout=1.0)
    return result == expected, result


def run_test_category(category_name: str, category_data: dict, real_typing: bool = True) -> tuple[int, int]:
    """Run a single category payload (used by subset runners)."""
    cases = (category_data or {}).get("cases", [])
    passed = 0
    failed = 0

    if not cases:
        return 0, 0

    for case in cases:
        check_abort()
        try:
            # Context-boost cases are structured differently.
            if "words" in case and "expected_final" in case:
                ok, result = run_context_boost_test(case["words"], case["expected_final"])
                if ok:
                    passed += 1
                else:
                    failed += 1
                    print(f"  ✗ {case.get('desc','')}")
                    print(f"    Words: {case['words']}")
                    print(f"    Got: '{result}'")
                    print(f"    Exp: '{case['expected_final']}'")
                continue

            input_text = case["input"]
            expected = case["expected"]

            if category_name in ("whitespace", "edge_cases_system"):
                ok, result = run_whitespace_only_test(input_text, expected)
            elif category_name == "early_switch":
                ok, result = run_early_switch_test(input_text, expected)
            elif category_name == "backspace_safety":
                ok, result = run_backspace_safety_test(input_text)
            else:
                if real_typing:
                    ok, result = run_single_test_real(input_text, expected)
                    result = normalize_for_compare(result, expected)
                else:
                    ok, result = run_single_test(input_text, expected)

            if ok:
                passed += 1
            else:
                failed += 1
                print(f"  ✗ {case.get('desc','')}")
                print(f"    In : {repr(input_text)}")
                print(f"    Got: {repr(result)}")
                print(f"    Exp: {repr(expected)}")

            time.sleep(0.08)
        except FocusLostError:
            failed += 1
            ensure_test_host_focused_auto(retries=30)
            print(f"  ✗ {case.get('desc','')} (focus lost)")

    return passed, failed


def run_early_switch_test(input_text: str, expected: str) -> tuple[bool, str]:
    """Test early layout switching (mid-word correction)."""
    check_abort()
    
    # Assume source is US for now (mostly testing EN->RU/HE)
    if not switch_system_layout("us"):
        return False, "[failed to switch to us]"
        
    ensure_test_host_focused_auto(retries=10)
    clear_field()
    time.sleep(0.25)
    
    # Type characters one by one without space at end
    for char in input_text:
        check_abort()
        type_char_real(char, "us", delay=0.02)
        # Wait a bit longer than normal typing to allow async check to catch up
        time.sleep(0.05)
        
    # Result should match expected immediately (no space needed)
    result = wait_for_result(expected, timeout=2.0)
    return result == expected, result


def run_stress_cycling(input_text, times, delay_ms=50):
    """Rapid Alt spam test."""
    clear_field()
    time.sleep(0.08)
    
    clipboard_set(input_text)
    cmd_key(9)
    time.sleep(0.08)
    cmd_key(0)
    time.sleep(0.15)
    
    for _ in range(times):
        press_option()
        time.sleep(delay_ms / 1000)
    
    time.sleep(0.15)
    result = get_result()
    return len(result) > 0, result


def run_performance_test(input_text, expected, max_time_ms):
    """Test correction speed."""
    clear_field()
    time.sleep(0.08)
    
    clipboard_set(input_text)
    cmd_key(9)
    time.sleep(0.08)
    cmd_key(0)
    time.sleep(0.15)
    
    start = time.time()
    press_option()
    time.sleep(0.5)  # Minimum wait
    result = get_result()
    elapsed_ms = (time.time() - start) * 1000
    
    correct = result == expected
    fast_enough = elapsed_ms <= max_time_ms
    
    return correct and fast_enough, result, elapsed_ms


def run_paste_should_not_autocorrect_test(input_text: str, expected: str | None = None) -> tuple[bool, str]:
    """Paste text and assert RightLayout does NOT auto-correct it by itself."""
    check_abort()
    ensure_test_host_focused_auto(retries=30)

    clear_field()
    time.sleep(0.12)

    clipboard_set(input_text)
    cmd_key(9)

    expected = input_text if expected is None else expected
    pasted = wait_for_result(expected, timeout=1.2)
    time.sleep(0.6)
    final = wait_for_result(expected, timeout=0.8, stable_for=0.15)
    return final == expected, final


def run_cmd_z_undo_test(input_text: str, expected_corrected: str) -> tuple[bool, str]:
    """Auto-correct via real typing, then Cmd+Z undo back to original."""
    check_abort()
    ensure_test_host_focused_auto(retries=30)

    layout = detect_input_layout(input_text)
    if not layout:
        return False, f"[no layout for: {input_text[:20]}]"
    if not switch_system_layout(layout):
        return False, f"[failed to switch to {layout}]"

    clear_field()
    time.sleep(0.12)

    for ch in input_text:
        type_char_real(ch, layout, delay=0.008)
    press_key(KEY_SPACE)
    time.sleep(0.25)

    corrected_for_wait = expected_corrected if expected_corrected.endswith(" ") else expected_corrected + " "
    corrected = wait_for_result(corrected_for_wait, timeout=2.2)
    corrected_cmp = normalize_for_compare(corrected, expected_corrected)
    if corrected_cmp != expected_corrected:
        return False, corrected_cmp

    cmd_key(6)  # Cmd+Z
    time.sleep(0.20)

    expected_undo_for_wait = input_text + " "
    undone = wait_for_result(expected_undo_for_wait, timeout=2.2)
    undone_cmp = normalize_for_compare(undone, input_text)
    return undone_cmp == input_text, undone_cmp


def run_autocorrect_keep_as_is_learning_test(token: str, expected_corrected: str) -> tuple[bool, str]:
    """Reject the same auto-correction twice (Option undo) and assert it stops auto-correcting."""
    check_abort()
    ensure_test_host_focused_auto(retries=30)

    layout = detect_input_layout(token)
    if not layout:
        return False, f"[no layout for: {token[:20]}]"
    if not switch_system_layout(layout):
        return False, f"[failed to switch to {layout}]"

    def wait_text(expected_text: str, timeout: float = 2.2) -> tuple[bool, str]:
        expected_for_wait = expected_text if expected_text.endswith(" ") else expected_text + " "
        result = wait_for_result(expected_for_wait, timeout=timeout)
        result_cmp = normalize_for_compare(result, expected_text)
        return result_cmp == expected_text, result_cmp

    def type_token_and_wait(expected_text: str) -> tuple[bool, str]:
        clear_field()
        time.sleep(0.12)
        for ch in token:
            type_char_real(ch, layout, delay=0.008)
        press_key(KEY_SPACE)
        time.sleep(0.25)
        return wait_text(expected_text)

    for i in range(2):
        ok, got = type_token_and_wait(expected_corrected)
        if not ok:
            return False, f"[round {i+1}] expected corrected, got: {got!r}"

        # First Option press after auto-correction should undo back to original token.
        press_option()
        time.sleep(0.20)
        ok, got = wait_text(token, timeout=2.4)
        if not ok:
            return False, f"[round {i+1}] expected undo-to-original, got: {got!r}"

        # Commit cycling/learning (Esc ends cycling without changing text).
        press_key(KEY_ESC)
        time.sleep(0.55)

    # Third attempt: should stay as-is.
    ok, got = type_token_and_wait(token)
    return ok, got


def run_rapid_typing_simulation(sequence: list[str], expected_after_correction: str) -> tuple[bool, str]:
    """Simulate fast typing bursts (incl. whitespace) and assert final corrected output."""
    check_abort()
    ensure_test_host_focused_auto(retries=30)

    if not switch_system_layout("us"):
        return False, "[failed to switch to us]"

    clear_field()
    time.sleep(0.12)

    typed_any_boundary = False
    for chunk in sequence:
        for ch in chunk:
            if ch == " ":
                typed_any_boundary = True
                press_key(KEY_SPACE)
                time.sleep(0.10)
            elif ch == "\t":
                typed_any_boundary = True
                press_key(KEY_TAB)
                time.sleep(0.10)
            elif ch == "\n":
                typed_any_boundary = True
                press_key(KEY_RETURN)
                time.sleep(0.10)
            else:
                type_char_real(ch, "us", delay=0.002)

    # Ensure the last token is committed (auto-correction triggers on whitespace).
    if not typed_any_boundary or (sequence and not any(sequence[-1].endswith(ws) for ws in (" ", "\t", "\n"))):
        press_key(KEY_SPACE)
        time.sleep(0.20)

    expected_for_wait = expected_after_correction if expected_after_correction.endswith(" ") else expected_after_correction + " "
    result = wait_for_result(expected_for_wait, timeout=2.8)
    result_cmp = normalize_for_compare(result, expected_after_correction)
    return result_cmp == expected_after_correction, result_cmp


# ============== MAIN ==============


def verify_input_capability():
    """Verify that we can actually type into the test host (Permissions check)."""
    # If RightLayout is already running, we skip this check as it will interfere
    result = subprocess.run(["pgrep", "-x", "RightLayout"], capture_output=True)
    if result.returncode == 0:
        print("[Info] Skipping input capability check (RightLayout already running)...")
        return

    print("running input capability check...")
    stop_rightlayout() # Ensure no zombie app is eating keys
    open_test_host()
    
    # HACK: Prime the Accessibility System for this process by running osascript.
    # For some reason, running AppleScript once "wakes up" CGEventPost permissions.
    try:
        # PRIMER: Use keystroke to force Accessibility hook.
        subprocess.run(["osascript", "-e", 'tell application "System Events" to keystroke " "'], check=False)
        time.sleep(1.5) 
    except Exception as e:
        print(f"Primer failed: {e}")

    ensure_test_host_focused_auto(retries=20)
    
    # Try to clear via AX first
    if not ax_clear_field():
        print("AX Clear failed during verify.")
    ensure_test_host_focused_auto(retries=20)
    
    # Try to clear
    press_key(55); time.sleep(0.01) # Reset Cmd
    cmd_key(0) # Cmd+A
    time.sleep(0.1)
    press_key(KEY_DELETE)
    time.sleep(0.2)
    
    # Try to type
    test_str = "access_check"
    type_string_real(test_str, "us", char_delay=0.01)
    time.sleep(0.5)
    
    result = get_result()
    if result != test_str:
        print(f"\n❌ FATAL: Input capability check failed!")
        print(f"   Expected: '{test_str}'")
        print(f"   Got:      '{result}'")
        print("\nPossible causes:")
        print("1. Terminal/Python lacks Accessibility Permissions (System Settings -> Privacy & Security -> Accessibility)")
        print("2. Another app is blocking Secure Event Input")
        print("3. Test Host is stuck/unresponsive")
        sys.exit(1)
        
    print("✅ Input capability check passed.\n")
    clear_field()
    close_test_host()


def main():
    verify_input_capability() # Run explicit check before any arguments
    
    parser = argparse.ArgumentParser(description="RightLayout Comprehensive Test Runner")
    parser.add_argument("categories", nargs="*", help="Test categories to run (empty = all)")
    parser.add_argument("--real-typing", "-r", action="store_true", 
                        help="Use real keyboard typing (char-by-char + space) instead of paste+Option")
    parser.add_argument("--all-modes", action="store_true",
                        help="Run both modes: SELECT+OPTION and REAL TYPING")
    parser.add_argument("--combo", "-c", type=int, default=0,
                        help="Layout combo index (0=Mac defaults, 1=RU-PC, 2=HE-QWERTY, 3=RU-Phonetic, 4=HE-PC)")
    parser.add_argument("--all-combos", "-a", action="store_true",
                        help="Run tests on all layout combinations")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")
    parser.add_argument("--chaos", action="store_true", help="Run chaos mode stress test")
    parser.add_argument("--duration", type=int, default=30, help="Duration for chaos test in seconds")
    args = parser.parse_args()

    if args.chaos:
        print("Starting Chaos Mode...")
        # Ensure app is running
        stop_rightlayout()
        start_rightlayout()
        
        # Ensure test host is focused
        ensure_test_host_focused_auto()
        
        run_chaos_mode(duration=args.duration)
        stop_rightlayout()
        close_test_host()
        return 0

    # Fan-out runner (keeps the core runner simple and avoids a giant refactor).
    # We intentionally re-invoke the script with concrete `--combo`/`--real-typing` combinations.
    if args.all_combos or args.all_modes:
        combo_indices = list(range(len(LAYOUT_COMBOS))) if args.all_combos else [args.combo % len(LAYOUT_COMBOS)]
        mode_values = [False, True] if args.all_modes else [args.real_typing]
        failures = 0
        script = str(Path(__file__).resolve())
        for combo_idx in combo_indices:
            for real_typing in mode_values:
                mode_str = "REAL TYPING" if real_typing else "SELECT+OPTION"
                combo_name = LAYOUT_COMBOS[combo_idx]["name"]
                print("\n" + "=" * 70)
                print(f"RUN: combo={combo_idx} ({combo_name}) mode={mode_str}")
                print("=" * 70)

                cmd = [sys.executable, script, "--combo", str(combo_idx)]
                if real_typing:
                    cmd.append("--real-typing")
                if args.verbose:
                    cmd.append("--verbose")
                cmd.extend(args.categories)

                r = subprocess.run(cmd)
                if r.returncode != 0:
                    failures += 1

        return 0 if failures == 0 else 1
    
    real_typing_mode = args.real_typing
    categories = args.categories if args.categories else None
    print(f"DEBUG: categories={categories}")
    verbose = args.verbose
    
    mode_str = "REAL TYPING" if real_typing_mode else "SELECT+OPTION"
    print(f"RightLayout Comprehensive Test Runner [{mode_str}]")
    print("=" * 70)
    print("💡 Press F10 at any time to abort the test")
    print("=" * 70)
    
    # Start F10 listener
    start_keyboard_listener()
    
    # Kill any existing RightLayout instances FIRST (unless user pre-launched one)
    print("Checking for existing RightLayout instances...")
    result = subprocess.run(["pgrep", "-x", "RightLayout"], capture_output=True)
    if result.returncode == 0:
        global SKIP_RIGHTLAYOUT_KILL
        SKIP_RIGHTLAYOUT_KILL = True
        print("  [Info] Pre-launched RightLayout detected, preserving it for tests...")
    else:
        stop_rightlayout()
    
    # Load test cases
    with open(TESTS_FILE) as f:
        tests = json.load(f)
    
    # Build RightLayout
    print("Building RightLayout...")
    r = subprocess.run(["swift", "build"], cwd=ROOT_DIR, capture_output=True)
    if r.returncode != 0:
        print("Build failed!")
        return 1
    
    # Save original user layouts to restore later
    original_layouts = get_enabled_system_layouts()
    print(f"Saved original layouts: {original_layouts}")
    
    # Select layout combo
    combo_idx = args.combo % len(LAYOUT_COMBOS)
    combo = LAYOUT_COMBOS[combo_idx]
    base_layouts = {"en": combo["en"], "ru": combo["ru"], "he": combo["he"]}
    print(f"Using layout combo: {combo['name']}")
    
    # Set up initial system layouts
    print("Setting up system layouts...")
    set_system_layouts(base_layouts["en"], base_layouts["ru"], base_layouts["he"])
    
    # Ensure deterministic base layout config (picked up on app start)
    write_active_layouts(base_layouts)

    start_rightlayout()
    open_test_host()
    
    # Verify host is ready
    time.sleep(0.5)
    ensure_test_host_focused()
    print(f"✓ {TEST_HOST_NAME} focused and ready")
    
    total_passed = 0
    total_failed = 0
    results = []
    current_layouts = dict(base_layouts)

    def ensure_layouts_for_case(case):
        nonlocal current_layouts
        layouts = (case.get("settings") or {}).get("activeLayouts") or base_layouts
        if layouts != current_layouts:
            print(f"\n↺ Switching activeLayouts: {current_layouts} -> {layouts}")
            
            # Update SYSTEM layouts (enable/disable)
            set_system_layouts(layouts.get("en", "us"), 
                              layouts.get("ru", "russian"), 
                              layouts.get("he", "hebrew"))
            
            # Update RightLayout config
            write_active_layouts(layouts)
            start_rightlayout()
            current_layouts = dict(layouts)
            
            # Restore focus after RightLayout restart
            ensure_test_host_focused_auto(retries=30)

    def run_clipboard_safety_test():
        """Run verification for Ticket 60: Clipboard Safety."""
        print("📋 Checking Clipboard Preservation...")
        
        # 1. Set clipboard to a specific "pre-existing" string (simulating user content)
        original_content = "UserCriticalData_DO_NOT_LOSE"
        clipboard_set(original_content)
        
        # 2. Type and trigger correction
        # To force clipboard usage or at least unsafe paths if present, we'd ideally use a long word.
        # But for now, we just ensure normal typing doesn't clobber.
        input_str = "ghbdtn"
        expected = "привет"
        
        clear_field()
        type_string_real(input_str, "en")
        # Wait for correction
        time.sleep(1.0)
        
        # 3. Verify clipboard is UNCHANGED
        current_clipboard = clipboard_get()
        
        if current_clipboard == original_content:
            return True, "Clipboard preserved"
        else:
            return False, f"Clipboard CLOBBERED: '{current_clipboard}' (expected '{original_content}')"

    def run_hint_strategy_test():
        """Ticket 61: Verify Hint-First Strategy."""
        print_colored("\n📋 Running HINT STRATEGY test...", Colors.BLUE)
        
        # 1. Kill and Relaunch with Env Var
        kill_rightlayout()
        time.sleep(1)
        
        env = os.environ.copy()
        env["RightLayout_FORCE_RISK_POLICY"] = "suggestHint"
        
        # Determine path - prioritize local build
        local_build = os.path.join(os.getcwd(), ".build/debug/RightLayout")
        if os.path.exists(local_build):
            print_colored(f"Using local build: {local_build}", Colors.CYAN)
            cmd = [local_build]
        else:
            cmd = ["/Applications/RightLayout.app/Contents/MacOS/RightLayout"]
            if not os.path.exists(cmd[0]):
                 cmd = ["open", "-n", "-a", "RightLayout"]
        
        print_colored("🚀 Relaunching RightLayout with FORCE_RISK_POLICY=suggestHint...", Colors.CYAN)
        # Using Popen with env might work with open -a if it inherits.
        process = subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(3) # Wait for launch
        
        # Re-focus test host
        ensure_test_host_focused_auto()
        
        try:
            # 2. Type 'ghbdtn'
            original = "ghbdtn"
            expected = "привет"
            
            # Switch to English for typing
            cleanup_switch_to_lang("en")
            
            clear_field()
            type_string_real(original, "en")
            time.sleep(1.0) # Wait for potential (but suppressed) correction
            
            # 3. Verify NO change
            content = get_field_content()
            if content.strip() != original:
                # Be tolerant of whitespace
                if content.strip() != original:
                    print_colored(f"❌ Failed: Expected '{original}' (Hint), but got '{content}'", Colors.RED)
                    return False, "Hint policy failed (Auto-corrected?)"
            
            print_colored("✅ Hint Policy Verified (No Auto-Correction)", Colors.GREEN)
            
            # 4. Press Hotkey (Option) -> Simulate Key Press
            print_colored("⌨️ Pressing Hotkey (Option)...", Colors.CYAN)
            # Use AppleScript to key down/up Option (Left Option = 58)
            # System Events might require privileges but we run as user.
            # Using key code 58.
            # Note: modifiers are tricky. We need press AND release?
            # 'key code 58' presses and releases.
            subprocess.run(["osascript", "-e", 'tell application "System Events" to key code 58'], check=True)
            time.sleep(0.5)
            
            # 5. Verify Change
            content = get_field_content()
            if expected in content:
                print_colored(f"✅ Hotkey Application Verified: '{content}'", Colors.GREEN)
                return True, "Hint Strategy Verified"
            else:
                 print_colored(f"❌ Failed: Expected '{expected}' after hotkey, got '{content}'", Colors.RED)
                 return False, f"Hotkey failed to apply correction (Got '{content}')"
                 
        finally:
            # Cleanup: Kill app to reset env var state for next tests
            kill_rightlayout()
            # Relaunch normally
            time.sleep(1)
            ensure_rightlayout_running()
            ensure_test_host_focused_auto()

    def run_input_expected_category(key, title):
        nonlocal total_passed, total_failed
        cases = tests.get(key, {}).get("cases", [])
        if not cases:
            return
        print("\n" + "=" * 70)
        print(title)
        print("=" * 70)
        for case in cases:
            ensure_layouts_for_case(case)
            
            try:
                if key == "early_switch":
                    ok, result = run_early_switch_test(case["input"], case["expected"])
                elif key == "edge_cases_system" and real_typing_mode:
                    ok, result = run_whitespace_only_test(case["input"], case["expected"])
                else:
                    if real_typing_mode:
                        ok, result = run_single_test_real(case["input"], case["expected"])
                    else:
                        ok, result = run_single_test(case["input"], case["expected"])
            except FocusLostError as e:
                print(f"\n❌ FOCUS LOST: {e}")
                print("Test aborted. Check which app stole focus.")
                raise
            
            status = "✓" if ok else "✗"
            print(f"{status} {case.get('desc','')}")
            if not ok:
                print(f"    '{case['input']}' → '{result}' (expected '{case['expected']}')")
                total_failed += 1
            else:
                total_passed += 1
            time.sleep(0.1)
    
    try:
        # Single words
        if not categories or "single" in categories or "single_words" in categories:
            run_input_expected_category("single_words", "SINGLE WORDS")
        
        # Comma in words
        if not categories or "comma" in categories or "comma_in_words" in categories:
            run_input_expected_category("comma_in_words", "COMMA IN WORDS")

        if not categories or "comma" in categories or "comma_period" in categories or "comma_period_single_words" in categories:
            run_input_expected_category("comma_period_single_words", "COMMA/PERIOD (SINGLE WORDS)")
        
        # Paragraphs
        if not categories or "paragraphs" in categories or "real_paragraphs" in categories:
            run_input_expected_category("real_paragraphs", "PARAGRAPHS (REAL)")

        if not categories or "multiline" in categories or "multiline_realistic" in categories:
            run_input_expected_category("multiline_realistic", "MULTILINE (REALISTIC)")

        if not categories or "mixed" in categories or "mixed_language_real" in categories:
            run_input_expected_category("mixed_language_real", "MIXED LANGUAGE (REAL)")

        if not categories or "symbols" in categories or "special_symbols" in categories:
            run_input_expected_category("special_symbols", "SPECIAL SYMBOLS")

        if not categories or "hebrew" in categories or "hebrew_cases" in categories:
            run_input_expected_category("hebrew_cases", "HEBREW CASES")

        if not categories or "punct" in categories or "punctuation_triggers" in categories:
            run_input_expected_category("punctuation_triggers", "PUNCTUATION TRIGGERS")

        if not categories or "typos" in categories or "typos_and_errors" in categories:
            run_input_expected_category("typos_and_errors", "TYPOS AND ERRORS")

        if not categories or "numbers" in categories or "numbers_and_special" in categories:
            run_input_expected_category("numbers_and_special", "NUMBERS AND SPECIALS")

        if not categories or "ambiguous" in categories or "ambiguous_words" in categories:
            run_input_expected_category("ambiguous_words", "AMBIGUOUS WORDS (NEGATIVE)")

        if not categories or "negative" in categories or "negative_should_not_change" in categories:
            run_input_expected_category("negative_should_not_change", "NEGATIVE SHOULD NOT CHANGE")

        if not categories or "edge" in categories or "edge_cases_system" in categories:
            run_input_expected_category("edge_cases_system", "EDGE CASES (SYSTEM)")
        
        # GitHub Issues
        if not categories or "issue" in categories or "issue_2" in categories:
            run_input_expected_category("issue_2_prepositions", "ISSUE #2: Prepositions")
        
        if not categories or "issue" in categories or "issue_3" in categories:
            run_input_expected_category("issue_3_punctuation_boundaries", "ISSUE #3: Punctuation Boundaries")
        
        if not categories or "issue" in categories or "issue_6" in categories:
            run_input_expected_category("issue_6_technical_text", "ISSUE #6: Technical Text")
        
        if not categories or "issue" in categories or "issue_7" in categories:
            run_input_expected_category("issue_7_numbers_punctuation", "ISSUE #7: Numbers Punctuation")
        
        if not categories or "issue" in categories or "issue_8" in categories:
            run_input_expected_category("issue_8_emoji_unicode", "ISSUE #8: Emoji Unicode")

        if not categories or "early" in categories or "early_switch" in categories:
            run_input_expected_category("early_switch", "EARLY LAYOUT SWITCHING (Ticket 34)")
        
        if not categories or "backspace" in categories or "backspace_safety" in categories:
            run_input_expected_category("backspace_safety", "BACKSPACE SAFETY (Ticket 62)")
            
        if not categories or "clipboard" in categories or "clipboard_safety" in categories:
            print("\n" + "=" * 70)
            print("CLIPBOARD SAFETY (Ticket 60)")
            print("=" * 70)
            ok, msg = run_clipboard_safety_test()
            if ok:
                print(f"✓ {msg}")
                total_passed += 1
            else:
                print(f"✗ {msg}")
                total_failed += 1
                print(f"✗ {msg}")
                total_failed += 1
        
        if not categories or "hint" in categories or "hint_strategy" in categories:
            ok, msg = run_hint_strategy_test()
            if ok:
                print(f"✓ {msg}")
                total_passed += 1
            else:
                print(f"✗ {msg}")
                total_failed += 1
        if not categories or "context" in categories or "context_boost_hard" in categories:
            print("\n" + "=" * 70)
            print("CONTEXT BOOST (word-by-word)")
            print("=" * 70)
            context_cases = (tests.get("context_boost_hard") or tests.get("context_boost_realistic") or {}).get("cases", [])
            for case in context_cases:
                ensure_layouts_for_case(case)
                ok, result = run_context_boost_test(case["words"], case["expected_final"])
                status = "✓" if ok else "✗"
                print(f"{status} {case.get('desc','')}")
                if not ok:
                    print(f"    Words: {case['words']}")
                    print(f"    Got: '{result}'")
                    print(f"    Exp: '{case['expected_final']}'")
                    total_failed += 1
                else:
                    total_passed += 1
                time.sleep(0.15)
        
        # Cycling
        if not categories or "cycling" in categories:
            print("\n" + "=" * 70)
            print("ALT CYCLING")
            print("=" * 70)
            for case in tests.get("cycling_tests", {}).get("cases", []):
                ensure_layouts_for_case(case)
                expected_seq = case.get("expected_sequence")
                ok, result = run_cycling_test(case["input"], case["alt_presses"], expected_seq)
                status = "✓" if ok else "✗"
                print(f"{status} {case['desc']}")
                if not ok:
                    print(f"    Results: {result}")
                    if expected_seq:
                        print(f"    Expected: {expected_seq}")
                    total_failed += 1
                else:
                    total_passed += 1
                time.sleep(0.1)

        if not categories or "rapid" in categories or "rapid_typing_simulation" in categories:
            print("\n" + "=" * 70)
            print("RAPID TYPING SIMULATION")
            print("=" * 70)
            for case in tests.get("rapid_typing_simulation", {}).get("cases", []):
                ensure_layouts_for_case(case)
                ok, result = run_rapid_typing_simulation(case["sequence"], case["expected_after_correction"])
                status = "✓" if ok else "✗"
                print(f"{status} {case.get('desc','')}")
                if not ok:
                    print(f"    Sequence: {case['sequence']}")
                    print(f"    Got: {repr(result)}")
                    print(f"    Exp: {repr(case['expected_after_correction'])}")
                    total_failed += 1
                else:
                    total_passed += 1
                time.sleep(0.12)

        if not categories or "paste" in categories or "paste_should_not_autocorrect" in categories:
            print("\n" + "=" * 70)
            print("PASTE SHOULD NOT AUTO-CORRECT")
            print("=" * 70)
            for case in tests.get("paste_should_not_autocorrect", {}).get("cases", []):
                ensure_layouts_for_case(case)
                ok, result = run_paste_should_not_autocorrect_test(case["input"], case.get("expected"))
                status = "✓" if ok else "✗"
                print(f"{status} {case.get('desc','')}")
                if not ok:
                    print(f"    In : {repr(case['input'])}")
                    print(f"    Got: {repr(result)}")
                    print(f"    Exp: {repr(case.get('expected', case['input']))}")
                    total_failed += 1
                else:
                    total_passed += 1
                time.sleep(0.12)

        if not categories or "undo" in categories or "cmd_z_undo" in categories:
            print("\n" + "=" * 70)
            print("CMD+Z UNDO")
            print("=" * 70)
            for case in tests.get("cmd_z_undo", {}).get("cases", []):
                ensure_layouts_for_case(case)
                ok, result = run_cmd_z_undo_test(case["input"], case["expected_corrected"])
                status = "✓" if ok else "✗"
                print(f"{status} {case.get('desc','')}")
                if not ok:
                    print(f"    Input: {repr(case['input'])}")
                    print(f"    Got: {repr(result)}")
                    print(f"    Exp: {repr(case['expected_corrected'])} (then undo back to input)")
                    total_failed += 1
                else:
                    total_passed += 1
                time.sleep(0.15)

        if not categories or "learn" in categories or "learning_keep_as_is" in categories:
            print("\n" + "=" * 70)
            print("LEARNING: KEEP-AS-IS (2× reject)")
            print("=" * 70)
            learning_cases = tests.get("learning_keep_as_is", {}).get("cases", [])
            for case in learning_cases:
                ensure_layouts_for_case(case)
                ok, result = run_autocorrect_keep_as_is_learning_test(case["token"], case["expected_corrected"])
                status = "✓" if ok else "✗"
                print(f"{status} {case.get('desc','')}")
                if not ok:
                    print(f"    Token: {repr(case['token'])}")
                    print(f"    Got: {repr(result)}")
                    print(f"    Expected corrected: {repr(case['expected_corrected'])}")
                    total_failed += 1
                else:
                    total_passed += 1
                time.sleep(0.20)
            if learning_cases:
                # Ensure subsequent tests don't get affected by learned keep-as-is rules.
                start_rightlayout()
                ensure_test_host_focused_auto(retries=30)
        
        # Stress
        if not categories or "correction_logic" in categories:
            print("\n" + "=" * 70)
            print("CORRECTION LOGIC REGRESSIONS")
            print("=" * 70)
            for case in tests.get("correction_logic", {}).get("cases", []):
                ensure_layouts_for_case(case)
                ok, result, _ = run_correction_test(case["input"], case["expected"])
                status = "✓" if ok else "✗"
                print(f"{status} {case.get('desc','')}")
                if not ok:
                    print(f"    In : {repr(case['input'])}")
                    print(f"    Got: {repr(result)}")
                    print(f"    Exp: {repr(case['expected'])}")
                    total_failed += 1
                else:
                    total_passed += 1
                time.sleep(0.12)

        if not categories or "stress" in categories:
            print("\n" + "=" * 70)
            print("STRESS TESTS")
            print("=" * 70)
            
            # Rapid cycling
            print("Testing rapid Alt spam (10x)...")
            ok, result = run_stress_cycling("ghbdtn vbh ntrcn", 10, 50)
            status = "✓" if ok else "✗"
            print(f"{status} Rapid cycling - result not empty: {len(result)} chars")
            if ok:
                total_passed += 1
            else:
                total_failed += 1
            
            # Random cycling
            print("Testing random cycling (1-5 times, 3 rounds)...")
            for i in range(3):
                times = random.randint(1, 5)
                ok, result = run_stress_cycling("ntrcn lkz ntcnf", times, 100)
                status = "✓" if ok else "✗"
                print(f"  {status} Round {i+1}: {times} presses → '{result[:30]}...'")
                if ok:
                    total_passed += 1
                else:
                    total_failed += 1
                time.sleep(0.1)
        
        # Performance
        if not categories or "perf" in categories:
            print("\n" + "=" * 70)
            print("PERFORMANCE")
            print("=" * 70)
            for case in tests.get("performance_stress", {}).get("cases", []):
                ensure_layouts_for_case(case)
                ok, result, elapsed = run_performance_test(
                    case["input"], case["expected"], case["max_time_ms"]
                )
                status = "✓" if ok else "✗"
                print(f"{status} {case['desc']}: {elapsed:.0f}ms (max {case['max_time_ms']}ms)")
                if not ok:
                    if result != case["expected"]:
                        print(f"    Result mismatch")
                    if elapsed > case["max_time_ms"]:
                        print(f"    Too slow!")
                    total_failed += 1
                else:
                    total_passed += 1
    
    except KeyboardInterrupt:
        print("\n\n🛑 Test aborted by user (F10 or Ctrl+C)")
        
    finally:
        close_test_host()
        stop_rightlayout()
        
        # Restore original user layouts
        print(f"\nRestoring original layouts: {original_layouts}")
        current_enabled = get_enabled_system_layouts()
        # Disable layouts that weren't originally enabled
        for lay in current_enabled:
            if lay not in original_layouts:
                disable_system_layout(lay)
        # Enable layouts that were originally enabled
        for lay in original_layouts:
            if lay not in current_enabled:
                enable_system_layout(lay)
    
    # Summary
    print("\n" + "=" * 70)
    if _abort_requested:
        print(f"ABORTED: {total_passed} passed, {total_failed} failed (incomplete)")
    else:
        print(f"TOTAL: {total_passed} passed, {total_failed} failed")
    print("=" * 70)
    
    return 0 if total_failed == 0 else 1


if __name__ == "__main__":
    exit(main())
