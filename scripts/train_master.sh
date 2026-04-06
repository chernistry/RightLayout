#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Paths
RAW_DIR="data/raw"
PROCESSED_DIR="data/processed"
TOOLS_DIR="Tools"
RESOURCES_DIR="RightLayout/Sources/Resources"

echo -e "${BLUE}==============================================${NC}"
echo -e "${GREEN}   RightLayout Interactive Training Master ${NC}"
echo -e "${BLUE}==============================================${NC}"
echo ""

# Ensure processed dir exists
mkdir -p "$PROCESSED_DIR"

# Non-interactive mode: `./train_master.sh 3` or `./train_master.sh --run 3`
AUTO_CHOICE=""
if [[ "${1:-}" == "--run" ]]; then
    AUTO_CHOICE="${2:-}"
elif [[ "${1:-}" =~ ^[1-7]$ ]]; then
    AUTO_CHOICE="${1:-}"
fi

while true; do
    echo "Files available in processed data:"
    if [ -f "$PROCESSED_DIR/ru.txt" ]; then echo -e "  ${GREEN}✓${NC} ru.txt"; else echo -e "  ${RED}✗${NC} ru.txt"; fi
    if [ -f "$PROCESSED_DIR/en.txt" ]; then echo -e "  ${GREEN}✓${NC} en.txt"; else echo -e "  ${RED}✗${NC} en.txt"; fi
    if [ -f "$PROCESSED_DIR/he.txt" ]; then echo -e "  ${GREEN}✓${NC} he.txt"; else echo -e "  ${RED}✗${NC} he.txt"; fi
    echo ""
    
    echo "Choose an action:"
    echo "  1) 📦 Extract Raw Wikipedia Dumps (prepare real data)"
    echo "  2) 📊 Train N-gram Models (requires extracted data)"
    echo "  3) 🧠 Train CoreML Model (requires extracted data for best results)"
    echo "  4) ✅ Run Tests"
    echo "  5) 💬 Import Telegram Chat Exports (append to corpus)"
    echo "  6) 🎬 Download OpenSubtitles (conversational HE/RU data)"
    echo "  7) 🧪 Run Synthetic Evaluation (slow)"
    echo "  q) Quit"
    echo ""
    if [ -n "$AUTO_CHOICE" ]; then
        choice="$AUTO_CHOICE"
        echo "Option: $choice (non-interactive)"
    else
        read -p "Option: " choice
    fi
    echo ""
    
    case $choice in
        1)
            echo -e "${BLUE}--- Extracting Wikipedia Dumps ---${NC}"
            ./rightlayout.sh corpus extract-wikipedia --lang ru --limit 50000 || true
            ./rightlayout.sh corpus extract-wikipedia --lang en --limit 50000 || true
            ./rightlayout.sh corpus extract-wikipedia --lang he --limit 50000 || true
            echo -e "${GREEN}Extraction step complete.${NC}"
            ;;
            
        2)
            echo -e "${BLUE}--- Training N-grams ---${NC}"
            ./rightlayout.sh train ngrams
            ;;
            
        3)
            echo -e "${BLUE}--- Training CoreML Model ---${NC}"
            ./rightlayout.sh train coreml
            ;;
            
        4)
            echo -e "${BLUE}--- Running Verification Tests ---${NC}"
            ./rightlayout.sh test
            ;;

        7)
            echo -e "${BLUE}--- Running Synthetic Evaluation ---${NC}"
            ./rightlayout.sh eval synthetic
            ;;
            
        5)
            echo -e "${BLUE}--- Importing Telegram Chat Exports ---${NC}"
            # Hardcoded paths from user request. Add more as needed.
            TELEGRAM_FILES=(
                "/path/to/telegram/export/result.json"
                "/path/to/telegram/chat_export/result.json"
                "/path/to/messages/result.json"
            )
            EXISTING_FILES=()
            for f in "${TELEGRAM_FILES[@]}"; do
                if [ -f "$f" ]; then
                    EXISTING_FILES+=("$f")
                else
                    echo -e "${YELLOW}Skipping (not found): $f${NC}"
                fi
            done
            if [ ${#EXISTING_FILES[@]} -gt 0 ]; then
                echo "Found ${#EXISTING_FILES[@]} Telegram export file(s). Extracting..."
                args=()
                for f in "${EXISTING_FILES[@]}"; do
                    args+=(--file "$f")
                done
                ./rightlayout.sh corpus import-telegram --output-dir "$PROCESSED_DIR" "${args[@]}"
                echo -e "${GREEN}Telegram data imported to $PROCESSED_DIR!${NC}"
            else
                echo -e "${RED}No Telegram export files found.${NC}"
            fi
            ;;
            
        6)
            echo -e "${BLUE}--- Downloading OpenSubtitles (conversational data) ---${NC}"
            ./rightlayout.sh corpus download-subtitles --limit 2000000
            ;;
            
        q)
            echo "Exiting."
            exit 0
            ;;
            
        *)
            echo "Invalid option."
            ;;
    esac
    echo ""
    if [ -n "$AUTO_CHOICE" ]; then
        exit 0
    fi
    read -p "Press Enter to continue..."
    echo ""
done
