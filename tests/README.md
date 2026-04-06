# RightLayout Test Infrastructure

This project has **two test layers** that serve different purposes:

## 1. Swift Unit Tests (`RightLayout/Tests/`)

**Purpose**: Fast, isolated tests for core logic components.

**Run with**:
```bash
swift test                             # Run all
swift test --filter CyclingTests       # Run specific test class
```

**Contains**:
- `CorrectionEngineTests.swift` - Core correction logic
- `LayoutMapperTests.swift` - Layout conversion mapping
- `CyclingTests.swift` - Alt hotkey cycling logic
- `PersonalizationTests.swift` - Learning system
- `AltHotkeyComprehensiveTests.swift` - Comprehensive Alt key mechanism tests
- 35+ other unit/integration test files

**When to use**: For fast iteration during development. No UI dependencies.

---

## 2. Python E2E Tests (`tests/`)

**Purpose**: Real-world typing simulation using macOS accessibility APIs.

**Run with**:
```bash
# Activate Python venv first
source .venv/bin/activate
pip install -r tests/requirements.txt

# Run all categories
python3 tests/run_tests.py

# Run with REAL typing (auto-correction on space)
python3 tests/run_tests.py --real-typing

# Run specific category
python3 tests/run_tests.py cycling_tests
python3 tests/run_tests.py single_words

# Run across all layout combinations
python3 tests/run_tests.py --all-combos --all-modes
```

**Contains**:
- `run_tests.py` - Main test runner (PyObjC + Quartz)
- `test_cases.json` - All E2E test data (1500+ lines)
- `utils/` - Test utilities (keycodes, generators)

**How it works**:
1. Launches `RightLayoutTestHost` (dedicated test app)
2. Injects keystrokes via CGEvent
3. Reads result from `~/.rightlayout/testhost_value.txt`
4. Compares against expected output

**Requirements**:
- macOS 13+
- Accessibility + Input Monitoring permissions
- Python 3 + PyObjC (`pip install -r tests/requirements.txt`)

**Press F10** to abort running tests.

---

## Test Data (`tests/test_cases.json`)

Both test layers can use this JSON file for test cases. Categories include:
- `single_words` - Basic corrections
- `cycling_tests` - Alt hotkey cycling
- `context_boost_hard` - Ambiguous first-word cases
- `mixed_language_real` - RU/EN/HE mixing
- `negative_should_not_change` - URLs, code, UUIDs
- And many more...

## Adding New Tests

**For unit/integration logic**: Add Swift test file to `RightLayout/Tests/`

**For real typing scenarios**: Add case to `tests/test_cases.json`
