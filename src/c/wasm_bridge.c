// wasm_bridge.c
// C bridge between JavaScript and Fortran for WebAssembly

#include "wasm_bridge.h"
#include <emscripten.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Fortran function declarations with underscore suffix (common naming convention)
extern void init_convolution_engine_(int* sample_rate);
extern void process_convolution_(double* input, double* output, int* num_samples);
extern void set_parameter_(char* param_name, double* value, int* param_name_len);
extern void set_ir_type_(char* ir_type, int* ir_type_len);
extern void cleanup_convolution_engine_();
extern void set_param_float_(int* param_id, float* value);
extern int is_initialized_();
extern int get_sample_rate_();
extern char* get_version_();

// Global state
static int g_sample_rate = 48000;
static int g_initialized = 0;

// WebAssembly exported function: Initialize engine
EMSCRIPTEN_KEEPALIVE
void init_engine(int sample_rate) {
    printf("Initializing convolution engine with sample rate: %d\n", sample_rate);
    g_sample_rate = sample_rate;
    init_convolution_engine_(&sample_rate);
    g_initialized = 1;
}

// WebAssembly exported function: Process audio
EMSCRIPTEN_KEEPALIVE
void process_audio(double* input, double* output, int num_samples) {
    if (!g_initialized) {
        printf("Error: Engine not initialized\n");
        // Copy input to output as fallback
        for (int i = 0; i < num_samples; i++) {
            output[i] = input[i];
        }
        return;
    }
    
    process_convolution_(input, output, &num_samples);
}

// WebAssembly exported function: Set parameter by ID
EMSCRIPTEN_KEEPALIVE
void set_parameter(int param_id, float value) {
    if (!g_initialized) {
        printf("Error: Engine not initialized\n");
        return;
    }
    
    printf("Setting parameter %d to %f\n", param_id, value);
    set_param_float_(&param_id, &value);
}

// WebAssembly exported function: Set parameter by name
EMSCRIPTEN_KEEPALIVE
void set_parameter_by_name(const char* param_name, float value) {
    if (!g_initialized) {
        printf("Error: Engine not initialized\n");
        return;
    }
    
    // Fortran expects the string and its length
    int len = strlen(param_name);
    double dvalue = (double)value;
    set_parameter_((char*)param_name, &dvalue, &len);
}

// WebAssembly exported function: Set impulse response type
EMSCRIPTEN_KEEPALIVE
void set_ir_type(const char* ir_type) {
    if (!g_initialized) {
        printf("Error: Engine not initialized\n");
        return;
    }
    
    printf("Setting IR type to: %s\n", ir_type);
    
    // Pass string and length to Fortran
    int len = strlen(ir_type);
    set_ir_type_((char*)ir_type, &len);
}

// WebAssembly exported function: Cleanup engine
EMSCRIPTEN_KEEPALIVE
void cleanup_engine() {
    if (g_initialized) {
        cleanup_convolution_engine_();
        g_initialized = 0;
    }
}

// Memory allocation helpers for JavaScript
EMSCRIPTEN_KEEPALIVE
double* allocate_double_array(int size) {
    return (double*)malloc(size * sizeof(double));
}

EMSCRIPTEN_KEEPALIVE
void free_double_array(double* ptr) {
    if (ptr) {
        free(ptr);
    }
}

// Get current engine status
EMSCRIPTEN_KEEPALIVE
int is_initialized() {
    return g_initialized;
}

// Get current sample rate
EMSCRIPTEN_KEEPALIVE
int get_sample_rate() {
    return g_sample_rate;
}

// Version information
EMSCRIPTEN_KEEPALIVE
const char* get_version() {
    return "1.0.0";
}

// Process with mix parameter (convenience function)
EMSCRIPTEN_KEEPALIVE
void process_audio_with_mix(double* input, double* output, int num_samples, float mix) {
    if (!g_initialized) {
        // Copy input to output as fallback
        for (int i = 0; i < num_samples; i++) {
            output[i] = input[i];
        }
        return;
    }
    
    // Create temporary buffer for wet signal
    double* wet_signal = (double*)malloc(num_samples * sizeof(double));
    if (!wet_signal) {
        // Memory allocation failed, copy input to output
        for (int i = 0; i < num_samples; i++) {
            output[i] = input[i];
        }
        return;
    }
    
    // Process convolution
    process_convolution_(input, wet_signal, &num_samples);
    
    // Apply mix
    float dry_gain = 1.0f - mix;
    float wet_gain = mix;
    
    for (int i = 0; i < num_samples; i++) {
        output[i] = dry_gain * input[i] + wet_gain * wet_signal[i];
    }
    
    free(wet_signal);
}