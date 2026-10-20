<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class EnsureEnabled
{
    public function handle(Request $request, Closure $next)
    {
        if (! $request->user()?->enabled) {
            Auth::logout();
            $request->session()->invalidate();
            $request->session()->regenerateToken();
            abort(403, 'Аккаунт отключён.');
        }

        return $next($request);
    }
}
