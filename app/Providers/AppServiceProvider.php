<?php

namespace App\Providers;

use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\URL;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void {}

    public function boot(): void
    {
        if ($this->app->isProduction() && parse_url((string) config('app.url'), PHP_URL_SCHEME) === 'https') {
            URL::forceHttps();
        }

        Gate::define('admin', fn (User $user) => $user->isAdmin());
        Gate::define('manage', fn (User $user, Restaurant $restaurant) => $user->enabled && $restaurant->owner_id === $user->id);
        RateLimiter::for('login', fn (Request $r) => Limit::perMinute(5)->by(mb_strtolower($r->string('email')).'|'.$r->ip()));
        RateLimiter::for('register', fn (Request $r) => Limit::perMinute(5)->by($r->ip()));
    }
}
