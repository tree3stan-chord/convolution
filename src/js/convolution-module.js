// convolution-module.js - FIXED VERSION
// WebAssembly module wrapper for the convolution reverb engine

class ConvolutionProcessor {
    constructor() {
        this.module = null;
        this.initialized = false;
        this.sampleRate = 48000;
        
        // Function pointers
        this.functions = {};
        
        // Parameter map - matches C code exactly
        this.parameterMap = {
            'roomSize': 0,
            'decayTime': 1,
            'preDelay': 2,
            'damping': 3,
            'lowFreq': 4,
            'diffusion': 5,
            'mix': 6,
            'earlyReflections': 7
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
            
            // Get function wrappers - check if we're using the bridge or direct functions
            // Try the bridge functions first, fall back to underscore versions
            try {
                this.functions = {
                    init_engine: this.module.cwrap('init_engine', null, ['number']),
                    process_audio: this.module.cwrap('process_audio', null, ['number', 'number', 'number']),
                    set_parameter: this.module.cwrap('set_parameter', null, ['number', 'number']),
                    set_ir_type: this.module.cwrap('set_ir_type', null, ['string']),
                    cleanup_engine: this.module.cwrap('cleanup_engine', null, []),
                    allocate_double_array: this.module.cwrap('allocate_double_array', 'number', ['number']),
                    free_double_array: this.module.cwrap('free_double_array', null, ['number']),
                    is_initialized: this.module.cwrap('is_initialized', 'number', []),
                    get_sample_rate: this.module.cwrap('get_sample_rate', 'number', []),
                    get_version: this.module.cwrap('get_version', 'string', [])
                };
            } catch (e) {
                console.warn('Bridge functions not found, trying underscore versions...');
                this.functions = {
                    init_engine: this.module.cwrap('init_convolution_engine_', null, ['number']),
                    process_audio: this.module.cwrap('process_convolution_', null, ['number', 'number', 'number']),
                    set_parameter: this.module.cwrap('set_param_float_', null, ['number', 'number']),
                    set_ir_type: this.module.cwrap('set_ir_type_', null, ['string', 'number']),
                    cleanup_engine: this.module.cwrap('cleanup_convolution_engine_', null, []),
                    allocate_double_array: this.module.cwrap('allocate_double_array', 'number', ['number']),
                    free_double_array: this.module.cwrap('free_double_array', null, ['number']),
                    is_initialized: this.module.cwrap('is_initialized_', 'number', []),
                    get_sample_rate: this.module.cwrap('get_sample_rate_', 'number', []),
                    get_version: this.module.cwrap('get_version_', 'string', [])
                };
            }
            
            // Initialize the engine
            this.sampleRate = sampleRate;
            console.log('ConvolutionProcessor: Initializing engine with sample rate:', sampleRate);
            this.functions.init_engine(sampleRate);
            
            // Verify initialization
            const isInit = this.functions.is_initialized();
            if (!isInit) {
                throw new Error('Engine failed to initialize');
            }
            
            this.initialized = true;
            
            console.log('ConvolutionProcessor: Initialization complete!');
            console.log('ConvolutionProcessor: Version:', this.getVersion());
            console.log('ConvolutionProcessor: Sample rate:', this.getSampleRate(), 'Hz');
            console.log('ConvolutionProcessor: Ready for processing');
            
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
        const inputPtr = this.functions.allocate_double_array(numSamples);
        const outputPtr = this.functions.allocate_double_array(numSamples);
        
        if (!inputPtr || !outputPtr) {
            console.error('ConvolutionProcessor: Failed to allocate memory');
            return inputArray;
        }
        
        try {
            // Copy input data to WASM memory
            if (inputArray instanceof Float32Array) {
                // Convert Float32 to Float64
                for (let i = 0; i < numSamples; i++) {
                    this.module.HEAPF64[inputPtr / 8 + i] = inputArray[i];
                }
            } else if (inputArray instanceof Float64Array) {
                // Direct copy
                this.module.HEAPF64.set(inputArray, inputPtr / 8);
            } else {
                // Convert from regular array
                for (let i = 0; i < numSamples; i++) {
                    this.module.HEAPF64[inputPtr / 8 + i] = inputArray[i];
                }
            }
            
            // Process audio
            this.functions.process_audio(inputPtr, outputPtr, numSamples);
            
            // Copy output data from WASM memory
            const outputArray = new Float32Array(numSamples);
            for (let i = 0; i < numSamples; i++) {
                outputArray[i] = this.module.HEAPF64[outputPtr / 8 + i];
            }
            
            return outputArray;
        } catch (error) {
            console.error('ConvolutionProcessor: Processing error:', error);
            return inputArray;
        } finally {
            // Always clean up allocated memory
            this.functions.free_double_array(inputPtr);
            this.functions.free_double_array(outputPtr);
        }
    }
    
    setParameter(paramName, value) {
        if (!this.initialized) {
            console.warn('ConvolutionProcessor: Cannot set parameter - not initialized');
            return;
        }
        
        const paramId = this.parameterMap[paramName];
        if (paramId !== undefined) {
            console.log(`ConvolutionProcessor: Setting ${paramName} (id=${paramId}) to ${value}`);
            
            try {
                // Call the WASM function with float value
                this.functions.set_parameter(paramId, parseFloat(value));
                console.log(`ConvolutionProcessor: Successfully set ${paramName}`);
            } catch (error) {
                console.error(`ConvolutionProcessor: Error setting parameter:`, error);
            }
        } else {
            console.warn(`ConvolutionProcessor: Unknown parameter: ${paramName}`);
            console.log('Available parameters:', Object.keys(this.parameterMap));
        }
    }
    
    setImpulseResponseType(irType) {
        if (!this.initialized) {
            console.warn('ConvolutionProcessor: Cannot set IR type - not initialized');
            return;
        }
        
        console.log(`ConvolutionProcessor: Setting IR type to ${irType}`);
        try {
            this.functions.set_ir_type(irType);
            console.log(`ConvolutionProcessor: Successfully set IR type`);
        } catch (error) {
            console.error('ConvolutionProcessor: Error setting IR type:', error);
        }
    }
    
    getVersion() {
        if (!this.initialized) return 'Not initialized';
        try {
            return this.functions.get_version();
        } catch (error) {
            console.error('ConvolutionProcessor: Error getting version:', error);
            return 'Error';
        }
    }
    
    getSampleRate() {
        if (!this.initialized) return 0;
        try {
            return this.functions.get_sample_rate();
        } catch (error) {
            console.error('ConvolutionProcessor: Error getting sample rate:', error);
            return 0;
        }
    }
    
    cleanup() {
        if (this.initialized) {
            console.log('ConvolutionProcessor: Cleaning up...');
            try {
                this.functions.cleanup_engine();
                this.initialized = false;
                console.log('ConvolutionProcessor: Cleanup complete');
            } catch (error) {
                console.error('ConvolutionProcessor: Error during cleanup:', error);
            }
        }
    }
}

// Export for use
if (typeof module !== 'undefined' && module.exports) {
    module.exports = ConvolutionProcessor;
}