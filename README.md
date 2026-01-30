# Zig Dev Version Installer

A simple utility script to download and install the latest dev version of Zig from https://ziglang.org/download.

## Features

- Automatically detects your system architecture (x86_64/aarch64, macOS/Linux)
- Checks if you already have the latest version installed
- Downloads and installs the latest dev version if needed
- Creates a symlink at `~/.local/zig` pointing to the latest version
- Automatically cleans up old versions (keeps only the current one)
- Provides instructions for adding Zig to your PATH

## Installation

The script installs Zig to `~/.local/zig-versions/` with each version in its own directory. A symlink at `~/.local/zig` always points to the latest version.

## Usage

```bash
./install-zig.sh
```

The script will:
1. Detect your system architecture
2. Check your current Zig version (if installed)
3. Fetch the latest dev version information
4. Download and install if a newer version is available
5. Update the symlink to point to the new version
6. Clean up old versions
7. Print instructions for adding Zig to your PATH

## Adding Zig to Your PATH

After running the installer, add one of the following to your `~/.zshrc`:

**Option 1: Alias (recommended)**
```bash
alias zig="$HOME/.local/zig/zig"
```

**Option 2: Add to PATH**
```bash
export PATH="$HOME/.local/zig:$PATH"
```

Then reload your shell:
```bash
source ~/.zshrc
```

## How It Works

1. **Installation Location**: Versions are stored in `~/.local/zig-versions/zig-{arch}-{version}/`
2. **Symlink**: `~/.local/zig` is a symlink to the latest version directory
3. **Version Detection**: The script runs `zig version` on the current installation to check if an update is needed
4. **Cleanup**: Old versions are automatically removed, keeping only the current one

## Requirements

- `curl` (for downloading)
- `tar` (for extracting archives)
- `python3` (for JSON parsing, usually pre-installed on macOS)
- Internet connection

## Notes

- The script preserves the full directory structure from the Zig tarball, as the binary needs access to files in its directory
- The symlink points to the directory (not just the binary) so Zig can find its supporting files
- Old versions are completely removed to save disk space
