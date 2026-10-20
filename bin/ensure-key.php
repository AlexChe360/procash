<?php

require dirname(__DIR__).'/vendor/autoload.php';

$values = Dotenv\Dotenv::createArrayBacked(dirname(__DIR__))->safeLoad();
$key = getenv('APP_KEY') ?: ($values['APP_KEY'] ?? '');
if ($key === '') {
    passthru(escapeshellarg(PHP_BINARY).' '.escapeshellarg(dirname(__DIR__).'/artisan').' key:generate --no-interaction', $status);
    exit($status);
}
