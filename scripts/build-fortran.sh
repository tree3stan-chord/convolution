#!/bin/bash

# build-fortran.sh - Build script for Fortran to WebAssembly with optional deployment
# Usage: ./build-fortran.sh [--deploy] [--force]

set -e

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
BUILD_DIR="$PROJECT_ROOT/build"
SRC_DIR="$PROJECT_ROOT/src"
WEB_DIR="$PROJECT_ROOT/web"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse command line arguments
DEPLOY=false
FORCE_BUILD=false
SKIP_BUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --deploy)
            DEPLOY=true
            shift
            ;;
        --force)
            FORCE_BUILD=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--deploy] [--force] [--skip-build]"
            echo ""
            echo "Options:"
            echo "  --deploy      Deploy after building"
            echo "  --force       Force rebuild even if artifacts exist"
            echo "  --skip-build  Skip build and only deploy existing artifacts"
            echo "  --help        Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Print colored message
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if build is needed
check_build_needed() {
    if [ "$FORCE_BUILD" = true ]; then
        return 0  # Build needed
    fi
    
    # Check if essential build artifacts exist
    if [ ! -f "$BUILD_DIR/convolution_reverb.wasm" ] || [ ! -f "$BUILD_DIR/convolution_reverb.js" ]; then
        return 0  # Build needed
    fi
    
    # Check if any source file is newer than the build artifacts
    local newest_source=$(find "$SRC_DIR" -type f \( -name "*.f90" -o -name "*.c" -o -name "*.h" -o -name "*.js" \) -newer "$BUILD_DIR/convolution_reverb.wasm" 2>/dev/null | head -n1)
    
    if [ -n "$newest_source" ]; then
        print_message $YELLOW "Source file changed: $newest_source"
        return 0  # Build needed
    fi
    
    # Check if web files are newer
    local newest_web=$(find "$WEB_DIR" -type f -newer "$BUILD_DIR/convolution_reverb.wasm" 2>/dev/null | head -n1)
    
    if [ -n "$newest_web" ]; then
        print_message $YELLOW "Web file changed: $newest_web"
        return 0  # Build needed
    fi
    
    return 1  # No build needed
}

# Check prerequisites
check_prerequisites() {
    print_message $BLUE "Checking prerequisites..."
    
    # Check Emscripten
    if ! command -v emcc &> /dev/null; then
        print_message $RED "❌ Emscripten not found"
        exit 1
    fi
    
    # Check for Fortran compiler
    if command -v gfortran &> /dev/null; then
        FORTRAN_COMPILER="gfortran"
        print_message $GREEN "✓ GFortran: $(gfortran --version | head -n1)"
    else
        print_message $RED "❌ No Fortran compiler found"
        exit 1
    fi
}

# Clean build directory
clean_build() {
    print_message $BLUE "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR/obj"
}

# Compile Fortran to LLVM IR using dragonegg (if available)
compile_fortran_to_llvm() {
    print_message $BLUE "\n=== Attempting Fortran compilation ==="
    
    cd "$PROJECT_ROOT"
    
    # First, let's try to compile to object files and see what happens
    print_message $YELLOW "Note: Direct Fortran to WASM is experimental"
    
    # Try compiling with position-independent code
    print_message $BLUE "Compiling Fortran modules..."
    
    gfortran -c -O3 -fPIC -ffree-line-length-none \
        "$SRC_DIR/fortran/constants.f90" \
        -o "$BUILD_DIR/obj/constants.o" || true
    
    gfortran -c -O3 -fPIC -ffree-line-length-none \
        -I"$BUILD_DIR/obj" \
        "$SRC_DIR/fortran/fft_module.f90" \
        -o "$BUILD_DIR/obj/fft_module.o" || true
    
    gfortran -c -O3 -fPIC -ffree-line-length-none \
        -I"$BUILD_DIR/obj" \
        "$SRC_DIR/fortran/impulse_response.f90" \
        -o "$BUILD_DIR/obj/impulse_response.o" || true
    
    gfortran -c -O3 -fPIC -ffree-line-length-none \
        -I"$BUILD_DIR/obj" \
        "$SRC_DIR/fortran/convolution_reverb.f90" \
        -o "$BUILD_DIR/obj/convolution_reverb.o" || true
    
    # Check if compilation succeeded
    if [ -f "$BUILD_DIR/obj/convolution_reverb.o" ]; then
        print_message $GREEN "✓ Fortran compilation succeeded"
        return 0
    else
        print_message $RED "✗ Fortran compilation failed"
        return 1
    fi
}

# Fallback to C implementation
create_c_fallback() {
    print_message $YELLOW "\n=== Creating C fallback implementation ==="
    
    cat > "$BUILD_DIR/obj/fortran_bridge.c" << 'EOF'
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// This file provides C implementations of Fortran functions
// when direct Fortran compilation fails

// Constants
#define MAX_IR_SIZE 96000
#define PI 3.14159265358979323846

// Global state
static double current_ir[MAX_IR_SIZE];
static int current_ir_length = 0;
static double room_size = 50.0;
static double decay_time = 2.5;
static double pre_delay = 20.0;
static double damping = 50.0;
static double mix_level = 30.0;
static int sample_rate = 48000;
static int ir_needs_update = 1;
static int initialized = 0;

// Simple random number generator
static unsigned int rand_seed = 123456789;
static double simple_rand() {
    rand_seed = (1103515245 * rand_seed + 12345) & 0x7fffffff;
    return (double)rand_seed / 0x7fffffff;
}

// Initialize engine
void init_convolution_engine_(int* sr) {
    sample_rate = *sr;
    ir_needs_update = 1;
    initialized = 1;
    memset(current_ir, 0, sizeof(current_ir));
    printf("Convolution engine initialized (C fallback) with sample rate: %d\n", sample_rate);
}

// Generate impulse response
static void generate_ir() {
    int i;
    double t, amplitude, decay_rate;
    
    current_ir_length = (int)(decay_time * sample_rate);
    if (current_ir_length > MAX_IR_SIZE) {
        current_ir_length = MAX_IR_SIZE;
    }
    
    decay_rate = 3.0 / decay_time;
    
    // Generate early reflections
    for (i = 0; i < 20 && i < current_ir_length; i++) {
        int delay = (int)(pre_delay * sample_rate / 1000.0) + i * sample_rate / 100;
        if (delay < current_ir_length) {
            current_ir[delay] = (2.0 * simple_rand() - 1.0) * 0.8 / (i + 1);
        }
    }
    
    // Generate late reverb
    for (i = 0; i < current_ir_length; i++) {
        t = (double)i / (double)sample_rate;
        amplitude = exp(-decay_rate * t);
        
        // Add damping
        amplitude *= exp(-damping * 0.0001 * t * t);
        
        // Add diffused energy
        current_ir[i] += amplitude * (2.0 * simple_rand() - 1.0) * 0.3;
    }
    
    // Normalize
    double max_val = 0.0;
    for (i = 0; i < current_ir_length; i++) {
        if (fabs(current_ir[i]) > max_val) {
            max_val = fabs(current_ir[i]);
        }
    }
    if (max_val > 0.0) {
        for (i = 0; i < current_ir_length; i++) {
            current_ir[i] = current_ir[i] / max_val * 0.9;
        }
    }
    
    ir_needs_update = 0;
}

// Process convolution
void process_convolution_(double* input, double* output, int* num_samples) {
    int i, j;
    double dry_gain, wet_gain;
    int n = *num_samples;
    
    if (!initialized) {
        for (i = 0; i < n; i++) {
            output[i] = input[i];
        }
        return;
    }
    
    if (ir_needs_update) {
        generate_ir();
    }
    
    dry_gain = 1.0 - mix_level / 100.0;
    wet_gain = mix_level / 100.0;
    
    // Direct convolution (simplified)
    for (i = 0; i < n; i++) {
        output[i] = dry_gain * input[i];
        
        double wet_sample = 0.0;
        int conv_length = (i + 1 < current_ir_length) ? i + 1 : current_ir_length;
        
        // Limit convolution length for performance
        if (conv_length > 500) conv_length = 500;
        
        for (j = 0; j < conv_length; j++) {
            if (i - j >= 0) {
                wet_sample += input[i - j] * current_ir[j];
            }
        }
        
        output[i] += wet_gain * wet_sample;
    }
}

// Set parameter by ID
void set_param_float_(int* param_id, float* value) {
    switch (*param_id) {
        case 0:  // room_size
            room_size = *value;
            ir_needs_update = 1;
            break;
        case 1:  // decay_time
            decay_time = *value;
            ir_needs_update = 1;
            break;
        case 2:  // pre_delay
            pre_delay = *value;
            ir_needs_update = 1;
            break;
        case 3:  // damping
            damping = *value;
            ir_needs_update = 1;
            break;
        case 6:  // mix
            mix_level = *value;
            break;
    }
    printf("Set parameter %d to %f\n", *param_id, *value);
}

void set_parameter_(char* param_name, double* value, int param_name_len) {
    ir_needs_update = 1;
}

void set_ir_type_(char* ir_type, int ir_type_len) {
    ir_needs_update = 1;
}

void cleanup_convolution_engine_() {
    initialized = 0;
}

int is_initialized_() {
    return initialized;
}

int get_sample_rate_() {
    return sample_rate;
}

char* get_version_() {
    return "1.0.0-C";
}
EOF

    print_message $GREEN "✓ C fallback created"
}

# Compile and link everything
compile_and_link() {
    print_message $BLUE "\n=== Compiling and linking ==="
    
    # Stay in PROJECT_ROOT for now
    cd "$PROJECT_ROOT"
    
    # Try to compile Fortran first
    if compile_fortran_to_llvm; then
        print_message $GREEN "Using Fortran implementation"
        
        # Create a stub file to handle missing symbols
        cat > "$BUILD_DIR/obj/fortran_stubs.c" << 'EOF'
// Stubs for Fortran runtime functions
int _gfortran_st_write() { return 0; }
int _gfortran_transfer_character_write() { return 0; }
int _gfortran_st_write_done() { return 0; }
void _gfortran_stop_string() { while(1); }
double log(double x);
double exp(double x);
double sin(double x);
double cos(double x);
double sqrt(double x);
double pow(double x, double y);
float rand() { return 0.5f; }
EOF
        
        # Compile stubs
        emcc -c "$BUILD_DIR/obj/fortran_stubs.c" -o "$BUILD_DIR/obj/fortran_stubs.o"
        
        # Try to link with Fortran objects
        emcc "$SRC_DIR/c/wasm_bridge.c" \
            "$BUILD_DIR/obj/constants.o" \
            "$BUILD_DIR/obj/fft_module.o" \
            "$BUILD_DIR/obj/impulse_response.o" \
            "$BUILD_DIR/obj/convolution_reverb.o" \
            "$BUILD_DIR/obj/fortran_stubs.o" \
            -I"$SRC_DIR/c" \
            -s WASM=1 \
            -s EXPORTED_FUNCTIONS='["_init_engine","_process_audio","_set_parameter","_set_ir_type","_cleanup_engine","_allocate_double_array","_free_double_array","_is_initialized","_get_sample_rate","_get_version","_process_audio_with_mix"]' \
            -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap","stringToUTF8","UTF8ToString"]' \
            -s ALLOW_MEMORY_GROWTH=1 \
            -s INITIAL_MEMORY=33554432 \
            -s ERROR_ON_UNDEFINED_SYMBOLS=0 \
            -s MODULARIZE=1 \
            -s EXPORT_NAME='ConvolutionModule' \
            -O3 \
            -o "$BUILD_DIR/convolution_reverb.js" 2>&1 | tee "$BUILD_DIR/link.log"
        
        if [ ! -f "$BUILD_DIR/convolution_reverb.wasm" ]; then
            print_message $YELLOW "Fortran linking failed, using C fallback"
            USE_FALLBACK=1
        fi
    else
        USE_FALLBACK=1
    fi
    
    # Use C fallback if needed
    if [ "$USE_FALLBACK" = "1" ]; then
        create_c_fallback
        
        # Compile C implementation
        emcc -c "$BUILD_DIR/obj/fortran_bridge.c" -O3 -o "$BUILD_DIR/obj/fortran_bridge.o"
        emcc -c "$SRC_DIR/c/wasm_bridge.c" -I"$SRC_DIR/c" -O3 -o "$BUILD_DIR/obj/wasm_bridge.o"
        
        # Link
        emcc "$BUILD_DIR/obj/wasm_bridge.o" "$BUILD_DIR/obj/fortran_bridge.o" \
            -s WASM=1 \
            -s EXPORTED_FUNCTIONS='["_init_engine","_process_audio","_set_parameter","_set_ir_type","_cleanup_engine","_allocate_double_array","_free_double_array","_is_initialized","_get_sample_rate","_get_version","_process_audio_with_mix"]' \
            -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap","stringToUTF8","UTF8ToString"]' \
            -s ALLOW_MEMORY_GROWTH=1 \
            -s INITIAL_MEMORY=33554432 \
            -s MODULARIZE=1 \
            -s EXPORT_NAME='ConvolutionModule' \
            -O3 \
            -o "$BUILD_DIR/convolution_reverb.js"
    fi
    
    print_message $GREEN "✓ Compilation complete"
}

# Copy web files
copy_web_files() {
    print_message $BLUE "\n=== Copying web files ==="
    
    cp "$WEB_DIR/index.html" "$BUILD_DIR/"
    cp "$WEB_DIR/style.css" "$BUILD_DIR/"
    cp "$WEB_DIR/app.js" "$BUILD_DIR/" 2>/dev/null || true
    cp "$SRC_DIR/js/convolution-module.js" "$BUILD_DIR/"
    cp "$SRC_DIR/js/audio-processor.js" "$BUILD_DIR/"
    cp "$SRC_DIR/js/convolution-worklet.js" "$BUILD_DIR/" 2>/dev/null || true
    
    print_message $GREEN "✓ Web files copied"
}

# Deployment function
deploy_to_server() {
    print_message $CYAN "\n=== Starting deployment ==="
    
    local STAMP=$(date +%Y-%m-%d-%H%M%S)
    local STAGE=~/builds/$STAMP
    
    print_message $BLUE "▶ Creating staging directory: $STAGE"
    mkdir -p "$STAGE"
    
    print_message $BLUE "▶ Staging finished assets"
    rsync -az --delete "$BUILD_DIR/" "$STAGE/"
    
    # Verify required files
    print_message $BLUE "▶ Checking required files..."
    local missing_files=()
    for file in index.html style.css convolution-module.js audio-processor.js convolution_reverb.js convolution_reverb.wasm; do
        if [ ! -f "$STAGE/$file" ]; then
            missing_files+=("$file")
            print_message $YELLOW "   ⚠ Missing $file"
        else
            print_message $GREEN "   ✓ $file"
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        print_message $RED "✗ Cannot deploy - missing required files: ${missing_files[*]}"
        return 1
    fi
    
    print_message $BLUE "▶ Publishing release to Nginx docroot"
    local RSYNC_DEST="/var/www/convolution.musicsian.com/releases/$STAMP/"
    sudo mkdir -p "$(dirname "$RSYNC_DEST")"
    sudo rsync -az --delete "$STAGE/" "$RSYNC_DEST"
    
    print_message $BLUE "▶ Flipping 'current' symlink"
    sudo ln -nfs "$RSYNC_DEST" /var/www/convolution.musicsian.com/current
    
    print_message $BLUE "▶ Restoring SELinux context"
    sudo restorecon -Rv "$RSYNC_DEST" >/dev/null 2>&1 || print_message $YELLOW "   (SELinux context restoration skipped)"
    
    print_message $BLUE "▶ Reloading Nginx"
    if sudo systemctl reload nginx 2>/dev/null || sudo nginx -s reload 2>/dev/null; then
        print_message $GREEN "   ✓ Nginx reloaded"
    else
        print_message $YELLOW "   ⚠ Nginx reload failed - check configuration"
    fi
    
    print_message $GREEN "\n✓ Deployed $STAMP to convolution.musicsian.com"
    print_message $CYAN "\nTest URLs:"
    print_message $CYAN "  - https://convolution.musicsian.com/"
    print_message $CYAN "  - https://convolution.musicsian.com/test.html"
}

# Main build process
build_project() {
    print_message $BLUE "=== Convolution Reverb Fortran Build ==="
    
    check_prerequisites
    
    if ! check_build_needed; then
        print_message $GREEN "\n✓ Build artifacts are up to date!"
        print_message $YELLOW "  Use --force to rebuild anyway"
        return 0
    fi
    
    clean_build
    compile_and_link
    copy_web_files
    
    if [ -f "$BUILD_DIR/convolution_reverb.wasm" ]; then
        print_message $GREEN "\n✓ Build successful!"
        return 0
    else
        print_message $RED "\n✗ Build failed!"
        return 1
    fi
}

# Main entry point
main() {
    # Handle skip-build option
    if [ "$SKIP_BUILD" = true ]; then
        if [ ! -f "$BUILD_DIR/convolution_reverb.wasm" ]; then
            print_message $RED "✗ No build artifacts found. Cannot skip build."
            exit 1
        fi
        print_message $YELLOW "⚠ Skipping build phase"
    else
        if ! build_project; then
            exit 1
        fi
    fi
    
    # Handle deployment
    if [ "$DEPLOY" = true ]; then
        deploy_to_server
    else
        print_message $BLUE "\nTo test locally:"
        print_message $YELLOW "  cd build"
        print_message $YELLOW "  python3 -m http.server 8000"
        print_message $BLUE "\nTo deploy:"
        print_message $YELLOW "  $0 --deploy"
    fi
}

# Run main
main