<?php

namespace Tests\Feature;

use App\Providers\AppServiceProvider;
use Tests\TestCase;

class HttpsTest extends TestCase
{
    public function test_https_proxy_preserves_secure_auth_form_actions_and_redirects(): void
    {
        $this->withServerVariables(['REMOTE_ADDR' => '172.18.0.1'])
            ->withHeaders(['X-Forwarded-Proto' => 'https', 'X-Forwarded-Port' => '443']);

        foreach (['login', 'register'] as $page) {
            $this->get('http://procash.test/'.$page)
                ->assertOk()
                ->assertSee('action="https://procash.test/'.$page.'"', false)
                ->assertDontSee('http://procash.test', false);
        }

        $this->get('http://procash.test/restaurants')->assertRedirect('https://procash.test/login');
    }

    public function test_production_https_url_prevents_insecure_forms_without_forwarded_headers(): void
    {
        config(['app.url' => 'https://procash.test']);
        $this->app['env'] = 'production';
        $this->app->getProvider(AppServiceProvider::class)->boot();

        foreach (['login', 'register'] as $page) {
            $this->get('http://procash.test/'.$page)
                ->assertOk()
                ->assertSee('action="https://procash.test/'.$page.'"', false)
                ->assertDontSee('http://procash.test', false);
        }

        $this->get('http://procash.test/restaurants')->assertRedirect('https://procash.test/login');
    }

    public function test_local_forms_still_work_over_http(): void
    {
        foreach (['login', 'register'] as $page) {
            $this->get('http://localhost:8080/'.$page)
                ->assertOk()
                ->assertSee('action="http://localhost:8080/'.$page.'"', false);
        }
    }
}
