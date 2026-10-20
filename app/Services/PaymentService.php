<?php

namespace App\Services;

use App\Models\Payment;
use App\Models\RestaurantOrder;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class PaymentService
{
    public function create(string $orderId): Payment
    {
        return DB::transaction(function () use ($orderId) {
            $order = RestaurantOrder::lockForUpdate()->findOrFail($orderId);
            if ($order->status !== 'OPEN' || bccomp($order->total_amount, '0', 2) <= 0) {
                throw ValidationException::withMessages(['order_id' => 'Заказ уже закрыт или недоступен для оплаты.']);
            }

            return $order->payments()->whereIn('status', ['CREATED', 'PENDING'])->latest()->first()
                ?? $order->payments()->create(['restaurant_id' => $order->restaurant_id, 'amount' => $order->total_amount, 'status' => 'PENDING', 'provider' => 'FREEDOM_PAY']);
        });
    }

    public function complete(Payment $payment, string $status): Payment
    {
        return DB::transaction(function () use ($payment, $status) {
            // Match create()'s lock order to avoid create/confirmation deadlocks.
            $order = RestaurantOrder::lockForUpdate()->findOrFail($payment->order_id);
            $payment = Payment::lockForUpdate()->findOrFail($payment->id);
            if ($payment->status === $status) {
                return $payment;
            }
            if (! in_array($payment->status, ['CREATED', 'PENDING'], true) || $order->status !== 'OPEN') {
                throw ValidationException::withMessages(['payment' => 'Платёж нельзя изменить в текущем статусе.']);
            }
            $payment->status = $status;
            if ($status === 'PAID') {
                $payment->paid_at = now();
                $order->status = 'PAID';
                $order->save();
            }
            $payment->save();

            return $payment;
        });
    }
}
