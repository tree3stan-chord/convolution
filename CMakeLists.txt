cmake_minimum_required(VERSION 3.10)
project(ConvolutionReverbWASM C Fortran)

# Set build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Emscripten toolchain check
if(EMSCRIPTEN)
    message(STATUS "Building with Emscripten")
    set(CMAKE_EXECUTABLE_SUFFIX ".js")
else()
    message(WARNING "Not using Emscripten toolchain. Use emcmake to configure.")
endif()

# Compiler settings
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Fortran compiler settings
if(CMAKE_Fortran_COMPILER_ID MATCHES "GNU")
    set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -O3 -ffast-math -fPIC")
elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Flang")
    set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -O3 -ffast-math")
endif()

# C compiler settings
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O3 -ffast-math")

# Source directories
set(SRC_DIR ${CMAKE_SOURCE_DIR}/src)
set(FORTRAN_DIR ${SRC_DIR}/fortran)
set(C_DIR ${SRC_DIR}/c)

# Fortran source files (order matters for module dependencies)
set(FORTRAN_SOURCES
    ${FORTRAN_DIR}/constants.f90
    ${FORTRAN_DIR}/fft_module.f90
    ${FORTRAN_DIR}/impulse_response.f90
    ${FORTRAN_DIR}/convolution_reverb.f90
)

# C source files
set(C_SOURCES
    ${C_DIR}/wasm_bridge.c
)

# Include directories
include_directories(${C_DIR})

# Create Fortran library
add_library(convolution_fortran STATIC ${FORTRAN_SOURCES})

# Set module directory for Fortran
set_target_properties(convolution_fortran PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/modules
)

# Include module directory
target_include_directories(convolution_fortran PUBLIC
    ${CMAKE_BINARY_DIR}/modules
)

# Create main executable
add_executable(convolution_reverb ${C_SOURCES})

# Link libraries
target_link_libraries(convolution_reverb convolution_fortran)

# Emscripten specific settings
if(EMSCRIPTEN)
    set(EMCC_FLAGS
        "-s WASM=1"
        "-s EXPORTED_FUNCTIONS='[\"_init_engine\",\"_process_audio\",\"_set_parameter\",\"_set_ir_type\",\"_cleanup_engine\",\"_allocate_double_array\",\"_free_double_array\",\"_is_initialized\",\"_get_sample_rate\",\"_get_version\",\"_process_audio_with_mix\"]'"
        "-s EXPORTED_RUNTIME_METHODS='[\"ccall\",\"cwrap\",\"allocateUTF8\",\"UTF8ToString\"]'"
        "-s ALLOW_MEMORY_GROWTH=1"
        "-s INITIAL_MEMORY=33554432"
        "-s MAXIMUM_MEMORY=2147483648"
        "-s MODULARIZE=1"
        "-s EXPORT_NAME='ConvolutionModule'"
        "-s ENVIRONMENT='web'"
        "-s SINGLE_FILE=0"
        "-s WASM_ASYNC_COMPILATION=1"
        "-s ERROR_ON_UNDEFINED_SYMBOLS=0"
        "-O3"
    )
    
    string(REPLACE ";" " " EMCC_FLAGS_STR "${EMCC_FLAGS}")
    
    set_target_properties(convolution_reverb PROPERTIES
        LINK_FLAGS "${EMCC_FLAGS_STR}"
    )
endif()

# Copy web files to build directory
set(WEB_DIR ${CMAKE_SOURCE_DIR}/web)
set(JS_DIR ${CMAKE_SOURCE_DIR}/src/js)

configure_file(${WEB_DIR}/index.html ${CMAKE_BINARY_DIR}/index.html COPYONLY)
configure_file(${WEB_DIR}/style.css ${CMAKE_BINARY_DIR}/style.css COPYONLY)
configure_file(${WEB_DIR}/app.js ${CMAKE_BINARY_DIR}/app.js COPYONLY)
configure_file(${JS_DIR}/convolution-module.js ${CMAKE_BINARY_DIR}/convolution-module.js COPYONLY)
configure_file(${JS_DIR}/audio-processor.js ${CMAKE_BINARY_DIR}/audio-processor.js COPYONLY)

# Install rules
install(FILES 
    ${CMAKE_BINARY_DIR}/convolution_reverb.js
    ${CMAKE_BINARY_DIR}/convolution_reverb.wasm
    ${CMAKE_BINARY_DIR}/index.html
    ${CMAKE_BINARY_DIR}/style.css
    ${CMAKE_BINARY_DIR}/app.js
    ${CMAKE_BINARY_DIR}/convolution-module.js
    ${CMAKE_BINARY_DIR}/audio-processor.js
    DESTINATION ${CMAKE_INSTALL_PREFIX}
)

# Print configuration summary
message(STATUS "")
message(STATUS "Configuration Summary:")
message(STATUS "  Build Type: ${CMAKE_BUILD_TYPE}")
message(STATUS "  Fortran Compiler: ${CMAKE_Fortran_COMPILER}")
message(STATUS "  Fortran Flags: ${CMAKE_Fortran_FLAGS}")
message(STATUS "  C Compiler: ${CMAKE_C_COMPILER}")
message(STATUS "  C Flags: ${CMAKE_C_FLAGS}")
if(EMSCRIPTEN)
    message(STATUS "  Emscripten: YES")
    message(STATUS "  Output: WebAssembly module")
else()
    message(STATUS "  Emscripten: NO")
    message(STATUS "  Output: Native executable")
endif()
message(STATUS "")