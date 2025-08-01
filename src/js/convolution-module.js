// convolution-module.js - JavaScript Wrapper for Convolution WebAssembly Module

class ConvolutionProcessor {
    constructor() {
        this.module = null;
        this.initialized = false;
        this.inputPtr = null;
        this.outputPtr = null;
        this.maxSamples = 0;
        this.sampleRate = 48000;
    }

    async initialize(wasmPath, sampleRate = 48000) {
        try {
            // Load the WebAssembly module
            this.module = await ConvolutionModule({
                locateFile: (file) => {
                    // Handle both .wasm and .js files
                    if (file.endsWith('.wasm') || file.endsWith('.js')) {
                        return wasmPath + file;
                    }
                    return file;
                }
            });

            this.sampleRate = sampleRate;

            // Initialize the engine
            this.module._init_engine(sampleRate);
            
            // Check if initialized
            if (this.module._is_initialized()) {
                this.initialized = true;
                console.log('ConvolutionProcessor initialized successfully');
                console.log('Version:', this.module.UTF8ToString(this.module._get_version()));
                console.log('Sample rate:', this.module._get_sample_rate());
            } else {
                throw new Error('Failed to initialize convolution engine');
            }
        } catch (error) {
            console.error('Error initializing ConvolutionProcessor:', error);
            throw error;
        }
    }

    allocateBuffers(numSamples) {
        if (numSamples > this.maxSamples) {
            // Free existing buffers
            if (this.inputPtr) {
                this.module._free_double_array(this.inputPtr);
                this.module._free_double_array(this.outputPtr);
            }

            // Allocate new buffers
            this.inputPtr = this.module._allocate_double_array(numSamples);
            this.outputPtr = this.module._allocate_double_array(numSamples);
            this.maxSamples = numSamples;

            if (!this.inputPtr || !this.outputPtr) {
                throw new Error('Failed to allocate memory buffers');
            }
        }
    }

    processAudio(inputArray) {
        if (!this.initialized) {
            throw new Error('ConvolutionProcessor not initialized');
        }

        const numSamples = inputArray.length;
        this.allocateBuffers(numSamples);

        // Convert to Float64Array if needed
        let inputFloat64;
        if (inputArray instanceof Float64Array) {
            inputFloat64 = inputArray;
        } else if (inputArray instanceof Float32Array) {
            inputFloat64 = new Float64Array(inputArray);
        } else {
            inputFloat64 = new Float64Array(inputArray);
        }

        // Copy input data to WebAssembly memory
        this.module.HEAPF64.set(inputFloat64, this.inputPtr / 8);

        // Process audio
        this.module._process_audio(this.inputPtr, this.outputPtr, numSamples);

        // Copy output data from WebAssembly memory
        const outputArray = new Float64Array(
            this.module.HEAPF64.buffer,
            this.outputPtr,
            numSamples
        );

        // Return a copy to avoid memory issues
        return new Float64Array(outputArray);
    }

    processAudioWithMix(inputArray, mixLevel) {
        if (!this.initialized) {
            throw new Error('ConvolutionProcessor not initialized');
        }

        const numSamples = inputArray.length;
        this.allocateBuffers(numSamples);

        // Convert to Float64Array if needed
        let inputFloat64;
        if (inputArray instanceof Float64Array) {
            inputFloat64 = inputArray;
        } else {
            inputFloat64 = new Float64Array(inputArray);
        }

        // Copy input data to WebAssembly memory
        this.module.HEAPF64.set(inputFloat64, this.inputPtr / 8);

        // Process audio with mix
        this.module._process_audio_with_mix(
            this.inputPtr, 
            this.outputPtr, 
            numSamples, 
            mixLevel / 100.0
        );

        // Copy output data from WebAssembly memory
        const outputArray = new Float64Array(
            this.module.HEAPF64.buffer,
            this.outputPtr,
            numSamples
        );

        return new Float64Array(outputArray);
    }

    setParameter(paramName, value) {
        if (!this.initialized) {
            console.warn('ConvolutionProcessor not initialized');
            return;
        }

        const paramMap = {
            'roomSize': 0,
            'decayTime': 1,
            'preDelay': 2,
            'damping': 3,
            'lowFreq': 4,
            'diffusion': 5,
            'mix': 6,
            'earlyReflections': 7
        };

        const paramId = paramMap[paramName];
        if (paramId !== undefined) {
            this.module._set_parameter(paramId, value);
            console.log(`Set ${paramName} to ${value}`);
        } else {
            console.warn(`Unknown parameter: ${paramName}`);
        }
    }

    setImpulseResponseType(irType) {
        if (!this.initialized) {
            console.warn('ConvolutionProcessor not initialized');
            return;
        }

        // Use stringToUTF8 instead of allocateUTF8
        const bufferSize = this.module.lengthBytesUTF8(irType) + 1;
        const irTypePtr = this.module._malloc(bufferSize);
        
        try {
            this.module.stringToUTF8(irType, irTypePtr, bufferSize);
            this.module._set_ir_type(irTypePtr);
            console.log(`Set impulse response type to: ${irType}`);
        } finally {
            // Always free the allocated string
            this.module._free(irTypePtr);
        }
    }

    getVersion() {
        if (!this.initialized) return 'Not initialized';
        
        const versionPtr = this.module._get_version();
        return this.module.UTF8ToString(versionPtr);
    }

    getSampleRate() {
        if (!this.initialized) return 0;
        
        return this.module._get_sample_rate();
    }

    isInitialized() {
        return this.initialized && this.module && this.module._is_initialized();
    }

    cleanup() {
        if (this.initialized) {
            // Free allocated buffers
            if (this.inputPtr) {
                this.module._free_double_array(this.inputPtr);
                this.module._free_double_array(this.outputPtr);
                this.inputPtr = null;
                this.outputPtr = null;
            }

            // Cleanup engine
            this.module._cleanup_engine();
            this.initialized = false;
            this.maxSamples = 0;
            
            console.log('ConvolutionProcessor cleaned up');
        }
    }
}

// For AudioWorklet support
class ConvolutionWorkletNode extends AudioWorkletNode {
    constructor(context, processorOptions) {
        super(context, 'convolution-processor', processorOptions);
    }

    setParameter(paramName, value) {
        this.port.postMessage({
            type: 'setParameter',
            paramName: paramName,
            value: value
        });
    }

    setImpulseResponseType(irType) {
        this.port.postMessage({
            type: 'setIRType',
            irType: irType
        });
    }
}

// Export for use in web applications and Node.js
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { ConvolutionProcessor, ConvolutionWorkletNode };
}

// For ES6 modules
if (typeof window !== 'undefined') {
    window.ConvolutionProcessor = ConvolutionProcessor;
    window.ConvolutionWorkletNode = ConvolutionWorkletNode;
}