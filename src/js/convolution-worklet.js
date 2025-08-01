// convolution-worklet.js - AudioWorklet Processor for Low-Latency Reverb

class ConvolutionReverbWorklet extends AudioWorkletProcessor {
    constructor() {
        super();
        
        this.initialized = false;
        this.wasmModule = null;
        this.inputPtr = null;
        this.outputPtr = null;
        this.bufferSize = 0;
        
        // Parameters
        this.parameters = {
            roomSize: 50,
            decayTime: 2.5,
            preDelay: 20,
            damping: 50,
            lowFreq: 50,
            diffusion: 80,
            mix: 30,
            earlyReflections: 50
        };
        
        // Handle messages from main thread
        this.port.onmessage = async (event) => {
            switch (event.data.type) {
                case 'init':
                    await this.initializeModule(event.data.wasmModule);
                    break;
                case 'setParameter':
                    this.setParameter(event.data.param, event.data.value);
                    break;
                case 'setIRType':
                    this.setIRType(event.data.irType);
                    break;
            }
        };
    }
    
    async initializeModule(wasmModule) {
        try {
            this.wasmModule = wasmModule;
            
            // Initialize the convolution engine
            this.wasmModule._init_engine(sampleRate);
            
            // Set initial parameters
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
            
            Object.keys(this.parameters).forEach((param) => {
                const paramId = paramMap[param];
                if (paramId !== undefined) {
                    this.wasmModule._set_parameter(paramId, this.parameters[param]);
                }
            });
            
            this.initialized = true;
            this.port.postMessage({ type: 'initialized' });
            
        } catch (error) {
            console.error('Worklet initialization error:', error);
            this.port.postMessage({ type: 'error', error: error.message });
        }
    }
    
    allocateBuffers(size) {
        if (size > this.bufferSize) {
            // Free existing buffers
            if (this.inputPtr) {
                this.wasmModule._free_double_array(this.inputPtr);
                this.wasmModule._free_double_array(this.outputPtr);
            }
            
            // Allocate new buffers
            this.inputPtr = this.wasmModule._allocate_double_array(size);
            this.outputPtr = this.wasmModule._allocate_double_array(size);
            this.bufferSize = size;
        }
    }
    
    setParameter(param, value) {
        if (!this.initialized) return;
        
        this.parameters[param] = value;
        
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
        
        const paramId = paramMap[param];
        if (paramId !== undefined) {
            this.wasmModule._set_parameter(paramId, value);
        }
    }
    
    setIRType(irType) {
        if (!this.initialized) return;
        
        const bufferSize = (irType.length + 1) * 4; // Rough estimate
        const irTypePtr = this.wasmModule._malloc(bufferSize);
        
        try {
            this.wasmModule.stringToUTF8(irType, irTypePtr, bufferSize);
            this.wasmModule._set_ir_type(irTypePtr);
        } finally {
            this.wasmModule._free(irTypePtr);
        }
    }
    
    process(inputs, outputs, parameters) {
        const input = inputs[0];
        const output = outputs[0];
        
        // Skip if not initialized or no input
        if (!this.initialized || !input || !input.length || !input[0]) {
            // Pass through silence
            if (output && output[0]) {
                for (let channel = 0; channel < output.length; channel++) {
                    output[channel].fill(0);
                }
            }
            return true;
        }
        
        const inputChannel = input[0];
        const numSamples = inputChannel.length;
        
        // Allocate buffers if needed
        this.allocateBuffers(numSamples);
        
        // Convert Float32 to Float64 for WASM processing
        const heap64 = this.wasmModule.HEAPF64;
        const inputOffset = this.inputPtr / 8;
        
        // Copy input to WASM memory
        for (let i = 0; i < numSamples; i++) {
            heap64[inputOffset + i] = inputChannel[i];
        }
        
        // Process audio
        this.wasmModule._process_audio(this.inputPtr, this.outputPtr, numSamples);
        
        // Copy output from WASM memory
        const outputOffset = this.outputPtr / 8;
        const outputChannel = output[0];
        
        for (let i = 0; i < numSamples; i++) {
            outputChannel[i] = heap64[outputOffset + i];
        }
        
        // Handle stereo output by copying to all channels
        for (let channel = 1; channel < output.length; channel++) {
            output[channel].set(outputChannel);
        }
        
        return true;
    }
}

registerProcessor('convolution-reverb-worklet', ConvolutionReverbWorklet);