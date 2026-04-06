<div align="center">

# RightLayout

**Type freely.**

RightLayout fixes your keyboard layout mistakes before you notice them.

[Download for Mac](https://github.com/chernistry/RightLayout/releases/latest) · [Website](https://alexchernysh.com/rightlayout)

---

*English · Russian · Hebrew*

*macOS 13+ · Free · Open Source*

</div>

---

> **This project is now community-maintained. The original author is no longer actively developing it. Contributions welcome!**

---

## How it works

You type in the wrong keyboard layout and RightLayout corrects it instantly using on-device AI (CoreML).

```
ghbdtn  →  привет
руддщ   →  hello  
akuo    →  שלום
```

No hotkeys. No notifications. Just correct text.

---

## Features

**Works invisibly**  
No popups, no interruptions. Corrections happen as you type.

**AI-powered language detection**  
A CoreML model trained on real multilingual typing data detects wrong-layout text with high accuracy.

**Learns you**  
Undo a correction twice — RightLayout remembers. It adapts to your writing style.

**Stays private**  
Everything runs on your Mac. Nothing leaves your device. Ever.

**Multilingual keyboard support**  
Supports English, Russian, and Hebrew layouts with extensible architecture for adding more languages.

---

## Install

1. Download the `.pkg` from [Releases](https://github.com/chernistry/RightLayout/releases/latest)
2. Run the installer
3. Grant Accessibility permission when prompted
4. Done — RightLayout works in the background

---

## Building from source

```bash
git clone https://github.com/chernistry/RightLayout.git
cd RightLayout
swift build
swift test
```

Requires macOS 13+, Xcode 15+, Swift 5.9+.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, code style, and how to add new languages.

---

## Looking for Maintainers

This project needs new maintainers. If you're interested in macOS development, keyboard input handling, or CoreML-based language detection, this is a great project to take on.

**What a maintainer would do:**
- Triage and respond to issues
- Review and merge pull requests
- Cut new releases
- Extend language support (German, French, Arabic, etc.)

If you're interested, open an issue titled "Maintainer interest" and describe your background. There are no gatekeepers — if you ship good PRs, you get commit access.

---

## Architecture

- `RightLayout/Sources/Engine/` — Core correction engine (language detection, layout mapping, confidence routing)
- `RightLayout/Sources/UI/` — SwiftUI settings and menu bar interface
- `RightLayout/Sources/Settings/` — User preferences and personalization
- `Tools/CoreMLTrainer/` — Python training pipeline for the CoreML language classifier

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on adding features and languages.

---

## License

Source Available — Non-Commercial.  
See [LICENSE](LICENSE) for details.

For commercial licensing inquiries, contact: alex@alexchernysh.com

---

<div align="center">

Built by [Alex Chernysh](https://alexchernysh.com)

</div>
