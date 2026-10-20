@extends('layouts.auth')
@section('title', 'Вход в личный кабинет')
@section('content')
@if(request()->has('logout'))<p class="pc-alert">Вы вышли из аккаунта.</p>@endif
<form class="auth-form" method="post" action="{{ route('login') }}">@csrf<x-field name="email" label="Email" type="email" autocomplete="username" maxlength="255"/><x-field name="password" label="Пароль" type="password" autocomplete="current-password"/><button class="auth-button" type="submit">Войти</button></form><p class="auth-switch">Нет аккаунта? <a href="{{ route('register') }}">Зарегистрироваться</a></p>
@endsection
