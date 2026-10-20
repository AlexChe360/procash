<?php

namespace App\Services;

use App\Models\RestaurantOrder;
use App\Models\RestaurantTable;
use Illuminate\Support\Facades\DB;

class OrderService
{
    public function seed(RestaurantTable $table): RestaurantOrder
    {
        return DB::transaction(function () use ($table) {
            $table = RestaurantTable::lockForUpdate()->findOrFail($table->id);
            $existing = $table->orders()->where('status', 'OPEN')->latest('opened_at')->first();
            if ($existing) {
                return $existing;
            }
            $order = $table->orders()->create(['restaurant_id' => $table->restaurant_id, 'order_number' => 'TEST-001', 'opened_at' => now(), 'total_amount' => '14700.00']);
            foreach ([['Цезарь с курицей', '1', '3200.00'], ['Капучино', '2', '1500.00'], ['Стейк', '1', '8500.00']] as [$name, $quantity, $price]) {
                $order->items()->create(['name' => $name, 'quantity' => $quantity, 'unit_price' => $price, 'total_price' => bcmul($quantity, $price, 2)]);
            }

            return $order->load('items');
        });
    }

    public function demo(string $restaurantId, int $tableNumber): array
    {
        abort_unless(config('procash.mock_orders'), 404);
        abort_if($tableNumber === 99, 404, 'Активный заказ не найден');

        return ['restaurantId' => $restaurantId, 'restaurantName' => 'ProCash Caffe', 'tableNumber' => $tableNumber, 'waiterName' => 'Айгерим', 'items' => [
            ['name' => 'Капучино', 'quantity' => 2, 'unitPrice' => 1200, 'totalPrice' => 2400],
            ['name' => 'Круассан', 'quantity' => 1, 'unitPrice' => 900, 'totalPrice' => 900],
        ], 'totalAmount' => 3300];
    }
}
