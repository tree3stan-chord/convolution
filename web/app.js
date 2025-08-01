// app.js - Main application logic for Convolution Reverb with AudioWorklet

// Global variables
let audioContext = null;
let processor = null;
let currentBuffer = null;
let isPlaying = false;
let currentSource = null;
let micStream = null;
let micSource = null;
let workletNode = null;
let isProcessingLive = false;
let useWorklet = true; // Flag to use AudioWorklet vs ScriptProcessor

// Initialize the application
async function initializeApp() {
    try {
        // Initialize audio context
        audioContext = new (window.AudioContext || window.webkitAudioContext)();
        
        // Enable live input button immediately
        document.getElementById('liveInputButton').disabled = false;
        
        // Initialize the convolution processor
        processor = new ConvolutionProcessor();
        await processor.initialize('./', audioContext.sampleRate);
        
        // Try to load AudioWorklet
        try {
            await audioContext.audioWorklet.addModule('convolution-worklet.js');
            console.log('AudioWorklet loaded successfully');
            useWorklet = true;
        } catch (error) {
            console.warn('AudioWorklet not supported or failed to load, falling back to ScriptProcessor', error);
            useWorklet = false;
        }
        
        // Update UI
        updateStatus('ready', 'WebAssembly module loaded successfully! Click "Start Live Input" to begin.');
        
        // Set up parameter controls
        setupParameterControls();
        
        // Set up file input
        setupFileInput();
        
        // Set up visualizer
        setupVisualizer();
        
        // Don't automatically start - wait for user interaction
        
    } catch (error) {
        console.error('Initialization error:', error);
        updateStatus('error', 'Error loading WebAssembly module: ' + error.message);
    }
}

// Start live microphone input with AudioWorklet
async function startLiveInputWithWorklet() {
    try {
        // Create AudioWorklet node
        workletNode = new AudioWorkletNode(audioContext, 'convolution-reverb-worklet');
        
        // Send the same WASM module instance to the worklet
        workletNode.port.postMessage({
            type: 'init',
            wasmModule: processor.module
        });
        
        // Wait for initialization
        await new Promise((resolve, reject) => {
            const timeout = setTimeout(() => {
                reject(new Error('Worklet initialization timeout'));
            }, 5000);
            
            workletNode.port.onmessage = (event) => {
                if (event.data.type === 'initialized') {
                    clearTimeout(timeout);
                    resolve();
                } else if (event.data.type === 'error') {
                    clearTimeout(timeout);
                    reject(new Error(event.data.error));
                }
            };
        });
        
        // Sync current parameters to worklet
        Object.keys(processor.parameters || {}).forEach(param => {
            const element = document.getElementById(param);
            if (element) {
                workletNode.port.postMessage({
                    type: 'setParameter',
                    param: param,
                    value: parseFloat(element.value)
                });
            }
        });
        
        // Connect microphone to worklet
        micSource.connect(workletNode);
        workletNode.connect(audioContext.destination);
        
        // Set up visualization using an AnalyserNode
        const analyser = audioContext.createAnalyser();
        analyser.fftSize = 2048;
        workletNode.connect(analyser);
        
        // Visualization loop
        const bufferLength = analyser.frequencyBinCount;
        const dataArray = new Float32Array(bufferLength);
        
        function updateVisualization() {
            if (!isProcessingLive) return;
            
            analyser.getFloatTimeDomainData(dataArray);
            drawLiveWaveform(dataArray);
            requestAnimationFrame(updateVisualization);
        }
        
        updateVisualization();
        
        console.log('AudioWorklet processing started');
        
    } catch (error) {
        console.error('Error setting up AudioWorklet:', error);
        throw error;
    }
}

// Start live microphone input with ScriptProcessor (fallback)
async function startLiveInputWithScriptProcessor() {
    const bufferSize = 2048;
    const scriptProcessor = audioContext.createScriptProcessor(bufferSize, 1, 1);
    
    scriptProcessor.onaudioprocess = (audioProcessingEvent) => {
        if (!isProcessingLive) return;
        
        const inputBuffer = audioProcessingEvent.inputBuffer;
        const outputBuffer = audioProcessingEvent.outputBuffer;
        const inputData = inputBuffer.getChannelData(0);
        const outputData = outputBuffer.getChannelData(0);
        
        try {
            // Process through WebAssembly
            const processedData = processor.processAudio(inputData);
            
            // Copy processed data to output
            for (let i = 0; i < outputData.length && i < processedData.length; i++) {
                outputData[i] = processedData[i];
            }
            
            // Update visualizer with live data
            drawLiveWaveform(outputData);
            
        } catch (error) {
            console.error('Processing error:', error);
            // Pass through on error
            outputData.set(inputData);
        }
    };
    
    // Store script processor globally for cleanup
    window.scriptProcessor = scriptProcessor;
    
    // Connect the audio graph
    micSource.connect(scriptProcessor);
    scriptProcessor.connect(audioContext.destination);
    
    console.log('ScriptProcessor processing started');
}

// Start live microphone input
async function startLiveInput() {
    // Check if still initializing
    if (!processor || !processor.isInitialized()) {
        updateStatus('error', 'Please wait for the module to finish loading...');
        return;
    }
    
    try {
        updateStatus('loading', 'Requesting microphone access...');
        
        // Stop any playing audio
        stopAudio();
        stopLiveInput();
        
        // Request microphone access
        micStream = await navigator.mediaDevices.getUserMedia({ 
            audio: {
                echoCancellation: false,
                noiseSuppression: false,
                autoGainControl: false,
                sampleRate: audioContext.sampleRate
            } 
        });
        
        updateStatus('ready', `Microphone connected - processing with ${useWorklet ? 'AudioWorklet (low latency)' : 'ScriptProcessor'}`);
        
        // Create microphone source
        micSource = audioContext.createMediaStreamSource(micStream);
        
        isProcessingLive = true;
        
        // Use AudioWorklet if available, otherwise fall back to ScriptProcessor
        if (useWorklet) {
            await startLiveInputWithWorklet();
        } else {
            await startLiveInputWithScriptProcessor();
        }
        
        // Update UI
        document.getElementById('liveInputButton').textContent = 'Stop Live Input';
        document.getElementById('liveInputButton').classList.add('active');
        document.getElementById('processButton').disabled = true;
        
    } catch (error) {
        console.error('Error accessing microphone:', error);
        if (error.name === 'NotAllowedError') {
            updateStatus('error', 'Microphone access denied. Please allow microphone access and reload.');
        } else if (error.name === 'NotFoundError') {
            updateStatus('error', 'No microphone found. Please connect a microphone.');
        } else {
            updateStatus('error', 'Error accessing microphone: ' + error.message);
        }
    }
}

// Stop live input
function stopLiveInput() {
    isProcessingLive = false;
    
    // Clean up AudioWorklet
    if (workletNode) {
        workletNode.disconnect();
        workletNode = null;
    }
    
    // Clean up ScriptProcessor
    if (window.scriptProcessor) {
        window.scriptProcessor.disconnect();
        window.scriptProcessor = null;
    }
    
    if (micSource) {
        micSource.disconnect();
        micSource = null;
    }
    
    if (micStream) {
        micStream.getTracks().forEach(track => track.stop());
        micStream = null;
    }
    
    document.getElementById('liveInputButton').textContent = 'Start Live Input';
    document.getElementById('liveInputButton').classList.remove('active');
    document.getElementById('processButton').disabled = false;
    
    updateStatus('ready', 'Live input stopped');
}

// Toggle live input
function toggleLiveInput() {
    if (isProcessingLive) {
        stopLiveInput();
    } else {
        startLiveInput();
    }
}

// Update status display
function updateStatus(status, message) {
    const statusElement = document.getElementById('status');
    statusElement.className = 'status ' + status;
    
    // Add live indicator for processing
    if (status === 'ready' && message.includes('Microphone connected')) {
        statusElement.innerHTML = message + '<span class="live-indicator"></span>';
    } else {
        statusElement.textContent = message;
    }
}

// Set up parameter controls
function setupParameterControls() {
    const parameters = {
        roomSize: { min: 0, max: 100, default: 50 },
        decayTime: { min: 0.1, max: 10, default: 2.5, step: 0.1 },
        preDelay: { min: 0, max: 100, default: 20 },
        damping: { min: 0, max: 100, default: 50 },
        lowFreq: { min: 0, max: 100, default: 50 },
        diffusion: { min: 0, max: 100, default: 80 },
        mix: { min: 0, max: 100, default: 30 },
        earlyReflections: { min: 0, max: 100, default: 50 }
    };
    
    Object.keys(parameters).forEach(param => {
        const element = document.getElementById(param);
        const valueElement = document.getElementById(param + 'Value');
        
        if (element && valueElement) {
            // Set initial value
            element.value = parameters[param].default;
            valueElement.textContent = parameters[param].default;
            
            // Add event listener
            element.addEventListener('input', (e) => {
                const value = parseFloat(e.target.value);
                valueElement.textContent = value;
                
                // Update main processor
                if (processor) {
                    processor.setParameter(param, value);
                }
                
                // Update worklet if active
                if (workletNode && isProcessingLive) {
                    workletNode.port.postMessage({
                        type: 'setParameter',
                        param: param,
                        value: value
                    });
                }
            });
        }
    });
    
    // Impulse response type selector
    const irSelector = document.getElementById('impulseResponse');
    if (irSelector) {
        irSelector.addEventListener('change', (e) => {
            if (processor) {
                processor.setImpulseResponseType(e.target.value);
            }
            
            // Update worklet if active
            if (workletNode && isProcessingLive) {
                workletNode.port.postMessage({
                    type: 'setIRType',
                    irType: e.target.value
                });
            }
        });
    }
}

// Set up file input
function setupFileInput() {
    const loadButton = document.getElementById('loadAudioButton');
    const fileInput = document.getElementById('audioFileInput');
    
    loadButton.addEventListener('click', () => {
        // Stop live input when loading a file
        if (isProcessingLive) {
            stopLiveInput();
        }
        fileInput.click();
    });
    
    fileInput.addEventListener('change', async (e) => {
        const file = e.target.files[0];
        if (file) {
            await loadAudioFile(file);
        }
    });
}

// Load audio file
async function loadAudioFile(file) {
    try {
        updateStatus('loading', 'Loading audio file...');
        
        const arrayBuffer = await file.arrayBuffer();
        currentBuffer = await audioContext.decodeAudioData(arrayBuffer);
        
        updateStatus('ready', `Loaded: ${file.name}`);
        document.getElementById('processButton').disabled = false;
        
        // Draw waveform
        drawWaveform(currentBuffer);
        
    } catch (error) {
        console.error('Error loading audio file:', error);
        updateStatus('error', 'Error loading audio file. Please try a different file.');
    }
}

// Process audio
async function processAudio() {
    if (!currentBuffer || !processor) return;
    
    // Stop any currently playing audio
    stopAudio();
    
    try {
        updateStatus('loading', 'Processing audio...');
        
        // Get the audio data
        const inputData = currentBuffer.getChannelData(0);
        
        // Process through WebAssembly
        const startTime = performance.now();
        const outputData = processor.processAudio(inputData);
        const processingTime = performance.now() - startTime;
        
        // Create output buffer
        const outputBuffer = audioContext.createBuffer(
            1,
            outputData.length,
            currentBuffer.sampleRate
        );
        outputBuffer.getChannelData(0).set(outputData);
        
        // Play the processed audio
        playBuffer(outputBuffer);
        
        updateStatus('ready', `Processed in ${processingTime.toFixed(1)}ms`);
        
    } catch (error) {
        console.error('Error processing audio:', error);
        updateStatus('error', 'Error processing audio: ' + error.message);
    }
}

// Play audio buffer
function playBuffer(buffer) {
    stopAudio();
    
    currentSource = audioContext.createBufferSource();
    currentSource.buffer = buffer;
    currentSource.connect(audioContext.destination);
    
    currentSource.onended = () => {
        isPlaying = false;
        updatePlayButton();
    };
    
    currentSource.start(0);
    isPlaying = true;
    updatePlayButton();
}

// Stop audio playback
function stopAudio() {
    if (currentSource) {
        currentSource.stop();
        currentSource.disconnect();
        currentSource = null;
    }
    isPlaying = false;
    updatePlayButton();
}

// Update play button state
function updatePlayButton() {
    const processButton = document.getElementById('processButton');
    if (processButton) {
        processButton.textContent = isPlaying ? 'Stop' : 'Process Audio';
    }
}

// Reset parameters
function resetParameters() {
    const defaults = {
        roomSize: 50,
        decayTime: 2.5,
        preDelay: 20,
        damping: 50,
        lowFreq: 50,
        diffusion: 80,
        mix: 30,
        earlyReflections: 50
    };
    
    Object.keys(defaults).forEach(param => {
        const element = document.getElementById(param);
        const valueElement = document.getElementById(param + 'Value');
        
        if (element && valueElement) {
            element.value = defaults[param];
            valueElement.textContent = defaults[param];
            
            if (processor) {
                processor.setParameter(param, defaults[param]);
            }
            
            // Update worklet if active
            if (workletNode && isProcessingLive) {
                workletNode.port.postMessage({
                    type: 'setParameter',
                    param: param,
                    value: defaults[param]
                });
            }
        }
    });
    
    // Reset IR type
    const irSelector = document.getElementById('impulseResponse');
    if (irSelector) {
        irSelector.value = 'hall';
        if (processor) {
            processor.setImpulseResponseType('hall');
        }
        
        if (workletNode && isProcessingLive) {
            workletNode.port.postMessage({
                type: 'setIRType',
                irType: 'hall'
            });
        }
    }
}

// Set up visualizer
let animationId = null;
function setupVisualizer() {
    const canvas = document.getElementById('waveformCanvas');
    const ctx = canvas.getContext('2d');
    
    // Set canvas size
    function resizeCanvas() {
        canvas.width = canvas.offsetWidth;
        canvas.height = canvas.offsetHeight;
        
        // Draw empty waveform
        drawEmptyWaveform();
    }
    
    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();
}

// Draw empty waveform
function drawEmptyWaveform() {
    const canvas = document.getElementById('waveformCanvas');
    const ctx = canvas.getContext('2d');
    
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.strokeStyle = '#90e0ef';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(0, canvas.height / 2);
    ctx.lineTo(canvas.width, canvas.height / 2);
    ctx.stroke();
}

// Draw live waveform
function drawLiveWaveform(data) {
    const canvas = document.getElementById('waveformCanvas');
    const ctx = canvas.getContext('2d');
    
    // Clear with fade effect
    ctx.fillStyle = 'rgba(0, 0, 0, 0.1)';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    
    // Draw waveform
    ctx.strokeStyle = '#90e0ef';
    ctx.lineWidth = 2;
    ctx.beginPath();
    
    const sliceWidth = canvas.width / data.length;
    let x = 0;
    
    for (let i = 0; i < data.length; i++) {
        const v = data[i];
        const y = (1 + v) * canvas.height / 2;
        
        if (i === 0) {
            ctx.moveTo(x, y);
        } else {
            ctx.lineTo(x, y);
        }
        
        x += sliceWidth;
    }
    
    ctx.stroke();
    
    // Draw center line
    ctx.strokeStyle = 'rgba(144, 224, 239, 0.2)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(0, canvas.height / 2);
    ctx.lineTo(canvas.width, canvas.height / 2);
    ctx.stroke();
}

// Draw waveform
function drawWaveform(audioBuffer) {
    const canvas = document.getElementById('waveformCanvas');
    const ctx = canvas.getContext('2d');
    const data = audioBuffer.getChannelData(0);
    
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    
    // Set up drawing style
    ctx.strokeStyle = '#90e0ef';
    ctx.lineWidth = 2;
    
    // Calculate downsampling rate
    const downsample = Math.max(1, Math.floor(data.length / canvas.width));
    
    // Draw waveform
    ctx.beginPath();
    
    for (let x = 0; x < canvas.width; x++) {
        const sampleIndex = x * downsample;
        
        // Find min and max in this pixel's samples
        let min = 1.0;
        let max = -1.0;
        
        for (let j = 0; j < downsample; j++) {
            const sample = data[sampleIndex + j] || 0;
            min = Math.min(min, sample);
            max = Math.max(max, sample);
        }
        
        // Scale to canvas height
        const yMin = (1 - min) * canvas.height / 2;
        const yMax = (1 - max) * canvas.height / 2;
        
        if (x === 0) {
            ctx.moveTo(x, (yMin + yMax) / 2);
        } else {
            ctx.lineTo(x, yMin);
            ctx.lineTo(x, yMax);
        }
    }
    
    ctx.stroke();
}

// Event listeners
document.addEventListener('DOMContentLoaded', () => {
    // Live input button
    const liveInputButton = document.getElementById('liveInputButton');
    if (liveInputButton) {
        liveInputButton.addEventListener('click', toggleLiveInput);
    }
    
    // Process button
    const processButton = document.getElementById('processButton');
    if (processButton) {
        processButton.addEventListener('click', () => {
            if (isPlaying) {
                stopAudio();
            } else {
                processAudio();
            }
        });
    }
    
    // Reset button
    const resetButton = document.getElementById('resetButton');
    if (resetButton) {
        resetButton.addEventListener('click', resetParameters);
    }
    
    // Initialize the app
    initializeApp();
});

// Handle audio context resume on user interaction
document.addEventListener('click', () => {
    if (audioContext && audioContext.state === 'suspended') {
        audioContext.resume();
    }
}, { once: true });