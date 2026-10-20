@extends('layouts.public')
@section('title', 'Оплата прошла успешно')
@section('content')
<section class="mock-card"><span class="mock-badge">MOCK</span><h1>Оплата прошла успешно</h1><div class="mock-amount"><strong>{{ number_format($payment->amount, 2, '.', ' ') }} ₸</strong></div><p>Счёт № {{ $payment->order->order_number }} оплачен.</p><p>Платёж {{ $payment->id }}</p><a class="secondary-button" href="{{ $payment->order->table->publicUrl() }}">Вернуться к столу</a></section>
@endsection
