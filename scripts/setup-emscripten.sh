#!/bin/bash

# Setup script for Emscripten and Fortran compiler

echo "Setting up build environment for Convolution Reverb WebAssembly..."

# Detect OS
OS="unknown"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [ -f /etc/fedora-release ]; then
        OS="fedora"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
fi

echo "Detected OS: $OS"

# Install Fortran compiler based on OS
echo "Installing Fortran compiler..."

case $OS in
    fedora|rhel)
        echo "Installing gfortran for Fedora/RHEL..."
        sudo dnf install -y gcc-gfortran
        # For LLVM Flang (experimental):
        # sudo dnf install -y llvm llvm-devel
        # We'll use f2c as an alternative
        sudo dnf install -y f2c
        ;;
    debian)
        echo "Installing gfortran for Debian/Ubuntu..."
        sudo apt-get update
        sudo apt-get install -y gfortran
        # Alternative: flang-11
        sudo apt-get install -y flang-11 || true
        ;;
    macos)
        echo "Installing gfortran for macOS..."
        brew install gcc
        brew install llvm
        ;;
    *)
        echo "Unknown OS. Please install a Fortran compiler manually."
        echo "Options: gfortran, flang, or f2c"
        ;;
esac

# Install Emscripten if not already installed
if ! command -v emcc &> /dev/null; then
    echo "Installing Emscripten..."
    if [ ! -d "emsdk" ]; then
        git clone https://github.com/emscripten-core/emsdk.git
    fi
    cd emsdk
    ./emsdk install latest
    ./emsdk activate latest
    source ./emsdk_env.sh
    cd ..
else
    echo "Emscripten already installed."
fi

# Install additional tools
echo "Installing additional build tools..."
case $OS in
    fedora|rhel)
        sudo dnf install -y cmake make llvm-devel
        ;;
    debian)
        sudo apt-get install -y cmake make llvm-dev
        ;;
    macos)
        brew install cmake
        ;;
esac

echo "Setup complete!"
echo ""
echo "Available Fortran compilers:"
command -v gfortran &> /dev/null && echo "  - gfortran: $(gfortran --version | head -n1)"
command -v flang &> /dev/null && echo "  - flang: $(flang --version | head -n1)"
command -v f2c &> /dev/null && echo "  - f2c: available"
echo ""
echo "To use Emscripten, run: source ./emsdk/emsdk_env.sh"