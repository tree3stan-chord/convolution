// convolution_engine.c
// Robust C implementation of convolution reverb engine
// Version 2.0.3-C with immediate parameter updates and better audibility

#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>

// Constants
#define MAX_IR_SECONDS   15
#define MAX_IR_SIZE      (MAX_IR_SECONDS * 48000)
#define MAX_BUFFER_SIZE  (MAX_IR_SIZE * 2)

#define PI      3.14159265358979323846
#define TWO_PI  (2.0 * PI)

// FFT size constants
#define MIN_FFT_SIZE 64
#define MAX_FFT_SIZE 65536
#define BLOCK_SIZE 128

// Reverb types - ULTIMATE COLLECTION OF SONIC INSANITY!
#define IR_TYPE_HALL 0
#define IR_TYPE_CATHEDRAL 1
#define IR_TYPE_ROOM 2
#define IR_TYPE_PLATE 3
#define IR_TYPE_SPRING 4
#define IR_TYPE_CAVE 5
#define IR_TYPE_SHIMMER 6
#define IR_TYPE_FREEZE 7
#define IR_TYPE_REVERSE 8
#define IR_TYPE_GATED 9
#define IR_TYPE_CHORUS 10
#define IR_TYPE_ALIEN 11
#define IR_TYPE_UNDERWATER 12
#define IR_TYPE_METALLIC 13
#define IR_TYPE_PSYCHEDELIC 14
#define IR_TYPE_SLAPBACK 15      // NEW: Rockabilly echo chamber
#define IR_TYPE_INFINITE 16      // NEW: Feedback loop of doom
#define IR_TYPE_SCATTERED 17     // NEW: Granular diffusion field
#define IR_TYPE_DOPPLER 18       // NEW: Moving source simulation
#define IR_TYPE_QUANTUM 19       // NEW: Probability-based reflections
#define IR_TYPE_VOID 20          // NEW: The sound of nothingness
#define IR_TYPE_CRYSTALLINE 21   // NEW: Glass palace reflections
#define IR_TYPE_MAGNETIC 22      // NEW: Tape saturation space
#define IR_TYPE_PLASMA 23        // NEW: Ionized gas chamber
#define IR_TYPE_NIGHTMARE 24     // NEW: Your worst acoustic dreams
#define IR_TYPE_MAX 25           // Total number of types

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

// Global engine instance with default values matching HTML
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

// Debug counter for periodic logging
static int process_counter = 0;

// Forward declaration
static void generate_impulse_response();

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

// Initialize engine with corrected function name
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
    
    // Allocate convolution history
    if (!conv_history) {
        conv_history = (double*)calloc(MAX_IR_SIZE, sizeof(double));
    }
    
    engine.buffer_size = buffer_size;
    engine.initialized = 1;
    
    printf("WebAssembly Convolution Reverb Engine v2.0.3-C initialized\n");
    printf("Sample rate: %d Hz | Max IR length: %.1fs\n", 
           *sr, (float)MAX_IR_SIZE / *sr);
}

// Generate early reflections using delay network
static void generate_early_reflections(double* ir, int ir_length, int pre_delay_samples) {
    // Early reflection tap times (in ms) based on room size
    const double tap_times[] = {
        13.7, 19.3, 23.1, 29.7, 31.1, 37.9, 41.3, 43.7,
        47.9, 53.3, 59.1, 61.3, 67.1, 71.3, 73.7, 79.3,
        83.1, 89.7, 97.3, 101.1, 107.9, 113.3
    };
    const int num_taps = sizeof(tap_times) / sizeof(tap_times[0]);
    
    double room_scale = 1.0 + (engine.room_size / 20.0) * 4.0;  // GIGANTIC rooms!
    double er_gain = engine.early_reflections / 3.0;  // THUNDEROUS early reflections!
    
    printf("  🏛️ EARLY REFLECTIONS: room_scale=%.2f (MASSIVE!), gain=%.2f (THUNDEROUS!) 🏛️\n", 
           room_scale, er_gain);
    
    for (int i = 0; i < num_taps; i++) {
        int delay = pre_delay_samples + (int)(tap_times[i] * engine.sample_rate / 1000.0 * room_scale);
        if (delay < ir_length) {
            double distance = tap_times[i] / 120.0;
            double amplitude = er_gain * pow(0.95, distance);
            
            // Randomize phase
            amplitude *= (fast_rand() > 0.5 ? 1.0 : -1.0);
            
            // Different patterns for different room types - MAXIMUM DISTINCTION!
            switch (engine.ir_type) {
                case IR_TYPE_CATHEDRAL:
                    if (i % 3 == 0) amplitude *= 3.0;
                    else if (i % 5 == 0) amplitude *= 2.0;
                    else continue;
                    delay += (int)(20 * fast_sin(i * 0.1));
                    break;
                    
                case IR_TYPE_ROOM:
                    amplitude *= 0.8;
                    if (i % 4 == 0) delay += 50;
                    break;
                    
                case IR_TYPE_PLATE:
                    delay += (int)(fast_rand() * 20 - 10);
                    amplitude *= (1.0 + 0.5 * fast_sin(i * 0.7));
                    break;
                    
                case IR_TYPE_SPRING:
                    delay += (int)(20 * fast_sin(i * 0.5));
                    amplitude *= (1.0 + 0.3 * fast_sin(i * 2.1));
                    break;
                    
                case IR_TYPE_CAVE:
                    delay += (int)(fast_rand() * 100);
                    amplitude *= 2.5;
                    if (i % 7 == 0) amplitude *= 3.0;
                    break;
                    
                case IR_TYPE_SHIMMER:
                    delay = delay * (1.0 - i * 0.001);
                    amplitude *= (1.0 + i * 0.01);
                    break;
                    
                case IR_TYPE_FREEZE:
                    if (i % 10 < 3) {
                        delay = pre_delay_samples + 100;
                        amplitude *= 5.0;
                    }
                    break;
                    
                case IR_TYPE_REVERSE:
                    delay = ir_length - delay;
                    amplitude *= 2.0;
                    break;
                    
                case IR_TYPE_GATED:
                    if (delay > pre_delay_samples + engine.sample_rate * 0.3) continue;
                    amplitude *= 4.0;
                    break;
                    
                case IR_TYPE_CHORUS:
                    for (int c = 0; c < 3; c++) {
                        if (delay + c * 20 < ir_length) {
                            ir[delay + c * 20] += amplitude * 0.7;
                        }
                    }
                    break;
                    
                case IR_TYPE_ALIEN:
                    delay = (int)(delay * (1.0 + 0.5 * fast_sin(delay * 0.01)));
                    amplitude *= (2.0 + fast_sin(i * 0.666));
                    break;
                    
                case IR_TYPE_UNDERWATER:
                    delay += (int)(30 * fast_sin(i * 0.3) * fast_sin(i * 1.7));
                    amplitude *= 1.5;
                    break;
                    
                case IR_TYPE_METALLIC:
                    if (i % 11 == 0 || i % 13 == 0) amplitude *= 4.0;
                    delay += (int)(5 * fast_sin(i * 10.0));
                    break;
                    
                case IR_TYPE_PSYCHEDELIC:
                    delay = (int)(delay * (1.0 + fast_rand()));
                    amplitude *= (1.0 + 2.0 * fast_sin(i * fast_rand() * 10.0));
                    if (fast_rand() > 0.8) amplitude *= 5.0;
                    break;
                    
                case IR_TYPE_SLAPBACK:
                    // Single strong echo
                    if (i == 0) {
                        delay = pre_delay_samples + engine.sample_rate / 10;  // 100ms
                        amplitude *= 10.0;
                    } else continue;
                    break;
                    
                case IR_TYPE_INFINITE:
                    // Feedback simulation
                    delay = pre_delay_samples + (i * 100);
                    amplitude *= pow(0.95, i) * 5.0;  // Slow decay
                    break;
                    
                case IR_TYPE_SCATTERED:
                    // Random granular bursts
                    delay = pre_delay_samples + (int)(fast_rand() * ir_length * 0.5);
                    amplitude *= (fast_rand() * 3.0);
                    break;
                    
                case IR_TYPE_DOPPLER:
                    // Simulated motion
                    double motion = fast_sin(i * 0.1);
                    delay = (int)(delay * (1.0 + motion * 0.3));
                    amplitude *= (1.0 + motion);
                    break;
                    
                case IR_TYPE_QUANTUM:
                    // Probability-based
                    if (fast_rand() > 0.7) {
                        amplitude *= 5.0 * fast_rand();
                        delay += (int)(fast_rand() * 200 - 100);
                    } else continue;
                    break;
                    
                case IR_TYPE_VOID:
                    // Almost nothing, then BANG
                    if (i == num_taps - 1) amplitude *= 100.0;
                    else amplitude *= 0.01;
                    break;
                    
                case IR_TYPE_CRYSTALLINE:
                    // Sharp, bright reflections
                    if (i % 2 == 0) {
                        delay += i * 5;
                        amplitude *= 2.0;
                    }
                    break;
                    
                case IR_TYPE_MAGNETIC:
                    // Tape-style warble
                    delay += (int)(10 * fast_sin(i * 0.2 + fast_sin(i * 0.05)));
                    amplitude *= (1.0 + 0.5 * fast_sin(i * 0.3));
                    break;
                    
                case IR_TYPE_PLASMA:
                    // Ionized bursts
                    if ((i * i) % 17 < 3) {
                        amplitude *= 8.0;
                        delay += (int)(fast_rand() * 50);
                    }
                    break;
                    
                case IR_TYPE_NIGHTMARE:
                    // Disturbing pattern
                    delay += (int)(50 * fast_sin(i * 0.666) * fast_sin(i * 0.13));
                    amplitude *= (1.0 + 3.0 * fast_sin(i * 6.66));
                    if (i % 13 == 0) amplitude *= -5.0;  // Phase inversion!
                    break;
            }
            
            // Apply diffusion with EXTREME spreading
            double diffusion_spread = engine.diffusion / 80.0;  // More aggressive spread
            int spread = (int)(10 * diffusion_spread);  // Double the spread range
            for (int j = -spread; j <= spread && delay + j < ir_length && delay + j >= 0; j++) {
                ir[delay + j] += amplitude * exp(-abs(j) * 0.15) * 1.5 / (spread + 1);  // Less decay, more amplitude
            }
        }
    }
}

// Generate reverb tail using statistical model
static void generate_reverb_tail(double* ir, int ir_length, int start_sample) {
    double decay_rate = 2.0 / engine.decay_time; // ULTRA slow decay - reverb that NEVER DIES
    double density = 5.0 + (engine.room_size / 20.0) * 50.0;  // QUANTUM DENSITY!
    int num_reflections = (int)(ir_length * 0.5 * density);  // HALF THE SAMPLES ARE REFLECTIONS!
    
    double hf_damping = engine.damping / 200.0;  // Less damping = MORE SHIMMER
    double lf_boost = (engine.low_freq / 25.0) * 3.0;  // TRIPLE the bass resonance!
    
    // INSANE reflection counts for ULTIMATE DENSITY
    if (num_reflections < 50000) num_reflections = 50000;  // MINIMUM 50K!
    if (num_reflections > 200000) num_reflections = 200000;  // Cap at 200K for CPU survival
    
    printf("  🌟 GENERATING %d QUANTUM REFLECTIONS FOR INFINITE TAIL 🌟\n", num_reflections);
    
    for (int i = 0; i < num_reflections; i++) {
        double progress = (double)i / num_reflections;
        int delay = start_sample + (int)(pow(fast_rand(), 0.5) * (ir_length - start_sample));
        
        if (delay < ir_length) {
            double t = (double)delay / engine.sample_rate;
            double amplitude = exp(-decay_rate * t);
            
            if (engine.damping > 50) {
                double damping_factor = (engine.damping - 50.0) / 50.0;
                amplitude *= exp(-damping_factor * damping_factor * t * 10.0);
            }
            
            // Room-specific coloration with EXTREME CHARACTER - NOW WITH NEW TYPES!
            switch (engine.ir_type) {
                case IR_TYPE_CATHEDRAL:
                    amplitude *= (1.0 + lf_boost * 5.0 * exp(-t * 0.05));  // MASSIVE bass, ultra-slow decay
                    if (i % 2 == 0) {
                        amplitude *= 5.0;  // QUINTUPLE every other reflection!
                    }
                    amplitude *= (1.0 + 2.0 * fast_sin(t * 250.0));  // Deep resonances
                    amplitude *= (1.0 + 1.5 * fast_sin(t * 666.0));  // Mystical harmonics!
                    amplitude *= (1.0 + fast_sin(t * 50.0));  // Sub-bass rumble
                    break;
                    
                case IR_TYPE_ROOM:
                    amplitude *= exp(-t * 5.0);  // Still fast but not as extreme
                    amplitude *= (1.0 + 2.0 * exp(-pow(t - 0.05, 2) * 50));  // Strong early energy
                    // Add room modes
                    amplitude *= (1.0 + fast_sin(t * 1000.0) + 0.5 * fast_sin(t * 2137.0));
                    break;
                    
                case IR_TYPE_PLATE:
                    amplitude *= (1.0 + 3.0 * fast_sin(t * 3000.0 + i * 0.5));  // EXTREME shimmer
                    amplitude *= (1.0 + 2.0 * fast_sin(t * 7000.0));  // High frequency madness
                    amplitude *= (1.0 + 1.5 * fast_sin(t * 11000.0));  // Ultra-high sparkle
                    amplitude *= (1.0 + fast_sin(t * 15000.0));  // Dog-whistle frequencies!
                    delay += (int)(30 * fast_sin(i * 0.2));  // Wider dispersion
                    if (delay >= ir_length) continue;
                    break;
                    
                case IR_TYPE_SPRING:
                    // MAXIMUM BOING - Multiple spring oscillations
                    delay += (int)(100 * fast_sin(t * 200.0) + 60 * fast_sin(t * 77.0));
                    delay += (int)(40 * fast_sin(t * 333.0));  // Triple spring madness!
                    if (delay >= ir_length || delay < 0) continue;
                    amplitude *= (1.0 + 4.0 * fast_sin(t * 600.0));  // MEGA oscillation
                    amplitude *= (1.0 + 2.0 * exp(-t * 1.0) * fast_sin(t * 2000.0));
                    amplitude *= (1.0 + fast_sin(t * 4567.0));  // Chaotic harmonics
                    break;
                    
                case IR_TYPE_CAVE:
                    // Deep, boomy cave resonances
                    amplitude *= (1.0 + lf_boost * 8.0);  // MASSIVE low end
                    amplitude *= exp(-t * 1.5);  // Very slow decay
                    // Stalactite drips
                    if ((int)(t * 1000) % 500 < 50) amplitude *= 3.0;
                    // Echo flutter
                    amplitude *= (1.0 + 2.0 * fast_sin(t * 100.0));
                    break;
                    
                case IR_TYPE_SHIMMER:
                    // Ethereal ascending effect
                    amplitude *= exp(-t * 2.0);
                    // Pitch shifting simulation
                    delay -= (int)(t * 50.0);  // Delays get shorter over time
                    if (delay < 0) continue;
                    // Octave harmonics
                    amplitude *= (1.0 + 2.0 * fast_sin(t * 2000.0 * (1.0 + t)));
                    amplitude *= (1.0 + 1.5 * fast_sin(t * 4000.0 * (1.0 + t * 0.5)));
                    break;
                    
                case IR_TYPE_FREEZE:
                    // Infinite sustain effect
                    amplitude *= 2.0;  // No decay!
                    // Clustered delays
                    delay = start_sample + (int)((fast_rand() * 0.1 + 0.45) * engine.sample_rate);
                    // Add harmonics
                    amplitude *= (1.0 + fast_sin(t * 1000.0) + fast_sin(t * 2000.0));
                    break;
                    
                case IR_TYPE_REVERSE:
                    // Backwards envelope
                    amplitude *= (1.0 - exp(-t * 5.0));  // Grows over time!
                    amplitude *= exp(-(engine.decay_time - t) * 3.0);  // Then fades
                    // Psychedelic modulation
                    amplitude *= (1.0 + 2.0 * fast_sin(t * 500.0));
                    break;
                    
                case IR_TYPE_GATED:
                    // 80s gated reverb on steroids
                    if (t > 0.5) amplitude = 0;  // Hard gate
                    else amplitude *= 10.0;  // LOUD when open
                    // Add some character
                    amplitude *= (1.0 + fast_sin(t * 5000.0));
                    break;
                    
                case IR_TYPE_CHORUS:
                    // Modulated delays
                    amplitude *= exp(-t * 3.0);
                    // LFO modulation
                    delay += (int)(20.0 * fast_sin(t * 5.0 + i * 0.1));
                    delay += (int)(15.0 * fast_sin(t * 7.0));
                    if (delay >= ir_length || delay < 0) continue;
                    // Detuning effect
                    amplitude *= (1.0 + fast_sin(t * 1000.0 + i * 0.5));
                    break;
                    
                case IR_TYPE_ALIEN:
                    // Non-euclidean space reverb
                    amplitude *= exp(-t * 2.0 * (1.0 + fast_sin(t * 0.5)));  // Varying decay
                    // Weird resonances
                    amplitude *= (1.0 + 3.0 * fast_sin(t * 666.0));
                    amplitude *= (1.0 + 2.0 * fast_sin(t * 1337.0));
                    amplitude *= (1.0 + 1.5 * fast_sin(t * 3141.0));  // Pi frequency!
                    // Phase warping
                    delay += (int)(50.0 * fast_sin(t * 10.0) * fast_sin(t * 0.1));
                    if (delay >= ir_length || delay < 0) continue;
                    break;
                    
                case IR_TYPE_UNDERWATER:
                    // Subaquatic filtering
                    amplitude *= exp(-t * 4.0);  // Medium decay
                    amplitude *= (1.0 + lf_boost * 4.0);  // Muffled highs
                    // Bubble oscillations
                    amplitude *= (1.0 + 2.0 * fast_sin(t * 200.0 + fast_rand() * 100.0));
                    amplitude *= (1.0 + fast_sin(t * 77.0));
                    // Current movement
                    delay += (int)(40.0 * fast_sin(t * 0.3));
                    break;
                    
                case IR_TYPE_METALLIC:
                    // Inside a metal tank
                    amplitude *= exp(-t * 3.5);
                    // Metallic ring
                    amplitude *= (1.0 + 4.0 * fast_sin(t * 2500.0) * exp(-t * 5.0));
                    amplitude *= (1.0 + 3.0 * fast_sin(t * 5700.0) * exp(-t * 8.0));
                    amplitude *= (1.0 + 2.0 * fast_sin(t * 8900.0) * exp(-t * 10.0));
                    // Resonant nodes
                    if ((int)(t * 5000) % 1000 < 100) amplitude *= 5.0;
                    break;
                    
                case IR_TYPE_PSYCHEDELIC:
                    // Complete chaos!
                    amplitude *= exp(-t * (1.0 + 3.0 * fast_rand()));  // Random decay
                    // Random resonances
                    for (int h = 0; h < 5; h++) {
                        amplitude *= (1.0 + fast_sin(t * (100.0 + fast_rand() * 10000.0)));
                    }
                    // Delay chaos
                    delay += (int)(100.0 * fast_sin(t * fast_rand() * 100.0));
                    delay = (int)(delay * (0.5 + fast_rand()));
                    if (delay >= ir_length || delay < 0) continue;
                    // Random amplitude bursts
                    if (fast_rand() > 0.95) amplitude *= 10.0;
                    break;
                    
                default: // HALL - Make it SYMPHONIC
                    amplitude *= (1.0 + lf_boost * 2.0 * exp(-t * 0.3));
                    double size_factor = (100.0 - engine.room_size) / 100.0;
                    amplitude *= exp(-size_factor * size_factor * t * 1.0);  // Slower decay
                    // Add concert hall resonances
                    amplitude *= (1.0 + 0.5 * fast_sin(t * 440.0));   // A440 resonance
                    amplitude *= (1.0 + 0.3 * fast_sin(t * 880.0));   // Octave
                    amplitude *= (1.0 + 0.2 * fast_sin(t * 1320.0));  // Fifth
                    break;
            }
            
            // Apply diffusion
            if (engine.diffusion > 50) {
                int smear = (int)((engine.diffusion - 50) * 0.2);
                for (int s = -smear; s <= smear && delay + s < ir_length && delay + s >= 0; s++) {
                    ir[delay + s] += amplitude * (2.0 * fast_rand() - 1.0) * 
                                    exp(-abs(s) * 0.3) / (smear + 1);
                }
            } else {
                // Low diffusion = MASSIVE discrete echoes
                ir[delay] += amplitude * (2.0 * fast_rand() - 1.0) * 10.0;  // 10X louder!
            }
        }
    }
}

// Apply spectral shaping
static void apply_spectral_shaping(double* ir, int ir_length) {
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
    printf("\n=== GENERATING NEW IMPULSE RESPONSE ===\n");
    
    // Clear the IR buffer
    memset(engine.impulse_response, 0, MAX_IR_SIZE * sizeof(double));
    
    // Calculate IR length
    engine.ir_length = (int)(engine.decay_time * engine.sample_rate);
    if (engine.ir_length > MAX_IR_SIZE) {
        engine.ir_length = MAX_IR_SIZE;
    }
    if (engine.ir_length < engine.sample_rate / 2) {
        engine.ir_length = engine.sample_rate / 2;
    }
    
    int pre_delay_samples = (int)(engine.pre_delay * engine.sample_rate / 1000.0);
    
    // Generate early reflections
    generate_early_reflections(engine.impulse_response, engine.ir_length, pre_delay_samples);
    
    // Generate reverb tail
    int tail_start = pre_delay_samples + (int)(0.02 * engine.sample_rate);
    generate_reverb_tail(engine.impulse_response, engine.ir_length, tail_start);
    
    // Apply spectral shaping
    apply_spectral_shaping(engine.impulse_response, engine.ir_length);
    
    // Normalize with COSMIC SCALE BOOST - WE'RE GOING INTERSTELLAR!
    double max_val = 0.0;
    double rms = 0.0;
    
    for (int i = 0; i < engine.ir_length; i++) {
        double abs_val = fabs(engine.impulse_response[i]);
        if (abs_val > max_val) max_val = abs_val;
        rms += engine.impulse_response[i] * engine.impulse_response[i];
    }
    
    rms = sqrt(rms / engine.ir_length);
    
    if (max_val > 0.0) {
        // 🌟 INTERSTELLAR BOOST - BEYOND ALL LIMITS! 🌟
        double target_peak = 10.0;  // TEN TIMES the original!
        double norm_factor = target_peak / max_val;
        
        // Allow boosting up to 20x for COSMIC REVERB
        if (norm_factor > 20.0) norm_factor = 20.0;
        
        // EXTREME boost based on reverb type
        switch (engine.ir_type) {
            case IR_TYPE_CATHEDRAL:
                norm_factor *= 2.0;  // DOUBLE for the house of God!
                printf("  ⛪ CATHEDRAL BOOST: DIVINE MULTIPLICATION x%.1f ⛪\n", norm_factor);
                break;
            case IR_TYPE_PLATE:
                norm_factor *= 1.8;  // Metal plates should RING FOREVER
                printf("  🔔 PLATE BOOST: ETERNAL RESONANCE x%.1f 🔔\n", norm_factor);
                break;
            case IR_TYPE_SPRING:
                norm_factor *= 2.5;  // Springs should OSCILLATE THE UNIVERSE
                printf("  🌀 SPRING BOOST: QUANTUM OSCILLATION x%.1f 🌀\n", norm_factor);
                break;
            case IR_TYPE_ROOM:
                norm_factor *= 1.5;  // Even small rooms are CAVERNS now
                printf("  🏛️ ROOM BOOST: CAVERN MODE x%.1f 🏛️\n", norm_factor);
                break;
            default:
                printf("  🎭 HALL BOOST: SYMPHONIC EXPLOSION x%.1f 🎭\n", norm_factor);
        }
        
        // Apply the cosmic boost with HARMONIC ENHANCEMENT
        for (int i = 0; i < engine.ir_length; i++) {
            engine.impulse_response[i] *= norm_factor;
            
            // Add subtle harmonic distortion for RICHNESS
            if (i % 2 == 0 && fabs(engine.impulse_response[i]) > 0.1) {
                engine.impulse_response[i] *= 1.02;  // Even harmonics boost
            }
        }
        
        rms *= norm_factor;
        
        printf("  🌌💫 CONVOLUTION MATRIX HYPERCHARGED: %.1fx boost applied! 💫🌌\n", norm_factor);
    }
    
    engine.ir_needs_update = 0;
    
    // Debug output with extended type names
    const char* type_names[] = {
        "Hall", "Cathedral", "Room", "Plate", "Spring", 
        "Cave", "Shimmer", "Freeze", "Reverse", "Gated",
        "Chorus", "Alien", "Underwater", "Metallic", "Psychedelic",
        "Slapback", "Infinite", "Scattered", "Doppler", "Quantum",
        "Void", "Crystalline", "Magnetic", "Plasma", "Nightmare"
    };
    int type_index = engine.ir_type;
    if (type_index >= IR_TYPE_MAX) type_index = 0;
    
    printf("Generated %s IR\n", type_names[type_index]);
    printf("  Length: %d samples (%.2fs)\n", 
           engine.ir_length, (double)engine.ir_length / engine.sample_rate);
    printf("  Parameters: room=%.1f, decay=%.1f, delay=%.1f, damp=%.1f\n",
           engine.room_size, engine.decay_time, engine.pre_delay, engine.damping);
    printf("  Mix=%.1f, diffusion=%.1f, early=%.1f\n",
           engine.mix_level, engine.diffusion, engine.early_reflections);
    printf("  Peak: %.4f, RMS: %.4f\n", max_val, rms);
    printf("=== IR GENERATION COMPLETE ===\n");
}

// Process audio with convolution - ENHANCED VERSION
void process_convolution_(double* input, double* output, int* num_samples) {
    int n = *num_samples;
    
    // Initialize if needed
    if (!engine.initialized || !engine.impulse_response) {
        memcpy(output, input, n * sizeof(double));
        return;
    }
    
    // ALWAYS check and update IR if needed
    if (engine.ir_needs_update) {
        printf("process_convolution_: IR needs update, regenerating...\n");
        generate_impulse_response();
        
        // Clear convolution history
        if (conv_history) {
            memset(conv_history, 0, MAX_IR_SIZE * sizeof(double));
        }
        history_pos = 0;
    }
    
    // Allocate convolution history buffer if needed
    if (!conv_history) {
        conv_history = (double*)calloc(MAX_IR_SIZE, sizeof(double));
        history_pos = 0;
    }
    
    // Calculate mix parameters - 🌌 CONVOLUTION SINGULARITY MODE 🌌
    double mix = engine.mix_level / 100.0;
    double dry_gain, wet_gain;
    
    // LOGARITHMIC EXPLOSION OF REVERB - EACH PERCENT IS EXPONENTIALLY MORE INSANE!!!
    if (mix < 0.01) {
        // 0-1%: Even 0.1% should RUMBLE
        dry_gain = 1.0;
        wet_gain = mix * 1000.0;  // 0 to 10.0 - INSTANT REVERB!
    } else if (mix < 0.1) {
        // 1-10%: EXPONENTIAL MADNESS BEGINS
        dry_gain = 1.0;
        wet_gain = 10.0 * pow(mix * 10.0, 2.5);  // 10 to 316 - GEOMETRIC GROWTH!
    } else if (mix < 0.3) {
        // 10-30%: ENTERING THE CONVOLUTION DIMENSION
        dry_gain = 1.0 * (1.0 - (mix - 0.1) * 2.5);  // 1.0 to 0.5
        wet_gain = 316.0 * pow(mix * 3.33, 1.5);  // 316 to 1000+ - TRANSCENDENT!
    } else if (mix < 0.5) {
        // 30-50%: REALITY STARTS WARPING
        dry_gain = 0.5 * (1.0 - (mix - 0.3) * 2.0);  // 0.5 to 0.1
        wet_gain = 1000.0 + (mix - 0.3) * 5000.0;  // 1000 to 2000 - ASTRONOMICAL!
    } else if (mix < 0.8) {
        // 50-80%: CONVOLUTION BLACK HOLE
        dry_gain = 0.1 * (1.0 - (mix - 0.5) * 2.0);  // 0.1 to 0.02
        wet_gain = 2000.0 * pow(mix * 2.0, 2.0);  // 2000 to 5120 - EVENT HORIZON!
    } else {
        // 80-100%: PURE CONVOLUTION SINGULARITY - INFINITE REVERB
        dry_gain = 0.01;  // Basically gone
        wet_gain = 5120.0 * pow(mix * 1.25, 3.0);  // 5120 to 10000+ - INFINITY APPROACHES!
    }
    
    // 🌟 QUANTUM BOOST for live processing - IT'S ALIVE! 🌟
    if (n <= 4096) {
        wet_gain *= 5.0;  // 5X MULTIPLIER!
        
        // Extra boost based on room type
        switch (engine.ir_type) {
            case IR_TYPE_CATHEDRAL:
                wet_gain *= 2.0;  // DOUBLE for cathedrals!
                printf("  ⛪ CATHEDRAL MODE: DIVINE CONVOLUTION x%.0f ⛪\n", wet_gain);
                break;
            case IR_TYPE_PLATE:
                wet_gain *= 1.8;  // SHIMMER OVERLOAD!
                printf("  ✨ PLATE MODE: INFINITE SHIMMER x%.0f ✨\n", wet_gain);
                break;
            case IR_TYPE_SPRING:
                wet_gain *= 2.2;  // BOING TO THE MAX!
                printf("  🌀 SPRING MODE: COSMIC BOING x%.0f 🌀\n", wet_gain);
                break;
            default:
                printf("  🚀 LIVE CONVOLUTION WARP DRIVE: x%.0f 🚀\n", wet_gain);
        }
    }
    
    // EPIC logging with ASCII art!
    if (++process_counter % 10 == 0) {
        printf("\n🌌 CONVOLUTION SINGULARITY STATUS 🌌\n");
        printf("Mix: %.0f%% | Dry: %.4f | Wet: %.0f\n", engine.mix_level, dry_gain, wet_gain);
        
        if (wet_gain > 5000) {
            printf("████████████████████████████████\n");
            printf("██ 🔥 REALITY DISTORTION 🔥 ██\n");
            printf("████████████████████████████████\n");
        } else if (wet_gain > 1000) {
            printf("╔════════════════════════════╗\n");
            printf("║ ⚡ CONVOLUTION STORM ⚡ ║\n");
            printf("╚════════════════════════════╝\n");
        } else if (wet_gain > 100) {
            printf("┌────────────────────────┐\n");
            printf("│ 🌊 REVERB TSUNAMI 🌊 │\n");
            printf("└────────────────────────┘\n");
        }
    }
    
    // Process each sample
    for (int i = 0; i < n; i++) {
        // Store input in circular buffer
        conv_history[history_pos] = input[i];
        
        // PERFORM CONVOLUTION WITH PARALLEL UNIVERSE PROCESSING
        double wet_sample = 0.0;
        double wet_sample_delayed = 0.0;  // Second layer for DEPTH
        double wet_sample_shimmer = 0.0;  // Third layer for SPARKLE
        
        int ir_len = engine.ir_length;
        
        // Primary convolution
        for (int j = 0; j < ir_len; j++) {
            int hist_idx = (history_pos - j + MAX_IR_SIZE) % MAX_IR_SIZE;
            wet_sample += conv_history[hist_idx] * engine.impulse_response[j];
        }
        
        // Add subtle pitch-shifted layers for THICKNESS (simple delay-based)
        if (engine.mix_level > 30) {
            for (int j = 0; j < ir_len; j += 2) {  // Slight decimation for pitch up
                int hist_idx = (history_pos - j + MAX_IR_SIZE) % MAX_IR_SIZE;
                wet_sample_shimmer += conv_history[hist_idx] * engine.impulse_response[j] * 0.3;
            }
            
            for (int j = 0; j < ir_len && j < ir_len - 1; j++) {  // Interpolation for pitch down
                int hist_idx = (history_pos - (j * 3 / 2) + MAX_IR_SIZE) % MAX_IR_SIZE;
                wet_sample_delayed += conv_history[hist_idx] * engine.impulse_response[j] * 0.2;
            }
        }
        
        // Combine all layers
        wet_sample = wet_sample + wet_sample_delayed + wet_sample_shimmer;
        
        // Mix dry and wet signals with CONVOLUTION SUPREMACY
        output[i] = dry_gain * input[i] + wet_gain * wet_sample;
        
        // Advanced multiband compression for HUGE levels without distortion
        double abs_out = fabs(output[i]);
        if (abs_out > 0.7) {
            // Smooth compression curve
            double sign = output[i] > 0 ? 1.0 : -1.0;
            double compressed = 0.7 + (abs_out - 0.7) * 0.3;  // 3:1 compression above 0.7
            compressed = fmin(compressed, 1.8);  // Soft ceiling at 1.8
            output[i] = sign * compressed;
        }
        
        // Final limiter with smooth saturation
        if (output[i] > 1.9) {
            output[i] = 1.9 + 0.1 * tanh((output[i] - 1.9) * 10.0);
        } else if (output[i] < -1.9) {
            output[i] = -1.9 - 0.1 * tanh((-output[i] - 1.9) * 10.0);
        }
        
        // Advance circular buffer
        history_pos = (history_pos + 1) % MAX_IR_SIZE;
    }
}

// ENHANCED: Parameter setter with immediate IR regeneration
void set_param_float_(int* param_id, float* value) {
    printf("\n>>> set_param_float_ called: id=%d, value=%.2f\n", *param_id, *value);
    
    int old_update_flag = engine.ir_needs_update;
    float old_value = 0.0;
    int needs_update = 0;
    
    switch (*param_id) {
        case 0: // roomSize
            old_value = engine.room_size;
            engine.room_size = *value;
            if (fabs(old_value - *value) > 0.01) {
                needs_update = 1;
            }
            printf("  Room size: %.1f -> %.1f\n", old_value, engine.room_size);
            break;
            
        case 1: // decayTime
            old_value = engine.decay_time;
            engine.decay_time = fmax(0.1, fmin(10.0, *value));
            if (fabs(old_value - engine.decay_time) > 0.01) {
                needs_update = 1;
            }
            printf("  Decay time: %.1f -> %.1f\n", old_value, engine.decay_time);
            break;
            
        case 2: // preDelay
            old_value = engine.pre_delay;
            engine.pre_delay = fmax(0.0, fmin(100.0, *value));
            if (fabs(old_value - engine.pre_delay) > 0.01) {
                needs_update = 1;
            }
            printf("  Pre-delay: %.1f -> %.1f\n", old_value, engine.pre_delay);
            break;
            
        case 3: // damping
            old_value = engine.damping;
            engine.damping = *value;
            if (fabs(old_value - *value) > 0.01) {
                needs_update = 1;
            }
            printf("  Damping: %.1f -> %.1f\n", old_value, engine.damping);
            break;
            
        case 4: // lowFreq
            old_value = engine.low_freq;
            engine.low_freq = *value;
            if (fabs(old_value - *value) > 0.01) {
                needs_update = 1;
            }
            printf("  Low freq: %.1f -> %.1f\n", old_value, engine.low_freq);
            break;
            
        case 5: // diffusion
            old_value = engine.diffusion;
            engine.diffusion = *value;
            if (fabs(old_value - *value) > 0.01) {
                needs_update = 1;
            }
            printf("  Diffusion: %.1f -> %.1f\n", old_value, engine.diffusion);
            break;
            
        case 6: // mix
            old_value = engine.mix_level;
            engine.mix_level = fmax(0.0, fmin(100.0, *value));
            printf("  Mix level: %.1f -> %.1f (no IR update needed)\n", old_value, engine.mix_level);
            // Mix doesn't need IR update
            break;
            
        case 7: // earlyReflections
            old_value = engine.early_reflections;
            engine.early_reflections = *value;
            if (fabs(old_value - *value) > 0.01) {
                needs_update = 1;
            }
            printf("  Early reflections: %.1f -> %.1f\n", old_value, engine.early_reflections);
            break;
            
        default:
            printf("  WARNING: Unknown parameter ID %d\n", *param_id);
            return;
    }
    
    // Force immediate IR regeneration if needed
    if (needs_update && engine.initialized) {
        engine.ir_needs_update = 1;
        printf("  >>> Parameter changed significantly - regenerating IR immediately!\n");
        generate_impulse_response();
        
        // Clear convolution history to avoid artifacts
        if (conv_history) {
            memset(conv_history, 0, MAX_IR_SIZE * sizeof(double));
            history_pos = 0;
        }
        printf("  >>> IR regenerated and history cleared\n");
    }
}

// String-based parameter setter (for compatibility)
void set_parameter_(char* param_name, double* value, int param_name_len) {
    char name[64] = {0};
    strncpy(name, param_name, (param_name_len < 63) ? param_name_len : 63);
    
    printf("Setting parameter '%s' to %.2f\n", name, *value);
    
    if (strcmp(name, "roomSize") == 0) {
        float fval = (float)*value;
        int id = 0;
        set_param_float_(&id, &fval);
    } else if (strcmp(name, "decayTime") == 0) {
        float fval = (float)*value;
        int id = 1;
        set_param_float_(&id, &fval);
    } else if (strcmp(name, "preDelay") == 0) {
        float fval = (float)*value;
        int id = 2;
        set_param_float_(&id, &fval);
    } else if (strcmp(name, "damping") == 0) {
        float fval = (float)*value;
        int id = 3;
        set_param_float_(&id, &fval);
    } else if (strcmp(name, "lowFreq") == 0) {
        float fval = (float)*value;
        int id = 4;
        set_param_float_(&id, &fval);
    } else if (strcmp(name, "diffusion") == 0) {
        float fval = (float)*value;
        int id = 5;
        set_param_float_(&id, &fval);
    } else if (strcmp(name, "mix") == 0) {
        float fval = (float)*value;
        int id = 6;
        set_param_float_(&id, &fval);
    } else if (strcmp(name, "earlyReflections") == 0) {
        float fval = (float)*value;
        int id = 7;
        set_param_float_(&id, &fval);
    }
}

// Set IR type with immediate regeneration
void set_ir_type_(char* ir_type_str, int ir_type_len) {
    char type[32] = {0};
    strncpy(type, ir_type_str, (ir_type_len < 31) ? ir_type_len : 31);
    
    printf("\n>>> set_ir_type_: '%s'\n", type);
    
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
    } else if (strcmp(type, "cave") == 0) {
        engine.ir_type = IR_TYPE_CAVE;
    } else if (strcmp(type, "shimmer") == 0) {
        engine.ir_type = IR_TYPE_SHIMMER;
    } else if (strcmp(type, "freeze") == 0) {
        engine.ir_type = IR_TYPE_FREEZE;
    } else if (strcmp(type, "reverse") == 0) {
        engine.ir_type = IR_TYPE_REVERSE;
    } else if (strcmp(type, "gated") == 0) {
        engine.ir_type = IR_TYPE_GATED;
    } else if (strcmp(type, "chorus") == 0) {
        engine.ir_type = IR_TYPE_CHORUS;
    } else if (strcmp(type, "alien") == 0) {
        engine.ir_type = IR_TYPE_ALIEN;
    } else if (strcmp(type, "underwater") == 0) {
        engine.ir_type = IR_TYPE_UNDERWATER;
    } else if (strcmp(type, "metallic") == 0) {
        engine.ir_type = IR_TYPE_METALLIC;
    } else if (strcmp(type, "psychedelic") == 0) {
        engine.ir_type = IR_TYPE_PSYCHEDELIC;
    }
    
    if (old_type != engine.ir_type) {
        printf("  🎭 IR type changed from %d to %d - MORPHING REALITY! 🎭\n", old_type, engine.ir_type);
        engine.ir_needs_update = 1;
        
        // Force immediate regeneration
        if (engine.initialized) {
            printf("  >>> 🌟 NEW UNIVERSE SELECTED - REGENERATING SPACE-TIME! 🌟\n");
            generate_impulse_response();
            if (conv_history) {
                memset(conv_history, 0, MAX_IR_SIZE * sizeof(double));
                history_pos = 0;
            }
            printf("  >>> 🎆 NEW REALITY LOADED! 🎆\n");
        }
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
    process_counter = 0;
}

// Status functions
int is_initialized_() {
    return engine.initialized;
}

int get_sample_rate_() {
    return engine.sample_rate;
}

char* get_version_() {
    static char version[] = "2.0.3-C";
    return version;
}

// Debug function to print current engine state
void debug_print_engine_state() {
    printf("\n=== CURRENT ENGINE STATE ===\n");
    printf("Initialized: %d\n", engine.initialized);
    printf("Sample Rate: %d Hz\n", engine.sample_rate);
    printf("IR Length: %d samples (%.2fs)\n", engine.ir_length, (double)engine.ir_length / engine.sample_rate);
    printf("IR Needs Update: %d\n", engine.ir_needs_update);
    printf("\nParameters:\n");
    printf("  Room Size: %.1f%%\n", engine.room_size);
    printf("  Decay Time: %.1fs\n", engine.decay_time);
    printf("  Pre-Delay: %.1fms\n", engine.pre_delay);
    printf("  Damping: %.1f%%\n", engine.damping);
    printf("  Low Freq: %.1f%%\n", engine.low_freq);
    printf("  Diffusion: %.1f%%\n", engine.diffusion);
    printf("  Mix Level: %.1f%%\n", engine.mix_level);
    printf("  Early Reflections: %.1f%%\n", engine.early_reflections);
    
    const char* type_names[] = {
        "Hall", "Cathedral", "Room", "Plate", "Spring", 
        "Cave", "Shimmer", "Freeze", "Reverse", "Gated",
        "Chorus", "Alien", "Underwater", "Metallic", "Psychedelic",
        "Slapback", "Infinite", "Scattered", "Doppler", "Quantum",
        "Void", "Crystalline", "Magnetic", "Plasma", "Nightmare"
    };
    int type_index = engine.ir_type;
    if (type_index >= IR_TYPE_MAX) type_index = 0;
    
    printf("  IR Type: %s (%d)\n", type_names[type_index], engine.ir_type);
    printf("===========================\n\n");
}

// Test function to verify reverb is working
void test_reverb_impulse() {
    printf("\n=== TESTING REVERB WITH IMPULSE ===\n");
    
    // Create a test impulse
    double test_input[1000] = {0};
    double test_output[1000] = {0};
    int num_samples = 1000;
    
    // Single impulse at the beginning
    test_input[0] = 1.0;
    
    // Process it
    process_convolution_(test_input, test_output, &num_samples);
    
    // Check the output
    double energy = 0.0;
    double max_val = 0.0;
    int last_nonzero = 0;
    
    for (int i = 0; i < num_samples; i++) {
        double val = fabs(test_output[i]);
        energy += val * val;
        if (val > max_val) max_val = val;
        if (val > 0.001) last_nonzero = i;
    }
    
    printf("Test results:\n");
    printf("  Input energy: 1.0\n");
    printf("  Output energy: %.4f\n", sqrt(energy));
    printf("  Max output: %.4f\n", max_val);
    printf("  Last significant sample: %d (%.1fms)\n", 
           last_nonzero, (double)last_nonzero * 1000.0 / engine.sample_rate);
    printf("  Mix level: %.1f%%\n", engine.mix_level);
    
    // Print first few output samples
    printf("  First 10 output samples: ");
    for (int i = 0; i < 10; i++) {
        printf("%.4f ", test_output[i]);
    }
    printf("\n");
    
    if (energy < 0.01) {
        printf("  WARNING: Very low output energy - reverb might not be working!\n");
    }
    
    printf("=========================\n\n");
}

// NOTE: Export functions are defined in wasm_bridge.c
// The bridge calls these internal functions with underscore suffixes