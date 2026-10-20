<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    public function register(Request $request)
    {
        $request->merge(['email' => mb_strtolower(trim($request->string('email')))]);
        $data = $request->validate([
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'password' => ['bail', 'required', 'string', 'min:8', 'max:72', 'confirmed', function (string $attribute, mixed $value, \Closure $fail) {
                if (strlen($value) > 72) {
                    $fail('Пароль должен занимать не более 72 байт.');
                }
            }],
        ]);
        User::create(['email' => $data['email'], 'password_hash' => Hash::make($data['password'])]);

        return redirect('/login?registered')->with('success', 'Аккаунт создан. Войдите в личный кабинет.');
    }

    public function login(Request $request)
    {
        $request->merge(['email' => mb_strtolower(trim($request->string('email')))]);
        $data = $request->validate(['email' => ['required', 'email', 'max:255'], 'password' => ['required', 'string']]);
        if (! Auth::attempt([...$data, 'enabled' => true])) {
            throw ValidationException::withMessages(['email' => 'Неверный email или пароль.']);
        }
        $request->session()->regenerate();

        return redirect()->intended($request->user()->isAdmin() ? '/admin' : '/dashboard');
    }

    public function logout(Request $request)
    {
        Auth::logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return redirect('/login?logout');
    }
}
