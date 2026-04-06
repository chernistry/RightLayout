#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "🚀 Download & Install Beam Cloud Model"
echo "======================================="

cd "$(dirname "$0")"

# Step 1: Download from Beam
echo -e "${BLUE}[1/3]${NC} Downloading model_ultra.pth from Beam..."
beam cp beam://rightlayout-training-data/model_ultra.pth ./
echo -e "${GREEN}✓${NC} Downloaded"

# Step 2: Export to CoreML
echo -e "${BLUE}[2/3]${NC} Exporting to CoreML..."
source venv/bin/activate 2>/dev/null || python3 -m venv venv && source venv/bin/activate
pip install -q torch coremltools
python3 export.py --ensemble --model_in model_ultra.pth --output LayoutClassifier.mlmodel
echo -e "${GREEN}✓${NC} Exported"

# Step 3: Install
echo -e "${BLUE}[3/3]${NC} Installing to project..."
cp LayoutClassifier.mlmodel ../../RightLayout/Sources/Resources/
echo -e "${GREEN}✓${NC} Installed"

echo ""
echo -e "${GREEN}✅ Done! Rebuild RightLayout to use new model.${NC}"
