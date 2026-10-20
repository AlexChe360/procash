@extends('layouts.app')
@section('title', 'Новый стол')
@section('content')
<a class="back-link" href="{{ route('tables.index', $restaurant) }}">Назад к столам</a><section class="dashboard-heading"><h1>Добавить стол</h1></section><section class="restaurant-form-card"><form class="restaurant-form" method="post" action="{{ route('tables.store', $restaurant) }}">@csrf<x-field name="table_number" label="Номер стола" maxlength="50"/><x-field name="display_name" label="Название стола" :required="false" maxlength="150"/><button class="primary-button" type="submit">Создать стол</button></form></section>
@endsection
