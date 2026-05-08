# Security Policy

## Data Access

RightLayout uses `CGEventTap` to monitor keyboard events. This is a sensitive macOS permission.

**What RightLayout accesses:**
- Keyboard input events (key presses/releases)
- Current keyboard layout information

**What RightLayout does NOT do:**
- Transmit any keystroke data over the network
- Log or store keystrokes to disk
- Access clipboard, files, or other system resources
- Communicate with any remote server

All processing happens locally on your machine. Your keystrokes never leave your computer.

## Reporting a Vulnerability

If you discover a security vulnerability in RightLayout, please report it privately:

1. Open a [GitHub Security Advisory](https://github.com/chernistry/RightLayout/security/advisories/new)
2. Or contact the maintainer directly

Please include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact

Expected response time: within 48 hours.

## Responsible Disclosure

- Do not publicly disclose the vulnerability until a fix is available
- We will work with you to understand and resolve the issue
- Credit will be given to the reporter (unless they prefer to remain anonymous)
