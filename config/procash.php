<?php

return [
    'public_base_url' => env('PROCASH_PUBLIC_BASE_URL', env('APP_URL', 'http://localhost:8080')),
    'mock_payments' => env('PROCASH_MOCK_PAYMENTS', true),
    'mock_orders' => env('PROCASH_MOCK_ORDERS', true),
];
