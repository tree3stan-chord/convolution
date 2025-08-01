// app.js - Lazy loading version that loads NOTHING until user clicks

// Global variables
let audioContext = null;
let processor = null;
let micStream = null;
let isInitialized = false;

// Only set up UI on page load
document.addEventListener('DOMContentLoaded', () => {
    console.log('DOM loaded - setting up UI only');
    
    // Update status
    document.getElementById('status').textContent = 'Click "Start Live Input" to begin';
    document.getElementById('status').className = 'status ready';
    
    // Enable only the live input button
    document.getElementById('liveInputButton').disabled = false;
    
    // Add click handler
    document.getElementById('liveInputButton').addEventListener('click', handleLiveInputClick);
    
    // Setup basic UI for parameters (no audio code)
    setupBasicUI();
});

// Setup basic UI without any audio code
function setupBasicUI() {
    // Just set initial values in UI
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

// Handle live input button click
async function handleLiveInputClick() {
    console.log('Live input button clicked');
    
    try {
        if (!isInitialized) {
            // First time - initialize everything
            document.getElementById('status').textContent = 'Initializing audio system...';
            
            // Create AudioContext NOW after user gesture
            console.log('Creating AudioContext after user gesture...');
            audioContext = new (window.AudioContext || window.webkitAudioContext)();
            console.log('AudioContext created, state:', audioContext.state);
            
            // Load and initialize the processor
            console.log('Loading ConvolutionProcessor...');
            if (typeof ConvolutionProcessor === 'undefined') {
                throw new Error('ConvolutionProcessor not found. Make sure convolution-module.js is loaded.');
            }
            
            processor = new ConvolutionProcessor();
            await processor.initialize('./', audioContext.sampleRate);
            console.log('Processor initialized');
            
            isInitialized = true;
        }
        
        // Request microphone
        document.getElementById('status').textContent = 'Requesting microphone access...';
        console.log('Requesting getUserMedia...');
        
        micStream = await navigator.mediaDevices.getUserMedia({
            audio: {
                echoCancellation: false,
                noiseSuppression: false,
                autoGainControl: false
            }
        });
        
        console.log('Microphone access granted');
        document.getElementById('status').textContent = 'Microphone connected!';
        
        // Create simple audio graph for testing
        const source = audioContext.createMediaStreamSource(micStream);
        const gain = audioContext.createGain();
        gain.gain.value = 0.5;
        
        source.connect(gain);
        gain.connect(audioContext.destination);
        
        // Update button
        document.getElementById('liveInputButton').textContent = 'Stop';
        
    } catch (error) {
        console.error('Error:', error);
        document.getElementById('status').textContent = 'Error: ' + error.message;
        document.getElementById('status').className = 'status error';
    }
}