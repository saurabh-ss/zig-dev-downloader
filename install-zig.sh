#!/bin/bash

set -euo pipefail

# Configuration
ZIG_BASE_DIR="$HOME/.local/zig-versions"
ZIG_SYMLINK="$HOME/.local/zig"
ZIG_DOWNLOAD_URL="https://ziglang.org/download/index.json"
TEMP_DIR=$(mktemp -d)

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Detect architecture
detect_arch() {
    local arch=$(uname -m)
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    case "$arch" in
        x86_64)
            if [[ "$os" == "darwin" ]]; then
                echo "x86_64-macos"
            elif [[ "$os" == "linux" ]]; then
                echo "x86_64-linux"
            else
                echo "x86_64-${os}"
            fi
            ;;
        arm64|aarch64)
            if [[ "$os" == "darwin" ]]; then
                echo "aarch64-macos"
            elif [[ "$os" == "linux" ]]; then
                echo "aarch64-linux"
            else
                echo "aarch64-${os}"
            fi
            ;;
        *)
            echo "Unsupported architecture: $arch" >&2
            exit 1
            ;;
    esac
}

# Get current installed version
get_current_version() {
    if [[ -L "$ZIG_SYMLINK" ]] && [[ -e "$ZIG_SYMLINK" ]]; then
        local zig_binary="$ZIG_SYMLINK/zig"
        if [[ -x "$zig_binary" ]]; then
            local version=$("$zig_binary" version 2>/dev/null | head -n1 | awk '{print $1}')
            echo "$version"
            return 0
        fi
    fi
    return 1
}

# Fetch latest version info from JSON API
get_latest_version_info() {
    local arch=$1
    local json_data
    local json_file="$TEMP_DIR/zig-downloads.json"
    
    if ! curl -s "$ZIG_DOWNLOAD_URL" > "$json_file"; then
        echo "Error: Failed to fetch version information" >&2
        exit 1
    fi
    
    # Try to use Python for JSON parsing (more reliable)
    if command -v python3 &> /dev/null; then
        local version=$(python3 -c "
import json
import sys
try:
    with open('$json_file', 'r') as f:
        data = json.load(f)
    if 'master' in data and 'version' in data['master']:
        print(data['master']['version'])
    else:
        sys.exit(1)
except Exception:
    sys.exit(1)
")
        
        local tarball_url=$(python3 -c "
import json
import sys
try:
    with open('$json_file', 'r') as f:
        data = json.load(f)
    arch_key = '$arch'
    if 'master' in data and arch_key in data['master'] and 'tarball' in data['master'][arch_key]:
        print(data['master'][arch_key]['tarball'])
    else:
        sys.exit(1)
except Exception:
    sys.exit(1)
")
    else
        # Fallback to grep/sed parsing (less reliable but works)
        local version=$(grep -A 1 '"master":' "$json_file" | \
            grep '"version"' | \
            sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -n1)
        
        # Extract tarball URL - need to find the arch key in master section
        local tarball_url=$(awk "/\"master\":/,/^  }/ { 
            if (/\".*$arch.*\":/) { 
                in_arch=1 
            } 
            if (in_arch && /\"tarball\"/) { 
                match(\$0, /\"tarball\"[[:space:]]*:[[:space:]]*\"([^\"]+)\"/, arr)
                print arr[1]
                exit
            } 
        }" "$json_file")
    fi
    
    if [[ -z "$version" ]]; then
        echo "Error: Could not parse version from JSON" >&2
        exit 1
    fi
    
    if [[ -z "$tarball_url" ]]; then
        echo "Error: Could not find download URL for architecture: $arch" >&2
        echo "Available architectures in master:" >&2
        grep -A 50 '"master":' "$json_file" | grep -o '"[^"]*-[^"]*":' | head -n5 >&2
        exit 1
    fi
    
    echo "$version|$tarball_url"
}

# Compare versions (simple string comparison for dev versions)
version_compare() {
    local current=$1
    local latest=$2
    
    if [[ "$current" == "$latest" ]]; then
        return 0  # Same version
    else
        return 1  # Different version
    fi
}

# Download and extract Zig
install_zig() {
    local version=$1
    local tarball_url=$2
    local arch=$3
    
    local version_dir="$ZIG_BASE_DIR/zig-${arch}-${version}"
    
    # Check if already installed
    if [[ -d "$version_dir" ]]; then
        echo "Version $version is already installed at $version_dir"
        return 0
    fi
    
    echo "Downloading Zig $version..."
    local tarball="$TEMP_DIR/zig-${version}.tar.xz"
    
    if ! curl -L -o "$tarball" "$tarball_url"; then
        echo "Error: Failed to download Zig" >&2
        exit 1
    fi
    
    echo "Extracting Zig..."
    mkdir -p "$ZIG_BASE_DIR"
    cd "$ZIG_BASE_DIR"
    
    # Extract to temporary location first to see what directory name is used
    local temp_extract="$TEMP_DIR/extract"
    mkdir -p "$temp_extract"
    
    if ! tar -xf "$tarball" -C "$temp_extract"; then
        echo "Error: Failed to extract archive" >&2
        exit 1
    fi
    
    # Find the extracted directory name
    local extracted_dir=$(find "$temp_extract" -maxdepth 1 -type d -name "zig-*" | head -n1)
    if [[ -z "$extracted_dir" ]]; then
        echo "Error: Could not find extracted directory" >&2
        exit 1
    fi
    
    local dir_name=$(basename "$extracted_dir")
    local target_dir="$ZIG_BASE_DIR/zig-${arch}-${version}"
    
    # Move to final location with our naming convention
    mv "$extracted_dir" "$target_dir"
    
    # Verify the binary exists
    if [[ ! -x "$target_dir/zig" ]]; then
        echo "Error: Zig binary not found after extraction" >&2
        exit 1
    fi
    
    echo "Zig $version installed successfully"
}

# Update symlink to point to latest version
update_symlink() {
    local version=$1
    local arch=$2
    local version_dir="$ZIG_BASE_DIR/zig-${arch}-${version}"
    
    if [[ ! -d "$version_dir" ]]; then
        echo "Error: Version directory not found: $version_dir" >&2
        exit 1
    fi
    
    # Remove old symlink if it exists
    if [[ -L "$ZIG_SYMLINK" ]] || [[ -e "$ZIG_SYMLINK" ]]; then
        rm -f "$ZIG_SYMLINK"
    fi
    
    # Create new symlink
    ln -s "$version_dir" "$ZIG_SYMLINK"
    echo "Symlink updated: $ZIG_SYMLINK -> $version_dir"
}

# Clean up old versions
cleanup_old_versions() {
    local current_version=$1
    local arch=$2
    local current_dir="zig-${arch}-${current_version}"
    
    echo "Cleaning up old versions..."
    cd "$ZIG_BASE_DIR"
    
    local removed=0
    for dir in zig-${arch}-*; do
        if [[ -d "$dir" ]] && [[ "$dir" != "$current_dir" ]]; then
            echo "Removing old version: $dir"
            rm -rf "$dir"
            ((removed++)) || true
        fi
    done
    
    if [[ $removed -eq 0 ]]; then
        echo "No old versions to clean up"
    else
        echo "Removed $removed old version(s)"
    fi
}

# Print instructions for .zshrc
print_zshrc_instructions() {
    echo ""
    echo "=========================================="
    echo "Add this to your ~/.zshrc file:"
    echo "  alias zig=\"$ZIG_SYMLINK/zig\""
    echo ""
    echo "Or add this to your PATH:"
    echo "  export PATH=\"$ZIG_SYMLINK:\$PATH\""
    echo "=========================================="
}

# Main execution
main() {
    local arch=$(detect_arch)
    echo "Detected architecture: $arch"
    
    # Get current version if installed
    local current_version=""
    if current_version=$(get_current_version); then
        echo "Current installed version: $current_version"
    else
        echo "No Zig installation found"
    fi
    
    # Get latest version info
    echo "Fetching latest version information..."
    local version_info=$(get_latest_version_info "$arch")
    local latest_version=$(echo "$version_info" | cut -d'|' -f1)
    local tarball_url=$(echo "$version_info" | cut -d'|' -f2)
    
    echo "Latest available version: $latest_version"
    
    # Check if update is needed
    if [[ -n "$current_version" ]] && [[ "$current_version" == "$latest_version" ]]; then
        echo "Zig is already up to date (version $latest_version)"
        print_zshrc_instructions
        exit 0
    fi
    
    # Install new version
    install_zig "$latest_version" "$tarball_url" "$arch"
    
    # Update symlink
    update_symlink "$latest_version" "$arch"
    
    # Clean up old versions
    cleanup_old_versions "$latest_version" "$arch"
    
    # Print instructions
    print_zshrc_instructions
    
    echo ""
    echo "Installation complete! Run 'source ~/.zshrc' or restart your terminal."
}

main "$@"
