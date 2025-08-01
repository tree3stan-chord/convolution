// convolution-module.js
// WebAssembly module wrapper for the convolution reverb engine

class ConvolutionProcessor {
    constructor() {
        this.module = null;
        this.initialized = false;
        this.sampleRate = 48000;
        
        // Function wrappers
        this.initEngine = null;
        this.processAudioNative = null;
        this.setParameterNative = null;
        this.setIRTypeNative = null;
        this.cleanupEngine = null;
        this.allocateDoubleArray = null;
        this.freeDoubleArray = null;
        this.isInitialized = null;
        this.getSampleRateNative = null;
        this.getVersionNative = null;
        
        // Parameter map
        this.parameterMap = {
            'roomSize': 0,
            'decayTime': 1,
            'preDelay': 2,
            'damping': 3,
            'lowFreq': 4,
            'diffusion': 5,
            'mix': 6,
            'earlyReflections': 7,
            'highFreq': 8,
            'lateMix': 9
        };
    }
    
    async initialize(wasmPath, sampleRate) {
        console.log('ConvolutionProcessor: Loading WebAssembly module...');
        
        try {
            // Load the WebAssembly module
            this.module = await ConvolutionModule({
                locateFile: (filename) => {
                    return wasmPath + filename;
                },
                print: (text) => console.log('WASM:', text),
                printErr: (text) => console.error('WASM Error:', text),
                onRuntimeInitialized: () => {
                    console.log('ConvolutionProcessor: WebAssembly runtime initialized');
                }
            });
            
            console.log('ConvolutionProcessor: Module loaded, setting up functions...');
            
            // Get function wrappers
            this.initEngine = this.module.cwrap('init_engine', null, ['number']);
            this.processAudioNative = this.module.cwrap('process_audio', null, ['number', 'number', 'number']);
            this.setParameterNative = this.module.cwrap('set_parameter', null, ['number', 'number']);
            this.setIRTypeNative = this.module.cwrap('set_ir_type', null, ['string']);
            this.cleanupEngine = this.module.cwrap('cleanup_engine', null, []);
            this.allocateDoubleArray = this.module.cwrap('allocate_double_array', 'number', ['number']);
            this.freeDoubleArray = this.module.cwrap('free_double_array', null, ['number']);
            this.isInitialized = this.module.cwrap('is_initialized', 'number', []);
            this.getSampleRateNative = this.module.cwrap('get_sample_rate', 'number', []);
            this.getVersionNative = this.module.cwrap('get_version', 'string', []);
            
            // Initialize the engine
            this.sampleRate = sampleRate;
            this.initEngine(sampleRate);
            
            this.initialized = true;
            
            console.log('ConvolutionProcessor: Initialization complete!');
            console.log('ConvolutionProcessor: Version:', this.getVersion());
            console.log('ConvolutionProcessor: Sample rate:', this.getSampleRate(), 'Hz');
            console.log('ConvolutionProcessor: Ready for live input');
            
            return true;
        } catch (error) {
            console.error('ConvolutionProcessor: Initialization failed:', error);
            throw error;
        }
    }
    
    processAudio(inputArray) {
        if (!this.initialized) {
            console.warn('ConvolutionProcessor: Not initialized, returning input');
            return inputArray;
        }
        
        const numSamples = inputArray.length;
        
        // Allocate memory for input and output
        const inputPtr = this.allocateDoubleArray(numSamples);
        const outputPtr = this.allocateDoubleArray(numSamples);
        
        try {
            // Copy input data to WASM memory - handle both Float32 and Float64
            if (inputArray instanceof Float32Array) {
                const float64Input = new Float64Array(inputArray);
                this.module.HEAPF64.set(float64Input, inputPtr / 8);
            } else {
                this.module.HEAPF64.set(inputArray, inputPtr / 8);
            }
            
            // Process audio
            this.processAudioNative(inputPtr, outputPtr, numSamples);
            
            // Copy output data from WASM memory
            const outputArray = new Float64Array(numSamples);
            outputArray.set(this.module.HEAPF64.subarray(outputPtr / 8, outputPtr / 8 + numSamples));
            
            // Convert to Float32Array for Web Audio API
            const float32Output = new Float32Array(numSamples);
            for (let i = 0; i < numSamples; i++) {
                float32Output[i] = outputArray[i];
            }
            
            return float32Output;
        } finally {
            // Clean up allocated memory
            this.freeDoubleArray(inputPtr);
            this.freeDoubleArray(outputPtr);
        }
    }
    
    setParameter(paramName, value) {
        if (!this.initialized) {
            console.warn('ConvolutionProcessor: Cannot set parameter - not initialized');
            return;
        }
        
        const paramId = this.parameterMap[paramName];
        if (paramId !== undefined) {
            console.log(`ConvolutionProcessor: Setting ${paramName} (${paramId}) to ${value}`);
            this.setParameterNative(paramId, value);
        } else {
            console.warn(`ConvolutionProcessor: Unknown parameter: ${paramName}`);
        }
    }
    
    setImpulseResponseType(irType) {
        if (!this.initialized) {
            console.warn('ConvolutionProcessor: Cannot set IR type - not initialized');
            return;
        }
        
        console.log(`ConvolutionProcessor: Setting IR type to ${irType}`);
        this.setIRTypeNative(irType);
    }
    
    getVersion() {
        if (!this.initialized) return 'Not initialized';
        return this.getVersionNative();
    }
    
    getSampleRate() {
        if (!this.initialized) return 0;
        return this.getSampleRateNative();
    }
    
    cleanup() {
        if (this.initialized) {
            console.log('ConvolutionProcessor: Cleaning up...');
            this.cleanupEngine();
            this.initialized = false;
        }
    }
}

// Export for use
if (typeof module !== 'undefined' && module.exports) {
    module.exports = ConvolutionProcessor;
}
