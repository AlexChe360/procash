<?php

namespace Tests\Feature;

use App\Models\Payment;
use App\Models\RestaurantOrder;
use App\Models\User;
use App\Services\OrderService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class PaymentTest extends TestCase
{
    use RefreshDatabase;

    private function order(): RestaurantOrder
    {
        $restaurant = User::factory()->create()->restaurants()->create(['name' => 'Cafe', 'slug' => 'cafe']);

        return app(OrderService::class)->seed($restaurant->tables()->create(['table_number' => '1']));
    }

    public function test_mock_order_is_idempotent_and_public_receipt_matches_database(): void
    {
        $order = $this->order();
        $this->actingAs($order->restaurant->owner)->post('/restaurants/'.$order->restaurant_id.'/tables/'.$order->restaurant_table_id.'/mock-order')->assertRedirect();
        $this->assertDatabaseCount('restaurant_orders', 1);
        $this->assertSame('14700.00', $order->total_amount);
        $this->assertCount(3, $order->items);
        $this->get('/r/cafe/q/'.$order->table->qr_token)->assertOk()->assertSee('Цезарь с курицей')->assertSee('14 700.00');
        $this->get('/restaurants/'.$order->restaurant_id.'/orders')->assertOk()->assertSee('TEST-001');
    }

    public function test_payment_uses_server_amount_is_reused_and_success_is_idempotent(): void
    {
        $order = $this->order();
        $this->post('/payments/create', ['orderId' => $order->id, 'amount' => '0.01'])->assertRedirect();
        $payment = Payment::firstOrFail();
        $this->assertSame('14700.00', $payment->amount);
        $this->post('/payments/create', ['order_id' => $order->id])->assertRedirect('/payments/'.$payment->id.'/mock');
        $this->assertDatabaseCount('payments', 1);
        $this->get('/payments/'.$payment->id.'/success')->assertNotFound();
        $this->get('/payments/'.$payment->id.'/mock')->assertOk();
        $this->post('/payments/'.$payment->id.'/mock/success')->assertRedirect('/payments/'.$payment->id.'/success');
        $this->assertSame('PAID', $order->fresh()->status);
        $paidAt = $payment->fresh()->paid_at->toISOString();
        $this->post('/payments/'.$payment->id.'/mock/success')->assertRedirect();
        $this->assertSame($paidAt, $payment->fresh()->paid_at->toISOString());
        $this->get('/payments/'.$payment->id.'/success')->assertOk()->assertSee('Оплата прошла успешно');
        $this->post('/payments/'.$payment->id.'/mock/fail')->assertSessionHasErrors('payment');
        $this->post('/payments/create', ['order_id' => $order->id])->assertSessionHasErrors('order_id');
        $this->actingAs($order->restaurant->owner)->get('/restaurants/'.$order->restaurant_id.'/payments')->assertOk()->assertSee('Оплачен');
    }

    public function test_failed_payment_can_be_retried_without_changing_the_failed_record(): void
    {
        $order = $this->order();
        $this->post('/payments/create', ['order_id' => $order->id]);
        $failed = Payment::firstOrFail();
        $this->post('/payments/'.$failed->id.'/mock/fail')->assertRedirect($order->table->publicUrl().'?payment=failed');
        $this->assertSame('OPEN', $order->fresh()->status);
        $this->post('/payments/create', ['order_id' => $order->id])->assertRedirect();
        $this->assertDatabaseCount('payments', 2);
        $this->assertSame('FAILED', $failed->fresh()->status);
        $this->post('/payments/'.$failed->id.'/mock/success')->assertSessionHasErrors('payment');
    }

    public function test_mock_switches_disable_fake_order_and_payment_mutations(): void
    {
        $order = $this->order();
        config(['procash.mock_payments' => false, 'procash.mock_orders' => false]);
        $this->post('/payments/create', ['order_id' => $order->id])->assertNotFound();
        $this->actingAs($order->restaurant->owner)->post('/restaurants/'.$order->restaurant_id.'/tables/'.$order->restaurant_table_id.'/mock-order')->assertNotFound();
        $this->get('/r/cafe/q/'.$order->table->qr_token)->assertOk()->assertSee('Онлайн-оплата пока недоступна');
    }
}
