@extends('layouts.app')
@section('title', 'Рестораны')
@section('content')
<section class="dashboard-heading"><div><span class="dashboard-eyebrow">Управление</span><h1>Ваши рестораны</h1></div><a class="primary-button" href="{{ route('restaurants.create') }}">Добавить ресторан</a></section><section class="pc-grid">@forelse($restaurants as $item)<article class="dashboard-panel"><h2><a href="{{ route('restaurants.show', $item) }}">{{ $item->name }}</a></h2><p>{{ $item->city }}</p><p>{{ $item->description }}</p><span class="stat-status">{{ __('procash.statuses.'.$item->status) }}</span><p>Столов: {{ $item->tables_count }}</p><a class="secondary-button" href="{{ route('restaurants.show', $item) }}">Открыть ресторан</a></article>@empty<div class="dashboard-panel"><h2>Ресторанов пока нет</h2><p>Добавьте свой первый ресторан, чтобы начать работу.</p></div>@endforelse</section>
@endsection
