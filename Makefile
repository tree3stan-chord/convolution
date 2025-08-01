# Makefile for Convolution Reverb WebAssembly (C-only version)

# Compiler
CC = emcc

# Directories
SRC_DIR = src
BUILD_DIR = build
C_DIR = $(SRC_DIR)/c
JS_DIR = $(SRC_DIR)/js
WEB_DIR = web

# Compiler flags
CFLAGS = -O3 -I$(C_DIR)

# Emscripten flags
EMFLAGS = -s WASM=1 \
          -s EXPORTED_FUNCTIONS='["_init_engine","_process_audio","_set_parameter","_set_ir_type","_cleanup_engine","_allocate_double_array","_free_double_array","_is_initialized","_get_sample_rate","_get_version","_process_audio_with_mix"]' \
          -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap","stringToUTF8","UTF8ToString"]' \
          -s ALLOW_MEMORY_GROWTH=1 \
          -s INITIAL_MEMORY=33554432 \
          -s MAXIMUM_MEMORY=2147483648 \
          -s MODULARIZE=1 \
          -s EXPORT_NAME='ConvolutionModule' \
          -s ENVIRONMENT='web' \
          -s SINGLE_FILE=0 \
          -O3

# Source files
C_SOURCES = $(C_DIR)/wasm_bridge.c \
            $(C_DIR)/convolution_engine.c

# Web files to copy
WEB_FILES = $(WEB_DIR)/index.html \
            $(WEB_DIR)/style.css \
            $(JS_DIR)/convolution-module.js \
            $(JS_DIR)/audio-processor.js

# Target files
WASM_TARGET = $(BUILD_DIR)/convolution_reverb.js

# Default target
all: $(WASM_TARGET) copy_files

# Create build directory
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Compile to WebAssembly
$(WASM_TARGET): $(C_SOURCES) | $(BUILD_DIR)
	@echo "Compiling to WebAssembly..."
	$(CC) $(CFLAGS) $(EMFLAGS) $(C_SOURCES) -o $@
	@echo "WebAssembly compilation complete!"

# Copy web files
copy_files: $(WASM_TARGET)
	@echo "Copying web files..."
	@cp $(WEB_FILES) $(BUILD_DIR)/
	@echo "Creating .htaccess..."
	@echo 'AddType application/wasm .wasm' > $(BUILD_DIR)/.htaccess
	@echo '<FilesMatch "\.(wasm)$$">' >> $(BUILD_DIR)/.htaccess
	@echo '    Header set Access-Control-Allow-Origin "*"' >> $(BUILD_DIR)/.htaccess
	@echo '</FilesMatch>' >> $(BUILD_DIR)/.htaccess
	@echo "Creating test page..."
	@cat > $(BUILD_DIR)/test.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Convolution Reverb Test</title>
    <meta charset="UTF-8">
</head>
<body>
    <h1>Convolution Reverb WebAssembly Test</h1>
    <div id="status">Loading...</div>
    <script src="convolution-module.js"></script>
    <script>
        async function test() {
            try {
                const processor = new ConvolutionProcessor();
                await processor.initialize('./', 48000);
                document.getElementById('status').textContent = 'Module loaded! Version: ' + processor.getVersion();
            } catch (error) {
                document.getElementById('status').textContent = 'Error: ' + error.message;
            }
        }
        test();
    </script>
</body>
</html>
EOF

# Clean build
clean:
	@echo "Cleaning build directory..."
	@rm -rf $(BUILD_DIR)

# Install (deploy) target
install: all
	@echo "Deploying to server..."
	@bash scripts/build-c.sh --deploy

# Development server
serve: all
	@echo "Starting development server on http://localhost:8000"
	@cd $(BUILD_DIR) && python3 -m http.server 8000

# Check prerequisites
check:
	@echo "Checking prerequisites..."
	@which emcc > /dev/null || (echo "Error: Emscripten not found!" && exit 1)
	@echo "✓ Emscripten found: $$(emcc --version | head -n1)"

# Help
help:
	@echo "Convolution Reverb WebAssembly Makefile (C-only)"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build WebAssembly module (default)"
	@echo "  clean    - Remove build directory"
	@echo "  serve    - Start development server"
	@echo "  install  - Deploy to production server"
	@echo "  check    - Check prerequisites"
	@echo "  help     - Show this help message"
	@echo ""
	@echo "Usage:"
	@echo "  make              - Build everything"
	@echo "  make clean        - Clean build"
	@echo "  make serve        - Build and test locally"
	@echo "  make install      - Build and deploy"

.PHONY: all clean install serve check help copy_files