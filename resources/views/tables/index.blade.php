@extends('layouts.app')
@section('title', 'Столы и QR-коды')
@section('content')
<a class="back-link" href="{{ route('restaurants.show', $restaurant) }}">{{ $restaurant->name }}</a><section class="dashboard-heading"><h1>Столы и QR-коды</h1><a class="primary-button" href="{{ route('tables.create', $restaurant) }}">Добавить стол</a></section><section class="pc-grid">@forelse($tables as $table)<article class="dashboard-panel"><h2>Стол {{ $table->table_number }}</h2><p>{{ $table->display_name }}</p><p>{{ $table->active ? 'Активен' : 'Отключён' }}</p><a class="secondary-button" href="{{ route('tables.show', [$restaurant, $table]) }}">Открыть QR-код</a></article>@empty<div class="dashboard-panel"><p>Добавьте стол и разместите его QR-код в ресторане.</p></div>@endforelse</section>
@endsection
