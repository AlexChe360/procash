<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class ReadinessTest extends TestCase
{
    use RefreshDatabase;

    public function test_public_pages_health_and_demo_api(): void
    {
        foreach (['/', '/login', '/register'] as $path) {
            $this->get($path)->assertOk();
        }
        $this->get('/api/v1/health')->assertExactJson(['status' => 'UP', 'service' => 'procash']);
        $this->get('/actuator/health')->assertOk()->assertJsonPath('status', 'UP');
        $this->get('/order?restaurantId=demo&tableNumber=1')->assertOk()->assertSee('Капучино');
        $this->actingAs(User::factory()->create());
        $this->getJson('/api/v1/orders/current?restaurantId=demo&tableNumber=1')->assertOk()->assertJsonPath('totalAmount', 3300)->assertJsonCount(2, 'items');
        $this->getJson('/api/v1/orders/current?restaurantId=demo&tableNumber=0')->assertStatus(400)->assertJsonPath('code', 'VALIDATION_ERROR');
        $this->getJson('/api/v1/orders/current?restaurantId=demo&tableNumber=99')->assertNotFound()->assertJsonPath('code', 'ORDER_NOT_FOUND');
        $this->getJson('/api/v1/orders/current')->assertStatus(400)->assertJsonPath('code', 'MISSING_PARAMETER');
        $this->getJson('/api/v1/orders/current?restaurantId=demo&tableNumber=abc')->assertStatus(400)->assertJsonPath('code', 'INVALID_PARAMETER_TYPE');
    }

    public function test_schema_adoption_is_repeatable_and_preserves_legacy_records(): void
    {
        $user = User::factory()->create(['password_hash' => '{bcrypt}legacy-hash']);
        $restaurant = $user->restaurants()->create(['name' => 'Existing', 'slug' => 'existing']);
        $application = $restaurant->application()->create();
        DB::table('freedom_pay_applications')->where('id', $application->id)->update(['status' => 'UNDER_REVIEW']);
        Schema::table('users', fn ($table) => $table->dropColumn('remember_token'));
        $migration = require database_path('migrations/2026_10_20_000001_create_procash_schema.php');
        $migration->up();
        $migration->up();
        $this->assertTrue(Schema::hasColumn('users', 'remember_token'));
        $this->assertSame('{bcrypt}legacy-hash', $user->fresh()->password_hash);
        $this->assertSame('Existing', $restaurant->fresh()->name);
        $this->assertSame('UNDER_FREEDOM_REVIEW', $application->fresh()->status);
        $this->assertDatabaseCount('users', 1);
    }
}
