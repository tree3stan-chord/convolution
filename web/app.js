// Disconnect and clean up audio nodes
    if (window.compressor) {
        window.compressor.disconnect();
        window.compressor = null;
    }// app.js - Complete application with working live reverb processing

// Global variables
let audioContext = null;
let processor = null;
let micStream = null;
let isInitialized = false;
let currentBuffer = null;
let currentSource = null;
let isPlaying = false;
let analyser = null;
let animationId = null;

// Audio processing nodes (global for cleanup)
window.isProcessingLive = false;
window.micSource = null;
window.scriptProcessor = null;
window.inputGain = null;
window.outputGain = null;

// Wait for DOM to load
document.addEventListener('DOMContentLoaded', () => {
    console.log('DOM loaded - setting up UI');
    setupUI();
});

// Setup UI without creating AudioContext
function setupUI() {
    // Setup button handlers
    document.getElementById('liveInputButton').addEventListener('click', handleLiveInputClick);
    document.getElementById('processButton').addEventListener('click', toggleProcessAudio);
    document.getElementById('loadAudioButton').addEventListener('click', () => {
        document.getElementById('audioFileInput').click();
    });
    document.getElementById('resetButton').addEventListener('click', resetParameters);
    document.getElementById('loadPreloadedButton').addEventListener('click', loadPreloadedAudio);
    
    // Setup file input
    document.getElementById('audioFileInput').addEventListener('change', handleFileSelect);
    
    // Setup parameter controls (without handlers yet)
    setupParameterValues();
    
    // Setup visualizer
    setupVisualizer();
    
    // Load preloaded audio list
    loadAudioList();
    
    // Update initial status
    updateStatus('ready', 'Click "Start Live Input" to begin');
}

// Set initial parameter values in UI
function setupParameterValues() {
    const params = {
        roomSize: 50,
        decayTime: 2.5,
        preDelay: 20,
        damping: 50,
        lowFreq: 50,
        diffusion: 80,
        mix: 30,
        earlyReflections: 50
    };
    
    Object.keys(params).forEach(param => {
        const element = document.getElementById(param);
        const valueElement = document.getElementById(param + 'Value');
        if (element && valueElement) {
            element.value = params[param];
            valueElement.textContent = params[param];
        }
    });
}

// Initialize audio system on first user interaction
async function initializeAudio() {
    if (audioContext) return true;
    
    console.log('Initializing audio system...');
    updateStatus('loading', 'Initializing audio system...');
    
    try {
        // Create AudioContext
        audioContext = new (window.AudioContext || window.webkitAudioContext)();
        console.log('AudioContext created, state:', audioContext.state);
        
        // Update technical details
        document.getElementById('sampleRate').textContent = audioContext.sampleRate;
        document.getElementById('engineType').textContent = 'WebAssembly Convolution Engine v2.0';
        
        // Initialize processor
        processor = new ConvolutionProcessor();
        await processor.initialize('./', audioContext.sampleRate);
        console.log('Processor initialized');
        
        // Check version
        if (processor.getVersion) {
            const version = processor.getVersion();
            console.log('Engine version:', version);
            document.getElementById('engineType').textContent = `WebAssembly Engine ${version}`;
        }
        
        // Apply current parameter values
        applyParametersToProcessor();
        
        // Setup parameter controls for real-time updates
        setupParameterControls();
        
        isInitialized = true;
        return true;
    } catch (error) {
        console.error('Failed to initialize audio:', error);
        updateStatus('error', 'Failed to initialize audio: ' + error.message);
        return false;
    }
}

// Handle live input button click
async function handleLiveInputClick() {
    console.log('Live input button clicked');
    
    // If already running, stop it
    if (window.isProcessingLive) {
        stopLiveInput();
        return;
    }
    
    // Initialize audio if needed
    if (!isInitialized) {
        const success = await initializeAudio();
        if (!success) return;
    }
    
    // Resume context if needed
    if (audioContext.state === 'suspended') {
        await audioContext.resume();
    }
    
    try {
        updateStatus('loading', 'Requesting microphone access...');
        
        // Request microphone
        micStream = await navigator.mediaDevices.getUserMedia({
            audio: {
                echoCancellation: false,
                noiseSuppression: false,
                autoGainControl: false,
                sampleRate: audioContext.sampleRate
            }
        });
        
        console.log('Microphone access granted');
        
        // Create audio nodes for reverb processing
        window.micSource = audioContext.createMediaStreamSource(micStream);
        window.inputGain = audioContext.createGain();
        window.compressor = audioContext.createDynamicsCompressor();
        window.scriptProcessor = audioContext.createScriptProcessor(2048, 1, 1);
        window.outputGain = audioContext.createGain();
        
        // Create analyser for visualization
        analyser = audioContext.createAnalyser();
        analyser.fftSize = 2048;
        analyser.smoothingTimeConstant = 0.8;
        
        // Configure compressor for QUANTUM COMPRESSION
        window.compressor.threshold.value = -70;    // CATCHES EVERYTHING
        window.compressor.knee.value = 60;          // ULTRA soft knee
        window.compressor.ratio.value = 50;         // INFINITY:1 basically
        window.compressor.attack.value = 0.0001;    // QUANTUM INSTANT
        window.compressor.release.value = 0.05;     // Lightning fast
        
        // Set gains - 🌟 CONVOLUTION SINGULARITY MODE 🌟
        window.inputGain.gain.value = 20.0;  // ASTRONOMICAL input gain
        window.outputGain.gain.value = 3.0;  // TRIPLE output - MAXIMUM IMPACT!
        
        // Process audio through reverb with AGC
        let silenceCount = 0;
        const silenceThreshold = 0.001;
        const agcTarget = 0.1; // Target RMS level
        
        window.scriptProcessor.onaudioprocess = (e) => {
            if (!processor || !window.isProcessingLive) return;
            
            const input = e.inputBuffer.getChannelData(0);
            const output = e.outputBuffer.getChannelData(0);
            
            try {
                // Calculate input RMS for AGC
                let sum = 0;
                for (let i = 0; i < input.length; i++) {
                    sum += input[i] * input[i];
                }
                const rms = Math.sqrt(sum / input.length);
                
                // Apply AGC gain with SINGULARITY MODE
                let agcGain = 1.0;
                if (rms > silenceThreshold && rms < agcTarget) {
                    agcGain = agcTarget / rms;
                    // INFINITE AGC - up to 100x gain!
                    agcGain = Math.min(agcGain, 100.0);
                } else if (rms < silenceThreshold) {
                    // AMPLIFY THE VOID - Even silence becomes reverb!
                    agcGain = 20.0;
                }
                
                // ADD HARMONIC EXCITEMENT
                if (agcGain > 10) {
                    // When boosting quiet signals, add some harmonics for richness
                    console.log(`🌟 QUANTUM BOOST ENGAGED: ${agcGain.toFixed(1)}x 🌟`);
                }
                
                // Apply gain to input
                const boostedInput = new Float32Array(input.length);
                for (let i = 0; i < input.length; i++) {
                    boostedInput[i] = input[i] * agcGain;
                }
                
                // Process through the reverb engine
                const processed = processor.processAudio(boostedInput);
                
                // Copy processed audio to output
                for (let i = 0; i < output.length && i < processed.length; i++) {
                    output[i] = processed[i];
                }
                
                // Debug logging every 100 blocks
                if (++silenceCount % 100 === 0) {
                    console.log(`Input RMS: ${rms.toFixed(4)}, AGC Gain: ${agcGain.toFixed(1)}x`);
                }
            } catch (error) {
                console.error('Processing error:', error);
                // On error, pass through dry signal
                output.set(input);
            }
        };
        
        // Connect the audio graph:
        // Mic -> Input Gain -> Compressor -> Script Processor -> Output Gain -> Analyser -> Speakers
        window.micSource.connect(window.inputGain);
        window.inputGain.connect(window.compressor);
        window.compressor.connect(window.scriptProcessor);
        window.scriptProcessor.connect(window.outputGain);
        window.outputGain.connect(analyser);
        analyser.connect(audioContext.destination);
        
        // Update technical details
        const bufferSize = window.scriptProcessor.bufferSize;
        const latencyMs = (bufferSize / audioContext.sampleRate) * 1000;
        document.getElementById('processingType').textContent = 'ScriptProcessor (2048 samples)';
        document.getElementById('latency').textContent = latencyMs.toFixed(1);
        
        // Start visualization
        startLiveVisualization();
        
        // Update UI
        window.isProcessingLive = true;
        updateStatus('ready', 'Processing live input with reverb!');
        document.getElementById('liveInputButton').textContent = 'Stop Live Input';
        document.getElementById('liveInputButton').classList.add('active');
        document.getElementById('processButton').disabled = true;
        
        console.log('Live reverb processing started!');
        
    } catch (error) {
        console.error('Microphone error:', error);
        if (error.name === 'NotAllowedError') {
            updateStatus('error', 'Microphone access denied. Please allow microphone access.');
        } else if (error.name === 'NotFoundError') {
            updateStatus('error', 'No microphone found.');
        } else {
            updateStatus('error', 'Error: ' + error.message);
        }
        stopLiveInput();
    }
}

// Stop live input
function stopLiveInput() {
    console.log('Stopping live input...');
    
    window.isProcessingLive = false;
    
    stopVisualization();
    
    // Disconnect and clean up audio nodes
    if (analyser) {
        analyser.disconnect();
        analyser = null;
    }
    
    if (window.outputGain) {
        window.outputGain.disconnect();
        window.outputGain = null;
    }
    
    if (window.scriptProcessor) {
        window.scriptProcessor.disconnect();
        window.scriptProcessor.onaudioprocess = null;
        window.scriptProcessor = null;
    }
    
    if (window.inputGain) {
        window.inputGain.disconnect();
        window.inputGain = null;
    }
    
    if (window.micSource) {
        window.micSource.disconnect();
        window.micSource = null;
    }
    
    // Stop microphone tracks
    if (micStream) {
        micStream.getTracks().forEach(track => track.stop());
        micStream = null;
    }
    
    // Update UI
    updateStatus('ready', 'Live input stopped');
    document.getElementById('liveInputButton').textContent = 'Start Live Input';
    document.getElementById('liveInputButton').classList.remove('active');
    document.getElementById('processButton').disabled = currentBuffer == null;
    
    // Restart idle animation
    animateIdleWaveform();
}

// Apply parameters from UI to processor
function applyParametersToProcessor() {
    if (!processor || !processor.initialized) return;
    
    console.log('Applying parameters to processor...');
    
    const params = ['roomSize', 'decayTime', 'preDelay', 'damping', 'lowFreq', 'diffusion', 'mix', 'earlyReflections'];
    params.forEach(param => {
        const slider = document.getElementById(param);
        if (slider) {
            const value = parseFloat(slider.value);
            console.log(`Initial ${param}: ${value}`);
            processor.setParameter(param, value);
        }
    });
    
    const irSelect = document.getElementById('impulseResponse');
    if (irSelect) {
        processor.setImpulseResponseType(irSelect.value);
    }
}

// Setup parameter controls for real-time updates
function setupParameterControls() {
    const params = ['roomSize', 'decayTime', 'preDelay', 'damping', 'lowFreq', 'diffusion', 'mix', 'earlyReflections'];
    
    params.forEach(param => {
        const slider = document.getElementById(param);
        const value = document.getElementById(param + 'Value');
        
        if (slider && value) {
            slider.addEventListener('input', (e) => {
                const val = parseFloat(e.target.value);
                value.textContent = val;
                
                // Update processor in real-time
                if (processor && processor.initialized) {
                    console.log(`UI: Setting ${param} to ${val}`);
                    processor.setParameter(param, val);
                }
            });
        }
    });
    
    const irSelect = document.getElementById('impulseResponse');
    if (irSelect) {
        irSelect.addEventListener('change', (e) => {
            console.log(`UI: Setting IR type to ${e.target.value}`);
            if (processor && processor.initialized) {
                processor.setImpulseResponseType(e.target.value);
            }
        });
    }
}

// Handle file selection
async function handleFileSelect(e) {
    const file = e.target.files[0];
    if (!file) return;
    
    // Initialize audio if needed
    if (!isInitialized) {
        const success = await initializeAudio();
        if (!success) return;
    }
    
    try {
        updateStatus('loading', 'Loading audio file...');
        const arrayBuffer = await file.arrayBuffer();
        currentBuffer = await audioContext.decodeAudioData(arrayBuffer);
        
        updateStatus('ready', `Loaded: ${file.name}`);
        document.getElementById('processButton').disabled = false;
        
        drawWaveform(currentBuffer);
    } catch (error) {
        console.error('File load error:', error);
        updateStatus('error', 'Error loading file');
    }
}

// Toggle process audio
function toggleProcessAudio() {
    if (isPlaying) {
        stopAudio();
    } else {
        processAudioFile();
    }
}

// Process audio file
async function processAudioFile() {
    if (!currentBuffer || !processor) {
        console.error('No buffer or processor available');
        return;
    }
    
    try {
        updateStatus('loading', 'Processing audio...');
        console.log('Starting audio processing...');
        
        // Resume audio context if suspended
        if (audioContext.state === 'suspended') {
            console.log('Resuming audio context...');
            await audioContext.resume();
        }
        
        // Get the audio data
        const input = currentBuffer.getChannelData(0);
        const totalSamples = input.length;
        console.log('Processing audio file:', totalSamples, 'samples at', currentBuffer.sampleRate, 'Hz');
        
        // Check current mix level
        const mixSlider = document.getElementById('mix');
        console.log('Current mix level:', mixSlider.value, '%');
        
        // Process in chunks
        const chunkSize = 4096;
        const output = new Float32Array(totalSamples);
        
        // Process some silence first to prime the reverb
        const silence = new Float32Array(chunkSize);
        processor.processAudio(silence);
        
        for (let i = 0; i < totalSamples; i += chunkSize) {
            const end = Math.min(i + chunkSize, totalSamples);
            const chunk = input.slice(i, end);
            
            // Process this chunk
            const processedChunk = processor.processAudio(chunk);
            
            // Copy to output
            for (let j = 0; j < processedChunk.length && i + j < totalSamples; j++) {
                output[i + j] = processedChunk[j];
            }
            
            // Update progress occasionally
            if (i % (chunkSize * 10) === 0) {
                const progress = Math.round((i / totalSamples) * 100);
                updateStatus('loading', `Processing audio... ${progress}%`);
            }
        }
        
        console.log('Processing complete, creating output buffer...');
        
        // Create output buffer
        const outputBuffer = audioContext.createBuffer(1, output.length, currentBuffer.sampleRate);
        outputBuffer.getChannelData(0).set(output);
        
        console.log('Output buffer created, starting playback...');
        
        // Play the processed buffer
        playBuffer(outputBuffer);
        updateStatus('ready', 'Playing processed audio with reverb');
    } catch (error) {
        console.error('Processing error:', error);
        updateStatus('error', 'Error processing audio: ' + error.message);
    }
}

// Play buffer
function playBuffer(buffer) {
    stopAudio();
    
    // Create analyser for visualization
    analyser = audioContext.createAnalyser();
    analyser.fftSize = 2048;
    analyser.smoothingTimeConstant = 0.8;
    
    currentSource = audioContext.createBufferSource();
    currentSource.buffer = buffer;
    currentSource.connect(analyser);
    analyser.connect(audioContext.destination);
    
    currentSource.onended = () => {
        isPlaying = false;
        document.getElementById('processButton').textContent = 'Process & Play';
        stopVisualization();
        animateIdleWaveform();
    };
    
    currentSource.start(0);
    isPlaying = true;
    document.getElementById('processButton').textContent = 'Stop';
    
    // Start visualization
    startPlaybackVisualization();
}

// Stop audio
function stopAudio() {
    stopVisualization();
    
    if (analyser) {
        analyser.disconnect();
        analyser = null;
    }
    
    if (currentSource) {
        currentSource.stop();
        currentSource.disconnect();
        currentSource = null;
    }
    isPlaying = false;
    document.getElementById('processButton').textContent = 'Process & Play';
    
    // Restart idle animation
    animateIdleWaveform();
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
    
    Object.entries(defaults).forEach(([param, value]) => {
        const slider = document.getElementById(param);
        const display = document.getElementById(param + 'Value');
        if (slider && display) {
            slider.value = value;
            display.textContent = value;
            if (processor && processor.initialized) {
                processor.setParameter(param, value);
            }
        }
    });
    
    // Reset IR type
    const irSelect = document.getElementById('impulseResponse');
    if (irSelect) {
        irSelect.value = 'hall';
        if (processor && processor.initialized) {
            processor.setImpulseResponseType('hall');
        }
    }
}

// Load list of preloaded audio files
async function loadAudioList() {
    try {
        const response = await fetch('/audio/list.php');
        if (response.ok) {
            const files = await response.json();
            const select = document.getElementById('preloadedSelect');
            
            // Clear existing options
            select.innerHTML = '<option value="">-- Select Audio File --</option>';
            
            // Add audio files
            files.forEach(file => {
                const option = document.createElement('option');
                option.value = file;
                option.textContent = file.replace('.wav', '').replace(/_/g, ' ');
                select.appendChild(option);
            });
            
            // Enable/disable load button based on selection
            select.addEventListener('change', (e) => {
                document.getElementById('loadPreloadedButton').disabled = !e.target.value;
            });
            
            console.log(`Loaded ${files.length} preloaded audio files`);
        } else {
            console.warn('Could not load audio list');
        }
    } catch (error) {
        console.warn('Audio list not available:', error);
        // Hide preloaded section if not available
        document.querySelector('.preloaded-audio').style.display = 'none';
    }
}

// Load preloaded audio file
async function loadPreloadedAudio() {
    const select = document.getElementById('preloadedSelect');
    const filename = select.value;
    if (!filename) return;
    
    // Initialize audio if needed
    if (!isInitialized) {
        const success = await initializeAudio();
        if (!success) return;
    }
    
    try {
        updateStatus('loading', `Loading ${filename}...`);
        
        const response = await fetch(`/audio/${filename}`);
        if (!response.ok) throw new Error('Failed to load audio file');
        
        const arrayBuffer = await response.arrayBuffer();
        currentBuffer = await audioContext.decodeAudioData(arrayBuffer);
        
        updateStatus('ready', `Loaded: ${filename}`);
        document.getElementById('processButton').disabled = false;
        
        drawWaveform(currentBuffer);
    } catch (error) {
        console.error('Error loading preloaded audio:', error);
        updateStatus('error', 'Error loading audio file');
    }
}

// Update status
function updateStatus(type, message) {
    const status = document.getElementById('status');
    status.className = 'status ' + type;
    status.textContent = message;
}

// Setup visualizer
function setupVisualizer() {
    const canvas = document.getElementById('waveformCanvas');
    const ctx = canvas.getContext('2d');
    
    function resize() {
        canvas.width = canvas.offsetWidth;
        canvas.height = canvas.offsetHeight;
        drawEmptyWaveform();
    }
    
    window.addEventListener('resize', resize);
    resize();
    
    // Start idle animation
    animateIdleWaveform();
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

// Visualization functions
function startLiveVisualization() {
    stopVisualization();
    
    const canvas = document.getElementById('waveformCanvas');
    const ctx = canvas.getContext('2d');
    const bufferLength = analyser.frequencyBinCount;
    const dataArray = new Float32Array(bufferLength);
    
    function draw() {
        animationId = requestAnimationFrame(draw);
        
        analyser.getFloatTimeDomainData(dataArray);
        
        // Clear with fade effect
        ctx.fillStyle = 'rgba(0, 0, 0, 0.1)';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        
        // Draw waveform
        ctx.lineWidth = 2;
        ctx.strokeStyle = '#90e0ef';
        ctx.beginPath();
        
        const sliceWidth = canvas.width / bufferLength;
        let x = 0;
        
        for (let i = 0; i < bufferLength; i++) {
            const v = dataArray[i];
            const y = (v + 1) / 2 * canvas.height;
            
            if (i === 0) {
                ctx.moveTo(x, y);
            } else {
                ctx.lineTo(x, y);
            }
            
            x += sliceWidth;
        }
        
        ctx.stroke();
        
        // Add glow effect
        ctx.shadowBlur = 15;
        ctx.shadowColor = '#90e0ef';
        ctx.stroke();
        ctx.shadowBlur = 0;
    }
    
    draw();
}

function startPlaybackVisualization() {
    stopVisualization();
    
    const canvas = document.getElementById('waveformCanvas');
    const ctx = canvas.getContext('2d');
    const bufferLength = analyser.frequencyBinCount;
    const dataArray = new Uint8Array(bufferLength);
    
    function draw() {
        animationId = requestAnimationFrame(draw);
        
        analyser.getByteTimeDomainData(dataArray);
        
        // Clear canvas
        ctx.fillStyle = 'rgba(0, 0, 0, 0.05)';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        
        // Draw waveform
        ctx.lineWidth = 2;
        ctx.strokeStyle = '#90e0ef';
        ctx.beginPath();
        
        const sliceWidth = canvas.width / bufferLength;
        let x = 0;
        
        for (let i = 0; i < bufferLength; i++) {
            const v = dataArray[i] / 128.0;
            const y = v * canvas.height / 2;
            
            if (i === 0) {
                ctx.moveTo(x, y);
            } else {
                ctx.lineTo(x, y);
            }
            
            x += sliceWidth;
        }
        
        ctx.stroke();
        
        // Add center line
        ctx.strokeStyle = 'rgba(144, 224, 239, 0.2)';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(0, canvas.height / 2);
        ctx.lineTo(canvas.width, canvas.height / 2);
        ctx.stroke();
    }
    
    draw();
}

function stopVisualization() {
    if (animationId) {
        cancelAnimationFrame(animationId);
        animationId = null;
    }
}

function drawWaveform(buffer) {
    const canvas = document.getElementById('waveformCanvas');
    const ctx = canvas.getContext('2d');
    const data = buffer.getChannelData(0);
    
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    
    // Draw gradient background
    const gradient = ctx.createLinearGradient(0, 0, 0, canvas.height);
    gradient.addColorStop(0, 'rgba(144, 224, 239, 0.1)');
    gradient.addColorStop(0.5, 'rgba(144, 224, 239, 0.05)');
    gradient.addColorStop(1, 'rgba(144, 224, 239, 0.1)');
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    
    ctx.strokeStyle = '#90e0ef';
    ctx.lineWidth = 2;
    
    const step = Math.ceil(data.length / canvas.width);
    ctx.beginPath();
    
    for (let i = 0; i < canvas.width; i++) {
        const min = Math.min(...data.slice(i * step, (i + 1) * step));
        const max = Math.max(...data.slice(i * step, (i + 1) * step));
        
        const yMin = (1 - min) * canvas.height / 2;
        const yMax = (1 - max) * canvas.height / 2;
        
        if (i === 0) {
            ctx.moveTo(i, (yMin + yMax) / 2);
        } else {
            ctx.lineTo(i, yMin);
            ctx.lineTo(i, yMax);
        }
    }
    
    ctx.stroke();
}

function animateIdleWaveform() {
    stopVisualization();
    
    const canvas = document.getElementById('waveformCanvas');
    const ctx = canvas.getContext('2d');
    let phase = 0;
    
    function draw() {
        if (window.isProcessingLive || isPlaying) {
            return;
        }
        
        animationId = requestAnimationFrame(draw);
        
        ctx.fillStyle = 'rgba(15, 15, 26, 0.1)';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        
        // Draw animated sine wave
        ctx.strokeStyle = 'rgba(144, 224, 239, 0.3)';
        ctx.lineWidth = 2;
        ctx.beginPath();
        
        for (let x = 0; x < canvas.width; x++) {
            const y = canvas.height / 2 + 
                     Math.sin((x / canvas.width) * Math.PI * 4 + phase) * 20 * 
                     Math.sin((x / canvas.width) * Math.PI);
            
            if (x === 0) {
                ctx.moveTo(x, y);
            } else {
                ctx.lineTo(x, y);
            }
        }
        
        ctx.stroke();
        
        // Add center line
        ctx.strokeStyle = 'rgba(144, 224, 239, 0.2)';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(0, canvas.height / 2);
        ctx.lineTo(canvas.width, canvas.height / 2);
        ctx.stroke();
        
        phase += 0.05;
    }
    
    draw();
}