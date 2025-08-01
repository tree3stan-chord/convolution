// audio-processor.js - Web Audio API Integration for Convolution Reverb

class ConvolutionReverbProcessor extends AudioWorkletProcessor {
    constructor() {
        super();
        this.initialized = false;
        this.wasmModule = null;
        this.inputPtr = null;
        this.outputPtr = null;
        this.bufferSize = 0;
        
        // Handle messages from main thread
        this.port.onmessage = (event) => {
            switch (event.data.type) {
                case 'init':
                    this.initializeModule(event.data.wasmModule, event.data.sampleRate);
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
    
    async initializeModule(wasmModule, sampleRate) {
        try {
            this.wasmModule = wasmModule;
            this.wasmModule._init_engine(sampleRate);
            this.initialized = true;
            this.port.postMessage({ type: 'initialized' });
        } catch (error) {
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
        if (!this.initialized || !this.wasmModule) return;
        
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
        if (!this.initialized || !this.wasmModule) return;
        
        const irTypePtr = this.wasmModule.allocateUTF8(irType);
        this.wasmModule._set_ir_type(irTypePtr);
        this.wasmModule._free(irTypePtr);
    }
    
    process(inputs, outputs, parameters) {
        const input = inputs[0];
        const output = outputs[0];
        
        if (!this.initialized || !input.length) {
            return true;
        }
        
        // Process each channel
        for (let channel = 0; channel < input.length; channel++) {
            const inputChannel = input[channel];
            const outputChannel = output[channel];
            const numSamples = inputChannel.length;
            
            // Allocate buffers if needed
            this.allocateBuffers(numSamples);
            
            // Convert Float32Array to Float64Array and copy to WASM memory
            const inputFloat64 = new Float64Array(inputChannel);
            this.wasmModule.HEAPF64.set(inputFloat64, this.inputPtr / 8);
            
            // Process audio
            this.wasmModule._process_audio(this.inputPtr, this.outputPtr, numSamples);
            
            // Copy output from WASM memory
            const outputFloat64 = new Float64Array(
                this.wasmModule.HEAPF64.buffer,
                this.outputPtr,
                numSamples
            );
            
            // Convert back to Float32Array
            outputChannel.set(new Float32Array(outputFloat64));
        }
        
        return true;
    }
}

registerProcessor('convolution-reverb-processor', ConvolutionReverbProcessor);

// Main thread audio context manager
class ConvolutionReverbNode {
    constructor(audioContext, wasmModulePath) {
        this.context = audioContext;
        this.wasmModulePath = wasmModulePath;
        this.node = null;
        this.initialized = false;
    }
    
    async initialize() {
        // Load the WebAssembly module
        const wasmModule = await ConvolutionModule({
            locateFile: (file) => this.wasmModulePath + file
        });
        
        // Create AudioWorkletNode
        await this.context.audioWorklet.addModule('audio-processor.js');
        this.node = new AudioWorkletNode(this.context, 'convolution-reverb-processor');
        
        // Send the WASM module to the worklet
        this.node.port.postMessage({
            type: 'init',
            wasmModule: wasmModule,
            sampleRate: this.context.sampleRate
        });
        
        // Wait for initialization
        return new Promise((resolve, reject) => {
            this.node.port.onmessage = (event) => {
                if (event.data.type === 'initialized') {
                    this.initialized = true;
                    resolve();
                } else if (event.data.type === 'error') {
                    reject(new Error(event.data.error));
                }
            };
        });
    }
    
    setParameter(param, value) {
        if (!this.initialized) return;
        
        this.node.port.postMessage({
            type: 'setParameter',
            param: param,
            value: value
        });
    }
    
    setIRType(irType) {
        if (!this.initialized) return;
        
        this.node.port.postMessage({
            type: 'setIRType',
            irType: irType
        });
    }
    
    connect(destination) {
        if (this.node) {
            this.node.connect(destination);
        }
    }
    
    disconnect() {
        if (this.node) {
            this.node.disconnect();
        }
    }
    
    get input() {
        return this.node;
    }
    
    get output() {
        return this.node;
    }
}

// Export for use
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { ConvolutionReverbNode, ConvolutionReverbProcessor };
}