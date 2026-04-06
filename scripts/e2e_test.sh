#!/usr/bin/env bash
# Test RightLayout with complex mixed-language string
# Uses clipboard paste + manual retype simulation

set -e

RightLayout_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="$HOME/.rightlayout/debug.log"

cd "$RightLayout_DIR"
swift build 2>&1 | tail -1

pkill -f ".build/debug/RightLayout" 2>/dev/null || true
sleep 0.3
rm -f "$LOG_FILE"
mkdir -p "$HOME/.rightlayout"

RightLayout_DEBUG_LOG=1 .build/debug/RightLayout &
RightLayout_PID=$!
sleep 1.5

cleanup() {
    kill $RightLayout_PID 2>/dev/null || true
    osascript -e 'tell application "TextEdit" to quit saving no' 2>/dev/null || true
}
trap cleanup EXIT

# Test: paste text, then trigger hotkey on last word
# RightLayout works on buffer which is filled by typing, not paste
# So we paste, then select last word and convert

TEST_STRING="נתרצנ целенаправленно yfgbcfyysq ד неправильной הפצרכפלרת"

result=$(osascript <<APPLESCRIPT
tell application "TextEdit"
    close every document saving no
    make new document
    activate
end tell
delay 0.5

tell application "System Events"
    tell process "TextEdit"
        set frontmost to true
        delay 0.3
        
        tell window 1
            set {wx, wy} to position
            set {ww, wh} to size
        end tell
        set clickX to (wx + ww / 2) as integer
        set clickY to (wy + wh / 2) as integer
        do shell script "cliclick c:" & clickX & "," & clickY
        delay 0.2
        
        -- Paste the test string (RightLayout won't see this in buffer)
        set the clipboard to "$TEST_STRING"
        keystroke "v" using command down
        delay 0.3
        
        -- Get initial content
        keystroke "a" using command down
        delay 0.1
        keystroke "c" using command down
        delay 0.1
        set initialText to the clipboard
        
        -- Select all text for conversion
        keystroke "a" using command down
        delay 0.2
        
        -- Press Option to convert selection
        key down option
        delay 0.03
        key up option
        delay 1.5
        
        -- Get result
        keystroke "a" using command down
        delay 0.1
        keystroke "c" using command down
        delay 0.1
        set resultText to the clipboard
        
        return initialText & "|" & resultText
    end tell
end tell
APPLESCRIPT
)

initial=$(echo "$result" | cut -d'|' -f1 | tr -d '\r')
converted=$(echo "$result" | cut -d'|' -f2 | tr -d '\r')

echo "Input:  '$initial'"
echo "Output: '$converted'"
echo ""

if [ "$converted" != "$initial" ]; then
    echo "✓ Conversion happened"
    echo ""
    echo "=== RightLayout Log ==="
    grep -E "(HOTKEY|correctLastWord|REPLACE)" "$LOG_FILE" 2>/dev/null | tail -20
else
    echo "✗ No change"
    echo ""
    echo "=== RightLayout Log ==="
    cat "$LOG_FILE" 2>/dev/null | tail -30
fi
