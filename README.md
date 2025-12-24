<div align="center">

# O.M.F.K

### Automatic keyboard layout correction for macOS

![OMFK Banner](assets/banner.png)

---

![How it works](assets/howitworks.gif)

**[Website](https://hireex.ai/omfk)** · **[Telegram](https://t.me/ohmyfuckingkeyboard)**

[![macOS](https://img.shields.io/badge/macOS-14.0+-000?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Download](https://img.shields.io/badge/Download-Latest_Release-6366f1?style=flat-square)](https://github.com/chernistry/omfk/releases/latest)
[![License](https://img.shields.io/badge/License-Proprietary-374151?style=flat-square)]()

</div>

---

## The Problem

You're typing, deep in thought... then you look up:

```
Ghbdtn? rfr ltkf&   →   Привет, как дела?
ру|дщ цщкдв          →   hello world
```

Wrong keyboard layout. Again.

**OMFK fixes this automatically, as you type.**

---

## Features

<table>
<tr>
<td width="50%">

**Real-time correction**

Detects wrong layouts on word boundaries and fixes them instantly. No hotkeys needed.

</td>
<td width="50%">

**Smart per-word analysis**

Each word is analyzed separately. Mixed-language sentences stay mixed — only wrong parts get fixed.

</td>
</tr>
<tr>
<td>

**Hotkey cycling**

Press `Option` to cycle through alternatives: original → Russian → English → Hebrew → back.

</td>
<td>

**100% private**

Everything runs on-device. No network calls. No logging. No telemetry.

</td>
</tr>
</table>

**Supported languages:** English, Russian, Hebrew

---

## Installation

### 1. Download

Get the latest `.dmg` from [Releases](https://github.com/chernistry/omfk/releases/latest).

### 2. Install

Open the DMG and drag **OMFK** to your Applications folder.

### 3. Grant Accessibility Access

On first launch, macOS will ask for Accessibility permission.

1. Open **System Settings → Privacy & Security → Accessibility**
2. Enable **OMFK**
3. OMFK will automatically start working once permission is granted

> **Note:** Accessibility access is required to monitor keyboard input. OMFK cannot function without it.

---

## Usage

| Action | How |
|--------|-----|
| Toggle auto-correction | Click menu bar icon |
| Cycle through alternatives | Press `Option` |
| Undo last correction | Press `Option` immediately after |
| Exclude an app | Settings → Per-App Rules |

---

## How It Works

OMFK uses an on-device neural network to detect which language you *intended* to type, then converts the text to the correct layout.

- Detection latency: <50ms
- Model runs entirely on your Mac via CoreML
- No internet connection required

---

## Troubleshooting

**"OMFK is damaged and can't be opened"**

Run in Terminal:
```bash
xattr -c /Applications/OMFK.app
```

**Corrections not working**

1. Check Accessibility permission is enabled
2. Quit and reopen OMFK
3. Check if the app is in your exclusion list

**Wrong corrections**

Press `Option` to cycle through alternatives, or disable auto-correction for that app.

---

## Requirements

- macOS Sonoma (14.0) or later
- Apple Silicon or Intel Mac

---

## Feedback

Found a bug or have a feature idea? [Open an issue](https://github.com/chernistry/omfk/issues/new/choose).

---

<div align="center">

[Download](https://github.com/chernistry/omfk/releases/latest) · [Report Issue](https://github.com/chernistry/omfk/issues)

Made by [Alex Chernysh](https://hireex.ai)

</div>
