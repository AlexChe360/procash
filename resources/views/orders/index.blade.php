@extends('layouts.app')
@section('title', 'Заказы')
@section('content')
<a class="back-link" href="{{ route('restaurants.show', $restaurant) }}">{{ $restaurant->name }}</a><section class="dashboard-heading"><h1>Заказы</h1></section><section class="dashboard-panel"><div class="pc-scroll"><table class="pc-table"><thead><tr><th>Счёт</th><th>Стол</th><th>Сумма</th><th>Статус</th><th>Открыт</th></tr></thead><tbody>@forelse($orders as $order)<tr><td>{{ $order->order_number }}</td><td>{{ $order->table->table_number }}</td><td>{{ number_format($order->total_amount, 2, '.', ' ') }} ₸</td><td>{{ __('procash.statuses.'.$order->status) }}</td><td>{{ $order->opened_at->format('d.m.Y H:i') }}</td></tr>@empty<tr><td colspan="5">Заказов пока нет.</td></tr>@endforelse</tbody></table></div>{{ $orders->links('components.pagination') }}</section>
@endsection
