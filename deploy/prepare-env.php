<?php

require dirname(__DIR__).'/vendor/autoload.php';

// Run from the release image; never source the server's .env as shell code.
$path = $argv[1] ?? '';
$image = $argv[2] ?? null;
if (! is_file($path) || ! is_readable($path) || ! is_writable($path)) {
    fwrite(STDERR, "The server .env must already exist and be readable/writable.\n");
    exit(1);
}

$contents = file_get_contents($path);
$values = Dotenv\Dotenv::createArrayBacked(dirname($path), basename($path))->safeLoad();
if (empty($values['POSTGRES_PASSWORD'])) {
    fwrite(STDERR, "Set POSTGRES_PASSWORD securely in the server .env.\n");
    exit(1);
}

$updates = [];
$key = $values['APP_KEY'] ?? '';
if ($key === '') {
    $updates['APP_KEY'] = 'base64:'.base64_encode(random_bytes(32));
} else {
    $decoded = str_starts_with($key, 'base64:') ? base64_decode(substr($key, 7), true) : $key;
    if ($decoded === false || strlen($decoded) !== 32) {
        fwrite(STDERR, "Existing APP_KEY is invalid for AES-256-CBC; it has not been replaced.\n");
        exit(1);
    }
}

if ($image !== null) {
    if (! preg_match('~^ghcr\.io/[a-z0-9._/-]+@sha256:[a-f0-9]{64}$~D', $image)) {
        fwrite(STDERR, "Expected an immutable GHCR image digest.\n");
        exit(1);
    }
    $updates['PROCASH_IMAGE'] = $image;
}

foreach ($updates as $name => $value) {
    $pattern = '/^[\t ]*(?:export[\t ]+)?'.preg_quote($name, '/').'[\t ]*=.*$/m';
    if (preg_match_all($pattern, $contents) > 1) {
        fwrite(STDERR, "Duplicate $name declarations in .env; no changes were saved.\n");
        exit(1);
    }
    $contents = preg_match($pattern, $contents)
        ? preg_replace_callback($pattern, fn () => $name.'='.$value, $contents)
        : rtrim($contents, "\r\n").PHP_EOL.$name.'='.$value.PHP_EOL;
}

if ($updates !== []) {
    $temporary = tempnam(dirname($path), '.procash-env-');
    try {
        chmod($temporary, 0600);
        if (file_put_contents($temporary, $contents, LOCK_EX) === false || ! rename($temporary, $path)) {
            throw new RuntimeException('Cannot atomically update the server .env.');
        }
    } finally {
        if (is_file($temporary)) {
            unlink($temporary);
        }
    }
}

fwrite(STDOUT, isset($updates['APP_KEY']) ? "Server APP_KEY created.\n" : "Existing server APP_KEY preserved.\n");
