@extends('layouts.public')
@section('title', 'Тестовая оплата')
@section('content')
<section class="mock-card"><span class="mock-badge">MOCK</span><h1>Freedom Pay</h1><p class="mock-description">Тестовая страница оплаты. Деньги не списываются.</p><div class="mock-amount"><span>К оплате</span><strong>{{ number_format($payment->amount, 2, '.', ' ') }} ₸</strong></div>
@if(in_array($payment->status, ['CREATED', 'PENDING'], true))<form method="post" action="/payments/{{ $payment->id }}/mock/success">@csrf<button class="mock-success-button" type="submit">Успешная оплата</button></form><form method="post" action="/payments/{{ $payment->id }}/mock/fail">@csrf<button class="mock-error-button" type="submit">Ошибка оплаты</button></form>@elseif($payment->status === 'PAID')<a class="mock-success-button" href="{{ route('payments.success', $payment) }}">Платёж уже оплачен</a>@else<p>{{ __('procash.statuses.'.$payment->status) }}</p><a href="{{ $payment->order->table->publicUrl() }}">Вернуться к заказу</a>@endif</section>
@endsection
