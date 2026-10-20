<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class AuthenticationTest extends TestCase
{
    use RefreshDatabase;

    public function test_registration_normalizes_email_and_never_accepts_elevated_roles(): void
    {
        $this->post('/register', ['email' => 'Owner@Example.com', 'password' => 'strong-password', 'passwordConfirmation' => 'strong-password', 'role' => 'ADMIN', 'enabled' => false])->assertRedirect('/login?registered');
        $user = User::firstOrFail();
        $this->assertSame('owner@example.com', $user->email);
        $this->assertSame('USER', $user->role);
        $this->assertTrue($user->enabled);
        $this->assertTrue(Hash::check('strong-password', $user->password_hash));
        $this->post('/register', ['email' => 'OWNER@example.com', 'password' => 'strong-password', 'password_confirmation' => 'strong-password'])->assertSessionHasErrors('email');
    }

    public function test_registration_requires_a_confirmed_password(): void
    {
        $this->post('/register', ['email' => 'owner@example.com', 'password' => 'short', 'password_confirmation' => 'different'])->assertSessionHasErrors('password');
        $this->assertDatabaseCount('users', 0);
        $this->post('/register', ['email' => 'unicode@example.com', 'password' => str_repeat('я', 40), 'password_confirmation' => str_repeat('я', 40)])->assertSessionHasErrors('password');
        $this->assertDatabaseCount('users', 0);
    }

    public function test_existing_spring_bcrypt_accounts_can_login_and_logout(): void
    {
        $hash = Hash::make('old-password');
        $user = User::factory()->create(['email' => 'legacy@example.com', 'password_hash' => '{bcrypt}'.str_replace('$2y$', '$2a$', $hash)]);
        $this->post('/login', ['email' => 'LEGACY@example.com', 'password' => 'old-password'])->assertRedirect('/dashboard');
        $this->assertAuthenticatedAs($user);
        $this->get('/dashboard')->assertOk()->assertSee('legacy@example.com');
        $this->post('/logout')->assertRedirect('/login?logout');
        $this->assertGuest();
    }

    public function test_disabled_accounts_cannot_login_or_keep_an_existing_session(): void
    {
        $user = User::factory()->create(['enabled' => false]);
        $this->post('/login', ['email' => $user->email, 'password' => 'test-password'])->assertSessionHasErrors('email');
        $this->assertGuest();
        $this->actingAs($user)->get('/restaurants')->assertForbidden();
        $this->assertGuest();
    }

    public function test_admin_login_and_role_access(): void
    {
        $admin = User::factory()->create(['role' => 'ADMIN']);
        $this->post('/login', ['email' => $admin->email, 'password' => 'test-password'])->assertRedirect('/admin');
        $this->get('/admin')->assertOk();
        $this->actingAs(User::factory()->create())->get('/admin/freedom-pay/applications')->assertForbidden();
    }

    public function test_guests_are_redirected_and_login_is_rate_limited(): void
    {
        $this->get('/restaurants')->assertRedirect('/login');
        for ($i = 0; $i < 5; $i++) {
            $this->post('/login', ['email' => 'missing@example.com', 'password' => 'wrong'])->assertStatus(302);
        }
        $this->post('/login', ['email' => 'missing@example.com', 'password' => 'wrong'])->assertStatus(429);
    }
}
