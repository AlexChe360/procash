<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class RequireMockPayments
{
    public function handle(Request $request, Closure $next)
    {
        abort_unless(config('procash.mock_payments'), 404);

        return $next($request);
    }
}
