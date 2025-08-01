// convolution_engine.c
// Robust C implementation of convolution reverb engine
// Version 2.0.0-C with enhanced parameter responsiveness

#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>

// Constants
#define MAX_IR_SIZE 96000
#define MAX_BUFFER_SIZE 192000
#define PI 3.14159265358979323846
#define TWO_PI (2.0 * PI)

// FFT size constants
#define MIN_FFT_SIZE 64
#define MAX_FFT_SIZE 65536
#define BLOCK_SIZE 128

// Reverb types
#define IR_TYPE_HALL 0
#define IR_TYPE_CATHEDRAL 1
#define IR_TYPE_ROOM 2
#define IR_TYPE_PLATE 3
#define IR_TYPE_SPRING 4

// Global state structure
typedef struct {
    double* impulse_response;
    double* overlap_buffer;
    double* fft_buffer;
    double* temp_buffer;
    int ir_length;
    int buffer_size;
    int overlap_size;
    
    // Parameters
    double room_size;
    double decay_time;
    double pre_delay;
    double damping;
    double diffusion;
    double low_freq;
    double high_freq;
    double early_reflections;
    double late_mix;
    double mix_level;
    
    // State
    int sample_rate;
    int ir_type;
    int ir_needs_update;
    int initialized;
    
    // Random state
    uint32_t rand_state;
} ConvolutionEngine;

// Global engine instance
static ConvolutionEngine engine = {
    .room_size = 50.0,
    .decay_time = 2.5,
    .pre_delay = 20.0,
    .damping = 50.0,
    .diffusion = 80.0,
    .low_freq = 50.0,
    .high_freq = 50.0,
    .early_reflections = 50.0,
    .late_mix = 50.0,
    .mix_level = 30.0,
    .sample_rate = 48000,
    .ir_type = IR_TYPE_HALL,
    .ir_needs_update = 1,
    .initialized = 0,
    .rand_state = 123456789
};

// Static buffer for convolution history
static double* conv_history = NULL;
static int history_pos = 0;

// Fast random number generator
static inline double fast_rand() {
    engine.rand_state = (engine.rand_state * 1103515245 + 12345) & 0x7fffffff;
    return (double)engine.rand_state / 0x7fffffff;
}

// Fast sine approximation
static inline double fast_sin(double x) {
    // Wrap to [-pi, pi]
    while (x > PI) x -= TWO_PI;
    while (x < -PI) x += TWO_PI;
    
    // Bhaskara I's sine approximation
    double x2 = x * x;
    if (x >= 0) {
        return (16.0 * x * (PI - x)) / (5.0 * PI * PI - 4.0 * x * (PI - x));
    } else {
        return (16.0 * x * (PI + x)) / (5.0 * PI * PI - 4.0 * x * (PI + x));
    }
}

// Initialize engine
void init_convolution_engine_(int* sr) {
    engine.sample_rate = *sr;
    engine.ir_needs_update = 1;
    
    // Allocate buffers
    int buffer_size = MAX_IR_SIZE * 2;
    
    if (!engine.impulse_response) {
        engine.impulse_response = (double*)calloc(MAX_IR_SIZE, sizeof(double));
    }
    if (!engine.overlap_buffer) {
        engine.overlap_buffer = (double*)calloc(buffer_size, sizeof(double));
    }
    if (!engine.fft_buffer) {
        engine.fft_buffer = (double*)calloc(buffer_size, sizeof(double));
    }
    if (!engine.temp_buffer) {
        engine.temp_buffer = (double*)calloc(buffer_size, sizeof(double));
    }
    
    engine.buffer_size = buffer_size;
    engine.initialized = 1;
    
    printf("WebAssembly Convolution Reverb Engine v2.0.0-C initialized\n");
    printf("Sample rate: %d Hz | Max IR length: %.1fs\n", 
           *sr, (float)MAX_IR_SIZE / *sr);
}

// Generate early reflections using delay network
static void generate_early_reflections(double* ir, int ir_length, int pre_delay_samples) {
    // Early reflection tap times (in ms) based on room size
    const double tap_times[] = {
        13.7, 19.3, 23.1, 29.7, 31.1, 37.9, 41.3, 43.7,
        47.9, 53.3, 59.1, 61.3, 67.1, 71.3, 73.7, 79.3
    };
    const int num_taps = sizeof(tap_times) / sizeof(tap_times[0]);
    
    double room_scale = engine.room_size / 50.0;
    double er_gain = engine.early_reflections / 50.0;
    
    for (int i = 0; i < num_taps; i++) {
        int delay = pre_delay_samples + (int)(tap_times[i] * engine.sample_rate / 1000.0 * room_scale);
        if (delay < ir_length) {
            // Decay based on distance - less aggressive decay for more prominent reflections
            double distance = tap_times[i] / 80.0;
            double amplitude = er_gain * pow(0.9, distance);  // Changed from 0.8 to 0.9 for louder reflections
            
            // Randomize phase
            amplitude *= (fast_rand() > 0.5 ? 1.0 : -1.0);
            
            // Apply diffusion
            double diffusion_spread = engine.diffusion / 100.0;
            int spread = (int)(3 * diffusion_spread);
            for (int j = -spread; j <= spread && delay + j < ir_length && delay + j >= 0; j++) {
                ir[delay + j] += amplitude * exp(-abs(j) * 0.5) / (spread + 1);
            }
        }
    }
}

// Generate reverb tail using statistical model
static void generate_reverb_tail(double* ir, int ir_length, int start_sample) {
    double decay_rate = 4.605 / engine.decay_time; // -60dB decay
    double density = 0.5 + (engine.room_size / 50.0) * 2.0;
    int num_reflections = (int)(ir_length * 0.02 * density);
    
    // High-frequency damping factor
    double hf_damping = engine.damping / 100.0;
    double lf_boost = engine.low_freq / 50.0;
    
    // Make sure we have enough reflections for audible reverb
    if (num_reflections < 1000) num_reflections = 1000;  // Increased from 500
    
    for (int i = 0; i < num_reflections; i++) {
        double progress = (double)i / num_reflections;
        int delay = start_sample + (int)(pow(fast_rand(), 0.5) * (ir_length - start_sample));
        
        if (delay < ir_length) {
            double t = (double)delay / engine.sample_rate;
            
            // Base amplitude with exponential decay
            double amplitude = exp(-decay_rate * t);
            
            // Frequency-dependent decay - make damping more pronounced
            double freq_factor = 1.0 - hf_damping * hf_damping * (1.0 - exp(-t * 3.0));
            amplitude *= freq_factor;
            
            // Room-specific coloration with more dramatic differences
            switch (engine.ir_type) {
                case IR_TYPE_CATHEDRAL:
                    // Enhanced low frequencies, longer decay
                    amplitude *= (1.0 + lf_boost * 1.5 * exp(-t * 0.3));  // Increased from 1.0
                    if (i % 3 == 0) { // More sparse strong reflections
                        amplitude *= 2.5;  // Increased from 2.0
                    }
                    break;
                    
                case IR_TYPE_ROOM:
                    // Faster decay, more uniform
                    amplitude *= exp(-t * 4.0); // Increased from 3.0 for even faster decay
                    break;
                    
                case IR_TYPE_PLATE:
                    // Metallic dispersion
                    amplitude *= (1.0 + 0.7 * fast_sin(t * 2000.0 + i * 0.2));  // Increased from 0.5
                    // Add shimmer
                    delay += (int)(5 * fast_sin(i * 0.1));  // Increased from 3
                    if (delay >= ir_length) continue;
                    break;
                    
                case IR_TYPE_SPRING:
                    // Chirped delays - more pronounced
                    delay += (int)(30 * fast_sin(t * 100.0));  // Increased from 20
                    if (delay >= ir_length || delay < 0) continue;
                    amplitude *= (1.0 + 1.0 * fast_sin(t * 400.0));  // Increased from 0.8
                    break;
                    
                default: // HALL
                    // Balanced response with clear room size effect
                    amplitude *= (1.0 + lf_boost * 0.5 * exp(-t * 0.8));  // Increased from 0.3
                    // Room size affects decay rate too
                    amplitude *= exp(-(100.0 - engine.room_size) * 0.02 * t);  // Increased from 0.01
                    break;
            }
            
            // Apply late mix more dramatically
            amplitude *= (engine.late_mix / 50.0) * 2.0;  // Increased from 1.5
            
            // Add to impulse response with random phase
            ir[delay] += amplitude * (2.0 * fast_rand() - 1.0);
        }
    }
}

// Apply spectral shaping
static void apply_spectral_shaping(double* ir, int ir_length) {
    // Simple low-pass and high-pass filtering
    double lp_state = 0.0;
    double hp_state = 0.0;
    
    double lp_cutoff = 0.1 + (engine.high_freq / 100.0) * 0.4;
    double hp_cutoff = 0.001 + (100.0 - engine.low_freq) / 100.0 * 0.05;
    
    for (int i = 0; i < ir_length; i++) {
        // Low-pass filter
        lp_state += (ir[i] - lp_state) * lp_cutoff;
        ir[i] = lp_state;
        
        // High-pass filter
        hp_state += (ir[i] - hp_state) * hp_cutoff;
        ir[i] -= hp_state;
    }
}

// Generate complete impulse response
static void generate_impulse_response() {
    // Clear the IR buffer
    memset(engine.impulse_response, 0, MAX_IR_SIZE * sizeof(double));
    
    // Calculate IR length
    engine.ir_length = (int)(engine.decay_time * engine.sample_rate);
    if (engine.ir_length > MAX_IR_SIZE) {
        engine.ir_length = MAX_IR_SIZE;
    }
    
    int pre_delay_samples = (int)(engine.pre_delay * engine.sample_rate / 1000.0);
    
    // Generate early reflections
    generate_early_reflections(engine.impulse_response, engine.ir_length, pre_delay_samples);
    
    // Generate reverb tail
    int tail_start = pre_delay_samples + (int)(0.05 * engine.sample_rate); // 50ms after pre-delay
    generate_reverb_tail(engine.impulse_response, engine.ir_length, tail_start);
    
    // Apply spectral shaping
    apply_spectral_shaping(engine.impulse_response, engine.ir_length);
    
    // Normalize
    double max_val = 0.0;
    double rms = 0.0;
    
    for (int i = 0; i < engine.ir_length; i++) {
        double abs_val = fabs(engine.impulse_response[i]);
        if (abs_val > max_val) max_val = abs_val;
        rms += engine.impulse_response[i] * engine.impulse_response[i];
    }
    
    rms = sqrt(rms / engine.ir_length);
    
    if (max_val > 0.0) {
        // Normalize to prevent clipping while maintaining good signal level
        double target_peak = 0.8;
        double target_rms = 0.1;
        double peak_norm = target_peak / max_val;
        double rms_norm = target_rms / rms;
        double norm_factor = fmin(peak_norm, rms_norm * 3.0);
        
        for (int i = 0; i < engine.ir_length; i++) {
            engine.impulse_response[i] *= norm_factor;
        }
    }
    
    engine.ir_needs_update = 0;
    
    // Debug output
    const char* type_names[] = {"Hall", "Cathedral", "Room", "Plate", "Spring"};
    printf("Generated %s IR: %d samples (%.2fs), RMS: %.4f\n", 
           type_names[engine.ir_type], engine.ir_length, 
           (double)engine.ir_length / engine.sample_rate, rms);
    
    printf("IR Debug - Type: %d, Length: %d samples (%.2fs)\n", 
           engine.ir_type, engine.ir_length, (double)engine.ir_length / engine.sample_rate);
    printf("  Room Size: %.1f, Decay Time: %.1fs, Pre-delay: %.1fms\n",
           engine.room_size, engine.decay_time, engine.pre_delay);
    printf("  Damping: %.1f%%, Diffusion: %.1f%%, Mix: %.1f%%\n",
           engine.damping, engine.diffusion, engine.mix_level);
    
    // Find the peak location and energy distribution
    int peak_idx = 0;
    double peak_val = 0.0;
    double early_energy = 0.0;  // First 100ms
    double late_energy = 0.0;   // After 100ms
    int early_boundary = (int)(0.1 * engine.sample_rate);  // 100ms
    
    for (int i = 0; i < engine.ir_length; i++) {
        double abs_val = fabs(engine.impulse_response[i]);
        if (abs_val > peak_val) {
            peak_val = abs_val;
            peak_idx = i;
        }
        
        if (i < early_boundary) {
            early_energy += engine.impulse_response[i] * engine.impulse_response[i];
        } else {
            late_energy += engine.impulse_response[i] * engine.impulse_response[i];
        }
    }
    
    early_energy = sqrt(early_energy);
    late_energy = sqrt(late_energy);
    
    printf("  Peak at: %dms (value: %.4f)\n", 
           (int)((double)peak_idx * 1000.0 / engine.sample_rate), peak_val);
    printf("  Early energy: %.4f, Late energy: %.4f, Ratio: %.2f\n",
           early_energy, late_energy, late_energy / (early_energy + 0.0001));
}

// Process audio with convolution
void process_convolution_(double* input, double* output, int* num_samples) {
    int n = *num_samples;
    
    if (!engine.initialized || !engine.impulse_response) {
        // Passthrough if not initialized
        memcpy(output, input, n * sizeof(double));
        return;
    }
    
    // Update IR if needed
    if (engine.ir_needs_update) {
        generate_impulse_response();
        // Reset convolution history when IR changes
        if (conv_history) {
            memset(conv_history, 0, MAX_IR_SIZE * sizeof(double));
        }
        history_pos = 0;
    }
    
    // Allocate convolution history buffer if needed
    if (!conv_history) {
        conv_history = (double*)calloc(MAX_IR_SIZE, sizeof(double));
    }
    
    // Calculate mix parameters
    double mix = engine.mix_level / 100.0;
    double dry_gain = cos(mix * PI * 0.5);  // Equal power crossfade
    double wet_gain = sin(mix * PI * 0.5);  // No reduction - full wet signal
    
    // Debug output every 1000 calls
    static int debug_counter = 0;
    if (++debug_counter % 1000 == 0) {
        printf("Processing - Mix: %.1f%% (dry: %.3f, wet: %.3f)\n", 
               engine.mix_level, dry_gain, wet_gain);
    }
    
    // Process each sample
    for (int i = 0; i < n; i++) {
        // Store input in circular buffer
        conv_history[history_pos] = input[i];
        
        // Perform convolution
        double wet_sample = 0.0;
        // Increase convolution length for proper reverb tail
        int ir_len = (engine.ir_length < 24000) ? engine.ir_length : 24000; // 500ms at 48kHz
        
        for (int j = 0; j < ir_len; j++) {
            int hist_idx = (history_pos - j + MAX_IR_SIZE) % MAX_IR_SIZE;
            wet_sample += conv_history[hist_idx] * engine.impulse_response[j];
        }
        
        // Mix dry and wet signals
        output[i] = dry_gain * input[i] + wet_gain * wet_sample;
        
        // Soft clipping to prevent harsh distortion
        if (output[i] > 0.95) {
            output[i] = 0.95 + 0.05 * tanh((output[i] - 0.95) * 10.0);
        } else if (output[i] < -0.95) {
            output[i] = -0.95 + 0.05 * tanh((output[i] + 0.95) * 10.0);
        }
        
        // Advance circular buffer position
        history_pos = (history_pos + 1) % MAX_IR_SIZE;
    }
}

// Parameter setters
void set_param_float_(int* param_id, float* value) {
    printf("Setting parameter %d to %.2f\n", *param_id, *value);
    
    switch (*param_id) {
        case 0: engine.room_size = *value; engine.ir_needs_update = 1; break;
        case 1: engine.decay_time = fmax(0.1, fmin(10.0, *value)); engine.ir_needs_update = 1; break;
        case 2: engine.pre_delay = fmax(0.0, fmin(100.0, *value)); engine.ir_needs_update = 1; break;
        case 3: engine.damping = *value; engine.ir_needs_update = 1; break;
        case 4: engine.low_freq = *value; engine.ir_needs_update = 1; break;
        case 5: engine.diffusion = *value; engine.ir_needs_update = 1; break;
        case 6: engine.mix_level = fmax(0.0, fmin(100.0, *value)); break;
        case 7: engine.early_reflections = *value; engine.ir_needs_update = 1; break;
        case 8: engine.high_freq = *value; engine.ir_needs_update = 1; break;
        case 9: engine.late_mix = *value; engine.ir_needs_update = 1; break;
    }
}

void set_parameter_(char* param_name, double* value, int param_name_len) {
    char name[64] = {0};
    strncpy(name, param_name, (param_name_len < 63) ? param_name_len : 63);
    
    printf("Setting parameter '%s' to %.2f\n", name, *value);
    
    if (strcmp(name, "roomSize") == 0) {
        engine.room_size = *value;
        engine.ir_needs_update = 1;
    } else if (strcmp(name, "decayTime") == 0) {
        engine.decay_time = fmax(0.1, fmin(10.0, *value));
        engine.ir_needs_update = 1;
    } else if (strcmp(name, "preDelay") == 0) {
        engine.pre_delay = fmax(0.0, fmin(100.0, *value));
        engine.ir_needs_update = 1;
    } else if (strcmp(name, "damping") == 0) {
        engine.damping = *value;
        engine.ir_needs_update = 1;
    } else if (strcmp(name, "lowFreq") == 0) {
        engine.low_freq = *value;
        engine.ir_needs_update = 1;
    } else if (strcmp(name, "diffusion") == 0) {
        engine.diffusion = *value;
        engine.ir_needs_update = 1;
    } else if (strcmp(name, "mix") == 0) {
        engine.mix_level = fmax(0.0, fmin(100.0, *value));
    } else if (strcmp(name, "earlyReflections") == 0) {
        engine.early_reflections = *value;
        engine.ir_needs_update = 1;
    }
}

void set_ir_type_(char* ir_type_str, int ir_type_len) {
    char type[32] = {0};
    strncpy(type, ir_type_str, (ir_type_len < 31) ? ir_type_len : 31);
    
    printf("Setting IR type to '%s'\n", type);
    
    int old_type = engine.ir_type;
    
    if (strcmp(type, "hall") == 0) {
        engine.ir_type = IR_TYPE_HALL;
    } else if (strcmp(type, "cathedral") == 0) {
        engine.ir_type = IR_TYPE_CATHEDRAL;
    } else if (strcmp(type, "room") == 0) {
        engine.ir_type = IR_TYPE_ROOM;
    } else if (strcmp(type, "plate") == 0) {
        engine.ir_type = IR_TYPE_PLATE;
    } else if (strcmp(type, "spring") == 0) {
        engine.ir_type = IR_TYPE_SPRING;
    }
    
    if (old_type != engine.ir_type) {
        engine.ir_needs_update = 1;
    }
}

// Cleanup
void cleanup_convolution_engine_() {
    if (engine.impulse_response) {
        free(engine.impulse_response);
        engine.impulse_response = NULL;
    }
    if (engine.overlap_buffer) {
        free(engine.overlap_buffer);
        engine.overlap_buffer = NULL;
    }
    if (engine.fft_buffer) {
        free(engine.fft_buffer);
        engine.fft_buffer = NULL;
    }
    if (engine.temp_buffer) {
        free(engine.temp_buffer);
        engine.temp_buffer = NULL;
    }
    if (conv_history) {
        free(conv_history);
        conv_history = NULL;
    }
    engine.initialized = 0;
    history_pos = 0;
}

// Status functions
int is_initialized_() {
    return engine.initialized;
}

int get_sample_rate_() {
    return engine.sample_rate;
}

char* get_version_() {
    return "2.0.0-C";
}