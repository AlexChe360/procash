@extends('layouts.auth')
@section('title', 'Создайте аккаунт')
@section('content')
<p>Добавьте ресторан и отправьте заявку на подключение интернет-эквайринга.</p><form class="auth-form" method="post" action="{{ route('register') }}">@csrf<x-field name="email" label="Email" type="email" autocomplete="username" maxlength="255"/><x-field name="password" label="Пароль" type="password" autocomplete="new-password" minlength="8" maxlength="72"/><x-field name="password_confirmation" label="Повторите пароль" type="password" autocomplete="new-password" minlength="8" maxlength="72"/><button class="auth-button" type="submit">Создать аккаунт</button></form><p class="auth-switch">Уже есть аккаунт? <a href="{{ route('login') }}">Войти</a></p>
@endsection
