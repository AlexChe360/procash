@extends('layouts.app')
@section('title', 'Стол '.$table->table_number)
@section('content')
<a class="back-link" href="{{ route('tables.index', $restaurant) }}">Назад к столам</a><section class="dashboard-heading"><div><h1>Стол {{ $table->table_number }}</h1><p>{{ $table->display_name }}</p></div></section><section class="dashboard-panel pc-qr"><img width="280" height="280" alt="QR-код стола {{ $table->table_number }}" src="{{ route('tables.qr', [$restaurant, $table]) }}"><p><a href="{{ $table->publicUrl() }}">{{ $table->publicUrl() }}</a></p><div class="pc-actions"><a class="primary-button" href="{{ route('tables.qr', [$restaurant, $table]) }}" download>Скачать QR-код PNG</a>@if(config('procash.mock_orders'))<form method="post" action="{{ route('tables.mock-order', [$restaurant, $table]) }}">@csrf<button class="secondary-button" type="submit">Создать тестовый заказ</button></form>@endif</div></section>
@endsection
