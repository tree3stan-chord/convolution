#ifndef WASM_BRIDGE_H
#define WASM_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

// Initialize the convolution engine with given sample rate
void init_engine(int sample_rate);

// Process audio chunk
void process_audio(double* input, double* output, int num_samples);

// Set parameter value
void set_parameter(int param_id, float value);

// Set impulse response type
void set_ir_type(const char* ir_type);

// Cleanup engine resources
void cleanup_engine(void);

// Memory management helpers
double* allocate_double_array(int size);
void free_double_array(double* ptr);

// Parameter IDs
enum ConvolutionParams {
    PARAM_ROOM_SIZE = 0,
    PARAM_DECAY_TIME = 1,
    PARAM_PRE_DELAY = 2,
    PARAM_DAMPING = 3,
    PARAM_LOW_FREQ = 4,
    PARAM_DIFFUSION = 5,
    PARAM_MIX = 6,
    PARAM_EARLY_REFLECTIONS = 7
};

#ifdef __cplusplus
}
#endif

#endif // WASM_BRIDGE_H