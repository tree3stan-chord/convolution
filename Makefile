# Makefile for Convolution Reverb WebAssembly

# Compilers
FC = gfortran
CC = emcc
AR = ar

# Directories
SRC_DIR = src
BUILD_DIR = build
OBJ_DIR = $(BUILD_DIR)/obj
FORTRAN_DIR = $(SRC_DIR)/fortran
C_DIR = $(SRC_DIR)/c
JS_DIR = $(SRC_DIR)/js
WEB_DIR = web

# Compiler flags
FFLAGS = -O3 -ffast-math -fPIC -c -J$(OBJ_DIR)
CFLAGS = -O3 -ffast-math -I$(C_DIR)
ARFLAGS = rcs

# Emscripten flags
EMFLAGS = -s WASM=1 \
          -s EXPORTED_FUNCTIONS='["_init_engine","_process_audio","_set_parameter","_set_ir_type","_cleanup_engine","_allocate_double_array","_free_double_array","_is_initialized","_get_sample_rate","_get_version","_process_audio_with_mix"]' \
          -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap","allocateUTF8","UTF8ToString"]' \
          -s ALLOW_MEMORY_GROWTH=1 \
          -s INITIAL_MEMORY=33554432 \
          -s MAXIMUM_MEMORY=2147483648 \
          -s MODULARIZE=1 \
          -s EXPORT_NAME='ConvolutionModule' \
          -s ENVIRONMENT='web' \
          -s SINGLE_FILE=0 \
          -s WASM_ASYNC_COMPILATION=1 \
          -s ERROR_ON_UNDEFINED_SYMBOLS=0 \
          -O3

# Source files
FORTRAN_SOURCES = $(FORTRAN_DIR)/constants.f90 \
                  $(FORTRAN_DIR)/fft_module.f90 \
                  $(FORTRAN_DIR)/impulse_response.f90 \
                  $(FORTRAN_DIR)/convolution_reverb.f90

C_SOURCES = $(C_DIR)/wasm_bridge.c

# Object files
FORTRAN_OBJECTS = $(OBJ_DIR)/constants.o \
                  $(OBJ_DIR)/fft_module.o \
                  $(OBJ_DIR)/impulse_response.o \
                  $(OBJ_DIR)/convolution_reverb.o

C_OBJECTS = $(OBJ_DIR)/wasm_bridge.o

# Web files to copy
WEB_FILES = $(WEB_DIR)/index.html \
            $(WEB_DIR)/style.css \
            $(WEB_DIR)/app.js \
            $(JS_DIR)/convolution-module.js \
            $(JS_DIR)/audio-processor.js

# Target files
FORTRAN_LIB = $(OBJ_DIR)/libconvolution.a
WASM_TARGET = $(BUILD_DIR)/convolution_reverb.js

# Default target
all: $(WASM_TARGET) copy_web_files

# Create directories
$(OBJ_DIR):
	@mkdir -p $(OBJ_DIR)

# Fortran compilation rules (order matters for modules)
$(OBJ_DIR)/constants.o: $(FORTRAN_DIR)/constants.f90 | $(OBJ_DIR)
	@echo "Compiling constants.f90..."
	$(FC) $(FFLAGS) -o $@ $<

$(OBJ_DIR)/fft_module.o: $(FORTRAN_DIR)/fft_module.f90 $(OBJ_DIR)/constants.o | $(OBJ_DIR)
	@echo "Compiling fft_module.f90..."
	$(FC) $(FFLAGS) -o $@ $<

$(OBJ_DIR)/impulse_response.o: $(FORTRAN_DIR)/impulse_response.f90 $(OBJ_DIR)/constants.o | $(OBJ_DIR)
	@echo "Compiling impulse_response.f90..."
	$(FC) $(FFLAGS) -o $@ $<

$(OBJ_DIR)/convolution_reverb.o: $(FORTRAN_DIR)/convolution_reverb.f90 $(OBJ_DIR)/constants.o $(OBJ_DIR)/fft_module.o $(OBJ_DIR)/impulse_response.o | $(OBJ_DIR)
	@echo "Compiling convolution_reverb.f90..."
	$(FC) $(FFLAGS) -o $@ $<

# Create static library from Fortran objects
$(FORTRAN_LIB): $(FORTRAN_OBJECTS)
	@echo "Creating Fortran static library..."
	$(AR) $(ARFLAGS) $@ $^

# C compilation
$(OBJ_DIR)/wasm_bridge.o: $(C_DIR)/wasm_bridge.c $(C_DIR)/wasm_bridge.h | $(OBJ_DIR)
	@echo "Compiling wasm_bridge.c..."
	$(CC) $(CFLAGS) -c -o $@ $<

# Link to WebAssembly
$(WASM_TARGET): $(C_OBJECTS) $(FORTRAN_LIB)
	@echo "Linking WebAssembly module..."
	$(CC) $(CFLAGS) $(EMFLAGS) -o $@ $(C_OBJECTS) $(FORTRAN_LIB)
	@echo "WebAssembly module created successfully!"

# Copy web files
copy_web_files: $(WASM_TARGET)
	@echo "Copying web files..."
	@cp $(WEB_FILES) $(BUILD_DIR)/
	@echo "Creating test.html..."
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
                document.getElementById('status').textContent = 'Module loaded successfully! Version: ' + processor.getVersion();
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

# Install target
install: all
	@echo "Installing to /usr/local/share/convolution-reverb..."
	@mkdir -p /usr/local/share/convolution-reverb
	@cp -r $(BUILD_DIR)/* /usr/local/share/convolution-reverb/

# Development server
serve: all
	@echo "Starting development server on http://localhost:8000"
	@cd $(BUILD_DIR) && python3 -m http.server 8000

# Help
help:
	@echo "Convolution Reverb WebAssembly Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build WebAssembly module and copy web files (default)"
	@echo "  clean    - Remove build directory"
	@echo "  install  - Install to system directory"
	@echo "  serve    - Start development server"
	@echo "  help     - Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  FC       - Fortran compiler (default: gfortran)"
	@echo "  CC       - C/Emscripten compiler (default: emcc)"
	@echo ""
	@echo "Usage:"
	@echo "  make              - Build everything"
	@echo "  make clean        - Clean build"
	@echo "  make serve        - Build and start server"
	@echo "  make FC=flang     - Build with flang compiler"

.PHONY: all clean install serve help copy_web_files