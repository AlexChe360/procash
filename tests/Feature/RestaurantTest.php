<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class RestaurantTest extends TestCase
{
    use RefreshDatabase;

    public function test_owner_can_create_a_restaurant_table_and_real_png_qr(): void
    {
        $user = User::factory()->create();
        $this->actingAs($user)->post('/restaurants', ['name' => 'Алматы Café', 'slug' => 'Almaty-Cafe', 'city' => 'Алматы', 'status' => 'ACTIVE', 'owner_id' => 'fake'])->assertRedirect();
        $restaurant = $user->restaurants()->firstOrFail();
        $this->assertSame('almaty-cafe', $restaurant->slug);
        $this->assertSame('DRAFT', $restaurant->status);
        $this->get('/restaurants')->assertOk()->assertSee('Алматы Café');
        $this->get('/restaurants/'.$restaurant->id)->assertOk();
        $this->post('/restaurants/'.$restaurant->id.'/tables', ['tableNumber' => '1', 'displayName' => 'У окна', 'qr_token' => 'fake'])->assertRedirect();
        $table = $restaurant->tables()->firstOrFail();
        $this->assertNotSame('fake', $table->qr_token);
        $this->get('/restaurants/'.$restaurant->id.'/tables/'.$table->id)->assertOk()->assertSee('У окна');
        $response = $this->get('/restaurants/'.$restaurant->id.'/tables/'.$table->id.'/qr.png?size=640')->assertOk()->assertHeader('Content-Type', 'image/png');
        $this->assertStringStartsWith("\x89PNG\r\n\x1a\n", $response->getContent());
        $this->assertGreaterThanOrEqual(600, getimagesizefromstring($response->getContent())[0]);
        $this->get('/restaurants/'.$restaurant->id.'/tables/'.$table->id.'/qr.png?size=100')->assertSessionHasErrors('size');
    }

    public function test_duplicate_slugs_and_table_numbers_are_rejected(): void
    {
        $user = User::factory()->create();
        $restaurant = $user->restaurants()->create(['name' => 'Cafe', 'slug' => 'cafe']);
        $this->actingAs($user)->post('/restaurants', ['name' => 'Other', 'slug' => 'CAFE'])->assertSessionHasErrors('slug');
        $restaurant->tables()->create(['table_number' => 'A1']);
        $this->post('/restaurants/'.$restaurant->id.'/tables', ['table_number' => 'a1'])->assertSessionHasErrors('table_number');
        $this->assertDatabaseCount('restaurant_tables', 1);
    }

    public function test_foreign_restaurants_and_nested_tables_are_protected(): void
    {
        $owner = User::factory()->create();
        $other = User::factory()->create();
        $restaurant = $owner->restaurants()->create(['name' => 'Owner', 'slug' => 'owner']);
        $foreign = $other->restaurants()->create(['name' => 'Foreign', 'slug' => 'foreign']);
        $table = $foreign->tables()->create(['table_number' => '1']);
        $this->actingAs($other);
        foreach (['', '/tables', '/orders', '/payments', '/payments/freedom-pay'] as $suffix) {
            $this->get('/restaurants/'.$restaurant->id.$suffix)->assertForbidden();
        }
        $this->actingAs($owner)->post('/restaurants/'.$restaurant->id.'/tables/'.$table->id.'/mock-order')->assertNotFound();
        $this->get('/restaurants/'.$restaurant->id.'/tables/'.$table->id.'/qr.png')->assertNotFound();
        $this->assertDatabaseCount('restaurant_orders', 0);
    }

    public function test_qr_slug_tokens_and_inactive_tables_are_checked(): void
    {
        $restaurant = User::factory()->create()->restaurants()->create(['name' => 'Cafe', 'slug' => 'cafe']);
        $table = $restaurant->tables()->create(['table_number' => '1']);
        $this->get('/r/cafe/q/'.$table->qr_token)->assertOk()->assertSee('Заказ пока не найден');
        $this->get('/r/wrong/q/'.$table->qr_token)->assertNotFound();
        $this->get('/r/cafe/q/not-a-uuid')->assertNotFound();
        $table->active = false;
        $table->save();
        $this->get('/r/cafe/q/'.$table->qr_token)->assertNotFound();
    }
}
