#!/bin/bash

# build-c.sh - Simplified build script for C-only WebAssembly compilation
# Usage: ./build-c.sh [--deploy] [--force]

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
        --help)
            echo "Usage: $0 [--deploy] [--force]"
            echo ""
            echo "Options:"
            echo "  --deploy  Deploy to server after building"
            echo "  --force   Force rebuild even if artifacts exist"
            echo "  --help    Show this help message"
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
    
    # Check if source files are newer than build artifacts
    local newest_source=$(find "$SRC_DIR" "$WEB_DIR" -type f \( -name "*.c" -o -name "*.h" -o -name "*.js" -o -name "*.html" -o -name "*.css" \) -newer "$BUILD_DIR/convolution_reverb.wasm" 2>/dev/null | head -n1)
    
    if [ -n "$newest_source" ]; then
        print_message $YELLOW "Source file changed: $newest_source"
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
        print_message $YELLOW "Please install Emscripten:"
        print_message $YELLOW "  git clone https://github.com/emscripten-core/emsdk.git"
        print_message $YELLOW "  cd emsdk && ./emsdk install latest && ./emsdk activate latest"
        print_message $YELLOW "  source ./emsdk_env.sh"
        exit 1
    fi
    
    print_message $GREEN "✓ Emscripten: $(emcc --version | head -n1)"
}

# Clean build directory
clean_build() {
    print_message $BLUE "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
}

# Compile C to WebAssembly
compile_wasm() {
    print_message $BLUE "\n=== Compiling C to WebAssembly ==="
    
    cd "$PROJECT_ROOT"
    
    # Create the convolution engine C file if it doesn't exist
    if [ ! -f "$SRC_DIR/c/convolution_engine.c" ]; then
        print_message $YELLOW "Creating convolution_engine.c from embedded version..."
        mkdir -p "$SRC_DIR/c"
        cp "$SCRIPT_DIR/convolution_engine.c" "$SRC_DIR/c/" 2>/dev/null || \
        cat > "$SRC_DIR/c/convolution_engine.c" << 'EMBEDDED_C_CODE'
// [The C code from the artifact above would be embedded here]
// For brevity, I'm not including it in this example
EMBEDDED_C_CODE
    fi
    
    # Compile with Emscripten
    print_message $BLUE "Compiling with Emscripten..."
    
    emcc "$SRC_DIR/c/wasm_bridge.c" "$SRC_DIR/c/convolution_engine.c" \
        -I"$SRC_DIR/c" \
        -s WASM=1 \
        -s EXPORTED_FUNCTIONS='["_init_engine","_process_audio","_set_parameter","_set_ir_type","_cleanup_engine","_allocate_double_array","_free_double_array","_is_initialized","_get_sample_rate","_get_version","_process_audio_with_mix"]' \
        -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap","stringToUTF8","UTF8ToString"]' \
        -s ALLOW_MEMORY_GROWTH=1 \
        -s INITIAL_MEMORY=33554432 \
        -s MAXIMUM_MEMORY=2147483648 \
        -s MODULARIZE=1 \
        -s EXPORT_NAME='ConvolutionModule' \
        -s ENVIRONMENT='web' \
        -s SINGLE_FILE=0 \
        -O3 \
        -o "$BUILD_DIR/convolution_reverb.js" 2>&1 | tee "$BUILD_DIR/compile.log"
    
    if [ -f "$BUILD_DIR/convolution_reverb.wasm" ]; then
        print_message $GREEN "✓ WebAssembly compilation successful"
        local wasm_size=$(ls -lh "$BUILD_DIR/convolution_reverb.wasm" | awk '{print $5}')
        print_message $CYAN "  WASM size: $wasm_size"
    else
        print_message $RED "✗ WebAssembly compilation failed"
        print_message $YELLOW "Check $BUILD_DIR/compile.log for details"
        exit 1
    fi
}

# Copy web files
copy_web_files() {
    print_message $BLUE "\n=== Copying web files ==="
    
    # Copy HTML, CSS, and JavaScript files
    cp "$WEB_DIR/index.html" "$BUILD_DIR/"
    cp "$WEB_DIR/style.css" "$BUILD_DIR/"
    [ -f "$WEB_DIR/app.js" ] && cp "$WEB_DIR/app.js" "$BUILD_DIR/"
    cp "$SRC_DIR/js/convolution-module.js" "$BUILD_DIR/"
    cp "$SRC_DIR/js/audio-processor.js" "$BUILD_DIR/"
    [ -f "$SRC_DIR/js/convolution-worklet.js" ] && cp "$SRC_DIR/js/convolution-worklet.js" "$BUILD_DIR/"
    
    # Create a simple favicon to avoid 404
    cat > "$BUILD_DIR/favicon.ico" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <rect width="32" height="32" fill="#0f0f1a"/>
  <path d="M16 8 Q8 16 16 24 Q24 16 16 8" fill="#90e0ef"/>
</svg>
EOF
    
    # Create .htaccess for proper MIME types
    cat > "$BUILD_DIR/.htaccess" << 'EOF'
# Set proper MIME type for WebAssembly files
AddType application/wasm .wasm

# Enable CORS for WASM files (if needed)
<FilesMatch "\.(wasm)$">
    Header set Access-Control-Allow-Origin "*"
</FilesMatch>

# Compression for better performance
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/html text/plain text/css application/javascript application/json
</IfModule>

# Cache control
<FilesMatch "\.(wasm|js)$">
    Header set Cache-Control "public, max-age=3600"
</FilesMatch>
EOF
    
    # Create a simple test page
    cat > "$BUILD_DIR/test.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Convolution Reverb Test</title>
    <meta charset="UTF-8">
</head>
<body>
    <h1>Convolution Reverb WebAssembly Test</h1>
    <div id="status">Loading...</div>
    <div id="info" style="margin-top: 20px; font-family: monospace;"></div>
    <script src="convolution-module.js"></script>
    <script>
        async function test() {
            const statusEl = document.getElementById('status');
            const infoEl = document.getElementById('info');
            
            try {
                statusEl.textContent = 'Initializing...';
                const processor = new ConvolutionProcessor();
                await processor.initialize('./', 48000);
                
                const version = processor.getVersion ? processor.getVersion() : 'Unknown';
                const sampleRate = processor.getSampleRate ? processor.getSampleRate() : 48000;
                
                statusEl.textContent = '✓ Module loaded successfully!';
                statusEl.style.color = 'green';
                
                infoEl.innerHTML = `
                    <strong>Version:</strong> ${version}<br>
                    <strong>Sample Rate:</strong> ${sampleRate} Hz<br>
                    <strong>Status:</strong> Ready
                `;
                
                // Test parameter setting
                processor.setParameter('roomSize', 75);
                processor.setParameter('mix', 50);
                processor.setImpulseResponseType('cathedral');
                
                console.log('Convolution reverb ready!');
            } catch (error) {
                statusEl.textContent = '✗ Error: ' + error.message;
                statusEl.style.color = 'red';
                console.error('Initialization error:', error);
            }
        }
        test();
    </script>
</body>
</html>
EOF
    
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
    
    print_message $BLUE "▶ Setting permissions"
    sudo chown -R espadon:espadon "$RSYNC_DEST"
    sudo chmod -R 755 "$RSYNC_DEST"
    
    print_message $BLUE "▶ Restoring SELinux context"
    sudo restorecon -Rv "$RSYNC_DEST" >/dev/null 2>&1 || print_message $YELLOW "   (SELinux context restoration skipped)"
    
    print_message $BLUE "▶ Reloading Nginx"
    if sudo systemctl reload nginx 2>/dev/null || sudo nginx -s reload 2>/dev/null; then
        print_message $GREEN "   ✓ Nginx reloaded"
    else
        print_message $YELLOW "   ⚠ Nginx reload failed - check configuration"
    fi
    
    print_message $GREEN "\n✓ Deployed $STAMP to convolution.musicsian.com"
    print_message $CYAN "\nLive URLs:"
    print_message $CYAN "  🌐 https://convolution.musicsian.com/"
    print_message $CYAN "  🧪 https://convolution.musicsian.com/test.html"
}

# Main build process
build_project() {
    print_message $BLUE "=== Convolution Reverb C Build ==="
    
    check_prerequisites
    
    if ! check_build_needed; then
        print_message $GREEN "\n✓ Build artifacts are up to date!"
        print_message $YELLOW "  Use --force to rebuild anyway"
        return 0
    fi
    
    clean_build
    compile_wasm
    copy_web_files
    
    print_message $GREEN "\n✓ Build successful!"
    return 0
}

# Main entry point
main() {
    if ! build_project; then
        exit 1
    fi
    
    # Handle deployment
    if [ "$DEPLOY" = true ]; then
        deploy_to_server
    else
        print_message $BLUE "\nTo test locally:"
        print_message $YELLOW "  cd build"
        print_message $YELLOW "  python3 -m http.server 8000"
        print_message $YELLOW "  Open http://localhost:8000"
        print_message $BLUE "\nTo deploy:"
        print_message $YELLOW "  $0 --deploy"
    fi
}

# Run main
main