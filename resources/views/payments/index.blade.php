@extends('layouts.app')
@section('title', 'Платежи')
@section('content')
<a class="back-link" href="{{ route('restaurants.show', $restaurant) }}">{{ $restaurant->name }}</a><section class="dashboard-heading"><h1>Платежи</h1></section><section class="dashboard-panel"><div class="pc-scroll"><table class="pc-table"><thead><tr><th>Счёт</th><th>Сумма</th><th>Статус</th><th>Создан</th><th>Оплачен</th></tr></thead><tbody>@forelse($payments as $payment)<tr><td>{{ $payment->order->order_number }}</td><td>{{ number_format($payment->amount, 2, '.', ' ') }} ₸</td><td>{{ __('procash.statuses.'.$payment->status) }}</td><td>{{ $payment->created_at->format('d.m.Y H:i') }}</td><td>{{ $payment->paid_at?->format('d.m.Y H:i') ?? '—' }}</td></tr>@empty<tr><td colspan="5">Платежей пока нет.</td></tr>@endforelse</tbody></table></div>{{ $payments->links('components.pagination') }}</section>
@endsection
