<?php

namespace App\Http\Controllers;

use App\Models\Payment;
use App\Services\PaymentService;
use Illuminate\Http\Request;

class PaymentController extends Controller
{
    public function create(Request $request, PaymentService $payments)
    {
        $data = $request->validate(['order_id' => ['required', 'uuid']]);
        $payment = $payments->create($data['order_id']);

        return redirect()->route('payments.mock', $payment);
    }

    public function mock(Payment $payment)
    {
        return view('payments.mock', compact('payment'));
    }

    public function paid(Payment $payment, PaymentService $payments)
    {
        $payments->complete($payment, 'PAID');

        return redirect()->route('payments.success', $payment);
    }

    public function failed(Payment $payment, PaymentService $payments)
    {
        $payments->complete($payment, 'FAILED');

        return redirect($payment->order->table->publicUrl().'?payment=failed');
    }

    public function success(Payment $payment)
    {
        abort_unless($payment->status === 'PAID', 404);

        return view('payments.success', compact('payment'));
    }
}
