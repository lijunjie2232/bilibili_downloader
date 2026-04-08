#!/bin/bash

# Installation script for Bilibili Downloader system tray dependencies
# This script installs the required libraries for system tray support on Linux

set -e  # Exit on error

echo "========================================="
echo "Bilibili Downloader - System Tray Setup"
echo "========================================="
echo ""

# Check if running on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo "⚠️  This script is for Linux systems only."
    echo "   macOS and Windows don't require additional dependencies."
    exit 0
fi

echo "📋 Checking system information..."
echo ""

# Detect package manager
if command -v apt-get &> /dev/null; then
    PKG_MANAGER="apt"
    echo "✓ Detected: Debian/Ubuntu-based system (apt)"
elif command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
    echo "✓ Detected: Fedora/RHEL-based system (dnf)"
elif command -v pacman &> /dev/null; then
    PKG_MANAGER="pacman"
    echo "✓ Detected: Arch Linux-based system (pacman)"
else
    echo "⚠️  Unknown package manager. Please install dependencies manually."
    echo ""
    echo "Required packages:"
    echo "  - libayatana-appindicator3-dev (or appindicator3-0.1)"
    exit 1
fi

echo ""
echo "🔍 Checking for existing installations..."
echo ""

# Check if already installed
if dpkg -l | grep -q "libayatana-appindicator3"; then
    echo "✓ libayatana-appindicator3 is already installed"
    ALREADY_INSTALLED=true
elif dpkg -l | grep -q "libappindicator3"; then
    echo "✓ libappindicator3 is already installed"
    ALREADY_INSTALLED=true
else
    echo "⚠️  System tray dependencies not found"
    ALREADY_INSTALLED=false
fi

echo ""

# Ask user if they want to proceed
if [ "$ALREADY_INSTALLED" = false ]; then
    echo "📦 The following packages will be installed:"
    echo ""
    
    if [ "$PKG_MANAGER" = "apt" ]; then
        echo "  • libayatana-appindicator3-dev"
    elif [ "$PKG_MANAGER" = "dnf" ]; then
        echo "  • libayatana-appindicator3-devel"
    elif [ "$PKG_MANAGER" = "pacman" ]; then
        echo "  • libayatana-appindicator"
    fi
    
    echo ""
    read -p "Continue with installation? (y/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
else
    echo "Dependencies are already installed."
    read -p "Reinstall anyway? (y/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Setup complete!"
        exit 0
    fi
fi

echo ""
echo "🔧 Installing dependencies..."
echo ""

# Install based on package manager
if [ "$PKG_MANAGER" = "apt" ]; then
    echo "Running: sudo apt-get update"
    sudo apt-get update -qq
    
    echo "Running: sudo apt-get install libayatana-appindicator3-dev"
    sudo apt-get install -y libayatana-appindicator3-dev
    
    # Also check for GNOME extension
    echo ""
    echo "🖥️  Checking for GNOME desktop environment..."
    if command -v gnome-shell &> /dev/null; then
        echo "✓ GNOME detected"
        echo ""
        echo "💡 For GNOME, you may also need the AppIndicator extension:"
        echo "   sudo apt-get install gnome-shell-extension-appindicator"
        echo ""
        echo "   Then enable it through GNOME Tweaks or visit:"
        echo "   https://extensions.gnome.org/extension/615/appindicator-support/"
    fi
    
elif [ "$PKG_MANAGER" = "dnf" ]; then
    echo "Running: sudo dnf install libayatana-appindicator3-devel"
    sudo dnf install -y libayatana-appindicator3-devel
    
elif [ "$PKG_MANAGER" = "pacman" ]; then
    echo "Running: sudo pacman -S libayatana-appindicator"
    sudo pacman -S --noconfirm libayatana-appindicator
fi

echo ""
echo "✅ Dependencies installed successfully!"
echo ""
echo "📝 Next steps:"
echo "   1. Rebuild your Flutter application:"
echo "      flutter build linux --release"
echo ""
echo "   2. Run the application:"
echo "      flutter run -d linux"
echo ""
echo "   3. The system tray icon should now appear when you run the app"
echo ""
echo "📖 For more information, see TRAY_SETUP.md"
echo ""
echo "========================================="
echo "Setup Complete!"
echo "========================================="
