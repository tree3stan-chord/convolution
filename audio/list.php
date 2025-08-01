<?php
// audio/list.php - API endpoint for listing audio files
// Provides a clean JSON interface for getting available audio files

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');

// Handle preflight requests
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

// Define allowed audio extensions
$allowed_extensions = ['wav', 'mp3', 'ogg', 'flac', 'm4a'];
$pattern = '*.{' . implode(',', $allowed_extensions) . '}';

// Get all audio files in the current directory
$files = glob($pattern, GLOB_BRACE);

// Filter out any hidden files or directories
$files = array_filter($files, function($file) {
    return is_file($file) && !str_starts_with(basename($file), '.');
});

// Get file information
$file_info = array_map(function($file) {
    return [
        'filename' => basename($file),
        'size' => filesize($file),
        'size_mb' => round(filesize($file) / 1048576, 2),
        'modified' => filemtime($file),
        'extension' => pathinfo($file, PATHINFO_EXTENSION)
    ];
}, $files);

// Sort by filename
usort($file_info, function($a, $b) {
    return strcasecmp($a['filename'], $b['filename']);
});

// Return just filenames for backwards compatibility
// Change to $file_info for full information
$filenames = array_map(function($info) {
    return $info['filename'];
}, $file_info);

// Return as JSON
echo json_encode($filenames, JSON_PRETTY_PRINT);