# Linux Terminal

A real Linux terminal for Android using Flutter + PRoot + Debian.

- Full Debian Linux environment via PRoot (no root required)
- Terminal emulator with ANSI color support
- Extra keys toolbar for mobile
- Download and install packages with `apt`

## Build

```bash
flutter build apk --release --target-platform android-arm64
```

## How it works

1. Downloads PRoot binary from Termux repository
2. Downloads Debian rootfs
3. Runs bash inside PRoot'd Debian environment
4. Terminal UI renders output via xterm.dart and flutter_pty
