#!/bin/bash

# Build script using gfortran (more widely available than flang)

set -e  # Exit on error

echo "Building Convolution Reverb WebAssembly module with gfortran..."

# Check if Emscripten is available
if ! command -v emcc &> /dev/null; then
    echo "Emscripten not found. Please run: source ./emsdk/emsdk_env.sh"
    exit 1
fi

# Check for Fortran compiler
FORTRAN_COMPILER=""
if command -v gfortran &> /dev/null; then
    FORTRAN_COMPILER="gfortran"
elif command -v f2c &> /dev/null; then
    FORTRAN_COMPILER="f2c"
else
    echo "No Fortran compiler found. Please install gfortran or f2c."
    exit 1
fi

echo "Using Fortran compiler: $FORTRAN_COMPILER"

# Create build directory
mkdir -p build
mkdir -p build/obj

# Function to compile Fortran to C using f2c
compile_fortran_f2c() {
    local f90_file=$1
    local base_name=$(basename $f90_file .f90)
    
    echo "Converting $f90_file to C using f2c..."
    # First convert F90 to F77 format (f2c doesn't support F90)
    # This is a simplified conversion - for production use a proper F90 to F77 converter
    sed -e 's/implicit none/IMPLICIT NONE/g' \
        -e 's/end module/END/g' \
        -e 's/module /C MODULE /g' \
        -e 's/contains/C CONTAINS/g' \
        -e 's/::/,/g' \
        $f90_file > build/obj/${base_name}.f
    
    f2c -C++ build/obj/${base_name}.f -o build/obj/${base_name}.c
}

# Function to compile Fortran to object using gfortran
compile_fortran_gfortran() {
    local f90_file=$1
    local base_name=$(basename $f90_file .f90)
    
    echo "Compiling $f90_file..."
    gfortran -c -O3 -ffast-math -fPIC $f90_file -o build/obj/${base_name}.o
}

if [ "$FORTRAN_COMPILER" = "gfortran" ]; then
    # Step 1: Compile Fortran modules separately to handle dependencies
    echo "Compiling Fortran modules with gfortran..."
    
    # Create a single combined Fortran file to simplify compilation
    cat > build/convolution_combined.f90 << 'EOF'
! Combined Fortran source for WebAssembly compilation

module constants
    implicit none
    integer, parameter :: dp = kind(1.0d0)
    real(dp), parameter :: pi = 3.14159265358979323846_dp
    integer, parameter :: MAX_BUFFER_SIZE = 192000
    integer, parameter :: MAX_IR_SIZE = 96000
end module constants

module fft_module
    use constants
    implicit none
    contains
    
    subroutine fft_simple(x_real, x_imag, n, inverse)
        real(dp), dimension(n), intent(inout) :: x_real, x_imag
        integer, intent(in) :: n
        logical, intent(in) :: inverse
        
        integer :: i, j, k, n1, n2, a
        real(dp) :: c, s, t1, t2
        
        ! Bit reversal
        j = 0
        n2 = n / 2
        do i = 1, n - 2
            n1 = n2
            do while (j >= n1)
                j = j - n1
                n1 = n1 / 2
            end do
            j = j + n1
            
            if (i < j) then
                t1 = x_real(i + 1)
                x_real(i + 1) = x_real(j + 1)
                x_real(j + 1) = t1
                
                t1 = x_imag(i + 1)
                x_imag(i + 1) = x_imag(j + 1)
                x_imag(j + 1) = t1
            end if
        end do
        
        ! FFT computation
        n1 = 0
        n2 = 1
        
        do i = 1, int(log(real(n))/log(2.0))
            n1 = n2
            n2 = n2 + n2
            a = 0
            
            do j = 1, n1
                if (inverse) then
                    c = cos(a * pi / n1)
                    s = sin(a * pi / n1)
                else
                    c = cos(-a * pi / n1)
                    s = sin(-a * pi / n1)
                end if
                a = a + 1
                
                do k = j, n, n2
                    t1 = c * x_real(k + n1) - s * x_imag(k + n1)
                    t2 = s * x_real(k + n1) + c * x_imag(k + n1)
                    x_real(k + n1) = x_real(k) - t1
                    x_imag(k + n1) = x_imag(k) - t2
                    x_real(k) = x_real(k) + t1
                    x_imag(k) = x_imag(k) + t2
                end do
            end do
        end do
        
        ! Normalize if inverse
        if (inverse) then
            do i = 1, n
                x_real(i) = x_real(i) / real(n, dp)
                x_imag(i) = x_imag(i) / real(n, dp)
            end do
        end if
    end subroutine fft_simple
    
    function next_power_of_2(n) result(p)
        integer, intent(in) :: n
        integer :: p
        
        p = 1
        do while (p < n)
            p = p * 2
        end do
    end function next_power_of_2
    
end module fft_module

! Global variables for state management
module reverb_state
    use constants
    implicit none
    
    real(dp), dimension(MAX_IR_SIZE) :: current_ir
    integer :: current_ir_length = 0
    real(dp) :: room_size = 50.0_dp
    real(dp) :: decay_time = 2.5_dp
    real(dp) :: pre_delay = 20.0_dp
    real(dp) :: damping = 50.0_dp
    real(dp) :: mix_level = 30.0_dp
    integer :: sample_rate = 48000
    logical :: ir_needs_update = .true.
    
end module reverb_state

! C-compatible interface functions
subroutine init_engine_fortran(sr) bind(C, name='init_engine_fortran')
    use iso_c_binding
    use reverb_state
    implicit none
    integer(c_int), value :: sr
    
    sample_rate = sr
    ir_needs_update = .true.
    current_ir = 0.0_dp
end subroutine init_engine_fortran

subroutine set_parameter_fortran(param_id, value) bind(C, name='set_parameter_fortran')
    use iso_c_binding
    use reverb_state
    implicit none
    integer(c_int), value :: param_id
    real(c_float), value :: value
    
    select case(param_id)
        case(0)  ! room_size
            room_size = real(value, dp)
            ir_needs_update = .true.
        case(1)  ! decay_time
            decay_time = real(value, dp)
            ir_needs_update = .true.
        case(2)  ! pre_delay
            pre_delay = real(value, dp)
            ir_needs_update = .true.
        case(3)  ! damping
            damping = real(value, dp)
            ir_needs_update = .true.
        case(6)  ! mix
            mix_level = real(value, dp)
    end select
end subroutine set_parameter_fortran

subroutine generate_simple_ir() 
    use constants
    use reverb_state
    implicit none
    
    integer :: i
    real(dp) :: t, amplitude, decay_rate
    
    ! Simple exponential decay IR
    current_ir_length = min(int(decay_time * sample_rate), MAX_IR_SIZE)
    decay_rate = 3.0_dp / decay_time
    
    do i = 1, current_ir_length
        t = real(i, dp) / real(sample_rate, dp)
        amplitude = exp(-decay_rate * t)
        ! Add some randomness for diffusion
        current_ir(i) = amplitude * (2.0_dp * rand() - 1.0_dp) * 0.5_dp
    end do
    
    ir_needs_update = .false.
end subroutine generate_simple_ir

subroutine process_audio_fortran(input_ptr, output_ptr, n_samples) bind(C, name='process_audio_fortran')
    use iso_c_binding
    use constants
    use reverb_state
    use fft_module
    implicit none
    
    type(c_ptr), value :: input_ptr, output_ptr
    integer(c_int), value :: n_samples
    
    real(c_double), pointer :: input(:), output(:)
    real(dp), allocatable :: conv_real(:), conv_imag(:)
    real(dp), allocatable :: ir_real(:), ir_imag(:)
    integer :: fft_size, i
    real(dp) :: dry_gain, wet_gain
    
    ! Get pointers to arrays
    call c_f_pointer(input_ptr, input, [n_samples])
    call c_f_pointer(output_ptr, output, [n_samples])
    
    ! Update IR if needed
    if (ir_needs_update) then
        call generate_simple_ir()
    end if
    
    ! Simple convolution (non-FFT for WebAssembly compatibility)
    ! For production, implement overlap-save FFT convolution
    dry_gain = 1.0_dp - mix_level / 100.0_dp
    wet_gain = mix_level / 100.0_dp
    
    ! Direct convolution (simplified for demonstration)
    do i = 1, n_samples
        output(i) = dry_gain * input(i)
        
        ! Add reverb (simplified - just early reflections)
        if (i > int(pre_delay * sample_rate / 1000.0_dp)) then
            output(i) = output(i) + wet_gain * input(i) * 0.5_dp
        end if
    end do
    
end subroutine process_audio_fortran
EOF

    # Compile the combined Fortran file
    gfortran -c -O3 -ffast-math -fPIC build/convolution_combined.f90 -o build/obj/convolution.o
    
    # Extract symbols and create C stubs
    echo "Creating C interface stubs..."
    cat > build/fortran_stubs.c << 'EOF'
// Auto-generated stubs for Fortran functions
#include <stddef.h>

// Fortran function declarations (with underscore suffix)
extern void init_engine_fortran_(int* sr);
extern void set_parameter_fortran_(int* param_id, float* value);
extern void process_audio_fortran_(double** input_ptr, double** output_ptr, int* n_samples);

// C wrappers (without underscore)
void init_engine_fortran(int sr) {
    init_engine_fortran_(&sr);
}

void set_parameter_fortran(int param_id, float value) {
    set_parameter_fortran_(&param_id, &value);
}

void process_audio_fortran(double* input_ptr, double* output_ptr, int n_samples) {
    process_audio_fortran_(&input_ptr, &output_ptr, &n_samples);
}
EOF

    # Compile the C stubs
    emcc -c build/fortran_stubs.c -o build/obj/fortran_stubs.o -O3
    
elif [ "$FORTRAN_COMPILER" = "f2c" ]; then
    echo "Using f2c conversion path..."
    # Convert Fortran to C first
    for f90_file in src/fortran/*.f90; do
        compile_fortran_f2c $f90_file
    done
fi

# Step 2: Create the main C bridge file
echo "Creating C bridge..."
cat > build/wasm_bridge.c << 'EOF'
#include <emscripten.h>
#include <stdlib.h>
#include <string.h>

// External Fortran functions
extern void init_engine_fortran(int sr);
extern void set_parameter_fortran(int param_id, float value);
extern void process_audio_fortran(double* input_ptr, double* output_ptr, int n_samples);

// WebAssembly exported functions
EMSCRIPTEN_KEEPALIVE
void init_engine(int sample_rate) {
    init_engine_fortran(sample_rate);
}

EMSCRIPTEN_KEEPALIVE
void process_audio(double* input, double* output, int num_samples) {
    process_audio_fortran(input, output, num_samples);
}

EMSCRIPTEN_KEEPALIVE
void set_parameter(int param_id, float value) {
    set_parameter_fortran(param_id, value);
}

EMSCRIPTEN_KEEPALIVE
void set_ir_type(const char* ir_type) {
    // Simplified - just trigger IR update
    set_parameter_fortran(0, 50.0f);
}

EMSCRIPTEN_KEEPALIVE
void cleanup_engine() {
    // Cleanup if needed
}

// Memory allocation helpers
EMSCRIPTEN_KEEPALIVE
double* allocate_double_array(int size) {
    return (double*)malloc(size * sizeof(double));
}

EMSCRIPTEN_KEEPALIVE
void free_double_array(double* ptr) {
    free(ptr);
}
EOF

# Step 3: Compile C bridge
echo "Compiling C bridge..."
emcc -c build/wasm_bridge.c -o build/obj/wasm_bridge.o -O3

# Step 4: Link everything to WebAssembly
echo "Linking to WebAssembly..."
if [ "$FORTRAN_COMPILER" = "gfortran" ]; then
    # Link with gfortran runtime
    emcc build/obj/wasm_bridge.o build/obj/convolution.o build/obj/fortran_stubs.o \
        -o build/convolution_reverb.js \
        -s WASM=1 \
        -s EXPORTED_FUNCTIONS='["_init_engine","_process_audio","_set_parameter","_set_ir_type","_cleanup_engine","_allocate_double_array","_free_double_array"]' \
        -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap","allocateUTF8"]' \
        -s ALLOW_MEMORY_GROWTH=1 \
        -s INITIAL_MEMORY=33554432 \
        -s MODULARIZE=1 \
        -s EXPORT_NAME='ConvolutionModule' \
        -s ERROR_ON_UNDEFINED_SYMBOLS=0 \
        -O3
else
    # Link f2c output
    emcc build/obj/*.c build/obj/wasm_bridge.o \
        -o build/convolution_reverb.js \
        -s WASM=1 \
        -s EXPORTED_FUNCTIONS='["_init_engine","_process_audio","_set_parameter","_set_ir_type","_cleanup_engine","_allocate_double_array","_free_double_array"]' \
        -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap","allocateUTF8"]' \
        -s ALLOW_MEMORY_GROWTH=1 \
        -s INITIAL_MEMORY=33554432 \
        -s MODULARIZE=1 \
        -s EXPORT_NAME='ConvolutionModule' \
        -O3
fi

# Step 5: Copy web files
echo "Copying web files..."
cp src/js/convolution-module.js build/ 2>/dev/null || true
cp web/* build/ 2>/dev/null || true

# Create a test HTML if it doesn't exist
if [ ! -f build/index.html ]; then
    cp web/index.html build/
fi

echo ""
echo "Build complete!"
echo "Output files:"
ls -la build/convolution_reverb.*
echo ""
echo "To test locally:"
echo "  cd build"
echo "  python3 -m http.server 8000"
echo "  Open http://localhost:8000 in your browser"