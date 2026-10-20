@extends('layouts.public')
@section('title', $order['restaurantName'])
@section('content')
<header class="public-header"><div class="restaurant-info"><h1>{{ $order['restaurantName'] }}</h1><p>Стол {{ $order['tableNumber'] }} · Официант {{ $order['waiterName'] }}</p></div></header><section class="receipt-card"><span class="mock-badge">Тестовый заказ</span>@foreach($order['items'] as $item)<article class="receipt-item"><div class="receipt-item-heading"><strong>{{ $item['name'] }}</strong><strong>{{ number_format($item['totalPrice'], 2, '.', ' ') }} ₸</strong></div><p>{{ $item['quantity'] }} × {{ $item['unitPrice'] }} ₸</p></article>@endforeach<div class="receipt-row receipt-final"><span>Итого</span><strong>{{ number_format($order['totalAmount'], 2, '.', ' ') }} ₸</strong></div></section>
@endsection
