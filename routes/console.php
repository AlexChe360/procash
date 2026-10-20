<?php

use App\Models\User;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Hash;

Artisan::command('procash:admin {email}', function () {
    $email = mb_strtolower(trim($this->argument('email')));
    if (! filter_var($email, FILTER_VALIDATE_EMAIL)) {
        $this->error('Введите корректный email.');

        return 1;
    }
    $user = User::whereRaw('lower(email) = ?', [$email])->first();
    if (! $user) {
        $password = $this->secret('Пароль администратора (от 12 до 72 символов)');
        if (strlen($password ?? '') < 12 || strlen($password) > 72) {
            $this->error('Пароль должен содержать от 12 до 72 байт.');

            return 1;
        }
        $user = new User(['email' => $email, 'password_hash' => Hash::make($password)]);
    }
    $user->role = 'ADMIN';
    $user->enabled = true;
    $user->save();
    $this->info('Администратор сохранён.');

    return 0;
})->purpose('Создать администратора или повысить существующего пользователя');
